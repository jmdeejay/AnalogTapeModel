unit ChowTape.DSP.Utils;

{
  Small DSP utilities: the level detector used by the compressor and the degrade
  envelope, and the Gaussian noise source behind the wow "variance" control.
}

interface

uses
  System.Math, ChowTape.DSP.Types;

type
  { chowdsp::LevelDetector -- a one-pole follower with separate attack and
    release time constants. }
  TLevelDetector = class
  private
    FExpFactor: Single;
    FYOld: Single;
    FIncreasing: Boolean;
    FTauAtt: Single;
    FTauRel: Single;
    FAbsBuffer: array of Single;
    function ProcessSampleInternal(X: Single; var Increasing: Boolean;
      var YOld: Single): Single; inline;
  public
    procedure Prepare(SampleRate: Double; MaxBlockSize: Integer);
    procedure Reset;
    procedure SetParameters(AttackTimeMs, ReleaseTimeMs: Single);
    function ProcessSample(X: Single): Single; inline;
    { Writes the detected level of BufferIn into channel 0 of LevelOut. }
    procedure ProcessBlock(BufferIn: TAudioBuffer; LevelOut: PSingle;
      NumSamples: Integer);
  end;

  { Normally-distributed white noise (chowdsp::Noise, Normal type). }
  TNoiseGenerator = class
  private
    FRandom: TRandom;
    FGain: Single;
  public
    constructor Create;
    procedure SetGainLinear(NewGain: Single);
    procedure Process(Buffer: PSingle; NumSamples: Integer);
  end;

implementation

{ TLevelDetector }

function CalcTimeConstant(TimeMs, ExpFactor: Single): Single;
begin
  if TimeMs < 1.0e-3 then
    Result := 0.0
  else
    Result := 1.0 - Exp(ExpFactor / TimeMs);
end;

procedure TLevelDetector.Prepare(SampleRate: Double; MaxBlockSize: Integer);
begin
  FExpFactor := -1000.0 / SampleRate;
  SetLength(FAbsBuffer, MaxBlockSize);
  Reset;
end;

procedure TLevelDetector.Reset;
begin
  FYOld := 0.0;
  FIncreasing := True;
end;

procedure TLevelDetector.SetParameters(AttackTimeMs, ReleaseTimeMs: Single);
begin
  FTauAtt := CalcTimeConstant(AttackTimeMs, FExpFactor);
  FTauRel := CalcTimeConstant(ReleaseTimeMs, FExpFactor);
end;

function TLevelDetector.ProcessSampleInternal(X: Single; var Increasing: Boolean;
  var YOld: Single): Single;
var
  Tau: Single;
begin
  if Increasing then
    Tau := FTauAtt
  else
    Tau := FTauRel;

  X := YOld + Tau * (X - YOld);

  Increasing := X > YOld;
  YOld := X;
  Result := X;
end;

function TLevelDetector.ProcessSample(X: Single): Single;
begin
  Result := ProcessSampleInternal(X, FIncreasing, FYOld);
end;

procedure TLevelDetector.ProcessBlock(BufferIn: TAudioBuffer; LevelOut: PSingle;
  NumSamples: Integer);
var
  N, Ch, NumIn: Integer;
  L, S: PSingleArray;
  NormGain: Single;
  Increasing: Boolean;
  YOld: Single;
begin
  L := PSingleArray(LevelOut);
  NumIn := BufferIn.NumChannels;

  S := PSingleArray(BufferIn.Channels[0]);
  for N := 0 to NumSamples - 1 do
    L^[N] := Abs(S^[N]);

  if NumIn > 1 then
  begin
    for Ch := 1 to NumIn - 1 do
    begin
      S := PSingleArray(BufferIn.Channels[Ch]);
      for N := 0 to NumSamples - 1 do
        L^[N] := L^[N] + Abs(S^[N]);
    end;
    NormGain := 1.0 / NumIn;
    for N := 0 to NumSamples - 1 do
      L^[N] := L^[N] * NormGain;
  end;

  Increasing := FIncreasing;
  YOld := FYOld;
  for N := 0 to NumSamples - 1 do
    L^[N] := ProcessSampleInternal(L^[N], Increasing, YOld);
  FIncreasing := Increasing;
  FYOld := YOld;
end;

{ TNoiseGenerator }

constructor TNoiseGenerator.Create;
begin
  inherited Create;
  FRandom := CreateRandom;
  FGain := 1.0;
end;

procedure TNoiseGenerator.SetGainLinear(NewGain: Single);
begin
  FGain := NewGain;
end;

procedure TNoiseGenerator.Process(Buffer: PSingle; NumSamples: Integer);
var
  N: Integer;
  P: PSingleArray;
  Radius, Theta, U: Single;
const
  InvSqrt2 = 0.70710678118654752440;
begin
  P := PSingleArray(Buffer);
  for N := 0 to NumSamples - 1 do
  begin
    // Box-Muller transform, matching chowdsp::NoiseHelpers::normal
    U := 1.0 - FRandom.NextFloat;
    if U <= 0.0 then
      U := 1.0e-20;
    Radius := Sqrt(-2.0 * Ln(U));
    Theta := TwoPiS * FRandom.NextFloat;
    P^[N] := Radius * Sin(Theta) * InvSqrt2 * FGain;
  end;
end;

end.
