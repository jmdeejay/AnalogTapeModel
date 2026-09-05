unit ChowTape.DSP.Degrade;

{ Tape degradation: added noise (optionally following the signal envelope), a
  randomly-varying lowpass, and level loss. Parameters are re-randomised every
  2048 samples so the effect drifts across the tape. }

interface

uses
  System.Math, System.Generics.Collections, ChowTape.DSP.Types,
  ChowTape.DSP.Filters, ChowTape.DSP.Basics, ChowTape.DSP.Utils, ChowTape.Params;

type
  TDegradeNoise = class
  private
    FCurGain: Single;
    FPrevGain: Single;
    FRandom: TRandom;
  public
    constructor Create;
    procedure SetGain(NewGain: Single); inline;
    procedure Prepare;
    procedure ProcessBlock(Buffer: PSingle; NumSamples: Integer);
  end;

  TDegradeProcessor = class
  private
    FPoint1xParam, FOnOffParam: TParameter;
    FDepthParam, FAmtParam, FVarParam, FEnvParam: TParameter;

    FFilterProc: TObjectList<TDegradeFilter>;
    FGainProc: TGainProcessor;

    FNoiseBuffer: TAudioBuffer;
    FNoiseProc: TObjectList<TDegradeNoise>;

    FLevelBuffer: array of Single;
    FLevelDetector: TLevelDetector;

    FRandom: TRandom;
    FFs: Single;
    FBypass: TBypassProcessor;
    FSampleCounter: Integer;
    FSmallBuffer: TAudioBuffer;

    procedure ProcessShortBlock(Buffer: TAudioBuffer);
  public
    constructor Create(AParams: TParameterSet);
    destructor Destroy; override;
    procedure CookParams;
    procedure PrepareToPlay(SampleRate: Double; SamplesPerBlock, NumChannels: Integer);
    procedure ProcessBlock(Buffer: TAudioBuffer);
  end;

implementation

const
  SmallBlockSize = 2048;

{ TDegradeNoise }

constructor TDegradeNoise.Create;
begin
  inherited Create;
  FCurGain := 0.0;
  FPrevGain := 0.0;
  FRandom := CreateRandom;
end;

procedure TDegradeNoise.SetGain(NewGain: Single);
begin
  FCurGain := NewGain;
end;

procedure TDegradeNoise.Prepare;
begin
  FPrevGain := FCurGain;
end;

procedure TDegradeNoise.ProcessBlock(Buffer: PSingle; NumSamples: Integer);
var
  N: Integer;
  P: PSingleArray;
  T: Single;
begin
  P := PSingleArray(Buffer);
  if FCurGain = FPrevGain then
  begin
    for N := 0 to NumSamples - 1 do
      P^[N] := P^[N] + (FRandom.NextFloat - 0.5) * FCurGain;
  end
  else
  begin
    for N := 0 to NumSamples - 1 do
    begin
      T := N / NumSamples;
      P^[N] := P^[N] + (FRandom.NextFloat - 0.5) * ((FCurGain * T) + (FPrevGain * (1.0 - T)));
    end;
    FPrevGain := FCurGain;
  end;
end;

{ TDegradeProcessor }

constructor TDegradeProcessor.Create(AParams: TParameterSet);
begin
  inherited Create;
  FPoint1xParam := AParams.ByID(pidDegPoint1x);
  FOnOffParam := AParams.ByID(pidDegOnOff);
  FDepthParam := AParams.ByID(pidDegDepth);
  FAmtParam := AParams.ByID(pidDegAmt);
  FVarParam := AParams.ByID(pidDegVar);
  FEnvParam := AParams.ByID(pidDegEnv);

  FFilterProc := TObjectList<TDegradeFilter>.Create(True);
  FNoiseProc := TObjectList<TDegradeNoise>.Create(True);
  FGainProc := TGainProcessor.Create;
  FNoiseBuffer := TAudioBuffer.Create;
  FLevelDetector := TLevelDetector.Create;
  FBypass := TBypassProcessor.Create;
  FSmallBuffer := TAudioBuffer.Create;
  FRandom := CreateRandom;
  FFs := 44100.0;
end;

destructor TDegradeProcessor.Destroy;
begin
  FFilterProc.Free;
  FNoiseProc.Free;
  FGainProc.Free;
  FNoiseBuffer.Free;
  FLevelDetector.Free;
  FBypass.Free;
  FSmallBuffer.Free;
  inherited Destroy;
end;

procedure TDegradeProcessor.CookParams;
var
  Point1x: Boolean;
  DepthValue, FreqHz, GainDB, EnvSkew, VarVal, AmtVal: Single;
  I: Integer;
begin
  Point1x := FPoint1xParam.GetBool;
  DepthValue := FDepthParam.GetValue;
  if Point1x then
    DepthValue := DepthValue * 0.1;

  AmtVal := FAmtParam.GetValue;
  VarVal := FVarParam.GetValue;

  FreqHz := 200.0 * Power(20000.0 / 200.0, 1.0 - AmtVal);
  GainDB := -24.0 * DepthValue;

  for I := 0 to FNoiseProc.Count - 1 do
    FNoiseProc[I].SetGain(0.5 * DepthValue * AmtVal);

  for I := 0 to FFilterProc.Count - 1 do
    FFilterProc[I].SetFreq(JMinF(FreqHz + (VarVal * (FreqHz / 0.6) *
      (FRandom.NextFloat - 0.5)), 0.49 * FFs));

  EnvSkew := 1.0 - Power(FEnvParam.GetValue, 0.8);
  FLevelDetector.SetParameters(10.0, 20.0 * Power(5000.0 / 20.0, EnvSkew));

  FGainProc.SetGain(DecibelsToGain(JMinF(GainDB + (VarVal * 36.0 *
    (FRandom.NextFloat - 0.5)), 3.0)));
end;

procedure TDegradeProcessor.PrepareToPlay(SampleRate: Double;
  SamplesPerBlock, NumChannels: Integer);
var
  Ch: Integer;
  F: TDegradeFilter;
begin
  FFs := SampleRate;

  FNoiseProc.Clear;
  FFilterProc.Clear;
  for Ch := 0 to NumChannels - 1 do
  begin
    FNoiseProc.Add(TDegradeNoise.Create);
    F := TDegradeFilter.Create;
    F.Reset(SampleRate, 20);
    FFilterProc.Add(F);
  end;

  CookParams;

  for Ch := 0 to FNoiseProc.Count - 1 do
    FNoiseProc[Ch].Prepare;

  FNoiseBuffer.SetSize(NumChannels, SamplesPerBlock);
  SetLength(FLevelBuffer, SamplesPerBlock);

  FLevelDetector.Prepare(SampleRate, SamplesPerBlock);
  FGainProc.PrepareToPlay;
  FBypass.Prepare(SamplesPerBlock, NumChannels, FOnOffParam.GetBool);

  FSampleCounter := 0;
end;

procedure TDegradeProcessor.ProcessBlock(Buffer: TAudioBuffer);
var
  I, SamplesToProcess, Ch: Integer;
  Ptrs: array of PSingle;
begin
  SetLength(Ptrs, Buffer.NumChannels);
  for Ch := 0 to Buffer.NumChannels - 1 do
    Ptrs[Ch] := Buffer.Channels[Ch];

  I := 0;
  while I < Buffer.NumSamples do
  begin
    SamplesToProcess := Min(SmallBlockSize, Buffer.NumSamples - I);
    FSmallBuffer.SetDataToReferTo(Ptrs, Buffer.NumChannels, I, SamplesToProcess);
    ProcessShortBlock(FSmallBuffer);
    Inc(I, SamplesToProcess);
  end;
end;

procedure TDegradeProcessor.ProcessShortBlock(Buffer: TAudioBuffer);
var
  NumChannels, NumSamples, Ch, N: Integer;
  NoisePtr, XPtr: PSingleArray;
  ApplyEnvelope: Boolean;
begin
  if not FBypass.ProcessBlockIn(Buffer, FOnOffParam.GetBool) then
    Exit;

  NumChannels := Buffer.NumChannels;
  NumSamples := Buffer.NumSamples;

  Inc(FSampleCounter, NumSamples);
  if FSampleCounter >= SmallBlockSize then
  begin
    CookParams;
    FSampleCounter := 0;
  end;

  FNoiseBuffer.SetSize(NumChannels, NumSamples, False, False, True);
  FNoiseBuffer.Clear;

  FLevelDetector.ProcessBlock(Buffer, @FLevelBuffer[0], NumSamples);

  ApplyEnvelope := FEnvParam.GetValue > 0.0;

  for Ch := 0 to NumChannels - 1 do
  begin
    NoisePtr := PSingleArray(FNoiseBuffer.Channels[Ch]);
    FNoiseProc[Ch].ProcessBlock(FNoiseBuffer.Channels[Ch], NumSamples);

    if ApplyEnvelope then
      for N := 0 to NumSamples - 1 do
        NoisePtr^[N] := NoisePtr^[N] * FLevelBuffer[N];

    XPtr := PSingleArray(Buffer.Channels[Ch]);
    for N := 0 to NumSamples - 1 do
      XPtr^[N] := XPtr^[N] + NoisePtr^[N];

    FFilterProc[Ch].Process(Buffer.Channels[Ch], NumSamples);
  end;

  FGainProc.ProcessBlock(Buffer);
  FBypass.ProcessBlockOut(Buffer, FOnOffParam.GetBool);
end;

end.
