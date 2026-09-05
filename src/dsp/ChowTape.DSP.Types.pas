unit ChowTape.DSP.Types;

{
  Foundation types shared by the whole DSP chain: an audio buffer, the two
  smoothed-value flavours used by the original plug-in (linear and
  multiplicative), a JUCE-compatible PRNG and assorted maths helpers.

  The smoothing and random behaviour deliberately mirror juce::SmoothedValue and
  juce::Random so that ported processors behave identically.
}

interface

uses
  System.Math;

type
  { Not declared by the RTL, but needed both by the VST ABI (which hands us
    arrays of channel pointers) and by the processor. }
  PPSingle = ^PSingle;
  PPDouble = ^PDouble;

  TFloatArray = array of Single;
  TDoubleArray = array of Double;
  PSingleArray = ^TSingleArray;
  TSingleArray = array[0..MaxInt div SizeOf(Single) - 1] of Single;
  PDoubleBuf = ^TDoubleBuf;
  TDoubleBuf = array[0..MaxInt div SizeOf(Double) - 1] of Double;

  PPSingleArray = ^TPSingleArray;
  TPSingleArray = array[0..63] of PSingle;

{ ---------------------------------------------------------------------------
  TAudioBuffer -- a channels x samples float buffer.

  It either owns its storage or aliases someone else's channel pointers, which
  is what lets the chew/degrade processors carve a long block into short
  sub-blocks without copying.
  --------------------------------------------------------------------------- }
type
  TAudioBuffer = class
  private
    FData: array of Single;
    FChannels: array of PSingle;
    FNumChannels: Integer;
    FNumSamples: Integer;
    FAllocatedSamples: Integer;
    FOwnsData: Boolean;
    function GetChannel(Index: Integer): PSingle; inline;
  public
    constructor Create; overload;
    constructor Create(ANumChannels, ANumSamples: Integer); overload;

    { Resizes the buffer. When KeepContents is False the new content is
      undefined unless ClearExtra is set. }
    procedure SetSize(ANumChannels, ANumSamples: Integer;
      KeepContents: Boolean = False; ClearExtra: Boolean = True;
      AvoidReallocating: Boolean = False);

    { Points this buffer at storage owned by somebody else, starting at
      StartSample within each of the supplied channel pointers. }
    procedure SetDataToReferTo(const AChannels: array of PSingle;
      ANumChannels, StartSample, ANumSamples: Integer);

    procedure Clear; overload;
    procedure Clear(StartSample, ANumSamples: Integer); overload;
    procedure CopyFrom(const Source: TAudioBuffer; AvoidReallocating: Boolean = False);

    procedure ApplyGain(Gain: Single); overload;
    procedure ApplyGain(Channel, StartSample, ANumSamples: Integer; Gain: Single); overload;
    procedure ApplyGain(StartSample, ANumSamples: Integer; Gain: Single); overload;
    procedure ApplyGainRamp(StartSample, ANumSamples: Integer; StartGain, EndGain: Single); overload;
    procedure ApplyGainRamp(Channel, StartSample, ANumSamples: Integer; StartGain, EndGain: Single); overload;

    procedure AddFrom(DestChannel, DestStart: Integer; Source: PSingle;
      ANumSamples: Integer; Gain: Single = 1.0); overload;
    procedure AddFrom(DestChannel, DestStart: Integer; const Source: TAudioBuffer;
      SourceChannel, SourceStart, ANumSamples: Integer; Gain: Single = 1.0); overload;
    procedure AddFromWithRamp(DestChannel, DestStart: Integer; Source: PSingle;
      ANumSamples: Integer; StartGain, EndGain: Single);

    property NumChannels: Integer read FNumChannels;
    property NumSamples: Integer read FNumSamples;
    property Channels[Index: Integer]: PSingle read GetChannel; default;
  end;

{ ---------------------------------------------------------------------------
  TAudioBufferD -- the double-precision counterpart, used by the hysteresis
  chain and the oversamplers.
  --------------------------------------------------------------------------- }
type
  TAudioBufferD = class
  private
    FData: array of Double;
    FChannels: array of PDouble;
    FNumChannels: Integer;
    FNumSamples: Integer;
    FAllocatedSamples: Integer;
    function GetChannel(Index: Integer): PDouble; inline;
  public
    procedure SetSize(ANumChannels, ANumSamples: Integer; KeepContents: Boolean = False);
    procedure Clear;
    procedure CopyFromFloat(const Source: TAudioBuffer);
    procedure CopyToFloat(Dest: TAudioBuffer);
    property NumChannels: Integer read FNumChannels;
    property NumSamples: Integer read FNumSamples write FNumSamples;
    property Channels[Index: Integer]: PDouble read GetChannel; default;
  end;

{ ---------------------------------------------------------------------------
  Smoothed values
  --------------------------------------------------------------------------- }
type
  TSmoothedValueLinear = record
  private
    FCurrent: Double;
    FTarget: Double;
    FStep: Double;
    FCountdown: Integer;
    FStepsToTarget: Integer;
  public
    procedure Reset(SampleRate, RampLengthSeconds: Double); overload;
    procedure Reset(NumSteps: Integer); overload;
    procedure SetCurrentAndTargetValue(NewValue: Double);
    procedure SetTargetValue(NewValue: Double);
    function GetNextValue: Double;
    function Skip(NumSamples: Integer): Double;
    function IsSmoothing: Boolean; inline;
    function GetCurrentValue: Double; inline;
    function GetTargetValue: Double; inline;
  end;

  TSmoothedValueMultiplicative = record
  private
    FCurrent: Double;
    FTarget: Double;
    FStep: Double;
    FCountdown: Integer;
    FStepsToTarget: Integer;
  public
    procedure Reset(SampleRate, RampLengthSeconds: Double); overload;
    procedure Reset(NumSteps: Integer); overload;
    procedure SetCurrentAndTargetValue(NewValue: Double);
    procedure SetTargetValue(NewValue: Double);
    function GetNextValue: Double;
    function Skip(NumSamples: Integer): Double;
    function IsSmoothing: Boolean; inline;
    function GetCurrentValue: Double; inline;
    function GetTargetValue: Double; inline;
  end;

  TSmoothedLinearArray = array of TSmoothedValueLinear;
  TSmoothedMulArray = array of TSmoothedValueMultiplicative;

{ ---------------------------------------------------------------------------
  TRandom -- the linear congruential generator used by juce::Random
  --------------------------------------------------------------------------- }
type
  TRandom = record
  private
    FSeed: Int64;
  public
    procedure SetSeed(NewSeed: Int64);
    function NextInt: Integer; overload;
    function NextInt(MaxValue: Integer): Integer; overload;
    function NextIntInRange(RangeStart, RangeEnd: Integer): Integer;
    function NextFloat: Single;
    function NextDouble: Double;
  end;

function CreateRandom: TRandom;

{ ---------------------------------------------------------------------------
  Maths helpers
  --------------------------------------------------------------------------- }
const
  TwoPiS: Single = 6.28318530717958647692;
  PiS: Single = 3.14159265358979323846;
  TwoPiD: Double = 6.28318530717958647692;
  PiD: Double = 3.14159265358979323846;

function DecibelsToGain(Decibels: Single; MinusInfinityDb: Single = -100.0): Single;
function GainToDecibels(Gain: Single; MinusInfinityDb: Single = -100.0): Single;
function JLimit(LowerLimit, UpperLimit, Value: Single): Single; inline;
function JMinF(A, B: Single): Single; inline;
function JMaxF(A, B: Single): Single; inline;
function SignOf(X: Double): Integer; inline;

{ Rational approximation of tan() used by juce::dsp::FastMathApproximations.
  Reproduced exactly because several filter cutoffs depend on its (slight)
  error. }
function FastTan(X: Single): Single;

{ Rounds denormal-sized values to zero. }
procedure SnapToZero(var X: Single); inline; overload;
procedure SnapToZero(var X: Double); inline; overload;

function SanitizeFloat(X: Single): Single; inline;

implementation

uses
  System.SysUtils, ChowTape.DSP.FastMath;

{ TAudioBuffer }

constructor TAudioBuffer.Create;
begin
  inherited Create;
  FOwnsData := True;
end;

constructor TAudioBuffer.Create(ANumChannels, ANumSamples: Integer);
begin
  inherited Create;
  FOwnsData := True;
  SetSize(ANumChannels, ANumSamples);
end;

function TAudioBuffer.GetChannel(Index: Integer): PSingle;
begin
  Result := FChannels[Index];
end;

procedure TAudioBuffer.SetSize(ANumChannels, ANumSamples: Integer;
  KeepContents, ClearExtra, AvoidReallocating: Boolean);
var
  Ch: Integer;
  NeedsRealloc: Boolean;
begin
  if ANumChannels < 0 then ANumChannels := 0;
  if ANumSamples < 0 then ANumSamples := 0;

  NeedsRealloc := (not FOwnsData) or (ANumChannels <> FNumChannels) or
    (ANumSamples > FAllocatedSamples) or
    ((not AvoidReallocating) and (ANumSamples <> FAllocatedSamples));

  if NeedsRealloc then
  begin
    if AvoidReallocating and FOwnsData and (ANumChannels = FNumChannels) and
       (ANumSamples <= FAllocatedSamples) then
    begin
      // storage is large enough, just re-point
    end
    else
    begin
      SetLength(FData, ANumChannels * ANumSamples);
      FAllocatedSamples := ANumSamples;
      SetLength(FChannels, ANumChannels);
      for Ch := 0 to ANumChannels - 1 do
        if ANumSamples > 0 then
          FChannels[Ch] := @FData[Ch * ANumSamples]
        else
          FChannels[Ch] := nil;
      FOwnsData := True;
      if ClearExtra and (not KeepContents) then
        FillChar(FData[0], Length(FData) * SizeOf(Single), 0);
    end;
  end;

  FNumChannels := ANumChannels;
  FNumSamples := ANumSamples;
end;

procedure TAudioBuffer.SetDataToReferTo(const AChannels: array of PSingle;
  ANumChannels, StartSample, ANumSamples: Integer);
var
  Ch: Integer;
begin
  SetLength(FData, 0);
  FAllocatedSamples := 0;
  FOwnsData := False;
  SetLength(FChannels, ANumChannels);
  for Ch := 0 to ANumChannels - 1 do
    FChannels[Ch] := @PSingleArray(AChannels[Ch])^[StartSample];
  FNumChannels := ANumChannels;
  FNumSamples := ANumSamples;
end;

procedure TAudioBuffer.Clear;
var
  Ch: Integer;
begin
  for Ch := 0 to FNumChannels - 1 do
    if FNumSamples > 0 then
      FillChar(FChannels[Ch]^, FNumSamples * SizeOf(Single), 0);
end;

procedure TAudioBuffer.Clear(StartSample, ANumSamples: Integer);
var
  Ch: Integer;
begin
  if ANumSamples <= 0 then Exit;
  for Ch := 0 to FNumChannels - 1 do
    FillChar(PSingleArray(FChannels[Ch])^[StartSample], ANumSamples * SizeOf(Single), 0);
end;

procedure TAudioBuffer.CopyFrom(const Source: TAudioBuffer; AvoidReallocating: Boolean);
var
  Ch: Integer;
begin
  SetSize(Source.NumChannels, Source.NumSamples, False, False, AvoidReallocating);
  for Ch := 0 to FNumChannels - 1 do
    if FNumSamples > 0 then
      Move(Source.Channels[Ch]^, FChannels[Ch]^, FNumSamples * SizeOf(Single));
end;

procedure TAudioBuffer.ApplyGain(Gain: Single);
begin
  ApplyGain(0, FNumSamples, Gain);
end;

procedure TAudioBuffer.ApplyGain(StartSample, ANumSamples: Integer; Gain: Single);
var
  Ch: Integer;
begin
  for Ch := 0 to FNumChannels - 1 do
    ApplyGain(Ch, StartSample, ANumSamples, Gain);
end;

procedure TAudioBuffer.ApplyGain(Channel, StartSample, ANumSamples: Integer; Gain: Single);
var
  N: Integer;
  P: PSingleArray;
begin
  if (ANumSamples <= 0) or (Gain = 1.0) then Exit;
  P := PSingleArray(FChannels[Channel]);
  for N := StartSample to StartSample + ANumSamples - 1 do
    P^[N] := P^[N] * Gain;
end;

procedure TAudioBuffer.ApplyGainRamp(StartSample, ANumSamples: Integer;
  StartGain, EndGain: Single);
var
  Ch: Integer;
begin
  for Ch := 0 to FNumChannels - 1 do
    ApplyGainRamp(Ch, StartSample, ANumSamples, StartGain, EndGain);
end;

procedure TAudioBuffer.ApplyGainRamp(Channel, StartSample, ANumSamples: Integer;
  StartGain, EndGain: Single);
var
  N: Integer;
  Gain, Increment: Single;
  P: PSingleArray;
begin
  if ANumSamples <= 0 then Exit;
  if StartGain = EndGain then
  begin
    ApplyGain(Channel, StartSample, ANumSamples, StartGain);
    Exit;
  end;
  Gain := StartGain;
  Increment := (EndGain - StartGain) / ANumSamples;
  P := PSingleArray(FChannels[Channel]);
  for N := StartSample to StartSample + ANumSamples - 1 do
  begin
    P^[N] := P^[N] * Gain;
    Gain := Gain + Increment;
  end;
end;

procedure TAudioBuffer.AddFrom(DestChannel, DestStart: Integer; Source: PSingle;
  ANumSamples: Integer; Gain: Single);
var
  N: Integer;
  D, S: PSingleArray;
begin
  if (ANumSamples <= 0) or (Gain = 0.0) then Exit;
  D := PSingleArray(FChannels[DestChannel]);
  S := PSingleArray(Source);
  if Gain = 1.0 then
  begin
    for N := 0 to ANumSamples - 1 do
      D^[DestStart + N] := D^[DestStart + N] + S^[N];
  end
  else
  begin
    for N := 0 to ANumSamples - 1 do
      D^[DestStart + N] := D^[DestStart + N] + S^[N] * Gain;
  end;
end;

procedure TAudioBuffer.AddFrom(DestChannel, DestStart: Integer;
  const Source: TAudioBuffer; SourceChannel, SourceStart, ANumSamples: Integer;
  Gain: Single);
begin
  AddFrom(DestChannel, DestStart,
    @PSingleArray(Source.Channels[SourceChannel])^[SourceStart], ANumSamples, Gain);
end;

procedure TAudioBuffer.AddFromWithRamp(DestChannel, DestStart: Integer;
  Source: PSingle; ANumSamples: Integer; StartGain, EndGain: Single);
var
  N: Integer;
  Gain, Increment: Single;
  D, S: PSingleArray;
begin
  if ANumSamples <= 0 then Exit;
  Gain := StartGain;
  Increment := (EndGain - StartGain) / ANumSamples;
  D := PSingleArray(FChannels[DestChannel]);
  S := PSingleArray(Source);
  for N := 0 to ANumSamples - 1 do
  begin
    D^[DestStart + N] := D^[DestStart + N] + S^[N] * Gain;
    Gain := Gain + Increment;
  end;
end;

{ TAudioBufferD }

function TAudioBufferD.GetChannel(Index: Integer): PDouble;
begin
  Result := FChannels[Index];
end;

procedure TAudioBufferD.SetSize(ANumChannels, ANumSamples: Integer; KeepContents: Boolean);
var
  Ch: Integer;
begin
  if (ANumChannels <> FNumChannels) or (ANumSamples > FAllocatedSamples) then
  begin
    SetLength(FData, ANumChannels * ANumSamples);
    FAllocatedSamples := ANumSamples;
    SetLength(FChannels, ANumChannels);
    for Ch := 0 to ANumChannels - 1 do
      if ANumSamples > 0 then
        FChannels[Ch] := @FData[Ch * ANumSamples]
      else
        FChannels[Ch] := nil;
    if not KeepContents then
      if Length(FData) > 0 then
        FillChar(FData[0], Length(FData) * SizeOf(Double), 0);
  end;
  FNumChannels := ANumChannels;
  FNumSamples := ANumSamples;
end;

procedure TAudioBufferD.Clear;
var
  Ch: Integer;
begin
  for Ch := 0 to FNumChannels - 1 do
    if FAllocatedSamples > 0 then
      FillChar(FChannels[Ch]^, FAllocatedSamples * SizeOf(Double), 0);
end;

procedure TAudioBufferD.CopyFromFloat(const Source: TAudioBuffer);
var
  Ch, N: Integer;
  S: PSingleArray;
  D: PDoubleBuf;
begin
  SetSize(Source.NumChannels, Source.NumSamples, True);
  for Ch := 0 to FNumChannels - 1 do
  begin
    S := PSingleArray(Source.Channels[Ch]);
    D := PDoubleBuf(FChannels[Ch]);
    for N := 0 to FNumSamples - 1 do
      D^[N] := S^[N];
  end;
end;

procedure TAudioBufferD.CopyToFloat(Dest: TAudioBuffer);
var
  Ch, N, NumCh: Integer;
  S: PDoubleBuf;
  D: PSingleArray;
begin
  // never resizes: Dest may be aliasing the host's own buffers
  NumCh := FNumChannels;
  if Dest.NumChannels < NumCh then
    NumCh := Dest.NumChannels;
  for Ch := 0 to NumCh - 1 do
  begin
    S := PDoubleBuf(FChannels[Ch]);
    D := PSingleArray(Dest.Channels[Ch]);
    for N := 0 to FNumSamples - 1 do
      D^[N] := S^[N];
  end;
end;

{ TSmoothedValueLinear }

procedure TSmoothedValueLinear.Reset(SampleRate, RampLengthSeconds: Double);
begin
  Reset(Round(Ceil(SampleRate * RampLengthSeconds)));
end;

procedure TSmoothedValueLinear.Reset(NumSteps: Integer);
begin
  FStepsToTarget := NumSteps;
  SetCurrentAndTargetValue(FTarget);
end;

procedure TSmoothedValueLinear.SetCurrentAndTargetValue(NewValue: Double);
begin
  FTarget := NewValue;
  FCurrent := NewValue;
  FCountdown := 0;
end;

procedure TSmoothedValueLinear.SetTargetValue(NewValue: Double);
begin
  if NewValue = FTarget then
    Exit;
  if FStepsToTarget <= 0 then
  begin
    SetCurrentAndTargetValue(NewValue);
    Exit;
  end;
  FTarget := NewValue;
  FCountdown := FStepsToTarget;
  FStep := (FTarget - FCurrent) / FCountdown;
end;

function TSmoothedValueLinear.GetNextValue: Double;
begin
  if FCountdown <= 0 then
    Exit(FTarget);
  Dec(FCountdown);
  if FCountdown <= 0 then
    FCurrent := FTarget
  else
    FCurrent := FCurrent + FStep;
  Result := FCurrent;
end;

function TSmoothedValueLinear.Skip(NumSamples: Integer): Double;
begin
  if NumSamples >= FCountdown then
  begin
    SetCurrentAndTargetValue(FTarget);
    Exit(FTarget);
  end;
  FCurrent := FCurrent + FStep * NumSamples;
  Dec(FCountdown, NumSamples);
  Result := FCurrent;
end;

function TSmoothedValueLinear.IsSmoothing: Boolean;
begin
  Result := FCountdown > 0;
end;

function TSmoothedValueLinear.GetCurrentValue: Double;
begin
  Result := FCurrent;
end;

function TSmoothedValueLinear.GetTargetValue: Double;
begin
  Result := FTarget;
end;

{ TSmoothedValueMultiplicative }

procedure TSmoothedValueMultiplicative.Reset(SampleRate, RampLengthSeconds: Double);
begin
  Reset(Round(Ceil(SampleRate * RampLengthSeconds)));
end;

procedure TSmoothedValueMultiplicative.Reset(NumSteps: Integer);
begin
  FStepsToTarget := NumSteps;
  if FTarget = 0.0 then
    FTarget := 1.0e-8;
  SetCurrentAndTargetValue(FTarget);
end;

procedure TSmoothedValueMultiplicative.SetCurrentAndTargetValue(NewValue: Double);
begin
  if NewValue = 0.0 then
    NewValue := 1.0e-8;
  FTarget := NewValue;
  FCurrent := NewValue;
  FCountdown := 0;
end;

procedure TSmoothedValueMultiplicative.SetTargetValue(NewValue: Double);
begin
  if NewValue = 0.0 then
    NewValue := 1.0e-8;
  if NewValue = FTarget then
    Exit;
  if FStepsToTarget <= 0 then
  begin
    SetCurrentAndTargetValue(NewValue);
    Exit;
  end;
  FTarget := NewValue;
  FCountdown := FStepsToTarget;
  if FCurrent = 0.0 then
    FCurrent := 1.0e-8;
  FStep := Exp((Ln(Abs(FTarget)) - Ln(Abs(FCurrent))) / FCountdown);
end;

function TSmoothedValueMultiplicative.GetNextValue: Double;
begin
  if FCountdown <= 0 then
    Exit(FTarget);
  Dec(FCountdown);
  if FCountdown <= 0 then
    FCurrent := FTarget
  else
    FCurrent := FCurrent * FStep;
  Result := FCurrent;
end;

function TSmoothedValueMultiplicative.Skip(NumSamples: Integer): Double;
begin
  if NumSamples >= FCountdown then
  begin
    SetCurrentAndTargetValue(FTarget);
    Exit(FTarget);
  end;
  FCurrent := FCurrent * Power(FStep, NumSamples);
  Dec(FCountdown, NumSamples);
  Result := FCurrent;
end;

function TSmoothedValueMultiplicative.IsSmoothing: Boolean;
begin
  Result := FCountdown > 0;
end;

function TSmoothedValueMultiplicative.GetCurrentValue: Double;
begin
  Result := FCurrent;
end;

function TSmoothedValueMultiplicative.GetTargetValue: Double;
begin
  Result := FTarget;
end;

{ TRandom }

procedure TRandom.SetSeed(NewSeed: Int64);
begin
  FSeed := NewSeed;
end;

function TRandom.NextInt: Integer;
begin
  FSeed := Int64((UInt64(FSeed) * UInt64($5DEECE66D) + 11) and UInt64($FFFFFFFFFFFF));
  Result := Integer(FSeed shr 16);
end;

function TRandom.NextInt(MaxValue: Integer): Integer;
begin
  if MaxValue <= 0 then
    Exit(0);
  Result := Integer((UInt64(Cardinal(NextInt)) * UInt64(MaxValue)) shr 32);
end;

function TRandom.NextIntInRange(RangeStart, RangeEnd: Integer): Integer;
begin
  Result := RangeStart + NextInt(RangeEnd - RangeStart);
end;

function TRandom.NextFloat: Single;
begin
  Result := Cardinal(NextInt) / 4294967295.0;
  if Result >= 1.0 then
    Result := 1.0 - 1.1920929e-7;
end;

function TRandom.NextDouble: Double;
begin
  Result := Cardinal(NextInt) / 4294967295.0;
end;

var
  GRandomCounter: Integer = 0;

function CreateRandom: TRandom;
var
  Seed: Int64;
begin
  // Each generator gets a distinct seed. The clock comes from Now rather than
  // GetTickCount64 so that this unit does not have to pull in Winapi.Windows,
  // which redeclares PSingle and would fork every shared pointer signature.
  Inc(GRandomCounter);
  Seed := Round(Frac(Now) * 86400000.0) xor (Int64(GRandomCounter) shl 24);
  Seed := Seed and $FFFFFFFFFFFF;
  if Seed = 0 then
    Seed := 1;
  Result.SetSeed(Seed);
end;

{ Maths helpers }

{ Power(10, dB/20) and Log10(g)*20 rewritten over exp and ln: the compressor
  runs both once per oversampled sample per channel, where the RTL versions
  measured more than the rest of that stage combined. }
const
  DbToNat = 0.11512925464970228420;   // ln(10) / 20
  NatToDb = 8.68588963806503655303;   // 20 / ln(10)

function DecibelsToGain(Decibels, MinusInfinityDb: Single): Single;
begin
  if Decibels > MinusInfinityDb then
    Result := QuickExp(Decibels * DbToNat)
  else
    Result := 0.0;
end;

function GainToDecibels(Gain, MinusInfinityDb: Single): Single;
begin
  if Gain > 0 then
    Result := JMaxF(MinusInfinityDb, Single(QuickLog(Gain) * NatToDb))
  else
    Result := MinusInfinityDb;
end;

function JLimit(LowerLimit, UpperLimit, Value: Single): Single;
begin
  if Value < LowerLimit then
    Result := LowerLimit
  else if Value > UpperLimit then
    Result := UpperLimit
  else
    Result := Value;
end;

function JMinF(A, B: Single): Single;
begin
  if A < B then Result := A else Result := B;
end;

function JMaxF(A, B: Single): Single;
begin
  if A > B then Result := A else Result := B;
end;

function SignOf(X: Double): Integer;
begin
  Result := Ord(X > 0.0) - Ord(X < 0.0);
end;

function FastTan(X: Single): Single;
var
  X2, Num, Den: Single;
begin
  X2 := X * X;
  Num := X * (-135135 + X2 * (17325 + X2 * (-378 + X2)));
  Den := -135135 + X2 * (62370 + X2 * (-3150 + 28 * X2));
  Result := Num / Den;
end;

procedure SnapToZero(var X: Single);
begin
  if not (Abs(X) > 1.0e-8) then
    X := 0.0;
end;

procedure SnapToZero(var X: Double);
begin
  if not (Abs(X) > 1.0e-8) then
    X := 0.0;
end;

function SanitizeFloat(X: Single): Single;
begin
  if X <> X then // NaN
    Result := 0.0
  else if (X > 1.0e10) or (X < -1.0e10) then
    Result := 0.0
  else
    Result := X;
end;

end.
