unit ChowTape.DSP.Filters;

{
  The filter primitives used across the tape model. Each one is a direct port of
  the chowdsp/JUCE class the original plug-in used, keeping the same topology so
  that coefficients and state behave identically.
}

interface

uses
  System.Math, ChowTape.DSP.Types;

const
  { The damping term of a 4th-order Linkwitz-Riley section. Declared here rather
    than in the implementation because ProcessSample is inlined. }
  LinkwitzRileyR2 = 1.41421356237;

type
  { First-order IIR in transposed direct form II, one state per channel. }
  TIIRFilter1 = class
  private
    FB: array[0..1] of Single;
    FA: array[0..1] of Single;
    FZ: array of Single;
  public
    procedure Prepare(NumChannels: Integer);
    procedure Reset;
    procedure SetCoefs(const NewB, NewA: array of Single);
    function ProcessSample(X: Single; Channel: Integer = 0): Single; inline;
    procedure ProcessBlock(Block: PSingle; NumSamples: Integer; Channel: Integer = 0);
  end;

  { Second-order IIR in transposed direct form II. }
  TIIRFilter2 = class
  private
    FB: array[0..2] of Single;
    FA: array[0..2] of Single;
    FZ: array of Single; // 2 states per channel
  public
    procedure Prepare(NumChannels: Integer);
    procedure Reset;
    procedure SetCoefs(const NewB, NewA: array of Single);
    function ProcessSample(X: Single; Channel: Integer = 0): Single; inline;
    procedure ProcessBlock(Block: PSingle; NumSamples: Integer; Channel: Integer = 0);
  end;

  { First-order shelving filter (Abel & Berners, dsp4dae p.249) as used by the
    tone control. }
  TShelfFilter = class(TIIRFilter1)
  public
    procedure CalcCoefs(LowGain, HighGain, Fc, Fs: Single);
  end;

  { 4th-order Linkwitz-Riley crossover in TPT form, giving simultaneous low and
    high outputs. }
  TLinkwitzRileyFilter = class
  private
    FG, FH: Single;
    FState: array of Single; // 4 states per channel
    FSampleRate: Double;
    FCutoff: Single;
    FNumChannels: Integer;
    procedure Update;
  public
    constructor Create;
    procedure Prepare(ASampleRate: Double; ANumChannels: Integer);
    procedure Reset;
    procedure SetCutoff(NewCutoffHz: Single);
    procedure ProcessSample(Ch: Integer; X: Single; var OutLow, OutHigh: Single); inline;
    procedure SnapToZeroState;
  end;

  { Topology-preserving state variable lowpass (chowdsp::SVFLowpass). }
  TSVFLowpass = class
  private
    FG0, FK0: Single;
    FA1, FA2, FA3, FAK: Single;
    FIc1, FIc2: array of Single;
    FSampleRate: Double;
    FCutoff: Single;
    FQ: Single;
    procedure Update;
  public
    constructor Create;
    procedure Prepare(ASampleRate: Double; ANumChannels: Integer);
    procedure Reset;
    procedure SetCutoffFrequency(NewCutoffHz: Single);
    procedure SetQValue(NewQ: Single);
    function ProcessSample(Channel: Integer; X: Single): Single; inline;
  end;

  { Cascade of two 2nd-order Butterworth high-pass sections. }
  TDCBlocker = class
  private
    FHpf: array[0..1] of TIIRFilter2;
    FFs: Single;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Prepare(ASampleRate: Double; DcFreq: Single);
    procedure CalcCoefs(Fc: Single);
    procedure ProcessBlock(Buffer: PSingle; NumSamples: Integer);
  end;

  { One-pole lowpass with a multiplicatively-smoothed cutoff, used by the chew
    and degrade effects. }
  TDegradeFilter = class
  private
    FFreq: TSmoothedValueMultiplicative;
    FFs: Single;
    FA: array[0..1] of Single;
    FB: array[0..1] of Single;
    FZ: array[0..1] of Single;
  public
    constructor Create;
    procedure Reset(ASampleRate: Single; Steps: Integer = 0);
    procedure CalcCoefs(Fc: Single); inline;
    procedure Process(Buffer: PSingle; NumSamples: Integer);
    function ProcessSample(X: Single): Single; inline;
    procedure SetFreq(NewFreq: Single);
  end;

  { Direct-form FIR with a double-buffered state so the inner product stays
    contiguous (chowdsp::FIRFilter). }
  TFIRFilter = class
  private
    FOrder: Integer;
    FNumChannels: Integer;
    FCoefficients: array of Single;
    FState: array of Single;
    FZPtr: array of Integer;
  public
    constructor Create(AOrder: Integer = 0);
    procedure SetOrder(NewOrder: Integer);
    procedure Prepare(ANumChannels: Integer);
    procedure Reset;
    procedure SetCoefficients(Coeffs: PSingle);
    function ProcessSample(X: Single; Channel: Integer = 0): Single; inline;
    procedure ProcessBlock(Block: PSingle; NumSamples: Integer; Channel: Integer = 0);
    procedure ProcessBlockBypassed(Block: PSingle; NumSamples: Integer; Channel: Integer = 0);
    procedure ProcessBuffer(Buffer: TAudioBuffer);
    procedure ProcessBufferBypassed(Buffer: TAudioBuffer);
    property Order: Integer read FOrder;
  end;

  { Multi-channel biquad sharing one coefficient set, matching
    dsp::ProcessorDuplicator<IIR::Filter, IIR::Coefficients>. }
  TMultiChannelBiquad = class
  private
    FCoeffs: array[0..4] of Single; // b0 b1 b2 a1 a2, normalised
    FState: array of Single;        // 2 per channel
    FNumChannels: Integer;
  public
    procedure Prepare(ANumChannels: Integer);
    procedure Reset;
    procedure MakePeakFilter(SampleRate: Double; Frequency, Q, GainFactor: Single);
    procedure ProcessBuffer(Buffer: TAudioBuffer);
  end;

{ Butterworth Q values for an order-N filter, returned lowest-index first. }
function ButterworthQs(N: Integer): TFloatArray;

implementation

{ TIIRFilter1 }

procedure TIIRFilter1.Prepare(NumChannels: Integer);
begin
  SetLength(FZ, NumChannels);
  Reset;
end;

procedure TIIRFilter1.Reset;
var
  I: Integer;
begin
  for I := 0 to High(FZ) do
    FZ[I] := 0.0;
end;

procedure TIIRFilter1.SetCoefs(const NewB, NewA: array of Single);
begin
  FB[0] := NewB[0];
  FB[1] := NewB[1];
  FA[0] := NewA[0];
  FA[1] := NewA[1];
end;

function TIIRFilter1.ProcessSample(X: Single; Channel: Integer): Single;
begin
  Result := FZ[Channel] + X * FB[0];
  FZ[Channel] := X * FB[1] - Result * FA[1];
end;

procedure TIIRFilter1.ProcessBlock(Block: PSingle; NumSamples, Channel: Integer);
var
  N: Integer;
  P: PSingleArray;
  Z1, Y: Single;
begin
  P := PSingleArray(Block);
  Z1 := FZ[Channel];
  for N := 0 to NumSamples - 1 do
  begin
    Y := Z1 + P^[N] * FB[0];
    Z1 := P^[N] * FB[1] - Y * FA[1];
    P^[N] := Y;
  end;
  FZ[Channel] := Z1;
end;

{ TIIRFilter2 }

procedure TIIRFilter2.Prepare(NumChannels: Integer);
begin
  SetLength(FZ, NumChannels * 2);
  Reset;
end;

procedure TIIRFilter2.Reset;
var
  I: Integer;
begin
  for I := 0 to High(FZ) do
    FZ[I] := 0.0;
end;

procedure TIIRFilter2.SetCoefs(const NewB, NewA: array of Single);
begin
  FB[0] := NewB[0]; FB[1] := NewB[1]; FB[2] := NewB[2];
  FA[0] := NewA[0]; FA[1] := NewA[1]; FA[2] := NewA[2];
end;

function TIIRFilter2.ProcessSample(X: Single; Channel: Integer): Single;
var
  Base: Integer;
begin
  Base := Channel * 2;
  Result := FZ[Base] + X * FB[0];
  FZ[Base] := FZ[Base + 1] + X * FB[1] - Result * FA[1];
  FZ[Base + 1] := X * FB[2] - Result * FA[2];
end;

procedure TIIRFilter2.ProcessBlock(Block: PSingle; NumSamples, Channel: Integer);
var
  N, Base: Integer;
  P: PSingleArray;
  Z1, Z2, Y: Single;
begin
  P := PSingleArray(Block);
  Base := Channel * 2;
  Z1 := FZ[Base];
  Z2 := FZ[Base + 1];
  for N := 0 to NumSamples - 1 do
  begin
    Y := Z1 + P^[N] * FB[0];
    Z1 := Z2 + P^[N] * FB[1] - Y * FA[1];
    Z2 := P^[N] * FB[2] - Y * FA[2];
    P^[N] := Y;
  end;
  FZ[Base] := Z1;
  FZ[Base + 1] := Z2;
end;

{ TShelfFilter }

procedure TShelfFilter.CalcCoefs(LowGain, HighGain, Fc, Fs: Single);
var
  RhoRecip, K, A0Inv: Single;
  Bs0, Bs1, As0, As1: Single;
  NewB, NewA: array[0..1] of Single;
begin
  // A shelf with equal gains either side is just a gain element.
  if LowGain = HighGain then
  begin
    NewB[0] := LowGain; NewB[1] := 0.0;
    NewA[0] := 1.0;     NewA[1] := 0.0;
    SetCoefs(NewB, NewA);
    Exit;
  end;

  RhoRecip := 1.0 / Sqrt(HighGain / LowGain);
  K := 1.0 / Tan(PiD * Fc / Fs);

  // bilinear transform of (highGain*rho_recip * s + lowGain) / (rho_recip * s + 1)
  Bs0 := HighGain * RhoRecip;
  Bs1 := LowGain;
  As0 := RhoRecip;
  As1 := 1.0;

  A0Inv := 1.0 / (As0 * K + As1 * 1.0);
  NewB[0] := (Bs0 * K + Bs1 * 1.0) * A0Inv;
  NewB[1] := (Bs0 * (-K) + Bs1 * 1.0) * A0Inv;
  NewA[0] := 1.0;
  NewA[1] := (As0 * (-K) + As1 * 1.0) * A0Inv;

  SetCoefs(NewB, NewA);
end;

{ TLinkwitzRileyFilter }

constructor TLinkwitzRileyFilter.Create;
begin
  inherited Create;
  FSampleRate := 44100.0;
  FCutoff := 2000.0;
  Update;
end;

procedure TLinkwitzRileyFilter.Prepare(ASampleRate: Double; ANumChannels: Integer);
begin
  FSampleRate := ASampleRate;
  FNumChannels := ANumChannels;
  SetLength(FState, ANumChannels * 4);
  Update;
  Reset;
end;

procedure TLinkwitzRileyFilter.Reset;
var
  I: Integer;
begin
  for I := 0 to High(FState) do
    FState[I] := 0.0;
end;

procedure TLinkwitzRileyFilter.SetCutoff(NewCutoffHz: Single);
begin
  FCutoff := NewCutoffHz;
  Update;
end;

procedure TLinkwitzRileyFilter.Update;
begin
  FG := Tan(PiD * FCutoff / FSampleRate);
  FH := 1.0 / (1.0 + LinkwitzRileyR2 * FG + FG * FG);
end;

procedure TLinkwitzRileyFilter.ProcessSample(Ch: Integer; X: Single;
  var OutLow, OutHigh: Single);
var
  B: Integer;
  YH, TB, YB, TL, YL, YH2, TB2, YB2, TL2, YL2: Single;
begin
  B := Ch * 4;

  YH := (X - (LinkwitzRileyR2 + FG) * FState[B] - FState[B + 1]) * FH;

  TB := FG * YH;
  YB := TB + FState[B];
  FState[B] := TB + YB;

  TL := FG * YB;
  YL := TL + FState[B + 1];
  FState[B + 1] := TL + YL;

  YH2 := (YL - (LinkwitzRileyR2 + FG) * FState[B + 2] - FState[B + 3]) * FH;

  TB2 := FG * YH2;
  YB2 := TB2 + FState[B + 2];
  FState[B + 2] := TB2 + YB2;

  TL2 := FG * YB2;
  YL2 := TL2 + FState[B + 3];
  FState[B + 3] := TL2 + YL2;

  OutLow := YL2;
  OutHigh := YL - LinkwitzRileyR2 * YB + YH - YL2;
end;

procedure TLinkwitzRileyFilter.SnapToZeroState;
var
  I: Integer;
begin
  for I := 0 to High(FState) do
    SnapToZero(FState[I]);
end;

{ TSVFLowpass }

constructor TSVFLowpass.Create;
begin
  inherited Create;
  FSampleRate := 44100.0;
  FCutoff := 1000.0;
  FQ := 1.0 / Sqrt(2.0);
  Update;
end;

procedure TSVFLowpass.Prepare(ASampleRate: Double; ANumChannels: Integer);
begin
  FSampleRate := ASampleRate;
  SetLength(FIc1, ANumChannels);
  SetLength(FIc2, ANumChannels);
  Update;
  Reset;
end;

procedure TSVFLowpass.Reset;
var
  I: Integer;
begin
  for I := 0 to High(FIc1) do
  begin
    FIc1[I] := 0.0;
    FIc2[I] := 0.0;
  end;
end;

procedure TSVFLowpass.SetCutoffFrequency(NewCutoffHz: Single);
begin
  FCutoff := NewCutoffHz;
  Update;
end;

procedure TSVFLowpass.SetQValue(NewQ: Single);
begin
  FQ := NewQ;
  FK0 := 1.0 / FQ;
  Update;
end;

procedure TSVFLowpass.Update;
var
  GK: Single;
begin
  FG0 := Tan(PiD * FCutoff / FSampleRate);
  FK0 := 1.0 / FQ;
  GK := FG0 + FK0;
  FA1 := 1.0 / (1.0 + FG0 * GK);
  FA2 := FG0 * FA1;
  FA3 := FG0 * FA2;
  FAK := GK * FA1;
end;

function TSVFLowpass.ProcessSample(Channel: Integer; X: Single): Single;
var
  V1, V2, V3: Single;
begin
  V3 := X - FIc2[Channel];
  V1 := FA2 * V3 + FA1 * FIc1[Channel];
  V2 := FA3 * V3 + FA2 * FIc1[Channel] + FIc2[Channel];

  FIc1[Channel] := 2.0 * V1 - FIc1[Channel];
  FIc2[Channel] := 2.0 * V2 - FIc2[Channel];

  Result := V2;
end;

{ TDCBlocker }

constructor TDCBlocker.Create;
var
  I: Integer;
begin
  inherited Create;
  for I := 0 to 1 do
  begin
    FHpf[I] := TIIRFilter2.Create;
    FHpf[I].Prepare(1);
  end;
  FFs := 44100.0;
end;

destructor TDCBlocker.Destroy;
var
  I: Integer;
begin
  for I := 0 to 1 do
    FHpf[I].Free;
  inherited Destroy;
end;

procedure TDCBlocker.Prepare(ASampleRate: Double; DcFreq: Single);
var
  I: Integer;
begin
  for I := 0 to 1 do
    FHpf[I].Reset;
  FFs := ASampleRate;
  CalcCoefs(DcFreq);
end;

procedure TDCBlocker.CalcCoefs(Fc: Single);
var
  Qs: TFloatArray;
  Wc, C, Phi, K, A0: Single;
  B, A: array[0..2] of Single;
  I: Integer;
begin
  Qs := ButterworthQs(4);

  Wc := TwoPiS * Fc / FFs;
  C := 1.0 / FastTan(Wc / 2.0);
  Phi := C * C;

  for I := 0 to 1 do
  begin
    K := C / Qs[I];
    A0 := Phi + K + 1.0;

    B[0] := Phi / A0;
    B[1] := -2.0 * B[0];
    B[2] := B[0];
    A[0] := 1.0;
    A[1] := 2.0 * (1.0 - Phi) / A0;
    A[2] := (Phi - K + 1.0) / A0;

    FHpf[I].SetCoefs(B, A);
  end;
end;

procedure TDCBlocker.ProcessBlock(Buffer: PSingle; NumSamples: Integer);
var
  I: Integer;
begin
  for I := 0 to 1 do
    FHpf[I].ProcessBlock(Buffer, NumSamples, 0);
end;

{ TDegradeFilter }

constructor TDegradeFilter.Create;
begin
  inherited Create;
  FFs := 44100.0;
  FFreq.SetCurrentAndTargetValue(20000.0);
  FFreq.Reset(200);
  FA[0] := 1.0; FA[1] := 0.0;
  FB[0] := 1.0; FB[1] := 0.0;
  FZ[0] := 0.0; FZ[1] := 0.0;
end;

procedure TDegradeFilter.Reset(ASampleRate: Single; Steps: Integer);
begin
  FFs := ASampleRate;
  FZ[0] := 0.0;
  FZ[1] := 0.0;
  if Steps > 0 then
    FFreq.Reset(Steps);
  FFreq.SetCurrentAndTargetValue(FFreq.GetTargetValue);
  CalcCoefs(FFreq.GetCurrentValue);
end;

procedure TDegradeFilter.CalcCoefs(Fc: Single);
var
  Wc, C, A0: Single;
begin
  Wc := TwoPiS * Fc / FFs;
  C := 1.0 / FastTan(Wc / 2.0);
  A0 := C + 1.0;

  FB[0] := 1.0 / A0;
  FB[1] := FB[0];
  FA[1] := (1.0 - C) / A0;
end;

function TDegradeFilter.ProcessSample(X: Single): Single;
begin
  Result := FZ[1] + X * FB[0];
  FZ[1] := X * FB[1] - Result * FA[1];
end;

procedure TDegradeFilter.Process(Buffer: PSingle; NumSamples: Integer);
var
  N: Integer;
  P: PSingleArray;
begin
  P := PSingleArray(Buffer);
  for N := 0 to NumSamples - 1 do
  begin
    if FFreq.IsSmoothing then
      CalcCoefs(FFreq.GetNextValue);
    P^[N] := ProcessSample(P^[N]);
  end;
end;

procedure TDegradeFilter.SetFreq(NewFreq: Single);
begin
  FFreq.SetTargetValue(NewFreq);
end;

{ TFIRFilter }

constructor TFIRFilter.Create(AOrder: Integer);
begin
  inherited Create;
  FNumChannels := 1;
  SetOrder(AOrder);
end;

procedure TFIRFilter.SetOrder(NewOrder: Integer);
begin
  FOrder := NewOrder;
  SetLength(FCoefficients, FOrder);
  Prepare(FNumChannels);
end;

procedure TFIRFilter.Prepare(ANumChannels: Integer);
begin
  FNumChannels := ANumChannels;
  SetLength(FState, ANumChannels * 2 * FOrder);
  SetLength(FZPtr, ANumChannels);
  Reset;
end;

procedure TFIRFilter.Reset;
var
  I: Integer;
begin
  for I := 0 to High(FState) do
    FState[I] := 0.0;
  for I := 0 to High(FZPtr) do
    FZPtr[I] := 0;
end;

procedure TFIRFilter.SetCoefficients(Coeffs: PSingle);
begin
  if FOrder > 0 then
    Move(Coeffs^, FCoefficients[0], FOrder * SizeOf(Single));
end;

function TFIRFilter.ProcessSample(X: Single; Channel: Integer): Single;
var
  Base, ZPtr, N, Limit: Integer;
  A0, A1, A2, A3: Single;
  Z, H: PSingleArray;
begin
  Base := Channel * 2 * FOrder;
  ZPtr := FZPtr[Channel];

  FState[Base + ZPtr] := X;
  FState[Base + ZPtr + FOrder] := X;

  // Two things matter in this loop, which runs 139 times per sample per
  // channel at 96 kHz. Indexing the dynamic arrays directly made the compiler
  // reload their pointers every tap, so they are hoisted; and a single
  // accumulator serialises on floating-point add latency, so the taps are
  // split across four. Summation order changes, which for a linear-phase FIR
  // costs nothing but the last bit or two.
  //
  // Worth knowing: dcc64 makes a markedly worse job of this loop than dcc32,
  // 2.6 ns per tap against 0.82, and it is not obvious why.
  Z := PSingleArray(@FState[Base + ZPtr]);
  H := PSingleArray(@FCoefficients[0]);

  A0 := 0.0;
  A1 := 0.0;
  A2 := 0.0;
  A3 := 0.0;

  Limit := FOrder - 3;
  N := 0;
  while N < Limit do
  begin
    A0 := A0 + Z^[N] * H^[N];
    A1 := A1 + Z^[N + 1] * H^[N + 1];
    A2 := A2 + Z^[N + 2] * H^[N + 2];
    A3 := A3 + Z^[N + 3] * H^[N + 3];
    Inc(N, 4);
  end;

  while N < FOrder do
  begin
    A0 := A0 + Z^[N] * H^[N];
    Inc(N);
  end;

  if ZPtr = 0 then
    FZPtr[Channel] := FOrder - 1
  else
    FZPtr[Channel] := ZPtr - 1;

  Result := (A0 + A1) + (A2 + A3);
end;

procedure TFIRFilter.ProcessBlock(Block: PSingle; NumSamples, Channel: Integer);
var
  N: Integer;
  P: PSingleArray;
begin
  P := PSingleArray(Block);
  for N := 0 to NumSamples - 1 do
    P^[N] := ProcessSample(P^[N], Channel);
end;

procedure TFIRFilter.ProcessBlockBypassed(Block: PSingle; NumSamples, Channel: Integer);
var
  N, Base, ZPtr: Integer;
  P: PSingleArray;
begin
  P := PSingleArray(Block);
  Base := Channel * 2 * FOrder;
  ZPtr := FZPtr[Channel];
  for N := 0 to NumSamples - 1 do
  begin
    FState[Base + ZPtr] := P^[N];
    FState[Base + ZPtr + FOrder] := P^[N];
    if ZPtr = 0 then
      ZPtr := FOrder - 1
    else
      Dec(ZPtr);
  end;
  FZPtr[Channel] := ZPtr;
end;

procedure TFIRFilter.ProcessBuffer(Buffer: TAudioBuffer);
var
  Ch: Integer;
begin
  for Ch := 0 to Buffer.NumChannels - 1 do
    ProcessBlock(Buffer.Channels[Ch], Buffer.NumSamples, Ch);
end;

procedure TFIRFilter.ProcessBufferBypassed(Buffer: TAudioBuffer);
var
  Ch: Integer;
begin
  for Ch := 0 to Buffer.NumChannels - 1 do
    ProcessBlockBypassed(Buffer.Channels[Ch], Buffer.NumSamples, Ch);
end;

{ TMultiChannelBiquad }

procedure TMultiChannelBiquad.Prepare(ANumChannels: Integer);
begin
  FNumChannels := ANumChannels;
  SetLength(FState, ANumChannels * 2);
  Reset;
end;

procedure TMultiChannelBiquad.Reset;
var
  I: Integer;
begin
  for I := 0 to High(FState) do
    FState[I] := 0.0;
end;

procedure TMultiChannelBiquad.MakePeakFilter(SampleRate: Double;
  Frequency, Q, GainFactor: Single);
var
  A, Omega, Alpha, C2, AlphaTimesA, AlphaOverA, A0Inv: Double;
  F: Double;
begin
  A := Sqrt(GainFactor);
  F := Frequency;
  if F < 2.0 then
    F := 2.0;
  Omega := (2.0 * PiD * F) / SampleRate;
  Alpha := Sin(Omega) / (Q * 2.0);
  C2 := -2.0 * Cos(Omega);
  AlphaTimesA := Alpha * A;
  AlphaOverA := Alpha / A;

  A0Inv := 1.0 / (1.0 + AlphaOverA);
  FCoeffs[0] := (1.0 + AlphaTimesA) * A0Inv;
  FCoeffs[1] := C2 * A0Inv;
  FCoeffs[2] := (1.0 - AlphaTimesA) * A0Inv;
  FCoeffs[3] := C2 * A0Inv;
  FCoeffs[4] := (1.0 - AlphaOverA) * A0Inv;
end;

procedure TMultiChannelBiquad.ProcessBuffer(Buffer: TAudioBuffer);
var
  Ch, N, Base: Integer;
  P: PSingleArray;
  S0, S1, X, Y: Single;
begin
  for Ch := 0 to Buffer.NumChannels - 1 do
  begin
    Base := Ch * 2;
    S0 := FState[Base];
    S1 := FState[Base + 1];
    P := PSingleArray(Buffer.Channels[Ch]);
    for N := 0 to Buffer.NumSamples - 1 do
    begin
      X := P^[N];
      Y := FCoeffs[0] * X + S0;
      S0 := FCoeffs[1] * X - FCoeffs[3] * Y + S1;
      S1 := FCoeffs[2] * X - FCoeffs[4] * Y;
      P^[N] := Y;
    end;
    SnapToZero(S0);
    SnapToZero(S1);
    FState[Base] := S0;
    FState[Base + 1] := S1;
  end;
end;

{ Helpers }

function ButterworthQs(N: Integer): TFloatArray;
var
  K, Lim: Integer;
  B: Double;
begin
  Lim := N div 2;
  SetLength(Result, Lim);
  for K := 1 to Lim do
  begin
    B := -2.0 * Cos((2.0 * K + N - 1) * PiD / (2.0 * N));
    Result[K - 1] := 1.0 / B;
  end;
end;

end.
