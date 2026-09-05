unit ChowTape.VST2.Plugin;

{
  The VST 2.4 wrapper: owns an AEffect record, the DSP processor and the editor,
  and translates between the host's opcode interface and them.
}

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.Math,
  System.Generics.Collections,   // so TParameterSet's inline getters can expand
  ChowTape.VST2.Intf, ChowTape.Processor, ChowTape.Params, ChowTape.Presets,
  ChowTape.PresetLibrary, ChowTape.GUI.Editor, ChowTape.GUI.Menu;

const
  ChowTapeUniqueID = $43684D64;  // 'ChMd'
  ChowTapeVersion  = 1000;       // 1.0.0.0
  ChowTapeNumIO    = 2;

type
  TChowTapePlugin = class
  private
    FEffect: TAEffect;
    FMaster: TAudioMasterCallback;
    FProcessor: TChowTapeProcessor;
    FEditor: TTapeEditor;
    FEditorRect: TERect;
    FSampleRate: Double;
    FBlockSize: Integer;
    FPreparedRate: Double;
    FPreparedBlock: Integer;
    FBypassed: Boolean;
    FCurrentProgram: Integer;
    FChunk: TBytes;
    { An editor whose close had to wait for a menu's modal loop to unwind. }
    FEditorPendingFree: Boolean;

    procedure HandleLatencyChanged(Sender: TObject; LatencySamples: Integer);
    procedure HandleBeginGesture(Sender: TObject; Param: TParameter);
    procedure HandleParamEdit(Sender: TObject; Param: TParameter);
    procedure HandleEndGesture(Sender: TObject; Param: TParameter);
    procedure HandleEditorResized(Sender: TObject; W, H: Integer);
    procedure ReleaseClosedEditor;
    procedure UpdateTimeInfo;
    procedure PrepareIfNeeded;
    function CallMaster(Opcode, Index: VstInt32; Value: VstIntPtr; Ptr: Pointer;
      Opt: Single): VstIntPtr;
  public
    constructor Create(AMaster: TAudioMasterCallback);
    destructor Destroy; override;

    function Dispatch(Opcode, Index: VstInt32; Value: VstIntPtr; Ptr: Pointer;
      Opt: Single): VstIntPtr;
    procedure SetParameter(Index: VstInt32; Value: Single);
    function GetParameter(Index: VstInt32): Single;
    procedure ProcessReplacing(Inputs, Outputs: PPSingle; SampleFrames: VstInt32);

    function AEffectPtr: PAEffect;
  end;

function VSTPluginMain(AMaster: TAudioMasterCallback): PAEffect; cdecl;

implementation

{ ---------------------------------------------------------------------------
  C entry points -- these forward to the object stored in AEffect.object
  --------------------------------------------------------------------------- }

function EffectFromAEffect(E: PAEffect): TChowTapePlugin; inline;
begin
  if E = nil then
    Result := nil
  else
    Result := TChowTapePlugin(E^.ObjectPtr);
end;

function DispatcherProc(E: PAEffect; Opcode, Index: VstInt32; Value: VstIntPtr;
  Ptr: Pointer; Opt: Single): VstIntPtr; cdecl;
var
  Plugin: TChowTapePlugin;
begin
  Plugin := EffectFromAEffect(E);
  if Plugin = nil then
    Exit(0);
  try
    Result := Plugin.Dispatch(Opcode, Index, Value, Ptr, Opt);
  except
    Result := 0;
  end;
end;

procedure SetParameterProc(E: PAEffect; Index: VstInt32; Value: Single); cdecl;
var
  Plugin: TChowTapePlugin;
begin
  Plugin := EffectFromAEffect(E);
  if Plugin = nil then
    Exit;
  try
    Plugin.SetParameter(Index, Value);
  except
  end;
end;

function GetParameterProc(E: PAEffect; Index: VstInt32): Single; cdecl;
var
  Plugin: TChowTapePlugin;
begin
  Plugin := EffectFromAEffect(E);
  if Plugin = nil then
    Exit(0.0);
  try
    Result := Plugin.GetParameter(Index);
  except
    Result := 0.0;
  end;
end;

procedure ProcessReplacingProc(E: PAEffect; Inputs, Outputs: PPSingle;
  SampleFrames: VstInt32); cdecl;
var
  Plugin: TChowTapePlugin;
begin
  Plugin := EffectFromAEffect(E);
  if Plugin = nil then
    Exit;
  try
    Plugin.ProcessReplacing(Inputs, Outputs, SampleFrames);
  except
  end;
end;

procedure ProcessDeprecatedProc(E: PAEffect; Inputs, Outputs: PPSingle;
  SampleFrames: VstInt32); cdecl;
begin
  // VST 2.4 hosts always use processReplacing; nothing to do here.
end;

{ TChowTapePlugin }

constructor TChowTapePlugin.Create(AMaster: TAudioMasterCallback);
begin
  inherited Create;
  FMaster := AMaster;
  FSampleRate := 44100.0;
  FBlockSize := 512;
  FCurrentProgram := 0;

  FProcessor := TChowTapeProcessor.Create;
  FProcessor.OnLatencyChanged := HandleLatencyChanged;

  FillChar(FEffect, SizeOf(FEffect), 0);
  FEffect.Magic := kEffectMagic;
  FEffect.Dispatcher := DispatcherProc;
  FEffect.Process := ProcessDeprecatedProc;
  FEffect.SetParameter := SetParameterProc;
  FEffect.GetParameter := GetParameterProc;
  FEffect.ProcessReplacing := ProcessReplacingProc;
  FEffect.ProcessDoubleReplacing := nil;
  FEffect.NumPrograms := FactoryPresetCount;
  FEffect.NumParams := FProcessor.Params.Count;
  FEffect.NumInputs := ChowTapeNumIO;
  FEffect.NumOutputs := ChowTapeNumIO;
  FEffect.Flags := effFlagsHasEditor or effFlagsCanReplacing or effFlagsProgramChunks;
  FEffect.InitialDelay := 0;
  FEffect.UniqueID := ChowTapeUniqueID;
  FEffect.Version := ChowTapeVersion;
  FEffect.ObjectPtr := Self;

  FEditorRect.Top := 0;
  FEditorRect.Left := 0;
  FEditorRect.Right := EditorBaseWidth;
  FEditorRect.Bottom := EditorBaseHeight;

  FPreparedRate := FSampleRate;
  FPreparedBlock := FBlockSize;
  FProcessor.PrepareToPlay(FSampleRate, FBlockSize, ChowTapeNumIO);
end;

destructor TChowTapePlugin.Destroy;
begin
  { the backstop for a deferred close that no later opcode came to collect }
  FEditorPendingFree := False;
  FreeAndNil(FEditor);
  FreeAndNil(FProcessor);
  inherited Destroy;
end;

function TChowTapePlugin.AEffectPtr: PAEffect;
begin
  Result := @FEffect;
end;

function TChowTapePlugin.CallMaster(Opcode, Index: VstInt32; Value: VstIntPtr;
  Ptr: Pointer; Opt: Single): VstIntPtr;
begin
  if Assigned(FMaster) then
    Result := FMaster(@FEffect, Opcode, Index, Value, Ptr, Opt)
  else
    Result := 0;
end;

procedure TChowTapePlugin.HandleLatencyChanged(Sender: TObject; LatencySamples: Integer);
begin
  if FEffect.InitialDelay = LatencySamples then
    Exit;
  FEffect.InitialDelay := LatencySamples;
  CallMaster(audioMasterIOChanged, 0, 0, nil, 0.0);
end;

procedure TChowTapePlugin.HandleBeginGesture(Sender: TObject; Param: TParameter);
begin
  CallMaster(audioMasterBeginEdit, Param.Index, 0, nil, 0.0);
end;

procedure TChowTapePlugin.HandleParamEdit(Sender: TObject; Param: TParameter);
begin
  CallMaster(audioMasterAutomate, Param.Index, 0, nil, Param.Normalised);
end;

procedure TChowTapePlugin.HandleEndGesture(Sender: TObject; Param: TParameter);
begin
  CallMaster(audioMasterEndEdit, Param.Index, 0, nil, 0.0);
end;

procedure TChowTapePlugin.PrepareIfNeeded;
begin
  if (FPreparedRate = FSampleRate) and (FPreparedBlock = FBlockSize) then
    Exit;
  FPreparedRate := FSampleRate;
  FPreparedBlock := FBlockSize;
  FProcessor.PrepareToPlay(FSampleRate, FBlockSize, ChowTapeNumIO);
end;

{ Frees an editor whose close was deferred. Only ever called from the editor
  opcodes, which the host runs on the message thread, and from the destructor
  as a backstop in case none of them comes again. }
procedure TChowTapePlugin.ReleaseClosedEditor;
begin
  if FEditorPendingFree and not MenuIsModal then
  begin
    FEditorPendingFree := False;
    FreeAndNil(FEditor);
  end;
end;

{ The editor's corner grip has changed the window size. The host owns the
  window the editor lives in, so it has to be told; effEditGetRect must report
  the new size too, for hosts that ask again rather than acting on the call. }
procedure TChowTapePlugin.HandleEditorResized(Sender: TObject; W, H: Integer);
begin
  FEditorRect.Right := W;
  FEditorRect.Bottom := H;
  CallMaster(audioMasterSizeWindow, W, H, nil, 0.0);
end;

procedure TChowTapePlugin.UpdateTimeInfo;
var
  TimeInfo: PVstTimeInfo;
begin
  TimeInfo := PVstTimeInfo(CallMaster(audioMasterGetTime, 0,
    kVstTempoValid or kVstTimeSigValid, nil, 0.0));

  if TimeInfo = nil then
    Exit;

  if (TimeInfo^.Flags and kVstTempoValid) <> 0 then
    if TimeInfo^.Tempo > 0 then
      FProcessor.Bpm := TimeInfo^.Tempo;

  if (TimeInfo^.Flags and kVstTimeSigValid) <> 0 then
    if TimeInfo^.TimeSigNumerator > 0 then
      FProcessor.TimeSigNumerator := TimeInfo^.TimeSigNumerator;
end;

procedure TChowTapePlugin.SetParameter(Index: VstInt32; Value: Single);
var
  P: TParameter;
begin
  if (Index < 0) or (Index >= FProcessor.Params.Count) then
    Exit;
  P := FProcessor.Params[Index];
  P.Normalised := EnsureRange(Value, 0.0, 1.0);
  FProcessor.ParameterChanged(P);
end;

function TChowTapePlugin.GetParameter(Index: VstInt32): Single;
begin
  if (Index < 0) or (Index >= FProcessor.Params.Count) then
    Exit(0.0);
  Result := FProcessor.Params[Index].Normalised;
end;

procedure TChowTapePlugin.ProcessReplacing(Inputs, Outputs: PPSingle;
  SampleFrames: VstInt32);
var
  OldMask: TArithmeticExceptionMask;
begin
  if SampleFrames <= 0 then
    Exit;

  // hosts do not guarantee a particular FPU state, and an unmasked exception
  // inside the solvers would take the whole host down
  OldMask := GetExceptionMask;
  SetExceptionMask(exAllArithmeticExceptions);
  try
    UpdateTimeInfo;

    if FBypassed then
      FProcessor.ProcessBlockBypassed(Inputs, Outputs, ChowTapeNumIO, SampleFrames)
    else
      FProcessor.ProcessBlock(Inputs, Outputs, ChowTapeNumIO, SampleFrames);
  finally
    SetExceptionMask(OldMask);
  end;
end;

function TChowTapePlugin.Dispatch(Opcode, Index: VstInt32; Value: VstIntPtr;
  Ptr: Pointer; Opt: Single): VstIntPtr;
var
  P: TParameter;
  Pin: PVstPinProperties;
  S: AnsiString;
begin
  Result := 0;

  case Opcode of
    effOpen:
      Result := 0;

    effClose:
      begin
        Free;
        Result := 1;
      end;

    effSetProgram:
      begin
        // Programs are the factory presets only: VST 2.4 fixes numPrograms at
        // instantiation, so user presets (which come and go) live in the
        // editor's own menu instead. Factory entries occupy the first
        // FactoryPresetCount slots of the library, so the index maps directly.
        if (Value >= 0) and (Value < FactoryPresetCount) then
        begin
          FCurrentProgram := Value;
          FProcessor.Presets.LoadPreset(FCurrentProgram);
          CallMaster(audioMasterUpdateDisplay, 0, 0, nil, 0.0);
        end;
      end;

    effGetProgram:
      Result := FCurrentProgram;

    effSetProgramName:
      // Presets are named by their file; renaming through the host would not
      // have anywhere to go.
      Result := 0;

    effGetProgramName:
      VstStrCopy(Ptr, FProcessor.Presets.DisplayName, kVstMaxProgNameLen);

    effGetProgramNameIndexed:
      begin
        if (Index >= 0) and (Index < FactoryPresetCount) then
        begin
          VstStrCopy(Ptr, GetFactoryPreset(Index).Name, kVstMaxProgNameLen);
          Result := 1;
        end;
      end;

    effGetParamLabel:
      begin
        if (Index >= 0) and (Index < FProcessor.Params.Count) then
        begin
          P := FProcessor.Params[Index];
          case P.Format of
            pfGainDb: VstStrCopy(Ptr, 'dB', kVstMaxParamStrLen);
            pfFreqHz: VstStrCopy(Ptr, 'Hz', kVstMaxParamStrLen);
            pfTimeMs: VstStrCopy(Ptr, 'ms', kVstMaxParamStrLen);
            pfPercent, pfBipolarPercent: VstStrCopy(Ptr, '%', kVstMaxParamStrLen);
          else
            VstStrCopy(Ptr, '', kVstMaxParamStrLen);
          end;
        end;
      end;

    effGetParamDisplay:
      if (Index >= 0) and (Index < FProcessor.Params.Count) then
        VstStrCopy(Ptr, FProcessor.Params[Index].GetText, kVstMaxParamStrLen);

    effGetParamName:
      if (Index >= 0) and (Index < FProcessor.Params.Count) then
        VstStrCopy(Ptr, FProcessor.Params[Index].Name, kVstMaxParamStrLen);

    effSetSampleRate:
      if Opt > 0 then
      begin
        FSampleRate := Opt;
        PrepareIfNeeded;
      end;

    effSetBlockSize:
      if Value > 0 then
      begin
        FBlockSize := Value;
        PrepareIfNeeded;
      end;

    effMainsChanged:
      if Value = 0 then
        FProcessor.ReleaseResources
      else
        PrepareIfNeeded;

    effEditGetRect:
      begin
        ReleaseClosedEditor;
        { hosts ask for the rect before the editor exists, so the size the
          state remembers has to come from the processor }
        if FProcessor.EditorWidth > 0 then
          FEditorRect.Right := FProcessor.EditorWidth;
        if FProcessor.EditorHeight > 0 then
          FEditorRect.Bottom := FProcessor.EditorHeight;
        if Ptr <> nil then
          PPointer(Ptr)^ := @FEditorRect;
        Result := 1;
      end;

    effEditOpen:
      begin
        ReleaseClosedEditor;
        if FEditor = nil then
        begin
          FEditor := TTapeEditor.Create(FProcessor);
          FEditor.OnBeginGesture := HandleBeginGesture;
          FEditor.OnParamEdit := HandleParamEdit;
          FEditor.OnEndGesture := HandleEndGesture;
          FEditor.OnResized := HandleEditorResized;
        end;
        if FEditor.Open(HWND(Ptr)) then
          Result := 1;
      end;

    effEditClose:
      begin
        if FEditor <> nil then
        begin
          { A menu's modal loop pumps messages from inside the editor's own
            window procedure, so the host can get here while that frame is
            still live -- freeing the editor now would destroy the very object
            whose method is going to resume when the loop unwinds. The window
            goes straight away, so the host has what it asked for; the object
            itself is released once the stack is clear. }
          if MenuIsModal then
          begin
            FEditor.BeginClose;
            DismissMenus;
            FEditorPendingFree := True;
          end
          else
            FreeAndNil(FEditor);
        end;
        Result := 1;
      end;

    effEditIdle:
      begin
        ReleaseClosedEditor;
        if FEditor <> nil then
          FEditor.Idle;
      end;

    effGetChunk:
      begin
        FChunk := FProcessor.SaveState;
        if (Ptr <> nil) and (Length(FChunk) > 0) then
          PPointer(Ptr)^ := @FChunk[0];
        Result := Length(FChunk);
      end;

    effSetChunk:
      begin
        if (Ptr <> nil) and (Value > 0) then
        begin
          SetLength(FChunk, Value);
          Move(Ptr^, FChunk[0], Value);
          FProcessor.LoadState(FChunk);
          Result := 1;
        end;
      end;

    effCanBeAutomated:
      Result := 1;

    effString2Parameter:
      begin
        if (Ptr <> nil) and (Index >= 0) and (Index < FProcessor.Params.Count) then
        begin
          P := FProcessor.Params[Index];
          P.SetValue(P.TextToValue(string(PAnsiChar(Ptr))));
          FProcessor.ParameterChanged(P);
          Result := 1;
        end;
      end;

    effGetInputProperties, effGetOutputProperties:
      begin
        if (Ptr <> nil) and (Index >= 0) and (Index < ChowTapeNumIO) then
        begin
          Pin := PVstPinProperties(Ptr);
          FillChar(Pin^, SizeOf(TVstPinProperties), 0);
          if Index = 0 then
            S := 'Left'
          else
            S := 'Right';
          VstStrCopy(@Pin^.Caption[0], string(S), SizeOf(Pin^.Caption));
          VstStrCopy(@Pin^.ShortLabel[0], string(S), SizeOf(Pin^.ShortLabel));
          Pin^.Flags := kVstPinIsActive or kVstPinIsStereo;
          Result := 1;
        end;
      end;

    effGetPlugCategory:
      Result := kPlugCategEffect;

    effSetBypass:
      begin
        FBypassed := Value <> 0;
        Result := 1;
      end;

    effGetEffectName:
      begin
        VstStrCopy(Ptr, 'CHOW Tape Model', kVstMaxEffectNameLen);
        Result := 1;
      end;

    effGetVendorString:
      begin
        VstStrCopy(Ptr, 'Chowdhury DSP (Delphi port)', kVstMaxVendorStrLen);
        Result := 1;
      end;

    effGetProductString:
      begin
        VstStrCopy(Ptr, 'CHOWTapeModel', kVstMaxProductStrLen);
        Result := 1;
      end;

    effGetVendorVersion:
      Result := ChowTapeVersion;

    effGetVstVersion:
      Result := 2400;

    effGetTailSize:
      Result := Max(1, FProcessor.LatencySamples);

    effSetProcessPrecision:
      if Value = kVstProcessPrecision32 then
        Result := 1
      else
        Result := 0;

    effGetNumMidiInputChannels, effGetNumMidiOutputChannels:
      Result := 0;

    effCanDo:
      begin
        if Ptr = nil then
          Exit(0);
        S := AnsiString(PAnsiChar(Ptr));
        if (S = 'receiveVstTimeInfo') or (S = 'plugAsChannelInsert') or
           (S = 'plugAsSend') or (S = 'bypass') then
          Result := 1
        else if (S = 'receiveVstEvents') or (S = 'receiveVstMidiEvent') or
                (S = 'sendVstEvents') or (S = 'sendVstMidiEvent') then
          Result := -1
        else
          Result := 0;
      end;

    effStartProcess, effStopProcess:
      Result := 1;
  end;
end;

{ ---------------------------------------------------------------------------
  Entry point
  --------------------------------------------------------------------------- }

function VSTPluginMain(AMaster: TAudioMasterCallback): PAEffect; cdecl;
var
  Plugin: TChowTapePlugin;
begin
  if not Assigned(AMaster) then
    Exit(nil);

  // hosts probe the plug-in with audioMasterVersion before instantiating it
  if AMaster(nil, audioMasterVersion, 0, 0, nil, 0.0) = 0 then
    Exit(nil);

  try
    Plugin := TChowTapePlugin.Create(AMaster);
    Result := Plugin.AEffectPtr;
  except
    Result := nil;
  end;
end;

end.
