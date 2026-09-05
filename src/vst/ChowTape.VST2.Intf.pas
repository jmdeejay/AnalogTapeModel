unit ChowTape.VST2.Intf;

{
  Pascal translation of the parts of the VST 2.4 C API that this plug-in needs.

  No Steinberg headers are required to build: everything below is the ABI as it
  is laid out by "aeffect.h" / "aeffectx.h". Field order and sizes must not be
  changed -- the host reads this record directly.
}

interface

uses
  Winapi.Windows,
  ChowTape.DSP.Types;   // for PPSingle / PPDouble, which the RTL does not declare

const
  kEffectMagic = $56737450; // 'VstP'

type
  { Re-exported so that anything working against the VST ABI only needs this
    unit. These are aliases, not new types, so they stay assignment-compatible
    with the processor's own signatures. }
  PPSingle = ChowTape.DSP.Types.PPSingle;
  PPDouble = ChowTape.DSP.Types.PPDouble;

  // The full ABI vocabulary is declared even where this plug-in does not
  // happen to use every type, so the unit stands on its own as a translation.
  VstInt16  = SmallInt;
  VstInt32  = Integer;
  VstInt64  = Int64;
  VstIntPtr = NativeInt;   // 32 bits on Win32, 64 bits on Win64

  PAEffect = ^TAEffect;

  TAEffectDispatcherProc = function(Effect: PAEffect; Opcode, Index: VstInt32;
    Value: VstIntPtr; Ptr: Pointer; Opt: Single): VstIntPtr; cdecl;
  TAEffectProcessProc = procedure(Effect: PAEffect; Inputs, Outputs: PPSingle;
    SampleFrames: VstInt32); cdecl;
  TAEffectProcessDoubleProc = procedure(Effect: PAEffect; Inputs, Outputs: PPDouble;
    SampleFrames: VstInt32); cdecl;
  TAEffectSetParameterProc = procedure(Effect: PAEffect; Index: VstInt32;
    Parameter: Single); cdecl;
  TAEffectGetParameterProc = function(Effect: PAEffect; Index: VstInt32): Single; cdecl;

  TAEffect = record
    Magic: VstInt32;
    Dispatcher: TAEffectDispatcherProc;
    Process: TAEffectProcessProc;              // deprecated in 2.4, kept for layout
    SetParameter: TAEffectSetParameterProc;
    GetParameter: TAEffectGetParameterProc;
    NumPrograms: VstInt32;
    NumParams: VstInt32;
    NumInputs: VstInt32;
    NumOutputs: VstInt32;
    Flags: VstInt32;
    Resvd1: VstIntPtr;
    Resvd2: VstIntPtr;
    InitialDelay: VstInt32;
    RealQualities: VstInt32;                   // deprecated
    OffQualities: VstInt32;                    // deprecated
    IORatio: Single;                           // deprecated
    ObjectPtr: Pointer;
    User: Pointer;
    UniqueID: VstInt32;
    Version: VstInt32;
    ProcessReplacing: TAEffectProcessProc;
    ProcessDoubleReplacing: TAEffectProcessDoubleProc;
    Future: array[0..55] of AnsiChar;
  end;

  TAudioMasterCallback = function(Effect: PAEffect; Opcode, Index: VstInt32;
    Value: VstIntPtr; Ptr: Pointer; Opt: Single): VstIntPtr; cdecl;

const
  // AEffect flags
  effFlagsHasEditor          = 1 shl 0;
  effFlagsCanReplacing       = 1 shl 4;
  effFlagsProgramChunks      = 1 shl 5;
  effFlagsIsSynth            = 1 shl 8;
  effFlagsNoSoundInStop      = 1 shl 9;
  effFlagsCanDoubleReplacing = 1 shl 12;

  // effOpcodes (host -> plug-in)
  effOpen                     = 0;
  effClose                    = 1;
  effSetProgram               = 2;
  effGetProgram               = 3;
  effSetProgramName           = 4;
  effGetProgramName           = 5;
  effGetParamLabel            = 6;
  effGetParamDisplay          = 7;
  effGetParamName             = 8;
  effSetSampleRate            = 10;
  effSetBlockSize             = 11;
  effMainsChanged             = 12;
  effEditGetRect              = 13;
  effEditOpen                 = 14;
  effEditClose                = 15;
  effEditIdle                 = 19;
  effGetChunk                 = 23;
  effSetChunk                 = 24;

  // effOpcodes2x
  effProcessEvents            = 25;
  effCanBeAutomated           = 26;
  effString2Parameter         = 27;
  effGetProgramNameIndexed    = 29;
  effGetInputProperties       = 33;
  effGetOutputProperties      = 34;
  effGetPlugCategory          = 35;
  effSetSpeakerArrangement    = 42;
  effSetBypass                = 44;
  effGetEffectName            = 45;
  effGetVendorString          = 47;
  effGetProductString         = 48;
  effGetVendorVersion         = 49;
  effVendorSpecific           = 50;
  effCanDo                    = 51;
  effGetTailSize              = 52;
  effGetParameterProperties   = 56;
  effGetVstVersion            = 58;
  effEditKeyDown              = 59;
  effEditKeyUp                = 60;
  effSetEditKnobMode          = 61;
  effStartProcess             = 71;
  effStopProcess              = 72;
  effSetTotalSampleToProcess  = 73;
  effSetProcessPrecision      = 77;
  effGetNumMidiInputChannels  = 78;
  effGetNumMidiOutputChannels = 79;

  // audioMasterOpcodes (plug-in -> host)
  audioMasterAutomate               = 0;
  audioMasterVersion                = 1;
  audioMasterCurrentId              = 2;
  audioMasterIdle                   = 3;
  audioMasterGetTime                = 7;
  audioMasterIOChanged              = 13;
  audioMasterUpdateDisplay          = 42;
  audioMasterSizeWindow             = 15;
  audioMasterGetSampleRate          = 16;
  audioMasterGetBlockSize           = 17;
  audioMasterGetCurrentProcessLevel = 23;
  audioMasterGetVendorString        = 32;
  audioMasterGetProductString       = 33;
  audioMasterGetVendorVersion       = 34;
  audioMasterCanDo                  = 37;
  audioMasterBeginEdit              = 43;
  audioMasterEndEdit                = 44;

  // plug-in categories
  kPlugCategEffect = 1;

  // process precision
  kVstProcessPrecision32 = 0;
  kVstProcessPrecision64 = 1;

  // VstTimeInfo flags
  kVstTransportPlaying = 1 shl 1;
  kVstTempoValid       = 1 shl 10;
  kVstTimeSigValid     = 1 shl 13;

  kVstMaxProgNameLen   = 24;
  kVstMaxParamStrLen   = 8;
  kVstMaxVendorStrLen  = 64;
  kVstMaxProductStrLen = 64;
  kVstMaxEffectNameLen = 32;

type
  PERect = ^TERect;
  TERect = record
    Top, Left, Bottom, Right: VstInt16;
  end;

  PVstTimeInfo = ^TVstTimeInfo;
  TVstTimeInfo = record
    SamplePos: Double;
    SampleRate: Double;
    NanoSeconds: Double;
    PpqPos: Double;
    Tempo: Double;
    BarStartPos: Double;
    CycleStartPos: Double;
    CycleEndPos: Double;
    TimeSigNumerator: VstInt32;
    TimeSigDenominator: VstInt32;
    SmpteOffset: VstInt32;
    SmpteFrameRate: VstInt32;
    SamplesToNextClock: VstInt32;
    Flags: VstInt32;
  end;

  PVstPinProperties = ^TVstPinProperties;
  TVstPinProperties = record
    Caption: array[0..63] of AnsiChar;
    Flags: VstInt32;
    ArrangementType: VstInt32;
    ShortLabel: array[0..7] of AnsiChar;
    Future: array[0..47] of AnsiChar;
  end;

const
  kVstPinIsActive   = 1 shl 0;
  kVstPinIsStereo   = 1 shl 1;

{ Copies a Delphi string into a fixed-size AnsiChar buffer supplied by the host,
  always leaving room for the terminating zero. }
procedure VstStrCopy(Dest: Pointer; const Source: string; MaxLen: Integer);

implementation

uses
  System.SysUtils, System.AnsiStrings;

procedure VstStrCopy(Dest: Pointer; const Source: string; MaxLen: Integer);
var
  S: AnsiString;
  Len: Integer;
begin
  if Dest = nil then
    Exit;
  S := AnsiString(Source);
  Len := Length(S);
  if Len > MaxLen - 1 then
    Len := MaxLen - 1;
  if Len > 0 then
    Move(PAnsiChar(S)^, Dest^, Len);
  PAnsiChar(Dest)[Len] := #0;
end;

end.
