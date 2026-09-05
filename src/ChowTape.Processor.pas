unit ChowTape.Processor;

{
  Top-level audio processor: owns the parameter set and the whole signal chain,
  and mirrors the block ordering of the original PluginProcessor.

  Chain: in gain -> input filters -> [mid/side encode] -> tone in -> compression
         -> hysteresis -> tone out -> chew -> degrade -> wow/flutter -> loss
         -> [mid/side decode] -> filter makeup -> out gain -> dry/wet
}

interface

uses
  System.SysUtils, System.Classes, System.Math, System.Generics.Collections,
  System.SyncObjs,
  ChowTape.DSP.Types, ChowTape.DSP.Basics, ChowTape.DSP.DelayLine,
  ChowTape.DSP.InputFilters, ChowTape.DSP.MidSide, ChowTape.DSP.ToneControl,
  ChowTape.DSP.Compression, ChowTape.DSP.HysteresisProcessor,
  ChowTape.DSP.Chew, ChowTape.DSP.Degrade, ChowTape.DSP.Loss,
  ChowTape.DSP.WowFlutter, ChowTape.DSP.Scope, ChowTape.Params,
  ChowTape.PresetLibrary;

type
  TLatencyChangedEvent = procedure(Sender: TObject; LatencySamples: Integer) of object;
  TParamChangedEvent = procedure(Sender: TObject; ParamIndex: Integer) of object;

  TChowTapeProcessor = class
  private
    FParams: TParameterSet;

    FInGainParam, FOutGainParam, FDryWetParam, FMixGroupParam: TParameter;

    FInGain, FOutGain: TGainProcessor;
    FInputFilters: TInputFilters;
    FMidSide: TMidSideProcessor;
    FToneControl: TToneControl;
    FCompression: TCompressionProcessor;
    FHysteresis: THysteresisProcessor;
    FDegrade: TDegradeProcessor;
    FChew: TChewProcessor;
    FLoss: TLossFilter;
    FFlutter: TWowFlutterProcessor;
    FDryWet: TDryWetProcessor;
    FDryDelay: TDelayLine;
    FScope: TTapeScope;

    FDryBuffer: TAudioBuffer;
    FWorkBuffer: TAudioBuffer;

    FSampleRate: Double;
    FBlockSize: Integer;
    FNumChannels: Integer;
    FPrepared: Boolean;
    FLatencySamples: Integer;

    FBpm: Double;
    FTimeSigNumerator: Integer;

    FOnLatencyChanged: TLatencyChangedEvent;
    FOnParamChanged: TParamChangedEvent;

    FPresetLibrary: TPresetLibrary;
    FEditorWidth, FEditorHeight: Integer;

    procedure LatencyCompensation;
    function CalcLatencySamples: Single;
  public
    constructor Create;
    destructor Destroy; override;

    procedure PrepareToPlay(SampleRate: Double; SamplesPerBlock, NumChannels: Integer);
    procedure ReleaseResources;
    procedure ProcessBlock(Inputs, Outputs: PPSingle; NumChannels, NumSamples: Integer);
    procedure ProcessBlockBypassed(Inputs, Outputs: PPSingle; NumChannels, NumSamples: Integer);

    { Called whenever a parameter changed, from the host, the editor or a mix
      group peer. Source = nil means "propagate to the mix group". }
    procedure ParameterChanged(Param: TParameter; FromMixGroup: Boolean = False);

    function SaveState: TBytes;
    procedure LoadState(const Data: TBytes);

    property Params: TParameterSet read FParams;
    property Presets: TPresetLibrary read FPresetLibrary;
    property Scope: TTapeScope read FScope;
    property Flutter: TWowFlutterProcessor read FFlutter;
    property Hysteresis: THysteresisProcessor read FHysteresis;
    property SampleRate: Double read FSampleRate;
    property LatencySamples: Integer read FLatencySamples;
    property Bpm: Double read FBpm write FBpm;
    property TimeSigNumerator: Integer read FTimeSigNumerator write FTimeSigNumerator;
    property NumChannels: Integer read FNumChannels;
    { The size the editor was last left at, carried in the plug-in state. }
    property EditorWidth: Integer read FEditorWidth write FEditorWidth;
    property EditorHeight: Integer read FEditorHeight write FEditorHeight;
    property OnLatencyChanged: TLatencyChangedEvent read FOnLatencyChanged write FOnLatencyChanged;
    property OnParamChanged: TParamChangedEvent read FOnParamChanged write FOnParamChanged;
  end;

implementation

{ ---------------------------------------------------------------------------
  Mix groups.

  Instances that pick the same group keep their parameters in sync. The original
  does this through shared plug-in state; here a process-wide registry gives the
  same behaviour for every instance loaded in one host.
  --------------------------------------------------------------------------- }
var
  GInstances: TList<TChowTapeProcessor> = nil;
  GInstanceLock: TCriticalSection = nil;

procedure RegisterInstance(P: TChowTapeProcessor);
begin
  GInstanceLock.Enter;
  try
    GInstances.Add(P);
  finally
    GInstanceLock.Leave;
  end;
end;

procedure UnregisterInstance(P: TChowTapeProcessor);
begin
  GInstanceLock.Enter;
  try
    GInstances.Remove(P);
  finally
    GInstanceLock.Leave;
  end;
end;

{ TChowTapeProcessor }

constructor TChowTapeProcessor.Create;
begin
  inherited Create;
  FParams := CreateTapeParameters;
  FEditorWidth := 0;    // "not set": the editor falls back to its design size
  FEditorHeight := 0;

  FInGainParam := FParams.ByID(pidInGain);
  FOutGainParam := FParams.ByID(pidOutGain);
  FDryWetParam := FParams.ByID(pidDryWet);
  FMixGroupParam := FParams.ByID(pidMixGroup);

  FInGain := TGainProcessor.Create;
  FOutGain := TGainProcessor.Create;
  FInputFilters := TInputFilters.Create(FParams);
  FMidSide := TMidSideProcessor.Create(FParams);
  FToneControl := TToneControl.Create(FParams);
  FCompression := TCompressionProcessor.Create(FParams);
  FHysteresis := THysteresisProcessor.Create(FParams);
  FDegrade := TDegradeProcessor.Create(FParams);
  FChew := TChewProcessor.Create(FParams);
  FLoss := TLossFilter.Create(FParams);
  FFlutter := TWowFlutterProcessor.Create(FParams);
  FDryWet := TDryWetProcessor.Create;
  FDryDelay := TDelayLine.Create(1 shl 21, diLagrange5th);
  FScope := TTapeScope.Create;

  FDryBuffer := TAudioBuffer.Create;
  FWorkBuffer := TAudioBuffer.Create;

  FSampleRate := 44100.0;
  FBlockSize := 512;
  FNumChannels := 2;
  FBpm := 120.0;
  FTimeSigNumerator := 4;

  FPresetLibrary := TPresetLibrary.Create(FParams);

  // Renoise stages gain differently, but VST 2.4 gives us no reliable way to
  // detect the host here, so we use the standard scale.
  FToneControl.SetDBScale(18.0);

  RegisterInstance(Self);
end;

destructor TChowTapeProcessor.Destroy;
begin
  UnregisterInstance(Self);

  FInGain.Free;
  FOutGain.Free;
  FInputFilters.Free;
  FMidSide.Free;
  FToneControl.Free;
  FCompression.Free;
  FHysteresis.Free;
  FDegrade.Free;
  FChew.Free;
  FLoss.Free;
  FFlutter.Free;
  FDryWet.Free;
  FDryDelay.Free;
  FScope.Free;
  FDryBuffer.Free;
  FWorkBuffer.Free;
  FPresetLibrary.Free;
  FParams.Free;
  inherited Destroy;
end;

procedure TChowTapeProcessor.PrepareToPlay(SampleRate: Double;
  SamplesPerBlock, NumChannels: Integer);
begin
  FSampleRate := SampleRate;
  FBlockSize := SamplesPerBlock;
  FNumChannels := NumChannels;

  FInGain.PrepareToPlay;
  FInputFilters.PrepareToPlay(SampleRate, SamplesPerBlock, NumChannels);
  FMidSide.Prepare(SampleRate, SamplesPerBlock);
  FToneControl.Prepare(SampleRate, NumChannels);
  FCompression.Prepare(SampleRate, SamplesPerBlock, NumChannels);
  FHysteresis.PrepareToPlay(SampleRate, SamplesPerBlock, NumChannels);
  FDegrade.PrepareToPlay(SampleRate, SamplesPerBlock, NumChannels);
  FChew.Prepare(SampleRate, SamplesPerBlock, NumChannels);
  FLoss.Prepare(SampleRate, SamplesPerBlock, NumChannels);

  FDryDelay.Prepare(NumChannels);
  FDryDelay.SetDelay(CalcLatencySamples);

  FFlutter.PrepareToPlay(SampleRate, SamplesPerBlock, NumChannels);
  FOutGain.PrepareToPlay;

  FScope.PrepareToPlay(SampleRate, SamplesPerBlock);

  FDryWet.SetDryWet(FDryWetParam.GetValue);
  FDryWet.Reset;
  FDryBuffer.SetSize(NumChannels, SamplesPerBlock);
  FWorkBuffer.SetSize(NumChannels, SamplesPerBlock);

  FLatencySamples := Round(CalcLatencySamples);
  if Assigned(FOnLatencyChanged) then
    FOnLatencyChanged(Self, FLatencySamples);

  FPrepared := True;
end;

procedure TChowTapeProcessor.ReleaseResources;
begin
  FHysteresis.ReleaseResources;
end;

function TChowTapeProcessor.CalcLatencySamples: Single;
begin
  Result := FLoss.GetLatencySamples + FHysteresis.GetLatencySamples +
    FCompression.GetLatencySamples;
end;

procedure TChowTapeProcessor.LatencyCompensation;
var
  LatencySampFloat: Single;
  LatencySamp: Integer;
begin
  LatencySampFloat := CalcLatencySamples;
  LatencySamp := Round(LatencySampFloat);

  if LatencySamp <> FLatencySamples then
  begin
    FLatencySamples := LatencySamp;
    if Assigned(FOnLatencyChanged) then
      FOnLatencyChanged(Self, FLatencySamples);
  end;

  FInputFilters.SetMakeupDelay(LatencySampFloat);

  // for near-true-bypass settings use a whole-sample delay, so that the
  // interpolator's frequency response cannot colour the dry path
  if FDryWet.GetDryWet < 0.15 then
    FDryDelay.SetDelay(LatencySamp)
  else
    FDryDelay.SetDelay(LatencySampFloat);

  FDryDelay.ProcessBuffer(FDryBuffer);
end;

procedure TChowTapeProcessor.ProcessBlock(Inputs, Outputs: PPSingle;
  NumChannels, NumSamples: Integer);
var
  Ch, N: Integer;
  Ptrs: array of PSingle;
  Src, Dst: PSingleArray;
begin
  if not FPrepared then
    Exit;

  // hosts are allowed to hand us a bigger block than they promised
  if (NumSamples > FBlockSize) or (NumChannels <> FNumChannels) then
    PrepareToPlay(FSampleRate, Max(NumSamples, FBlockSize), NumChannels);

  // copy the input into our own storage so the chain can work in place
  SetLength(Ptrs, NumChannels);
  for Ch := 0 to NumChannels - 1 do
    Ptrs[Ch] := PPSingleArray(Outputs)^[Ch];

  FWorkBuffer.SetSize(NumChannels, NumSamples, False, False, True);
  for Ch := 0 to NumChannels - 1 do
  begin
    Src := PSingleArray(PPSingleArray(Inputs)^[Ch]);
    Dst := PSingleArray(FWorkBuffer.Channels[Ch]);
    Move(Src^, Dst^, NumSamples * SizeOf(Single));
  end;

  FInGain.SetGain(DecibelsToGain(FInGainParam.GetValue));
  FOutGain.SetGain(DecibelsToGain(FOutGainParam.GetValue));
  FDryWet.SetDryWet(FDryWetParam.GetValue);

  FDryBuffer.CopyFrom(FWorkBuffer, True);

  FInGain.ProcessBlock(FWorkBuffer);
  FInputFilters.ProcessBlock(FWorkBuffer);

  FScope.PushInput(FWorkBuffer);

  FMidSide.ProcessInput(FWorkBuffer);
  FToneControl.ProcessBlockIn(FWorkBuffer);
  FCompression.ProcessBlock(FWorkBuffer);
  FHysteresis.ProcessBlock(FWorkBuffer);
  FToneControl.ProcessBlockOut(FWorkBuffer);
  FChew.ProcessBlock(FWorkBuffer);
  FDegrade.ProcessBlock(FWorkBuffer);
  FFlutter.ProcessBlock(FWorkBuffer);
  FLoss.ProcessBlock(FWorkBuffer);

  LatencyCompensation;

  FMidSide.ProcessOutput(FWorkBuffer);
  FInputFilters.ProcessBlockMakeup(FWorkBuffer);
  FOutGain.ProcessBlock(FWorkBuffer);
  FDryWet.ProcessBlock(FDryBuffer, FWorkBuffer);

  for Ch := 0 to NumChannels - 1 do
  begin
    Src := PSingleArray(FWorkBuffer.Channels[Ch]);
    for N := 0 to NumSamples - 1 do
      Src^[N] := SanitizeFloat(Src^[N]);
  end;

  FScope.PushOutput(FWorkBuffer);

  for Ch := 0 to NumChannels - 1 do
  begin
    Src := PSingleArray(FWorkBuffer.Channels[Ch]);
    Dst := PSingleArray(Ptrs[Ch]);
    Move(Src^, Dst^, NumSamples * SizeOf(Single));
  end;
end;

procedure TChowTapeProcessor.ProcessBlockBypassed(Inputs, Outputs: PPSingle;
  NumChannels, NumSamples: Integer);
var
  Ch: Integer;
  Src, Dst: PSingleArray;
begin
  if not FPrepared then
    Exit;

  if (NumSamples > FBlockSize) or (NumChannels <> FNumChannels) then
    PrepareToPlay(FSampleRate, Max(NumSamples, FBlockSize), NumChannels);

  FDryBuffer.SetSize(NumChannels, NumSamples, False, False, True);
  for Ch := 0 to NumChannels - 1 do
  begin
    Src := PSingleArray(PPSingleArray(Inputs)^[Ch]);
    Dst := PSingleArray(FDryBuffer.Channels[Ch]);
    Move(Src^, Dst^, NumSamples * SizeOf(Single));
  end;

  LatencyCompensation;

  for Ch := 0 to NumChannels - 1 do
  begin
    Src := PSingleArray(FDryBuffer.Channels[Ch]);
    Dst := PSingleArray(PPSingleArray(Outputs)^[Ch]);
    Move(Src^, Dst^, NumSamples * SizeOf(Single));
  end;
end;

procedure TChowTapeProcessor.ParameterChanged(Param: TParameter; FromMixGroup: Boolean);
var
  I: Integer;
  Group: Integer;
  Other: TChowTapeProcessor;
  OtherParam: TParameter;
begin
  if Assigned(FOnParamChanged) then
    FOnParamChanged(Self, Param.Index);

  if FromMixGroup then
    Exit;

  Group := FMixGroupParam.GetIndex;
  if (Group = 0) or (Param = FMixGroupParam) then
    Exit;

  GInstanceLock.Enter;
  try
    for I := 0 to GInstances.Count - 1 do
    begin
      Other := GInstances[I];
      if Other = Self then
        Continue;
      if Other.Params.IndexOf(pidMixGroup) <> Group then
        Continue;

      OtherParam := Other.Params.ByID(Param.ID);
      if OtherParam <> nil then
      begin
        OtherParam.Normalised := Param.Normalised;
        Other.ParameterChanged(OtherParam, True);
      end;
    end;
  finally
    GInstanceLock.Leave;
  end;
end;

function TChowTapeProcessor.SaveState: TBytes;
var
  SL: TStringList;
  I: Integer;
  S: string;
  FS: TFormatSettings;
begin
  FS := TFormatSettings.Invariant;
  SL := TStringList.Create;
  try
    SL.Add('ChowTapeModel');
    SL.Add('version=1');
    SL.Add('preset=' + FPresetLibrary.CurrentName);
    SL.Add('presetmodified=' + IntToStr(Ord(FPresetLibrary.IsDirty)));
    { foleys stores the last editor size in the plug-in state, so a session
      reopens at the size it was left at }
    SL.Add('editorwidth=' + IntToStr(FEditorWidth));
    SL.Add('editorheight=' + IntToStr(FEditorHeight));
    for I := 0 to FParams.Count - 1 do
      SL.Add(FParams[I].ID + '=' + FloatToStr(FParams[I].Normalised, FS));
    S := SL.Text;
  finally
    SL.Free;
  end;
  Result := TEncoding.UTF8.GetBytes(S);
end;

procedure TChowTapeProcessor.LoadState(const Data: TBytes);
var
  SL: TStringList;
  I, EqPos: Integer;
  Line, Key, Value: string;
  PresetName: string;
  PresetModified: Boolean;
  P: TParameter;
  V: Double;
  FS: TFormatSettings;
begin
  if Length(Data) = 0 then
    Exit;

  PresetName := '';
  PresetModified := False;

  FS := TFormatSettings.Invariant;
  SL := TStringList.Create;
  try
    SL.Text := TEncoding.UTF8.GetString(Data);
    if (SL.Count = 0) or (Trim(SL[0]) <> 'ChowTapeModel') then
      Exit;

    for I := 1 to SL.Count - 1 do
    begin
      Line := SL[I];
      EqPos := Pos('=', Line);
      if EqPos <= 0 then
        Continue;
      Key := Copy(Line, 1, EqPos - 1);
      Value := Copy(Line, EqPos + 1, MaxInt);

      if Key = 'version' then
        Continue;
      if Key = 'preset' then
      begin
        PresetName := Value;
        Continue;
      end;
      if Key = 'presetmodified' then
      begin
        PresetModified := Value <> '0';
        Continue;
      end;
      if Key = 'editorwidth' then
      begin
        FEditorWidth := StrToIntDef(Value, FEditorWidth);
        Continue;
      end;
      if Key = 'editorheight' then
      begin
        FEditorHeight := StrToIntDef(Value, FEditorHeight);
        Continue;
      end;

      P := FParams.ByID(Key);
      if (P <> nil) and TryStrToFloat(Value, V, FS) then
        P.Normalised := EnsureRange(V, 0.0, 1.0);
    end;
  finally
    SL.Free;
  end;

  // The state carries parameter values directly, so the preset name is only a
  // label; re-select it and restore whether it had been edited.
  if PresetName <> '' then
    FPresetLibrary.SelectByName(PresetName);
  if PresetModified then
    FPresetLibrary.MarkDirty
  else
    FPresetLibrary.MarkClean;

  if FPrepared then
  begin
    FLatencySamples := Round(CalcLatencySamples);
    if Assigned(FOnLatencyChanged) then
      FOnLatencyChanged(Self, FLatencySamples);
  end;
end;

initialization
  GInstanceLock := TCriticalSection.Create;
  GInstances := TList<TChowTapeProcessor>.Create;

finalization
  GInstances.Free;
  GInstanceLock.Free;

end.
