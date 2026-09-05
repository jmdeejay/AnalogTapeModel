unit ChowTape.DSP.FastMath;

{
  Fast transcendentals for the hysteresis solver.

  Measurement, not guesswork, put these here. System.Math.Tanh clears the
  floating-point status word and classifies the operand's IEEE bits on every
  call before doing any arithmetic -- sensible for a general-purpose routine,
  ruinous in a loop that runs it four to nine times per sample per channel at
  the oversampled rate. Benchmarking put it at 36 ns on Win64 and 58 ns on
  Win32, which worked out at ~45% of the whole solver.

  FastExp uses the standard table-assisted range reduction:

      exp(x) = 2^k * 2^(j/32) * exp(r),   |r| <= ln2/64 ~ 0.0108

  where k and j come from rounding x*32/ln2, 2^(j/32) is a 32-entry table and
  2^k is built directly in the exponent field. Over so small an r a degree-4
  series is already good to about 1e-12 relative, far beyond anything the tape
  model can resolve.

  The solver only ever wants coth, so FastCoth is provided directly and skips
  the reciprocal that 1.0 / Tanh(x) would need.

  Accuracy is checked against the RTL by bench\ChowTapeBench.dpr -- change
  anything here and re-run it.
}

interface

{ exp(x). Relative error < 1e-12 across the range that matters.

  Note this is only faster than the RTL on x64. 32-bit Delphi targets the x87,
  whose F2XM1/FSCALE pair System.Exp compiles down to, and no software
  polynomial beats a hardware exponential: measured 36.9 ns against the RTL's
  27.6 ns. FastTanh and FastCoth therefore pick whichever is quicker for the
  target -- see FastMathExpBackend. FastExp itself always runs the software
  path so the benchmark can compare the two. }
function FastExp(X: Double): Double;
{ tanh(x), saturating to +/-1 beyond |x| = 19 where doubles cannot tell the
  difference anyway. }
function FastTanh(X: Double): Double;
{ coth(x) = 1/tanh(x), computed without the extra divide. }
function FastCoth(X: Double): Double;

{ Natural log. Relative error < 1.3e-12 over any range that matters.

  The compressor converts to and from decibels once per oversampled sample per
  channel, and the RTL's Log10 and Power were measured costing more than the
  rest of that stage put together. }
function FastLog(X: Double): Double;

{ cos(x). Absolute error < 1.2e-10 for |x| < 40, which covers the LFO phases
  plus their offsets. The wow/flutter oscillators evaluate four cosines per
  sample per channel and Win64 has no hardware cosine, so the RTL's is a
  software routine costing about five times this. }
function FastCos(X: Double): Double;

{ Whichever of the above is quicker on this target. x86 keeps hitting the same
  result -- the x87's F2XM1, FYL2X and FCOS beat any software polynomial -- so
  these dispatch to the RTL there and to the fast versions on x64. Use them
  unless you are specifically benchmarking one implementation. }
function QuickExp(X: Double): Double; inline;
function QuickLog(X: Double): Double; inline;
function QuickCos(X: Double): Double; inline;

{ Which implementations the Quick* routines resolve to, for the bench header. }
function FastMathExpBackend: string;

implementation

const
  { 32 / ln2 }
  InvLn2Times32 = 46.16624130844683;
  { ln2/32, split so that N * Hi is exact and the product does not lose bits }
  Ln2Over32Hi = 0.02166084898635745;
  Ln2Over32Lo = 4.061408397093569e-10;

  { Beyond these exp overflows or flushes to zero; the solver never gets near
    them, but the function should be safe on its own. }
  ExpUpperLimit = 709.78;
  ExpLowerLimit = -708.0;

  { tanh and coth are +/-1 to within a double's resolution past this. }
  TanhSaturation = 19.0;
  { Below this the exp form loses bits to cancellation, so use the series. }
  SmallArgument = 1.0e-4;

  OneThird = 1.0 / 3.0;
  OneSixth = 1.0 / 6.0;
  OneTwentyFourth = 1.0 / 24.0;

  Ln2 = 0.69314718055994530942;
  Sqrt2 = 1.41421356237309504880;
  OneOver7 = 1.0 / 7.0;
  OneOver9 = 1.0 / 9.0;
  OneOver11 = 1.0 / 11.0;
  OneOver13 = 1.0 / 13.0;

  { pi/2 split so the quarter-turn reduction stays exact for the arguments the
    LFOs produce }
  HalfPiHi = 1.5707963109016418;
  HalfPiLo = 1.5893254712295857e-08;
  TwoOverPi = 0.6366197723675814;

  OneOver4Fact = 1.0 / 24.0;
  OneOver5Fact = 1.0 / 120.0;
  OneOver6Fact = 1.0 / 720.0;
  OneOver7Fact = 1.0 / 5040.0;
  OneOver8Fact = 1.0 / 40320.0;
  OneOver9Fact = 1.0 / 362880.0;
  OneOver10Fact = 1.0 / 3628800.0;
  OneOver11Fact = 1.0 / 39916800.0;

  { 2^(j/32), j = 0..31 }
  TwoPowTable: array[0..31] of Double = (
    1.0, 1.0218971486541166,
    1.0442737824274138, 1.0671404006768237,
    1.0905077326652577, 1.1143867425958924,
    1.1387886347566916, 1.1637248587775775,
    1.189207115002721, 1.215247359980469,
    1.241857812073484, 1.2690509571917332,
    1.2968395546510096, 1.3252366431597413,
    1.3542555469368927, 1.383909881963832,
    1.4142135623730951, 1.4451808069770467,
    1.4768261459394993, 1.5091644275934228,
    1.5422108254079407, 1.5759808451078865,
    1.6104903319492543, 1.645755478153965,
    1.681792830507429, 1.718619298122478,
    1.7562521603732995, 1.7947090750031072,
    1.8340080864093424, 1.8741676341103,
    1.9152065613971474, 1.9571441241754002
  );

function FastExp(X: Double): Double;
var
  R, P, Scale: Double;
  N, K, J: Integer;
  Bits: UInt64;
begin
  if X >= ExpUpperLimit then
    Exit(1.0e308);
  if X <= ExpLowerLimit then
    Exit(0.0);

  N := Round(X * InvLn2Times32);

  // two-part reduction: N * Hi is exact, so only the tiny Lo term rounds
  R := X - N * Ln2Over32Hi;
  R := R - N * Ln2Over32Lo;

  // exp(R) for |R| <= ln2/64; the degree-5 term would sit around 1e-14
  P := 1.0 + R * (1.0 + R * (0.5 + R * (OneSixth + R * OneTwentyFourth)));

  // floor division: "and 31" then subtract keeps K correct for negative N,
  // which a shr would not (Delphi's shr on Integer is logical, not arithmetic)
  J := N and 31;
  K := (N - J) div 32;

  Bits := UInt64(K + 1023) shl 52;
  Scale := PDouble(@Bits)^;

  Result := Scale * TwoPowTable[J] * P;
end;

function QuickExp(X: Double): Double;
begin
{$IFDEF CPUX86}
  Result := System.Exp(X);
{$ELSE}
  Result := FastExp(X);
{$ENDIF}
end;

function QuickLog(X: Double): Double;
begin
{$IFDEF CPUX86}
  Result := System.Ln(X);
{$ELSE}
  Result := FastLog(X);
{$ENDIF}
end;

function QuickCos(X: Double): Double;
begin
{$IFDEF CPUX86}
  Result := System.Cos(X);
{$ELSE}
  Result := FastCos(X);
{$ENDIF}
end;

function FastMathExpBackend: string;
begin
{$IFDEF CPUX86}
  Result := 'x87 hardware (System.Exp / Ln / Cos)';
{$ELSE}
  Result := 'software (FastExp / FastLog / FastCos)';
{$ENDIF}
end;

function FastLog(X: Double): Double;
var
  Bits: UInt64;
  E: Integer;
  M, F, F2, P: Double;
begin
  if X <= 0.0 then
    Exit(-1.0e308);

  // split off the exponent, leaving a mantissa in [1, 2)
  Bits := PUInt64(@X)^;
  E := Integer((Bits shr 52) and $7FF) - 1023;
  if E = -1023 then
    Exit(-1.0e308);   // zero or denormal; callers clamp these anyway

  Bits := (Bits and $000FFFFFFFFFFFFF) or $3FF0000000000000;
  M := PDouble(@Bits)^;

  // centre on 1 so the series converges fastest
  if M > Sqrt2 then
  begin
    M := M * 0.5;
    Inc(E);
  end;

  // ln(m) = 2*atanh((m-1)/(m+1)); |f| <= 0.1716 so f^15 is already negligible
  F := (M - 1.0) / (M + 1.0);
  F2 := F * F;
  P := OneOver13;
  P := P * F2 + OneOver11;
  P := P * F2 + OneOver9;
  P := P * F2 + OneOver7;
  P := P * F2 + 0.2;
  P := P * F2 + OneThird;
  P := P * F2 + 1.0;

  Result := 2.0 * F * P + E * Ln2;
end;

function FastCos(X: Double): Double;
var
  Y, Y2, P: Double;
  N: Integer;
begin
  // reduce to the nearest quarter turn, leaving |Y| <= pi/4
  N := Round(X * TwoOverPi);
  Y := X - N * HalfPiHi;
  Y := Y - N * HalfPiLo;   // two-part, so the reduction keeps its bits
  Y2 := Y * Y;

  case N and 3 of
    1, 3:
      begin
        // sin(Y)
        P := -OneOver11Fact;
        P := P * Y2 + OneOver9Fact;
        P := P * Y2 - OneOver7Fact;
        P := P * Y2 + OneOver5Fact;
        P := P * Y2 - OneSixth;
        P := P * Y2 + 1.0;
        Result := Y * P;
        if (N and 3) = 1 then
          Result := -Result;
      end;
  else
    begin
      // cos(Y)
      P := -OneOver10Fact;
      P := P * Y2 + OneOver8Fact;
      P := P * Y2 - OneOver6Fact;
      P := P * Y2 + OneOver4Fact;
      P := P * Y2 - 0.5;
      P := P * Y2 + 1.0;
      Result := P;
      if (N and 3) = 2 then
        Result := -Result;
    end;
  end;
end;

function FastTanh(X: Double): Double;
var
  E: Double;
begin
  if X > TanhSaturation then
    Exit(1.0);
  if X < -TanhSaturation then
    Exit(-1.0);

  if Abs(X) < SmallArgument then
    // tanh(x) = x - x^3/3 + ...; the exp form would cancel here
    Exit(X - X * X * X * OneThird);

  E := QuickExp(X + X);
  Result := (E - 1.0) / (E + 1.0);
end;

function FastCoth(X: Double): Double;
var
  E: Double;
begin
  if X > TanhSaturation then
    Exit(1.0);
  if X < -TanhSaturation then
    Exit(-1.0);

  if Abs(X) < SmallArgument then
    // coth(x) = 1/x + x/3 - ...
    Exit(1.0 / X + X * OneThird);

  E := QuickExp(X + X);
  Result := (E + 1.0) / (E - 1.0);
end;

end.
