unit ChowTape.DSP.WowFlutter;

{ Wow and flutter: two LFO generators modulate a fractional delay line.

  Flutter is a sum of three harmonically-related sinusoids; wow is a single slow
  sinusoid plus an Ornstein-Uhlenbeck random walk that provides the "variance"
  and "drift" behaviour. }

interface

uses
  System.Math, System.Generics.Collections, ChowTape.DSP.Types,
  ChowTape.DSP.FastMath, ChowTape.DSP.Filters, ChowTape.DSP.DelayLine,
  ChowTape.DSP.Basics, ChowTape.DSP.Utils, ChowTape.Params;

const
  { Slew floor below which a depth counts as "off". }
  DepthSlewMin = 0.001;

  { Relative phases of the three flutter partials. Declared in the interface
    because GetLFO is inlined. }
  PhaseOff1 = 0.0;
  PhaseOff2 = 13.0 * 3.14159265358979323846 / 4.0;
  PhaseOff3 = -3.14159265358979323846 / 10.0;

type
  { Ornstein-Uhlenbeck process, after ZetaCarinaeModules. }
  TOHProcess = class
  private
    FSqrtDelta: Single;
    FT: Single;
    FY: array of Single;
    FAmt, FMean, FDamping: Single;
    FNoiseGen: TNoiseGenerator;
    FNoiseBuffer: array of Single;
    FLpf: TSVFLowpass;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Prepare(SampleRate: Double; SamplesPerBlock, NumChannels: Integer);
    procedure PrepareBlock(AmtParam: Single; NumSamples: Integer);
    function Process(N, Ch: Integer): Single; inline;
  end;

  TFlutterProcess = class
  private
    FPhase1, FPhase2, FPhase3: TFloatArray;
    FAmp1, FAmp2, FAmp3: Single;
    FDepthSlew: TSmoothedMulArray;
    FAngleDelta1, FAngleDelta2, FAngleDelta3: Single;
    FDCOffset: Single;
    FBuffer: TAudioBuffer;
    FFs: Single;
    FTurnedOff: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Prepare(SampleRate: Double; SamplesPerBlock, NumChannels: Integer);
    procedure PrepareBlock(CurDepth, FlutterFreq: Single; NumSamples, NumChannels: Integer);
    function ShouldTurnOff: Boolean; inline;
    procedure UpdatePhase(Ch: Integer); inline;
    procedure GetLFO(N, Ch: Integer; out LFO, Offset: Single); inline;
    procedure BoundPhase(Ch: Integer); inline;
    function GetMeterValue: Single;
  end;

  TWowProcess = class
  private
    FAngleDelta: Single;
    FAmp: Single;
    FPhase: TFloatArray;
    FDepthSlew: TSmoothedMulArray;
    FBuffer: TAudioBuffer;
    FFs: Single;
    FOHProc: TOHProcess;
    FDriftRand: TRandom;
    FTurnedOff: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Prepare(SampleRate: Double; SamplesPerBlock, NumChannels: Integer);
    procedure PrepareBlock(CurDepth, WowFreq, WowVar, WowDrift: Single;
      NumSamples, NumChannels: Integer);
    function ShouldTurnOff: Boolean; inline;
    procedure UpdatePhase(Ch: Integer); inline;
    procedure GetLFO(N, Ch: Integer; out LFO, Offset: Single); inline;
    procedure BoundPhase(Ch: Integer); inline;
    function GetMeterValue: Single;
  end;

  TWowFlutterProcessor = class
  private
    FFlutterOnOff: TParameter;
    FFlutterRate, FFlutterDepth: TParameter;
    FWowRate, FWowDepth, FWowVariance, FWowDrift: TParameter;

    FBypass: TBypassProcessor;
    FFs: Single;

    FWowProcessor: TWowProcess;
    FFlutterProcessor: TFlutterProcess;

    FDelay: TDelayLine;
    FDCBlocker: TObjectList<TDCBlocker>;

    FWowMeter, FFlutterMeter: Single;

    procedure ProcessWetBuffer(Buffer: TAudioBuffer);
    procedure ProcessBypassed(Buffer: TAudioBuffer);
  public
    constructor Create(AParams: TParameterSet);
    destructor Destroy; override;
    procedure PrepareToPlay(SampleRate: Double; SamplesPerBlock, NumChannels: Integer);
    procedure ProcessBlock(Buffer: TAudioBuffer);
    property WowMeter: Single read FWowMeter;
    property FlutterMeter: Single read FFlutterMeter;
  end;

implementation

const
  HistorySize = 1 shl 21;

function BufferRMS(Buffer: TAudioBuffer): Single;
var
  N: Integer;
  P: PSingleArray;
  Sum: Double;
begin
  if (Buffer.NumChannels = 0) or (Buffer.NumSamples = 0) then
    Exit(0.0);
  P := PSingleArray(Buffer.Channels[0]);
  Sum := 0.0;
  for N := 0 to Buffer.NumSamples - 1 do
    Sum := Sum + P^[N] * P^[N];
  Result := Sqrt(Sum / Buffer.NumSamples);
  if IsNan(Result) then
    Result := 0.0;
end;

{ TOHProcess }

constructor TOHProcess.Create;
begin
  inherited Create;
  FNoiseGen := TNoiseGenerator.Create;
  FLpf := TSVFLowpass.Create;
  FSqrtDelta := 1.0 / Sqrt(48000.0);
  FT := 1.0 / 48000.0;
end;

destructor TOHProcess.Destroy;
begin
  FNoiseGen.Free;
  FLpf.Free;
  inherited Destroy;
end;

procedure TOHProcess.Prepare(SampleRate: Double; SamplesPerBlock, NumChannels: Integer);
var
  I: Integer;
begin
  FNoiseGen.SetGainLinear(1.0 / 2.33);

  FLpf.Prepare(SampleRate, NumChannels);
  FLpf.SetCutoffFrequency(10.0);
  FLpf.Reset;

  SetLength(FNoiseBuffer, SamplesPerBlock);

  FSqrtDelta := 1.0 / Sqrt(SampleRate);
  FT := 1.0 / SampleRate;

  SetLength(FY, NumChannels);
  for I := 0 to NumChannels - 1 do
    FY[I] := 1.0;
end;

procedure TOHProcess.PrepareBlock(AmtParam: Single; NumSamples: Integer);
var
  N: Integer;
begin
  if Length(FNoiseBuffer) < NumSamples then
    SetLength(FNoiseBuffer, NumSamples);

  for N := 0 to NumSamples - 1 do
    FNoiseBuffer[N] := 0.0;
  FNoiseGen.Process(@FNoiseBuffer[0], NumSamples);

  AmtParam := Power(AmtParam, 1.25);
  FAmt := AmtParam;
  FDamping := AmtParam * 20.0 + 1.0;
  FMean := AmtParam;
end;

function TOHProcess.Process(N, Ch: Integer): Single;
begin
  FY[Ch] := FY[Ch] + FSqrtDelta * FNoiseBuffer[N] * FAmt;
  FY[Ch] := FY[Ch] + FDamping * (FMean - FY[Ch]) * FT;
  Result := FLpf.ProcessSample(Ch, FY[Ch]);
end;

{ TFlutterProcess }

constructor TFlutterProcess.Create;
begin
  inherited Create;
  FBuffer := TAudioBuffer.Create;
  FFs := 48000.0;
end;

destructor TFlutterProcess.Destroy;
begin
  FBuffer.Free;
  inherited Destroy;
end;

procedure TFlutterProcess.Prepare(SampleRate: Double; SamplesPerBlock, NumChannels: Integer);
var
  I: Integer;
begin
  FFs := SampleRate;

  SetLength(FDepthSlew, NumChannels);
  for I := 0 to NumChannels - 1 do
  begin
    FDepthSlew[I].Reset(SampleRate, 0.05);
    FDepthSlew[I].SetCurrentAndTargetValue(DepthSlewMin);
  end;

  FTurnedOff := True;

  SetLength(FPhase1, NumChannels);
  SetLength(FPhase2, NumChannels);
  SetLength(FPhase3, NumChannels);
  for I := 0 to NumChannels - 1 do
  begin
    FPhase1[I] := 0.0;
    FPhase2[I] := 0.0;
    FPhase3[I] := 0.0;
  end;

  FAmp1 := -230.0 * 1000.0 / FFs;
  FAmp2 := -80.0 * 1000.0 / FFs;
  FAmp3 := -99.0 * 1000.0 / FFs;
  FDCOffset := 350.0 * 1000.0 / FFs;

  FBuffer.SetSize(NumChannels, SamplesPerBlock);
end;

procedure TFlutterProcess.PrepareBlock(CurDepth, FlutterFreq: Single;
  NumSamples, NumChannels: Integer);
var
  I: Integer;
begin
  // Comparing the slewed depth against the floor with = would be fragile, so
  // the "is it off?" decision is recorded here instead.
  FTurnedOff := CurDepth <= DepthSlewMin;

  for I := 0 to High(FDepthSlew) do
    FDepthSlew[I].SetTargetValue(JMaxF(DepthSlewMin, CurDepth));

  FAngleDelta1 := TwoPiS * FlutterFreq / FFs;
  FAngleDelta2 := 2.0 * FAngleDelta1;
  FAngleDelta3 := 3.0 * FAngleDelta1;

  FBuffer.SetSize(NumChannels, NumSamples, False, False, True);
  FBuffer.Clear;
end;

function TFlutterProcess.ShouldTurnOff: Boolean;
begin
  Result := FTurnedOff;
end;

procedure TFlutterProcess.UpdatePhase(Ch: Integer);
begin
  FPhase1[Ch] := FPhase1[Ch] + FAngleDelta1;
  FPhase2[Ch] := FPhase2[Ch] + FAngleDelta2;
  FPhase3[Ch] := FPhase3[Ch] + FAngleDelta3;
end;

procedure TFlutterProcess.GetLFO(N, Ch: Integer; out LFO, Offset: Single);
var
  V: Single;
begin
  // Three cosines per sample per channel, and Win64 has no hardware cosine:
  // this was most of the wow/flutter cost.
  UpdatePhase(Ch);
  V := FDepthSlew[Ch].GetNextValue *
    (FAmp1 * QuickCos(FPhase1[Ch] + PhaseOff1) +
     FAmp2 * QuickCos(FPhase2[Ch] + PhaseOff2) +
     FAmp3 * QuickCos(FPhase3[Ch] + PhaseOff3));
  PSingleArray(FBuffer.Channels[Ch])^[N] := V;
  LFO := V;
  Offset := FDCOffset;
end;

procedure TFlutterProcess.BoundPhase(Ch: Integer);
begin
  while FPhase1[Ch] >= TwoPiS do FPhase1[Ch] := FPhase1[Ch] - TwoPiS;
  while FPhase2[Ch] >= TwoPiS do FPhase2[Ch] := FPhase2[Ch] - TwoPiS;
  while FPhase3[Ch] >= TwoPiS do FPhase3[Ch] := FPhase3[Ch] - TwoPiS;
end;

function TFlutterProcess.GetMeterValue: Single;
begin
  if ShouldTurnOff then
    FBuffer.Clear;
  FBuffer.ApplyGain(1.3333 / FAmp1);
  Result := BufferRMS(FBuffer);
end;

{ TWowProcess }

constructor TWowProcess.Create;
begin
  inherited Create;
  FBuffer := TAudioBuffer.Create;
  FOHProc := TOHProcess.Create;
  FDriftRand := CreateRandom;
  FFs := 44100.0;
end;

destructor TWowProcess.Destroy;
begin
  FBuffer.Free;
  FOHProc.Free;
  inherited Destroy;
end;

procedure TWowProcess.Prepare(SampleRate: Double; SamplesPerBlock, NumChannels: Integer);
var
  I: Integer;
begin
  FFs := SampleRate;

  SetLength(FDepthSlew, NumChannels);
  for I := 0 to NumChannels - 1 do
  begin
    FDepthSlew[I].Reset(SampleRate, 0.05);
    FDepthSlew[I].SetCurrentAndTargetValue(DepthSlewMin);
  end;

  FTurnedOff := True;

  SetLength(FPhase, NumChannels);
  for I := 0 to NumChannels - 1 do
    FPhase[I] := 0.0;

  FAmp := 1000.0 * 1000.0 / SampleRate;
  FBuffer.SetSize(NumChannels, SamplesPerBlock);

  FOHProc.Prepare(SampleRate, SamplesPerBlock, NumChannels);
end;

procedure TWowProcess.PrepareBlock(CurDepth, WowFreq, WowVar, WowDrift: Single;
  NumSamples, NumChannels: Integer);
var
  I: Integer;
  FreqAdjust: Single;
begin
  FTurnedOff := CurDepth <= DepthSlewMin;

  for I := 0 to High(FDepthSlew) do
    FDepthSlew[I].SetTargetValue(JMaxF(DepthSlewMin, CurDepth));

  FreqAdjust := WowFreq * (1.0 + Power(FDriftRand.NextFloat, 1.25) * WowDrift);
  FAngleDelta := TwoPiS * FreqAdjust / FFs;

  FBuffer.SetSize(NumChannels, NumSamples, False, False, True);
  FBuffer.Clear;

  FOHProc.PrepareBlock(WowVar, NumSamples);
end;

function TWowProcess.ShouldTurnOff: Boolean;
begin
  Result := FTurnedOff;
end;

procedure TWowProcess.UpdatePhase(Ch: Integer);
begin
  FPhase[Ch] := FPhase[Ch] + FAngleDelta;
end;

procedure TWowProcess.GetLFO(N, Ch: Integer; out LFO, Offset: Single);
var
  CurDepth, V: Single;
begin
  UpdatePhase(Ch);
  CurDepth := FDepthSlew[Ch].GetNextValue * FAmp;
  V := CurDepth * (QuickCos(FPhase[Ch]) + FOHProc.Process(N, Ch));
  PSingleArray(FBuffer.Channels[Ch])^[N] := V;
  LFO := V;
  Offset := CurDepth;
end;

procedure TWowProcess.BoundPhase(Ch: Integer);
begin
  while FPhase[Ch] >= TwoPiS do
    FPhase[Ch] := FPhase[Ch] - TwoPiS;
end;

function TWowProcess.GetMeterValue: Single;
begin
  if ShouldTurnOff then
    FBuffer.Clear;
  FBuffer.ApplyGain(0.83333 / FAmp);
  Result := BufferRMS(FBuffer);
end;

{ TWowFlutterProcessor }

constructor TWowFlutterProcessor.Create(AParams: TParameterSet);
begin
  inherited Create;
  FFlutterRate := AParams.ByID(pidFlutterRate);
  FFlutterDepth := AParams.ByID(pidFlutterDepth);
  FWowRate := AParams.ByID(pidWowRate);
  FWowDepth := AParams.ByID(pidWowDepth);
  FWowVariance := AParams.ByID(pidWowVar);
  FWowDrift := AParams.ByID(pidWowDrift);
  FFlutterOnOff := AParams.ByID(pidFlutterOnOff);

  FBypass := TBypassProcessor.Create;
  FWowProcessor := TWowProcess.Create;
  FFlutterProcessor := TFlutterProcess.Create;
  FDelay := TDelayLine.Create(HistorySize, diLagrange3rd);
  FDCBlocker := TObjectList<TDCBlocker>.Create(True);
  FFs := 48000.0;
end;

destructor TWowFlutterProcessor.Destroy;
begin
  FBypass.Free;
  FWowProcessor.Free;
  FFlutterProcessor.Free;
  FDelay.Free;
  FDCBlocker.Free;
  inherited Destroy;
end;

procedure TWowFlutterProcessor.PrepareToPlay(SampleRate: Double;
  SamplesPerBlock, NumChannels: Integer);
var
  Ch: Integer;
  DC: TDCBlocker;
begin
  FFs := SampleRate;

  FBypass.Prepare(SamplesPerBlock, NumChannels, FFlutterOnOff.GetBool);
  FWowProcessor.Prepare(SampleRate, SamplesPerBlock, NumChannels);
  FFlutterProcessor.Prepare(SampleRate, SamplesPerBlock, NumChannels);

  FDelay.Prepare(NumChannels);
  FDelay.SetDelay(0.0);

  FDCBlocker.Clear;
  for Ch := 0 to NumChannels - 1 do
  begin
    DC := TDCBlocker.Create;
    DC.Prepare(SampleRate, 15.0);
    FDCBlocker.Add(DC);
  end;
end;

procedure TWowFlutterProcessor.ProcessBlock(Buffer: TAudioBuffer);
var
  NumChannels, NumSamples, Ch: Integer;
  CurDepthWow, WowFreq, CurDepthFlutter, FlutterFreq: Single;
  TurnOff: Boolean;
begin
  NumChannels := Buffer.NumChannels;
  NumSamples := Buffer.NumSamples;

  CurDepthWow := Power(FWowDepth.GetValue, 3.0);
  WowFreq := Power(4.5, FWowRate.GetValue) - 1.0;
  FWowProcessor.PrepareBlock(CurDepthWow, WowFreq, FWowVariance.GetValue,
    FWowDrift.GetValue, NumSamples, NumChannels);

  CurDepthFlutter := Power(Power(FFlutterDepth.GetValue, 3.0) * 81.0 / 625.0, 0.5);
  FlutterFreq := 0.1 * Power(1000.0, FFlutterRate.GetValue);
  FFlutterProcessor.PrepareBlock(CurDepthFlutter, FlutterFreq, NumSamples, NumChannels);

  TurnOff := (not FFlutterOnOff.GetBool) or
    (FWowProcessor.ShouldTurnOff and FFlutterProcessor.ShouldTurnOff);

  if FBypass.ProcessBlockIn(Buffer, not TurnOff) then
  begin
    ProcessWetBuffer(Buffer);

    for Ch := 0 to NumChannels - 1 do
      FDCBlocker[Ch].ProcessBlock(Buffer.Channels[Ch], NumSamples);

    FBypass.ProcessBlockOut(Buffer, not TurnOff);
  end
  else
    ProcessBypassed(Buffer);

  FWowMeter := FWowProcessor.GetMeterValue;
  FFlutterMeter := FFlutterProcessor.GetMeterValue;
end;

procedure TWowFlutterProcessor.ProcessWetBuffer(Buffer: TAudioBuffer);
var
  Ch, N: Integer;
  X: PSingleArray;
  WowLFO, WowOffset, FlutterLFO, FlutterOffset, NewLength: Single;
begin
  for Ch := 0 to Buffer.NumChannels - 1 do
  begin
    X := PSingleArray(Buffer.Channels[Ch]);
    for N := 0 to Buffer.NumSamples - 1 do
    begin
      FWowProcessor.GetLFO(N, Ch, WowLFO, WowOffset);
      FFlutterProcessor.GetLFO(N, Ch, FlutterLFO, FlutterOffset);

      NewLength := (WowLFO + FlutterLFO + FlutterOffset + WowOffset) * FFs / 1000.0;
      NewLength := JLimit(0.0, HistorySize, NewLength);

      FDelay.SetDelay(NewLength);
      FDelay.PushSample(Ch, X^[N]);
      X^[N] := FDelay.PopSample(Ch);
    end;

    FWowProcessor.BoundPhase(Ch);
    FFlutterProcessor.BoundPhase(Ch);
  end;
end;

procedure TWowFlutterProcessor.ProcessBypassed(Buffer: TAudioBuffer);
var
  Ch, N: Integer;
begin
  for Ch := 0 to Buffer.NumChannels - 1 do
  begin
    FDelay.SetDelay(0.0);
    for N := 0 to Buffer.NumSamples - 1 do
    begin
      FWowProcessor.UpdatePhase(Ch);
      FFlutterProcessor.UpdatePhase(Ch);

      FDelay.PushSample(Ch, 0.0);
      FDelay.PopSample(Ch);
    end;

    FWowProcessor.BoundPhase(Ch);
    FFlutterProcessor.BoundPhase(Ch);
  end;
end;

end.
