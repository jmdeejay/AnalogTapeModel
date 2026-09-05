unit ChowTape.DSP.Oversampling;

{
  Multi-stage 2x oversampling, ported from juce::dsp::Oversampling together with
  the two half-band filter designs it relies on
  (FilterDesign::designIIRLowpassHalfBandPolyphaseAllpassMethod and
  ::designFIRLowpassHalfBandEquirippleMethod).

  Everything runs in double precision: the hysteresis chain needs it anyway, and
  using one implementation for both the tape and compression stages keeps the
  latency figures consistent.
}

interface

uses
  System.Math, System.Generics.Collections, ChowTape.DSP.Types;

const
  { Power of two so the wrap is a mask. Only ever holds a sub-sample delay. }
  FracDelaySize = 16;

type
  TOSFilterType = (osPolyphaseIIR, osEquirippleFIR);

  { One 2x (or 1x, for the dummy) stage. }
  TOversamplingStage = class
  protected
    FBuffer: TAudioBufferD;
    FNumChannels: Integer;
    FFactor: Integer;
  public
    constructor Create(ANumChannels, AFactor: Integer);
    destructor Destroy; override;
    procedure InitProcessing(MaxSamplesBefore: Integer); virtual;
    procedure Reset; virtual;
    function GetLatencyInSamples: Double; virtual;
    procedure ProcessSamplesUp(Input: TAudioBufferD); virtual; abstract;
    procedure ProcessSamplesDown(Output: TAudioBufferD); virtual; abstract;
    function GetProcessedSamples(NumSamples: Integer): TAudioBufferD;
    property Factor: Integer read FFactor;
    property Buffer: TAudioBufferD read FBuffer;
  end;

  TOversamplingDummy = class(TOversamplingStage)
  public
    constructor Create(ANumChannels: Integer);
    procedure ProcessSamplesUp(Input: TAudioBufferD); override;
    procedure ProcessSamplesDown(Output: TAudioBufferD); override;
  end;

  TOversampling2TimesPolyphaseIIR = class(TOversamplingStage)
  private
    FCoefficientsUp: TDoubleArray;
    FCoefficientsDown: TDoubleArray;
    FLatency: Double;
    FV1Up: array of Double;   // NumChannels * Length(CoefficientsUp)
    FV1Down: array of Double;
    FDelayDown: array of Double;
  public
    constructor Create(ANumChannels: Integer;
      TransitionWidthUp, StopbandDbUp, TransitionWidthDown, StopbandDbDown: Double);
    procedure InitProcessing(MaxSamplesBefore: Integer); override;
    procedure Reset; override;
    function GetLatencyInSamples: Double; override;
    procedure ProcessSamplesUp(Input: TAudioBufferD); override;
    procedure ProcessSamplesDown(Output: TAudioBufferD); override;
  end;

  TOversampling2TimesEquirippleFIR = class(TOversamplingStage)
  private
    FCoefficientsUp: TDoubleArray;
    FCoefficientsDown: TDoubleArray;
    FStateUp: array of Double;
    FStateDown: array of Double;
    FStateDown2: array of Double;
    FPosition: array of Integer;
    FNUp, FNDown, FNDiv2Down, FNDiv4Down: Integer;
  public
    constructor Create(ANumChannels: Integer;
      TransitionWidthUp, StopbandDbUp, TransitionWidthDown, StopbandDbDown: Double);
    procedure InitProcessing(MaxSamplesBefore: Integer); override;
    procedure Reset; override;
    function GetLatencyInSamples: Double; override;
    procedure ProcessSamplesUp(Input: TAudioBufferD); override;
    procedure ProcessSamplesDown(Output: TAudioBufferD); override;
  end;

  { Thiran-interpolated sub-sample delay used for integer-latency compensation. }
  TFractionalDelayD = class
  private
    FBuffer: array of Double;
    FTotalSize: Integer;
    FNumChannels: Integer;
    FWritePos: array of Integer;
    FReadPos: array of Integer;
    FState: array of Double;
    FDelayInt: Integer;
    FDelayFrac: Double;
    FAlpha: Double;
  public
    procedure Prepare(ANumChannels: Integer);
    procedure Reset;
    procedure SetDelay(NewDelay: Double);
    procedure Process(Block: TAudioBufferD);
  end;

  TOversampling = class
  private
    FStages: TObjectList<TOversamplingStage>;
    FNumChannels: Integer;
    FFactorOversampling: Integer;
    FShouldUseIntegerLatency: Boolean;
    FFractionalDelay: Double;
    FDelay: TFractionalDelayD;
    FIsReady: Boolean;
    procedure AddStage(FilterType: TOSFilterType;
      TwUp, StopUp, TwDown, StopDown: Double);
    function GetUncompensatedLatency: Double;
    procedure UpdateDelayLine;
  public
    constructor Create(ANumChannels, AFactor: Integer; FilterType: TOSFilterType;
      IsMaximumQuality: Boolean = True; UseIntegerLatency: Boolean = False);
    destructor Destroy; override;
    procedure InitProcessing(MaxSamplesPerBlock: Integer);
    procedure Reset;
    function GetLatencyInSamples: Double;
    function GetOversamplingFactor: Integer;
    { Upsamples InputBlock and returns the (internally owned) oversampled block. }
    function ProcessSamplesUp(Input: TAudioBufferD): TAudioBufferD;
    procedure ProcessSamplesDown(Output: TAudioBufferD);
  end;

{ Half-band filter designs ---------------------------------------------------}

procedure DesignIIRHalfBandPolyphase(NormalisedTransitionWidth, StopbandDb: Double;
  out Coefficients: TDoubleArray; out LatencySamples: Double);
function DesignFIRHalfBandEquiripple(NormalisedTransitionWidth, AmplitudeDb: Double): TDoubleArray;

implementation

{ ---------------------------------------------------------------------------
  Minimal complex + polynomial helpers, only what the two designs need.
  --------------------------------------------------------------------------- }
type
  TComplex = record
    Re, Im: Double;
  end;

function CMake(ARe, AIm: Double): TComplex; inline;
begin
  Result.Re := ARe;
  Result.Im := AIm;
end;

function CAdd(const A, B: TComplex): TComplex; inline;
begin
  Result.Re := A.Re + B.Re;
  Result.Im := A.Im + B.Im;
end;

function CMul(const A, B: TComplex): TComplex; inline;
begin
  Result.Re := A.Re * B.Re - A.Im * B.Im;
  Result.Im := A.Re * B.Im + A.Im * B.Re;
end;

function CDiv(const A, B: TComplex): TComplex; inline;
var
  D: Double;
begin
  D := B.Re * B.Re + B.Im * B.Im;
  Result.Re := (A.Re * B.Re + A.Im * B.Im) / D;
  Result.Im := (A.Im * B.Re - A.Re * B.Im) / D;
end;

function CScale(const A: TComplex; S: Double): TComplex; inline;
begin
  Result.Re := A.Re * S;
  Result.Im := A.Im * S;
end;

function CArg(const A: TComplex): Double; inline;
begin
  Result := ArcTan2(A.Im, A.Re);
end;

function CAbs(const A: TComplex): Double; inline;
begin
  Result := Sqrt(A.Re * A.Re + A.Im * A.Im);
end;

{ exp(-2*pi*f*i / fs) }
function CExpJW(Frequency, SampleRate: Double): TComplex; inline;
var
  Theta: Double;
begin
  Theta := -2.0 * PiD * Frequency / SampleRate;
  Result.Re := Cos(Theta);
  Result.Im := Sin(Theta);
end;

function PolyMul(const A, B: TDoubleArray): TDoubleArray;
var
  I, J: Integer;
begin
  SetLength(Result, Length(A) + Length(B) - 1);
  for I := 0 to High(Result) do
    Result[I] := 0.0;
  for I := 0 to High(A) do
    for J := 0 to High(B) do
      Result[I + J] := Result[I + J] + A[I] * B[J];
end;

function PolyAdd(const A, B: TDoubleArray): TDoubleArray;
var
  I, N: Integer;
begin
  N := Max(Length(A), Length(B));
  SetLength(Result, N);
  for I := 0 to N - 1 do
  begin
    Result[I] := 0.0;
    if I <= High(A) then Result[I] := Result[I] + A[I];
    if I <= High(B) then Result[I] := Result[I] + B[I];
  end;
end;

{ ---------------------------------------------------------------------------
  designIIRLowpassHalfBandPolyphaseAllpassMethod
  --------------------------------------------------------------------------- }
procedure DesignIIRHalfBandPolyphase(NormalisedTransitionWidth, StopbandDb: Double;
  out Coefficients: TDoubleArray; out LatencySamples: Double);
var
  Wt, Ds, K, Kp, E, Q, K1, Q1: Double;
  N, NN, I, M, Idx: Integer;
  Ai: TDoubleArray;
  Num, Den, Delta, Wi, Api: Double;
  Num1, Den1, Num2, Den2, NumF1, NumF2, Numer, Denom: TDoubleArray;
  Sect, DenSect: TDoubleArray;
  FullCoeffs: TDoubleArray;
  Order: Integer;
  Inversion: Double;
  Jw, Factor, CNum, CDen: TComplex;
begin
  Wt := 2.0 * PiD * NormalisedTransitionWidth;
  Ds := Power(10.0, StopbandDb * 0.05);

  K := Power(Tan((PiD - Wt) / 4.0), 2.0);
  Kp := Sqrt(1.0 - K * K);
  E := (1.0 - Sqrt(Kp)) / (1.0 + Sqrt(Kp)) * 0.5;
  Q := E + 2.0 * Power(E, 5.0) + 15.0 * Power(E, 9.0) + 150.0 * Power(E, 13.0);

  K1 := Ds * Ds / (1.0 - Ds * Ds);
  N := Round(Ceil(Ln(K1 * K1 / 16.0) / Ln(Q)));

  if N mod 2 = 0 then
    Inc(N);
  if N = 1 then
    N := 3;

  Q1 := Power(Q, N);
  K1 := 4.0 * Sqrt(Q1);

  NN := (N - 1) div 2;
  SetLength(Ai, NN);

  for I := 1 to NN do
  begin
    Num := 0.0;
    Delta := 1.0;
    M := 0;
    while Abs(Delta) > 1e-100 do
    begin
      Delta := Power(-1.0, M) * Power(Q, M * (M + 1)) *
        Sin((2 * M + 1) * PiD * I / N);
      Num := Num + Delta;
      Inc(M);
    end;
    Num := Num * 2.0 * Power(Q, 0.25);

    Den := 0.0;
    Delta := 1.0;
    M := 1;
    while Abs(Delta) > 1e-100 do
    begin
      Delta := Power(-1.0, M) * Power(Q, M * M) *
        Cos(M * 2.0 * PiD * I / N);
      Den := Den + Delta;
      Inc(M);
    end;
    Den := 1.0 + 2.0 * Den;

    Wi := Num / Den;
    Api := Sqrt((1.0 - Wi * Wi * K) * (1.0 - Wi * Wi / K)) / (1.0 + Wi * Wi);
    Ai[I - 1] := (1.0 - Api) / (1.0 + Api);
  end;

  // The processing coefficients are simply the even-indexed alphas (direct
  // path) followed by the odd-indexed ones (delayed path).
  SetLength(Coefficients, NN);
  Idx := 0;
  I := 0;
  while I < NN do
  begin
    Coefficients[Idx] := Ai[I];
    Inc(Idx);
    Inc(I, 2);
  end;
  I := 1;
  while I < NN do
  begin
    Coefficients[Idx] := Ai[I];
    Inc(Idx);
    Inc(I, 2);
  end;

  // Latency: build the equivalent high-order IIR and read its phase near DC.
  Num1 := TDoubleArray.Create(1.0);
  Den1 := TDoubleArray.Create(1.0);
  Num2 := TDoubleArray.Create(1.0);
  Den2 := TDoubleArray.Create(1.0);

  I := 0;
  while I < NN do
  begin
    Sect := TDoubleArray.Create(Ai[I], 0.0, 1.0);
    DenSect := TDoubleArray.Create(1.0, 0.0, Ai[I]);
    Num1 := PolyMul(Num1, Sect);
    Den1 := PolyMul(Den1, DenSect);
    Inc(I, 2);
  end;

  // delayed path always starts with a pure one-sample delay
  Num2 := PolyMul(Num2, TDoubleArray.Create(0.0, 1.0));
  Den2 := PolyMul(Den2, TDoubleArray.Create(1.0, 0.0));

  I := 1;
  while I < NN do
  begin
    Sect := TDoubleArray.Create(Ai[I], 0.0, 1.0);
    DenSect := TDoubleArray.Create(1.0, 0.0, Ai[I]);
    Num2 := PolyMul(Num2, Sect);
    Den2 := PolyMul(Den2, DenSect);
    Inc(I, 2);
  end;

  NumF1 := PolyMul(Num1, Den2);
  NumF2 := PolyMul(Num2, Den1);
  Numer := PolyAdd(NumF1, NumF2);
  Denom := PolyMul(Den1, Den2);

  Inversion := 1.0 / Denom[0];
  Order := High(Numer);
  SetLength(FullCoeffs, (Order + 1) + High(Denom));
  for I := 0 to Order do
    FullCoeffs[I] := Numer[I] * Inversion;
  for I := 1 to High(Denom) do
    FullCoeffs[Order + I] := Denom[I] * Inversion;

  Jw := CExpJW(0.0001, 1.0);
  CNum := CMake(0.0, 0.0);
  Factor := CMake(1.0, 0.0);
  for I := 0 to Order do
  begin
    CNum := CAdd(CNum, CScale(Factor, FullCoeffs[I]));
    Factor := CMul(Factor, Jw);
  end;

  CDen := CMake(1.0, 0.0);
  Factor := Jw;
  for I := Order + 1 to 2 * Order do
  begin
    CDen := CAdd(CDen, CScale(Factor, FullCoeffs[I]));
    Factor := CMul(Factor, Jw);
  end;

  LatencySamples := -CArg(CDiv(CNum, CDen)) / (0.0001 * 2.0 * PiD);
end;

{ ---------------------------------------------------------------------------
  designFIRLowpassHalfBandEquirippleMethod
  --------------------------------------------------------------------------- }
function GetPartialImpulseResponseHn(N: Integer; Kp: Double): TDoubleArray;
var
  Alpha, Ai, Hn: TDoubleArray;
  K: Integer;
  C1, C2, C3, C4: Double;
begin
  SetLength(Alpha, 2 * N + 1);
  for K := 0 to High(Alpha) do
    Alpha[K] := 0.0;

  Alpha[2 * N] := 1.0 / Power(1.0 - Kp * Kp, N);

  if N > 0 then
    Alpha[2 * N - 2] := -(2.0 * N * Kp * Kp + 1.0) * Alpha[2 * N];

  if N > 1 then
    Alpha[2 * N - 4] :=
      -(4.0 * N + 1.0 + (N - 1) * (2.0 * N - 1) * Kp * Kp) / (2.0 * N) * Alpha[2 * N - 2]
      - (2.0 * N + 1.0) * ((N + 1) * Kp * Kp + 1.0) / (2.0 * N) * Alpha[2 * N];

  for K := N downto 3 do
  begin
    C1 := (3.0 * (N * (N + 2) - K * (K - 2)) + 2.0 * K - 3.0 +
      2.0 * (K - 2) * (2 * K - 3) * Kp * Kp) * Alpha[2 * K - 4];
    C2 := (3.0 * (N * (N + 2) - (K - 1) * (K + 1)) + 2.0 * (2 * K - 1) +
      2.0 * K * (2 * K - 1) * Kp * Kp) * Alpha[2 * K - 2];
    C3 := (N * (N + 2) - (K - 1) * (K + 1)) * Alpha[2 * K];
    C4 := (N * (N + 2) - (K - 3) * (K - 1));
    Alpha[2 * K - 6] := -(C1 + C2 + C3) / C4;
  end;

  SetLength(Ai, 2 * N + 2);
  for K := 0 to High(Ai) do
    Ai[K] := 0.0;
  for K := 0 to N do
    Ai[2 * K + 1] := Alpha[2 * K] / (2.0 * K + 1.0);

  SetLength(Hn, 4 * N + 3);
  for K := 0 to High(Hn) do
    Hn[K] := 0.0;
  for K := 0 to N do
  begin
    Hn[2 * N + 1 + (2 * K + 1)] := 0.5 * Ai[2 * K + 1];
    Hn[2 * N + 1 - (2 * K + 1)] := 0.5 * Ai[2 * K + 1];
  end;

  Result := Hn;
end;

function FIRMagnitudeForFrequency(const C: TDoubleArray; Frequency, SampleRate: Double): Double;
var
  Jw, Factor, Numer: TComplex;
  I: Integer;
begin
  Jw := CExpJW(Frequency, SampleRate);
  Numer := CMake(0.0, 0.0);
  Factor := CMake(1.0, 0.0);
  for I := 0 to High(C) do
  begin
    Numer := CAdd(Numer, CScale(Factor, C[I]));
    Factor := CMul(Factor, Jw);
  end;
  Result := CAbs(Numer);
end;

function DesignFIRHalfBandEquiripple(NormalisedTransitionWidth, AmplitudeDb: Double): TDoubleArray;
var
  WpT, Kp, A, B, NNorm, W01, Om01: Double;
  N, I, Diff: Integer;
  Hn, Hnm, Padded, Hh: TDoubleArray;
begin
  WpT := (0.5 - NormalisedTransitionWidth) * PiD;

  N := Round(Ceil((AmplitudeDb - 18.18840664 * WpT + 33.64775300) /
    (18.54155181 * WpT - 29.13196871)));
  Kp := (N * WpT - 1.57111377 * N + 0.00665857) / (-1.01927560 * N + 0.37221484);
  A := (0.01525753 * N + 0.03682344 + 9.24760314 / N) * Kp + 1.01701407 + 0.73512298 / N;
  B := (0.00233667 * N - 1.35418408 + 5.75145813 / N) * Kp + 1.02999650 - 0.72759508 / N;

  Hn := GetPartialImpulseResponseHn(N, Kp);
  Hnm := GetPartialImpulseResponseHn(N - 1, Kp);

  Diff := (Length(Hn) - Length(Hnm)) div 2;
  SetLength(Padded, Length(Hnm) + 2 * Diff);
  for I := 0 to High(Padded) do
    Padded[I] := 0.0;
  for I := 0 to High(Hnm) do
    Padded[I + Diff] := Hnm[I];
  Hnm := Padded;

  SetLength(Hh, Length(Hn));
  for I := 0 to High(Hn) do
    Hh[I] := A * Hn[I] + B * Hnm[I];

  if N mod 2 = 0 then
    NNorm := 2.0 * FIRMagnitudeForFrequency(Hh, 0.5, 1.0)
  else
  begin
    W01 := Sqrt(Kp * Kp + (1.0 - Kp * Kp) * Power(Cos(PiD / (2.0 * N + 1.0)), 2.0));
    if Abs(W01) > 1.0 then
      NNorm := 2.0 * FIRMagnitudeForFrequency(Hh, 0.5, 1.0)
    else
    begin
      Om01 := ArcCos(-W01);
      NNorm := -2.0 * FIRMagnitudeForFrequency(Hh, Om01 / (2.0 * PiD), 1.0);
    end;
  end;

  SetLength(Result, Length(Hn));
  for I := 0 to High(Hn) do
    Result[I] := (A * Hn[I] + B * Hnm[I]) / NNorm;

  Result[2 * N + 1] := 0.5;
end;

{ TOversamplingStage }

constructor TOversamplingStage.Create(ANumChannels, AFactor: Integer);
begin
  inherited Create;
  FNumChannels := ANumChannels;
  FFactor := AFactor;
  FBuffer := TAudioBufferD.Create;
end;

destructor TOversamplingStage.Destroy;
begin
  FBuffer.Free;
  inherited Destroy;
end;

procedure TOversamplingStage.InitProcessing(MaxSamplesBefore: Integer);
begin
  FBuffer.SetSize(FNumChannels, MaxSamplesBefore * FFactor);
end;

procedure TOversamplingStage.Reset;
begin
  FBuffer.Clear;
end;

function TOversamplingStage.GetLatencyInSamples: Double;
begin
  Result := 0.0;
end;

function TOversamplingStage.GetProcessedSamples(NumSamples: Integer): TAudioBufferD;
begin
  FBuffer.NumSamples := NumSamples;
  Result := FBuffer;
end;

{ TOversamplingDummy }

constructor TOversamplingDummy.Create(ANumChannels: Integer);
begin
  inherited Create(ANumChannels, 1);
end;

procedure TOversamplingDummy.ProcessSamplesUp(Input: TAudioBufferD);
var
  Ch: Integer;
begin
  for Ch := 0 to Input.NumChannels - 1 do
    Move(Input.Channels[Ch]^, FBuffer.Channels[Ch]^, Input.NumSamples * SizeOf(Double));
end;

procedure TOversamplingDummy.ProcessSamplesDown(Output: TAudioBufferD);
var
  Ch: Integer;
begin
  for Ch := 0 to Output.NumChannels - 1 do
    Move(FBuffer.Channels[Ch]^, Output.Channels[Ch]^, Output.NumSamples * SizeOf(Double));
end;

{ TOversampling2TimesPolyphaseIIR }

constructor TOversampling2TimesPolyphaseIIR.Create(ANumChannels: Integer;
  TransitionWidthUp, StopbandDbUp, TransitionWidthDown, StopbandDbDown: Double);
var
  LatUp, LatDown: Double;
begin
  inherited Create(ANumChannels, 2);
  DesignIIRHalfBandPolyphase(TransitionWidthUp, StopbandDbUp, FCoefficientsUp, LatUp);
  DesignIIRHalfBandPolyphase(TransitionWidthDown, StopbandDbDown, FCoefficientsDown, LatDown);
  FLatency := LatUp + LatDown;

  SetLength(FV1Up, ANumChannels * Length(FCoefficientsUp));
  SetLength(FV1Down, ANumChannels * Length(FCoefficientsDown));
  SetLength(FDelayDown, ANumChannels);
end;

procedure TOversampling2TimesPolyphaseIIR.InitProcessing(MaxSamplesBefore: Integer);
begin
  inherited InitProcessing(MaxSamplesBefore);
end;

procedure TOversampling2TimesPolyphaseIIR.Reset;
var
  I: Integer;
begin
  inherited Reset;
  for I := 0 to High(FV1Up) do FV1Up[I] := 0.0;
  for I := 0 to High(FV1Down) do FV1Down[I] := 0.0;
  for I := 0 to High(FDelayDown) do FDelayDown[I] := 0.0;
end;

function TOversampling2TimesPolyphaseIIR.GetLatencyInSamples: Double;
begin
  Result := FLatency;
end;

procedure TOversampling2TimesPolyphaseIIR.ProcessSamplesUp(Input: TAudioBufferD);
var
  NumStages, DelayedStages, DirectStages, NumSamples: Integer;
  Ch, I, N, VBase: Integer;
  Src, Dst: PDoubleBuf;
  Inp, Outp, Alpha: Double;
begin
  NumStages := Length(FCoefficientsUp);
  DelayedStages := NumStages div 2;
  DirectStages := NumStages - DelayedStages;
  NumSamples := Input.NumSamples;

  for Ch := 0 to Input.NumChannels - 1 do
  begin
    Dst := PDoubleBuf(FBuffer.Channels[Ch]);
    Src := PDoubleBuf(Input.Channels[Ch]);
    VBase := Ch * NumStages;

    for I := 0 to NumSamples - 1 do
    begin
      Inp := Src^[I];
      for N := 0 to DirectStages - 1 do
      begin
        Alpha := FCoefficientsUp[N];
        Outp := Alpha * Inp + FV1Up[VBase + N];
        FV1Up[VBase + N] := Inp - Alpha * Outp;
        Inp := Outp;
      end;
      Dst^[I shl 1] := Inp;

      Inp := Src^[I];
      for N := DirectStages to NumStages - 1 do
      begin
        Alpha := FCoefficientsUp[N];
        Outp := Alpha * Inp + FV1Up[VBase + N];
        FV1Up[VBase + N] := Inp - Alpha * Outp;
        Inp := Outp;
      end;
      Dst^[(I shl 1) + 1] := Inp;
    end;

    for N := 0 to NumStages - 1 do
      SnapToZero(FV1Up[VBase + N]);
  end;
end;

procedure TOversampling2TimesPolyphaseIIR.ProcessSamplesDown(Output: TAudioBufferD);
var
  NumStages, DelayedStages, DirectStages, NumSamples: Integer;
  Ch, I, N, VBase: Integer;
  Src, Dst: PDoubleBuf;
  Inp, Outp, Alpha, DirectOut, Delay: Double;
begin
  NumStages := Length(FCoefficientsDown);
  DelayedStages := NumStages div 2;
  DirectStages := NumStages - DelayedStages;
  NumSamples := Output.NumSamples;

  for Ch := 0 to Output.NumChannels - 1 do
  begin
    Src := PDoubleBuf(FBuffer.Channels[Ch]);
    Dst := PDoubleBuf(Output.Channels[Ch]);
    VBase := Ch * NumStages;
    Delay := FDelayDown[Ch];

    for I := 0 to NumSamples - 1 do
    begin
      Inp := Src^[I shl 1];
      for N := 0 to DirectStages - 1 do
      begin
        Alpha := FCoefficientsDown[N];
        Outp := Alpha * Inp + FV1Down[VBase + N];
        FV1Down[VBase + N] := Inp - Alpha * Outp;
        Inp := Outp;
      end;
      DirectOut := Inp;

      Inp := Src^[(I shl 1) + 1];
      for N := DirectStages to NumStages - 1 do
      begin
        Alpha := FCoefficientsDown[N];
        Outp := Alpha * Inp + FV1Down[VBase + N];
        FV1Down[VBase + N] := Inp - Alpha * Outp;
        Inp := Outp;
      end;

      Dst^[I] := (Delay + DirectOut) * 0.5;
      Delay := Inp;
    end;

    FDelayDown[Ch] := Delay;
    for N := 0 to NumStages - 1 do
      SnapToZero(FV1Down[VBase + N]);
  end;
end;

{ TOversampling2TimesEquirippleFIR }

constructor TOversampling2TimesEquirippleFIR.Create(ANumChannels: Integer;
  TransitionWidthUp, StopbandDbUp, TransitionWidthDown, StopbandDbDown: Double);
begin
  inherited Create(ANumChannels, 2);
  FCoefficientsUp := DesignFIRHalfBandEquiripple(TransitionWidthUp, StopbandDbUp);
  FCoefficientsDown := DesignFIRHalfBandEquiripple(TransitionWidthDown, StopbandDbDown);

  FNUp := Length(FCoefficientsUp);
  FNDown := Length(FCoefficientsDown);
  FNDiv2Down := FNDown div 2;
  FNDiv4Down := FNDiv2Down div 2;

  SetLength(FStateUp, ANumChannels * FNUp);
  SetLength(FStateDown, ANumChannels * FNDown);
  SetLength(FStateDown2, ANumChannels * (FNDiv4Down + 1));
  SetLength(FPosition, ANumChannels);
end;

procedure TOversampling2TimesEquirippleFIR.InitProcessing(MaxSamplesBefore: Integer);
begin
  inherited InitProcessing(MaxSamplesBefore);
end;

procedure TOversampling2TimesEquirippleFIR.Reset;
var
  I: Integer;
begin
  inherited Reset;
  for I := 0 to High(FStateUp) do FStateUp[I] := 0.0;
  for I := 0 to High(FStateDown) do FStateDown[I] := 0.0;
  for I := 0 to High(FStateDown2) do FStateDown2[I] := 0.0;
  for I := 0 to High(FPosition) do FPosition[I] := 0;
end;

function TOversampling2TimesEquirippleFIR.GetLatencyInSamples: Double;
begin
  Result := ((FNUp - 1) + (FNDown - 1)) * 0.5;
end;

procedure TOversampling2TimesEquirippleFIR.ProcessSamplesUp(Input: TAudioBufferD);
var
  N, NDiv2, NumSamples, Ch, I, K, Base: Integer;
  Src, Dst: PDoubleBuf;
  Outp: Double;
begin
  N := FNUp;
  NDiv2 := N div 2;
  NumSamples := Input.NumSamples;

  for Ch := 0 to Input.NumChannels - 1 do
  begin
    Dst := PDoubleBuf(FBuffer.Channels[Ch]);
    Src := PDoubleBuf(Input.Channels[Ch]);
    Base := Ch * N;

    for I := 0 to NumSamples - 1 do
    begin
      FStateUp[Base + N - 1] := 2.0 * Src^[I];

      Outp := 0.0;
      K := 0;
      while K < NDiv2 do
      begin
        Outp := Outp + (FStateUp[Base + K] + FStateUp[Base + N - K - 1]) * FCoefficientsUp[K];
        Inc(K, 2);
      end;

      Dst^[I shl 1] := Outp;
      Dst^[(I shl 1) + 1] := FStateUp[Base + NDiv2 + 1] * FCoefficientsUp[NDiv2];

      K := 0;
      while K < N - 2 do
      begin
        FStateUp[Base + K] := FStateUp[Base + K + 2];
        Inc(K, 2);
      end;
    end;
  end;
end;

procedure TOversampling2TimesEquirippleFIR.ProcessSamplesDown(Output: TAudioBufferD);
var
  N, NDiv2, NDiv4, NumSamples, Ch, I, K, Base, Base2, Pos: Integer;
  Src, Dst: PDoubleBuf;
  Outp: Double;
begin
  N := FNDown;
  NDiv2 := FNDiv2Down;
  NDiv4 := FNDiv4Down;
  NumSamples := Output.NumSamples;

  for Ch := 0 to Output.NumChannels - 1 do
  begin
    Src := PDoubleBuf(FBuffer.Channels[Ch]);
    Dst := PDoubleBuf(Output.Channels[Ch]);
    Base := Ch * N;
    Base2 := Ch * (NDiv4 + 1);
    Pos := FPosition[Ch];

    for I := 0 to NumSamples - 1 do
    begin
      FStateDown[Base + N - 1] := Src^[I shl 1];

      Outp := 0.0;
      K := 0;
      while K < NDiv2 do
      begin
        Outp := Outp + (FStateDown[Base + K] + FStateDown[Base + N - K - 1]) * FCoefficientsDown[K];
        Inc(K, 2);
      end;

      Outp := Outp + FStateDown2[Base2 + Pos] * FCoefficientsDown[NDiv2];
      FStateDown2[Base2 + Pos] := Src^[(I shl 1) + 1];

      Dst^[I] := Outp;

      for K := 0 to N - 3 do
        FStateDown[Base + K] := FStateDown[Base + K + 2];

      if Pos = 0 then
        Pos := NDiv4
      else
        Dec(Pos);
    end;

    FPosition[Ch] := Pos;
  end;
end;

{ TFractionalDelayD }

procedure TFractionalDelayD.Prepare(ANumChannels: Integer);
begin
  FTotalSize := FracDelaySize;
  FNumChannels := ANumChannels;
  SetLength(FBuffer, ANumChannels * FTotalSize);
  SetLength(FWritePos, ANumChannels);
  SetLength(FReadPos, ANumChannels);
  SetLength(FState, ANumChannels);
  Reset;
end;

procedure TFractionalDelayD.Reset;
var
  I: Integer;
begin
  for I := 0 to High(FBuffer) do FBuffer[I] := 0.0;
  for I := 0 to FNumChannels - 1 do
  begin
    FWritePos[I] := 0;
    FReadPos[I] := 0;
    FState[I] := 0.0;
  end;
end;

procedure TFractionalDelayD.SetDelay(NewDelay: Double);
begin
  if NewDelay < 0.0 then NewDelay := 0.0;
  if NewDelay > FTotalSize - 3 then NewDelay := FTotalSize - 3;
  FDelayInt := Floor(NewDelay);
  FDelayFrac := NewDelay - FDelayInt;

  if (FDelayFrac < 0.618) and (FDelayInt >= 1) then
  begin
    FDelayFrac := FDelayFrac + 1.0;
    Dec(FDelayInt);
  end;
  FAlpha := (1.0 - FDelayFrac) / (1.0 + FDelayFrac);
end;

procedure TFractionalDelayD.Process(Block: TAudioBufferD);
var
  Ch, N, Base, Index1, Index2: Integer;
  P: PDoubleBuf;
  V1, V2, Outp: Double;
begin
  for Ch := 0 to Block.NumChannels - 1 do
  begin
    Base := Ch * FTotalSize;
    P := PDoubleBuf(Block.Channels[Ch]);
    for N := 0 to Block.NumSamples - 1 do
    begin
      FBuffer[Base + FWritePos[Ch]] := P^[N];
      // FracDelaySize is a power of two, so these are masks rather than the
      // integer divisions a variable modulo would compile to
      FWritePos[Ch] := (FWritePos[Ch] + FracDelaySize - 1) and (FracDelaySize - 1);

      Index1 := (FReadPos[Ch] + FDelayInt) and (FracDelaySize - 1);
      Index2 := (Index1 + 1) and (FracDelaySize - 1);
      V1 := FBuffer[Base + Index1];
      V2 := FBuffer[Base + Index2];

      Outp := V2 + FAlpha * (V1 - FState[Ch]);
      FState[Ch] := Outp;
      P^[N] := Outp;

      FReadPos[Ch] := (FReadPos[Ch] + FracDelaySize - 1) and (FracDelaySize - 1);
    end;
  end;
end;

{ TOversampling }

constructor TOversampling.Create(ANumChannels, AFactor: Integer;
  FilterType: TOSFilterType; IsMaximumQuality, UseIntegerLatency: Boolean);
var
  N: Integer;
  TwUp, TwDown, GainStartUp, GainStartDown, GainFactorUp, GainFactorDown: Double;
begin
  inherited Create;
  FNumChannels := ANumChannels;
  FShouldUseIntegerLatency := UseIntegerLatency;
  FFactorOversampling := 1;
  FStages := TObjectList<TOversamplingStage>.Create(True);
  FDelay := TFractionalDelayD.Create;

  if AFactor = 0 then
    FStages.Add(TOversamplingDummy.Create(ANumChannels))
  else
    for N := 0 to AFactor - 1 do
    begin
      if IsMaximumQuality then
      begin
        TwUp := 0.10; TwDown := 0.12;
        GainStartUp := -90.0; GainStartDown := -75.0;
        GainFactorUp := 10.0; GainFactorDown := 10.0;
      end
      else
      begin
        TwUp := 0.12; TwDown := 0.15;
        GainStartUp := -70.0; GainStartDown := -60.0;
        GainFactorUp := 8.0; GainFactorDown := 8.0;
      end;

      if N = 0 then
      begin
        TwUp := TwUp * 0.5;
        TwDown := TwDown * 0.5;
      end;

      AddStage(FilterType, TwUp, GainStartUp + GainFactorUp * N,
        TwDown, GainStartDown + GainFactorDown * N);
    end;
end;

destructor TOversampling.Destroy;
begin
  FStages.Free;
  FDelay.Free;
  inherited Destroy;
end;

procedure TOversampling.AddStage(FilterType: TOSFilterType;
  TwUp, StopUp, TwDown, StopDown: Double);
begin
  if FilterType = osPolyphaseIIR then
    FStages.Add(TOversampling2TimesPolyphaseIIR.Create(FNumChannels, TwUp, StopUp, TwDown, StopDown))
  else
    FStages.Add(TOversampling2TimesEquirippleFIR.Create(FNumChannels, TwUp, StopUp, TwDown, StopDown));
  FFactorOversampling := FFactorOversampling * 2;
end;

function TOversampling.GetUncompensatedLatency: Double;
var
  I, Order: Integer;
begin
  Result := 0.0;
  Order := 1;
  for I := 0 to FStages.Count - 1 do
  begin
    Order := Order * FStages[I].Factor;
    Result := Result + FStages[I].GetLatencyInSamples / Order;
  end;
end;

function TOversampling.GetLatencyInSamples: Double;
begin
  Result := GetUncompensatedLatency;
  if FShouldUseIntegerLatency then
    Result := Result + FFractionalDelay;
end;

function TOversampling.GetOversamplingFactor: Integer;
begin
  Result := FFactorOversampling;
end;

procedure TOversampling.InitProcessing(MaxSamplesPerBlock: Integer);
var
  I, CurrentNumSamples: Integer;
begin
  CurrentNumSamples := MaxSamplesPerBlock;
  for I := 0 to FStages.Count - 1 do
  begin
    FStages[I].InitProcessing(CurrentNumSamples);
    CurrentNumSamples := CurrentNumSamples * FStages[I].Factor;
  end;

  FDelay.Prepare(FNumChannels);
  UpdateDelayLine;

  FIsReady := True;
  Reset;
end;

procedure TOversampling.UpdateDelayLine;
var
  Latency: Double;
begin
  Latency := GetUncompensatedLatency;
  FFractionalDelay := 1.0 - (Latency - Floor(Latency));

  if Abs(FFractionalDelay - 1.0) < 1e-9 then
    FFractionalDelay := 0.0
  else if FFractionalDelay < 0.618 then
    FFractionalDelay := FFractionalDelay + 1.0;

  FDelay.SetDelay(FFractionalDelay);
end;

procedure TOversampling.Reset;
var
  I: Integer;
begin
  if FIsReady then
    for I := 0 to FStages.Count - 1 do
      FStages[I].Reset;
  FDelay.Reset;
end;

function TOversampling.ProcessSamplesUp(Input: TAudioBufferD): TAudioBufferD;
var
  I: Integer;
  Block: TAudioBufferD;
begin
  if not FIsReady then
    Exit(nil);

  FStages[0].ProcessSamplesUp(Input);
  Block := FStages[0].GetProcessedSamples(Input.NumSamples * FStages[0].Factor);

  for I := 1 to FStages.Count - 1 do
  begin
    FStages[I].ProcessSamplesUp(Block);
    Block := FStages[I].GetProcessedSamples(Block.NumSamples * FStages[I].Factor);
  end;

  Result := Block;
end;

procedure TOversampling.ProcessSamplesDown(Output: TAudioBufferD);
var
  N, CurrentNumSamples: Integer;
  AudioBlock: TAudioBufferD;
begin
  if not FIsReady then
    Exit;

  CurrentNumSamples := Output.NumSamples;
  for N := 0 to FStages.Count - 2 do
    CurrentNumSamples := CurrentNumSamples * FStages[N].Factor;

  for N := FStages.Count - 1 downto 1 do
  begin
    AudioBlock := FStages[N - 1].GetProcessedSamples(CurrentNumSamples);
    FStages[N].ProcessSamplesDown(AudioBlock);
    CurrentNumSamples := CurrentNumSamples div FStages[N].Factor;
  end;

  FStages[0].ProcessSamplesDown(Output);

  if FShouldUseIntegerLatency and (FFractionalDelay > 0.0) then
    FDelay.Process(Output);
end;

end.
