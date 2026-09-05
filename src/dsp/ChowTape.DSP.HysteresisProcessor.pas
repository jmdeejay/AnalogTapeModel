unit ChowTape.DSP.HysteresisProcessor;

{ Wraps the hysteresis solver: parameter smoothing, oversampling, the "V1"
  bias-oscillator mode kept for backwards compatibility, makeup gain and DC
  blocking. }

interface

uses
  System.Math, System.Generics.Collections, ChowTape.DSP.Types,
  ChowTape.DSP.Filters, ChowTape.DSP.Hysteresis, ChowTape.DSP.HysteresisSTN,
  ChowTape.DSP.VariableOS, ChowTape.DSP.Basics, ChowTape.Params;

type
  THysteresisProcessor = class
  private
    FDriveParam, FSatParam, FWidthParam, FModeParam, FOnOffParam: TParameter;

    FDrive, FWidth, FSat: TSmoothedLinearArray;
    FMakeup: TSmoothedValueMultiplicative;

    FFs: Double;
    FOSManager: TVariableOversampling;
    FHProcs: TObjectList<THysteresisProcessing>;
    FSolver: TSolverType;
    FDCBlocker: TObjectList<TDCBlocker>;

    FBiasGain: Double;
    FBiasFreq: Double;
    FBiasAngle: array of Double;
    FWasV1, FUseV1: Boolean;
    FClipLevel: Single;
    FSTNAvailable: Boolean;

    FDoubleBuffer: TAudioBufferD;
    FBypass: TBypassProcessor;
    FNumChannels: Integer;

    procedure SetSolver(NewSolver: Integer);
    procedure SetDrive(NewDrive: Single);
    procedure SetSaturation(NewSaturation: Single);
    procedure SetWidth(NewWidth: Single);
    procedure SetOversampling;
    function CalcMakeup: Double;
    procedure CalcBiasFreq;

    procedure DoProcess(Block: TAudioBufferD; NeedsSmoothing: Boolean);
    procedure DoProcessV1(Block: TAudioBufferD; NeedsSmoothing: Boolean);
    procedure ApplyMakeup(Block: TAudioBufferD);
    procedure ApplyDCBlockers(Buffer: TAudioBuffer);
  public
    constructor Create(AParams: TParameterSet);
    destructor Destroy; override;

    procedure PrepareToPlay(SampleRate: Double; SamplesPerBlock, NumChannels: Integer);
    procedure ReleaseResources;
    procedure ProcessBlock(Buffer: TAudioBuffer);
    function GetLatencySamples: Single;
    property OSManager: TVariableOversampling read FOSManager;
  end;

implementation

const
  NumSteps = 500;
  V1Norm = 1.414 / 10000.0;
  DCFreq = 35.0;

constructor THysteresisProcessor.Create(AParams: TParameterSet);
begin
  inherited Create;
  FDriveParam := AParams.ByID(pidDrive);
  FSatParam := AParams.ByID(pidSat);
  FWidthParam := AParams.ByID(pidWidth);
  FModeParam := AParams.ByID(pidMode);
  FOnOffParam := AParams.ByID(pidHystOnOff);

  FOSManager := TVariableOversampling.Create(AParams, False);
  FHProcs := TObjectList<THysteresisProcessing>.Create(True);
  FDCBlocker := TObjectList<TDCBlocker>.Create(True);
  FDoubleBuffer := TAudioBufferD.Create;
  FBypass := TBypassProcessor.Create;

  FFs := 44100.0;
  FSolver := stRK4;
  FBiasGain := 10.0;
  FBiasFreq := 48000.0;
  FClipLevel := 20.0;
  FWasV1 := False;
  FUseV1 := False;

  // Reading this here rather than per block keeps the file check off the audio
  // thread; the networks are parsed when the first solver is constructed.
  FSTNAvailable := STNModelsAvailable;
end;

destructor THysteresisProcessor.Destroy;
begin
  FOSManager.Free;
  FHProcs.Free;
  FDCBlocker.Free;
  FDoubleBuffer.Free;
  FBypass.Free;
  inherited Destroy;
end;

procedure THysteresisProcessor.SetSolver(NewSolver: Integer);
begin
  // "V1" is index NumSolvers -- an RK4 run with the old bias oscillator
  FUseV1 := NewSolver = NumSolvers;
  if FUseV1 then
    FSolver := stRK4
  else
    FSolver := TSolverType(EnsureRange(NewSolver, 0, NumSolvers - 1));

  // Without its trained networks the STN solver can only ever return zero, so
  // fall back to RK4 rather than silently muting the plug-in. The settings
  // menu reports when this is happening.
  if (FSolver = stSTN) and (not FSTNAvailable) then
    FSolver := stRK4;

  case FSolver of
    stRK2: FClipLevel := 8.0;
    stRK4: FClipLevel := 10.0;
    stNR4, stNR8: FClipLevel := 12.5;
  else
    FClipLevel := 20.0;
  end;
end;

function THysteresisProcessor.CalcMakeup: Double;
begin
  Result := (1.0 + 0.6 * FWidth[0].GetTargetValue) /
    (0.5 + 1.5 * (1.0 - FSat[0].GetTargetValue));
end;

procedure THysteresisProcessor.SetDrive(NewDrive: Single);
var
  I: Integer;
begin
  for I := 0 to High(FDrive) do
    FDrive[I].SetTargetValue(NewDrive);
end;

procedure THysteresisProcessor.SetWidth(NewWidth: Single);
var
  I: Integer;
begin
  for I := 0 to High(FWidth) do
    FWidth[I].SetTargetValue(NewWidth);
end;

procedure THysteresisProcessor.SetSaturation(NewSaturation: Single);
var
  I: Integer;
begin
  for I := 0 to High(FSat) do
    FSat[I].SetTargetValue(NewSaturation);
end;

procedure THysteresisProcessor.SetOversampling;
var
  Ch: Integer;
begin
  if FOSManager.UpdateOSFactor then
  begin
    for Ch := 0 to FHProcs.Count - 1 do
    begin
      FHProcs[Ch].SetSampleRate(FFs * FOSManager.GetOSFactor);
      FHProcs[Ch].Cook(FDrive[Ch].GetCurrentValue, FWidth[Ch].GetCurrentValue,
        FSat[Ch].GetCurrentValue, FWasV1);
      FHProcs[Ch].Reset;
    end;

    CalcBiasFreq;
  end;
end;

procedure THysteresisProcessor.CalcBiasFreq;
begin
  FBiasFreq := FFs * FOSManager.GetOSFactor / 2.0;
end;

procedure THysteresisProcessor.PrepareToPlay(SampleRate: Double;
  SamplesPerBlock, NumChannels: Integer);
var
  Ch: Integer;
  HP: THysteresisProcessing;
  DC: TDCBlocker;
begin
  FFs := SampleRate;
  FNumChannels := NumChannels;
  FWasV1 := FUseV1;

  FOSManager.PrepareToPlay(SampleRate, SamplesPerBlock, NumChannels);
  CalcBiasFreq;

  SetLength(FDrive, NumChannels);
  SetLength(FWidth, NumChannels);
  SetLength(FSat, NumChannels);
  for Ch := 0 to NumChannels - 1 do
  begin
    FDrive[Ch].Reset(NumSteps);
    FWidth[Ch].Reset(NumSteps);
    FSat[Ch].Reset(NumSteps);
  end;

  FHProcs.Clear;
  for Ch := 0 to NumChannels - 1 do
  begin
    HP := THysteresisProcessing.Create;
    HP.SetSampleRate(SampleRate * FOSManager.GetOSFactor);
    HP.Cook(FDrive[Ch].GetCurrentValue, FWidth[Ch].GetCurrentValue,
      FSat[Ch].GetCurrentValue, FWasV1);
    HP.Reset;
    FHProcs.Add(HP);
  end;

  SetLength(FBiasAngle, NumChannels);
  for Ch := 0 to NumChannels - 1 do
    FBiasAngle[Ch] := 0.0;

  FMakeup.Reset(NumSteps);

  FDCBlocker.Clear;
  for Ch := 0 to NumChannels - 1 do
  begin
    DC := TDCBlocker.Create;
    DC.Prepare(SampleRate, DCFreq);
    FDCBlocker.Add(DC);
  end;

  FDoubleBuffer.SetSize(NumChannels, SamplesPerBlock);
  FBypass.Prepare(SamplesPerBlock, NumChannels, FOnOffParam.GetBool);
end;

procedure THysteresisProcessor.ReleaseResources;
begin
  FOSManager.Reset;
end;

function THysteresisProcessor.GetLatencySamples: Single;
begin
  // oversampling latency plus a small fudge factor for the hysteresis itself
  if FOnOffParam.GetBool then
    Result := FOSManager.GetLatencySamples + 1.4
  else
    Result := 0.0;
end;

procedure THysteresisProcessor.ApplyMakeup(Block: TAudioBufferD);
var
  Ch, N: Integer;
  Scaler: Double;
  X: PDoubleBuf;
begin
  if FMakeup.IsSmoothing then
  begin
    for N := 0 to Block.NumSamples - 1 do
    begin
      Scaler := FMakeup.GetNextValue;
      for Ch := 0 to Block.NumChannels - 1 do
        PDoubleBuf(Block.Channels[Ch])^[N] := PDoubleBuf(Block.Channels[Ch])^[N] * Scaler;
    end;
  end
  else
  begin
    Scaler := FMakeup.GetTargetValue;
    for Ch := 0 to Block.NumChannels - 1 do
    begin
      X := PDoubleBuf(Block.Channels[Ch]);
      for N := 0 to Block.NumSamples - 1 do
        X^[N] := X^[N] * Scaler;
    end;
  end;
end;

procedure THysteresisProcessor.DoProcess(Block: TAudioBufferD; NeedsSmoothing: Boolean);
var
  Ch, N: Integer;
  X: PDoubleBuf;
  HP: THysteresisProcessing;
begin
  for Ch := 0 to Block.NumChannels - 1 do
  begin
    X := PDoubleBuf(Block.Channels[Ch]);
    HP := FHProcs[Ch];

    if NeedsSmoothing then
    begin
      for N := 0 to Block.NumSamples - 1 do
      begin
        HP.Cook(FDrive[Ch].GetNextValue, FWidth[Ch].GetNextValue,
          FSat[Ch].GetNextValue, False);
        X^[N] := HP.Process(FSolver, X^[N]);
      end;
    end
    else
    begin
      for N := 0 to Block.NumSamples - 1 do
        X^[N] := HP.Process(FSolver, X^[N]);
    end;
  end;

  ApplyMakeup(Block);
end;

procedure THysteresisProcessor.DoProcessV1(Block: TAudioBufferD; NeedsSmoothing: Boolean);
var
  Ch, N: Integer;
  X: PDoubleBuf;
  HP: THysteresisProcessing;
  AngleDelta, BAngle, BAngleMult, Bias: Double;
begin
  AngleDelta := TwoPiD * FBiasFreq / (FFs * FOSManager.GetOSFactor);

  for Ch := 0 to Block.NumChannels - 1 do
  begin
    X := PDoubleBuf(Block.Channels[Ch]);
    HP := FHProcs[Ch];
    BAngle := FBiasAngle[Ch];

    if NeedsSmoothing then
    begin
      for N := 0 to Block.NumSamples - 1 do
      begin
        HP.Cook(FDrive[Ch].GetNextValue, FWidth[Ch].GetNextValue,
          FSat[Ch].GetNextValue, True);

        Bias := FBiasGain * (1.0 - FWidth[Ch].GetCurrentValue) * Sin(BAngle);
        BAngle := BAngle + AngleDelta;
        if BAngle >= TwoPiD then
          BAngle := BAngle - TwoPiD;

        X^[N] := HP.Process(stRK4, (X^[N] + Bias) * 10000.0) * V1Norm;
      end;
    end
    else
    begin
      BAngleMult := FBiasGain * (1.0 - FWidth[Ch].GetCurrentValue);
      for N := 0 to Block.NumSamples - 1 do
      begin
        Bias := BAngleMult * Sin(BAngle);
        BAngle := BAngle + AngleDelta;
        if BAngle >= TwoPiD then
          BAngle := BAngle - TwoPiD;

        X^[N] := HP.Process(stRK4, (X^[N] + Bias) * 10000.0) * V1Norm;
      end;
    end;

    FBiasAngle[Ch] := BAngle;
  end;
end;

procedure THysteresisProcessor.ApplyDCBlockers(Buffer: TAudioBuffer);
var
  Ch: Integer;
begin
  for Ch := 0 to Buffer.NumChannels - 1 do
    FDCBlocker[Ch].ProcessBlock(Buffer.Channels[Ch], Buffer.NumSamples);
end;

procedure THysteresisProcessor.ProcessBlock(Buffer: TAudioBuffer);
var
  Ch, N: Integer;
  NeedsSmoothing: Boolean;
  P: PSingleArray;
  OSBlock: TAudioBufferD;
  I: Integer;
begin
  if not FBypass.ProcessBlockIn(Buffer, FOnOffParam.GetBool) then
    Exit;

  SetSolver(FModeParam.GetIndex);
  SetDrive(FDriveParam.GetValue);
  SetSaturation(FSatParam.GetValue);
  SetWidth(1.0 - FWidthParam.GetValue);
  FMakeup.SetTargetValue(CalcMakeup);
  SetOversampling;

  NeedsSmoothing := FDrive[0].IsSmoothing or FWidth[0].IsSmoothing or
    FSat[0].IsSmoothing or (FWasV1 <> FUseV1);

  if FUseV1 <> FWasV1 then
    for I := 0 to FHProcs.Count - 1 do
      FHProcs[I].Reset;

  FWasV1 := FUseV1;

  // clip the input: the solvers go unstable if driven too hard
  for Ch := 0 to Buffer.NumChannels - 1 do
  begin
    P := PSingleArray(Buffer.Channels[Ch]);
    for N := 0 to Buffer.NumSamples - 1 do
      P^[N] := JLimit(-FClipLevel, FClipLevel, P^[N]);
  end;

  FDoubleBuffer.CopyFromFloat(Buffer);
  OSBlock := FOSManager.ProcessSamplesUp(FDoubleBuffer);

  if FUseV1 then
    DoProcessV1(OSBlock, NeedsSmoothing)
  else
    DoProcess(OSBlock, NeedsSmoothing);

  FDoubleBuffer.NumSamples := Buffer.NumSamples;
  FOSManager.ProcessSamplesDown(FDoubleBuffer);
  FDoubleBuffer.CopyToFloat(Buffer);

  ApplyDCBlockers(Buffer);

  FBypass.ProcessBlockOut(Buffer, FOnOffParam.GetBool);
end;

end.
