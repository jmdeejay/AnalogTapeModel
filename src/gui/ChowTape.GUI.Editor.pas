unit ChowTape.GUI.Editor;

{
  The plug-in editor window.

  A plain Win32 child window is created inside whatever HWND the host hands us,
  and everything inside it is drawn with GDI+ into an off-screen bitmap. The
  layout follows gui.xml: a flex-based arrangement of four tabbed panels between
  a scope strip at the top and a control bar at the bottom.
}

interface

uses
  Winapi.Windows, Winapi.Messages, Winapi.GDIPAPI, Winapi.GDIPOBJ,
  System.SysUtils, System.Classes, System.Math, System.Generics.Collections,
  ChowTape.GUI.Graphics, ChowTape.GUI.Controls, ChowTape.GUI.Menu, ChowTape.Params,
  ChowTape.Processor, ChowTape.Presets, ChowTape.PresetLibrary,
  ChowTape.DSP.Types;

const
  EditorBaseWidth = 720;
  EditorBaseHeight = 620;

  { gui.xml asks for resizable="1" resize-corner="1" and leaves the limits at
    foleys' defaults, which are effectively none. These keep the fixed-height
    header, tab bars and read-outs from crowding each other out. }
  EditorMinWidth = 600;
  EditorMinHeight = 520;
  EditorMaxWidth = 1920;
  EditorMaxHeight = 1600;
  { juce::AudioProcessorEditor's corner grip }
  ResizeGripSize = 18;

type
  TParamEditEvent = procedure(Sender: TObject; Param: TParameter) of object;
  TEditorResizeEvent = procedure(Sender: TObject; W, H: Integer) of object;

  TTapeEditor = class(TObject, ITapeEditorHost)
  private
    FProcessor: TChowTapeProcessor;
    FHwnd: HWND;
    FParentHwnd: HWND;
    FWidth, FHeight: Integer;
    FScale: Single;

    FBackBitmap: HBITMAP;
    FBackDC: HDC;
    FBackW, FBackH: Integer;

    { Everything but the scope and the wow/flutter lights is the same from one
      frame to the next, and redrawing it costs the best part of twenty
      milliseconds. It is drawn into FStaticDC when something actually changes;
      between changes only the animated rectangles are blitted back out of it
      and redrawn. }
    FStaticBitmap: HBITMAP;
    FStaticDC: HDC;
    FStaticValid: Boolean;
    FDirty: Boolean;
    FParamSnapshot: TArray<Single>;
    FFramesSinceFull: Integer;
    FClosing: Boolean;

    FControls: TControlList;          // top-level controls (owned)
    FPanels: TList<TTapeTabbedPanel>; // references into FControls
    FTooltipBar: TTapeTooltipBar;
    FPresetsCombo: TTapeComboBox;
    FPrevPresetBtn: TTapeArrowButton;
    FNextPresetBtn: TTapeArrowButton;
    FOversamplingCombo: TTapeComboBox;
    FModeCombo: TTapeComboBox;
    FMixGroupCombo: TTapeComboBox;
    FBarBackground: TTapeFilledPanel;
    FResizeGrip: TTapeResizeGrip;
    FBottomBarIndex: Integer;
    FResizeBaseW, FResizeBaseH: Integer;

    FCaptured: TTapeControl;
    FHovered: TTapeControl;
    FTimerActive: Boolean;

    FOnBeginGesture: TParamEditEvent;
    FOnParamEdit: TParamEditEvent;
    FOnEndGesture: TParamEditEvent;
    FOnResized: TEditorResizeEvent;

    procedure BuildUI;
    function AddSlider(Page: TTapeTabPage; const ParamID, Caption, Tip: string;
      Style: TTapeSliderStyle): TTapeSlider;
    function AddPower(Page: TTapeTabPage; const ParamID, AName, Tip: string): TTapePowerButton;
    function AddToggle(Page: TTapeTabPage; const ParamID, TextOff, TextOn,
      AName, Tip: string): TTapeTextButton;
    function MakeSpeedHandler(Speed: Single): TProc;
    procedure DoLayout;
    procedure SyncBarFontSize(G: TGPGraphics);
    function SettingsFilePath: string;
    procedure LoadSettings;
    procedure SaveSettings;
    procedure SetEditorSize(W, H: Integer);
    procedure PaintTo(DC: HDC);
    procedure PaintStaticTo(DC: HDC);
    procedure PaintAnimatedTo(DC: HDC);
    procedure RestoreAnimatedRegions;
    function ParametersChanged: Boolean;
    procedure EnsureBackBuffer(W, H: Integer);
    function ControlAt(X, Y: Single): TTapeControl;
    procedure UpdateEnabledStates;

    procedure ShowPresetsMenu;
    procedure ShowSettingsMenu;
    procedure ShowOversamplingMenu;
    procedure ShowSyncMenu(IsFlutter: Boolean);
    procedure SetRateValue(IsFlutter: Boolean; Value: Single);
    procedure SetSpeed(Speed: Single);
    procedure SavePresetAs;
    procedure ResaveCurrentPreset;
    procedure DeleteCurrentPreset;
    procedure GoToPresetFolder;
    procedure ChoosePresetFolder;
    procedure StepPreset(Forward: Boolean);
    procedure NotifyAllParamsChanged;
  protected
    // ITapeEditorHost -- lifetime is managed explicitly, so reference counting
    // is disabled
    function QueryInterface(const IID: TGUID; out Obj): HResult; stdcall;
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;

    procedure RequestRepaint;
    procedure SetTooltip(const AName, AText: string);
    procedure BeginGesture(P: TParameter);
    procedure NotifyParamChanged(P: TParameter);
    procedure EndGesture(P: TParameter);
    function HostWindow: HWND;
    function ScaleFactor: Single;
    function IsClosing: Boolean;
  public
    constructor Create(AProcessor: TChowTapeProcessor);
    destructor Destroy; override;

    function Open(AParent: HWND): Boolean;
    procedure Close;
    { Tears the window down but leaves the object standing, for when the host
      asks to close while a menu's modal loop is still on the stack. }
    procedure BeginClose;
    procedure Idle;

    function WndProc(Msg: UINT; WP: WPARAM; LP: LPARAM): LRESULT;

    property Handle: HWND read FHwnd;
    property Width: Integer read FWidth;
    property Height: Integer read FHeight;
    property OnBeginGesture: TParamEditEvent read FOnBeginGesture write FOnBeginGesture;
    property OnParamEdit: TParamEditEvent read FOnParamEdit write FOnParamEdit;
    property OnEndGesture: TParamEditEvent read FOnEndGesture write FOnEndGesture;
    { raised after a drag on the corner grip, so the plug-in can tell the host
      the window has changed size }
    property OnResized: TEditorResizeEvent read FOnResized write FOnResized;
  end;

implementation

uses
  Winapi.CommDlg, Winapi.ShellAPI, Winapi.ShlObj, Winapi.ActiveX,
  System.IOUtils, System.StrUtils,
  ChowTape.DSP.HysteresisSTN;

const
  { the DLL says which build it is, the way the original's info line names the
    architecture it was compiled for }
{$IFDEF WIN64}
  ArchLabel = '64 bits';
{$ELSE}
  ArchLabel = '32 bits';
{$ENDIF}

  EditorClassName = 'ChowTapeModelEditorWnd';
  TimerId = 1;
  TimerIntervalMs = 33;

var
  GClassRegistered: Boolean = False;
  GGdiplusToken: ULONG_PTR = 0;
  GEditorCount: Integer = 0;

{ ---------------------------------------------------------------------------
  A small flex layout, enough to reproduce the original's arrangement.
  --------------------------------------------------------------------------- }
type
  TFlexChild = record
    Grow: Single;
    MinSize: Single;
    MaxSize: Single;
  end;

function FC(AGrow: Single; AMin: Single = 0.0; AMax: Single = 1.0e9): TFlexChild;
begin
  Result.Grow := AGrow;
  Result.MinSize := AMin;
  Result.MaxSize := AMax;
end;

function Flex(const Area: TRectF; Vertical: Boolean;
  const Children: array of TFlexChild): TArray<TRectF>;
var
  I, Pass, N: Integer;
  Sizes: TArray<Single>;
  Fixed: TArray<Boolean>;
  Total, Remaining, SumGrow, Pos, S: Single;
begin
  N := Length(Children);
  SetLength(Result, N);
  SetLength(Sizes, N);
  SetLength(Fixed, N);
  if N = 0 then
    Exit;

  if Vertical then
    Total := Area.H
  else
    Total := Area.W;

  for I := 0 to N - 1 do
    Fixed[I] := False;

  for Pass := 0 to 2 do
  begin
    Remaining := Total;
    SumGrow := 0.0;
    for I := 0 to N - 1 do
      if Fixed[I] then
        Remaining := Remaining - Sizes[I]
      else
        SumGrow := SumGrow + Children[I].Grow;

    if SumGrow <= 0 then
      Break;

    for I := 0 to N - 1 do
      if not Fixed[I] then
      begin
        S := Remaining * Children[I].Grow / SumGrow;
        if S < Children[I].MinSize then
        begin
          Sizes[I] := Children[I].MinSize;
          Fixed[I] := True;
        end
        else if S > Children[I].MaxSize then
        begin
          Sizes[I] := Children[I].MaxSize;
          Fixed[I] := True;
        end
        else
          Sizes[I] := S;
      end;
  end;

  if Vertical then
  begin
    Pos := Area.Y;
    for I := 0 to N - 1 do
    begin
      Result[I] := RectF(Area.X, Pos, Area.W, Sizes[I]);
      Pos := Pos + Sizes[I];
    end;
  end
  else
  begin
    Pos := Area.X;
    for I := 0 to N - 1 do
    begin
      Result[I] := RectF(Pos, Area.Y, Sizes[I], Area.H);
      Pos := Pos + Sizes[I];
    end;
  end;
end;

{ ---------------------------------------------------------------------------
  Window plumbing
  --------------------------------------------------------------------------- }

function EditorWndProc(Wnd: HWND; Msg: UINT; WP: WPARAM; LP: LPARAM): LRESULT; stdcall;
var
  Editor: TTapeEditor;
begin
  Editor := TTapeEditor(Pointer(GetWindowLongPtr(Wnd, GWLP_USERDATA)));
  if Editor <> nil then
    Result := Editor.WndProc(Msg, WP, LP)
  else
    Result := DefWindowProc(Wnd, Msg, WP, LP);
end;

procedure RegisterEditorClass;
var
  WC: TWndClassEx;
begin
  if GClassRegistered then
    Exit;

  FillChar(WC, SizeOf(WC), 0);
  WC.cbSize := SizeOf(WC);
  WC.style := CS_DBLCLKS or CS_OWNDC;
  WC.lpfnWndProc := @EditorWndProc;
  WC.hInstance := HInstance;
  WC.hCursor := LoadCursor(0, IDC_ARROW);
  WC.hbrBackground := 0;
  WC.lpszClassName := EditorClassName;

  RegisterClassEx(WC);
  GClassRegistered := True;
end;

procedure StartGdiPlus;
var
  Input: TGdiplusStartupInput;
begin
  if GGdiplusToken <> 0 then
    Exit;
  Input.GdiplusVersion := 1;
  Input.DebugEventCallback := nil;
  Input.SuppressBackgroundThread := False;
  Input.SuppressExternalCodecs := False;
  GdiplusStartup(GGdiplusToken, @Input, nil);
end;

procedure StopGdiPlus;
begin
  if GGdiplusToken = 0 then
    Exit;
  GdiplusShutdown(GGdiplusToken);
  GGdiplusToken := 0;
end;

{ TTapeEditor }

constructor TTapeEditor.Create(AProcessor: TChowTapeProcessor);
begin
  inherited Create;
  FProcessor := AProcessor;
  { the size the plug-in state remembers, if it remembers one }
  FWidth := EditorBaseWidth;
  FHeight := EditorBaseHeight;
  if FProcessor.EditorWidth > 0 then
    FWidth := EnsureRange(FProcessor.EditorWidth, EditorMinWidth, EditorMaxWidth);
  if FProcessor.EditorHeight > 0 then
    FHeight := EnsureRange(FProcessor.EditorHeight, EditorMinHeight, EditorMaxHeight);
  FScale := 1.0;
  FControls := TControlList.Create(True);
  FPanels := TList<TTapeTabbedPanel>.Create;
end;

destructor TTapeEditor.Destroy;
begin
  Close;
  FPanels.Free;
  FControls.Free;
  inherited Destroy;
end;

function TTapeEditor.QueryInterface(const IID: TGUID; out Obj): HResult;
begin
  if GetInterface(IID, Obj) then
    Result := S_OK
  else
    Result := E_NOINTERFACE;
end;

function TTapeEditor._AddRef: Integer;
begin
  Result := -1;
end;

function TTapeEditor._Release: Integer;
begin
  Result := -1;
end;

function TTapeEditor.HostWindow: HWND;
begin
  Result := FHwnd;
end;

function TTapeEditor.ScaleFactor: Single;
begin
  Result := FScale;
end;

procedure TTapeEditor.RequestRepaint;
begin
  { Every control calls this when its own state changes, so it is also the
    place to note that the static snapshot no longer matches.

    It deliberately does not invalidate: the timer does that, once per tick.
    WM_PAINT is only delivered when the queue is otherwise empty, so asking
    here would let a fast drag -- which delivers mouse moves far faster than
    thirty a second -- queue up full repaints as fast as they can be drawn.
    Waiting for the tick caps them at the rate the display needs, at the cost
    of at most one frame of latency. Hosts that drive the editor through
    effEditIdle instead of our timer still need the direct route. }
  FDirty := True;
  if (FHwnd <> 0) and not FTimerActive then
    InvalidateRect(FHwnd, nil, False);
end;

procedure TTapeEditor.SetTooltip(const AName, AText: string);
begin
  if FTooltipBar <> nil then
  begin
    FTooltipBar.SetContent(AName, AText);
    RequestRepaint;
  end;
end;

procedure TTapeEditor.BeginGesture(P: TParameter);
begin
  if Assigned(FOnBeginGesture) then
    FOnBeginGesture(Self, P);
end;

procedure TTapeEditor.NotifyParamChanged(P: TParameter);
begin
  FProcessor.ParameterChanged(P);
  if Assigned(FOnParamEdit) then
    FOnParamEdit(Self, P);
  UpdateEnabledStates;
end;

procedure TTapeEditor.EndGesture(P: TParameter);
begin
  if Assigned(FOnEndGesture) then
    FOnEndGesture(Self, P);
end;

function TTapeEditor.Open(AParent: HWND): Boolean;
begin
  { normally a no-op on a fresh editor, but an editor whose close was deferred
    past a menu could still be holding its controls }
  Close;
  FClosing := False;

  StartGdiPlus;
  InitTapeFonts;
  RegisterEditorClass;
  LoadSettings;

  FParentHwnd := AParent;
  FHwnd := CreateWindowEx(0, EditorClassName, '',
    WS_CHILD or WS_VISIBLE or WS_CLIPCHILDREN,
    0, 0, FWidth, FHeight, AParent, 0, HInstance, nil);

  if FHwnd = 0 then
    Exit(False);

  SetWindowLongPtr(FHwnd, GWLP_USERDATA, NativeInt(Self));

  BuildUI;
  DoLayout;
  UpdateEnabledStates;

  SetTimer(FHwnd, TimerId, TimerIntervalMs, nil);
  FTimerActive := True;
  Inc(GEditorCount);

  Result := True;
end;

function TTapeEditor.IsClosing: Boolean;
begin
  Result := FClosing;
end;

{ Everything but the controls: the host gets its window back straight away,
  while anything still on the stack keeps the objects it is holding. }
procedure TTapeEditor.BeginClose;
begin
  FClosing := True;

  if FHwnd <> 0 then
  begin
    if FTimerActive then
    begin
      KillTimer(FHwnd, TimerId);
      FTimerActive := False;
    end;
    SetWindowLongPtr(FHwnd, GWLP_USERDATA, 0);
    DestroyWindow(FHwnd);
    FHwnd := 0;
    Dec(GEditorCount);
  end;

  FCaptured := nil;
  FHovered := nil;
end;

procedure TTapeEditor.Close;
begin
  BeginClose;

  FControls.Clear;
  FPanels.Clear;
  FTooltipBar := nil;
  FPresetsCombo := nil;
  FPrevPresetBtn := nil;
  FNextPresetBtn := nil;
  FOversamplingCombo := nil;
  FModeCombo := nil;
  FMixGroupCombo := nil;
  FBarBackground := nil;
  FResizeGrip := nil;

  if FBackDC <> 0 then
  begin
    DeleteDC(FBackDC);
    FBackDC := 0;
  end;
  if FBackBitmap <> 0 then
  begin
    DeleteObject(FBackBitmap);
    FBackBitmap := 0;
  end;
  if FStaticDC <> 0 then
  begin
    DeleteDC(FStaticDC);
    FStaticDC := 0;
  end;
  if FStaticBitmap <> 0 then
  begin
    DeleteObject(FStaticBitmap);
    FStaticBitmap := 0;
  end;
  FStaticValid := False;
end;

procedure TTapeEditor.Idle;
begin
  // hosts that do not run our timer can drive repaints through effEditIdle
  if (FHwnd <> 0) and (not FTimerActive) then
    RequestRepaint;
end;

{ ---------------------------------------------------------------------------
  Building the control tree
  --------------------------------------------------------------------------- }

function TTapeEditor.AddSlider(Page: TTapeTabPage; const ParamID, Caption, Tip: string;
  Style: TTapeSliderStyle): TTapeSlider;
begin
  Result := TTapeSlider.Create(Self, FProcessor.Params.ByID(ParamID), Caption, Style);
  Result.Tooltip := Tip;
  Page.Controls.Add(Result);
end;

function TTapeEditor.AddPower(Page: TTapeTabPage;
  const ParamID, AName, Tip: string): TTapePowerButton;
begin
  Result := TTapePowerButton.Create(Self, FProcessor.Params.ByID(ParamID));
  Result.Name := AName;
  Result.Tooltip := Tip;
  Page.Controls.Add(Result);
end;

function TTapeEditor.AddToggle(Page: TTapeTabPage;
  const ParamID, TextOff, TextOn, AName, Tip: string): TTapeTextButton;
begin
  Result := TTapeTextButton.Create(Self, FProcessor.Params.ByID(ParamID),
    TextOff, TextOn);
  Result.Name := AName;
  Result.Tooltip := Tip;
  Page.Controls.Add(Result);
end;

function TTapeEditor.MakeSpeedHandler(Speed: Single): TProc;
begin
  // Speed is a value parameter, so each button closes over its own copy.
  Result := procedure
    begin
      SetSpeed(Speed);
    end;
end;

procedure TTapeEditor.BuildUI;
var
  P: TParameterSet;
  Panel: TTapeTabbedPanel;
  Page: TTapeTabPage;
  Combo: TTapeComboBox;
  Btn: TTapeActionButton;
  Icon: TTapeIconButton;
  Info: TTapeInfoLine;
  Speeds: array[0..3] of Single;
  I: Integer;
  SpeedText: string;

  function AddTop(C: TTapeControl): TTapeControl;
  begin
    FControls.Add(C);
    Result := C;
  end;

begin
  P := FProcessor.Params;
  FControls.Clear;
  FPanels.Clear;

  // --- header -------------------------------------------------------------
  AddTop(TTapeTitle.Create(Self, 'Chow Tape Model', '', 40.0));
  { InfoComp's scheme: the line runs in the accent colour with the version
    number picked out in white }
  Info := TTapeInfoLine.Create(Self);
  Info.Add('Delphi VST 2.4 port ' + ArchLabel + '  |  ', clAccent);
  Info.Add('v1.1.0', clWhite);
  Info.Add('  |  by JM-DG', clAccent);
  AddTop(Info);
  AddTop(TTapeScopeView.Create(Self, FProcessor.Scope));

  // --- panel 1: basic controls -------------------------------------------
  Panel := TTapeTabbedPanel.Create(Self);
  AddTop(Panel);
  FPanels.Add(Panel);

  Page := Panel.AddPage('Gain');
  AddSlider(Page, pidInGain, 'Input Gain',
    'Sets the input gain to the tape model in Decibels.', ssRotary);
  { gui.xml singles this one out with a brighter teal, slider-track="FF0BBDC2".
    That only made sense while the other knobs were cyan; against the accent
    the lone teal knob is the odd one out, so it goes with the rest. }
  AddSlider(Page, pidDryWet, 'Dry/Wet',
    'Sets dry/wet mix of the entire plugin.', ssRotary);
  AddSlider(Page, pidOutGain, 'Output Gain',
    'Sets the output gain from the tape model in Decibels.', ssRotary);

  Page := Panel.AddPage('Filters');
  AddSlider(Page, pidIFiltLow, 'Low Cut',
    'Applies a low cut filter before applying tape processing.', ssRotary);
  AddSlider(Page, pidIFiltHigh, 'High Cut',
    'Applies a high cut filter before applying tape processing.', ssRotary);
  AddToggle(Page, pidIFiltMakeup, 'Makeup', 'Makeup', 'Makeup',
    'Adds the signal cut out by the cut filters back to the processed signal.');
  AddPower(Page, pidIFiltOnOff, 'Filters On/Off',
    'Turns the pre-processing filters on or off.');

  Page := Panel.AddPage('Stereo');
  AddToggle(Page, pidMidSide, 'Stereo', 'Mid/Side', 'Mid/Side',
    'Toggles between left/right and mid/side processing modes (Stereo only)');
  AddSlider(Page, pidStereoBalance, 'Balance',
    'Controls the balance between the two channels (stereo or mid/side).', ssRotary);
  AddToggle(Page, pidStereoMakeup, 'Makeup', 'Makeup', 'Stereo Makeup',
    'Compensates for the stereo balance at the plugin output.');

  // --- panel 2: saturation ------------------------------------------------
  Panel := TTapeTabbedPanel.Create(Self);
  AddTop(Panel);
  FPanels.Add(Panel);

  Page := Panel.AddPage('Tape');
  AddSlider(Page, pidWidth, 'Bias',
    'Controls the amount of bias used by the tape recorder. Turning down the bias can create "deadzone" distortion.',
    ssRotary);
  AddSlider(Page, pidSat, 'Saturation',
    'Controls the amount of tape saturation applied to the signal.', ssRotary);
  AddSlider(Page, pidDrive, 'Drive',
    'Controls the amount of amplification done during the tape magnetisation process.',
    ssRotary);
  AddPower(Page, pidHystOnOff, 'Tape On/Off', 'Turns the tape processing on or off.');

  Page := Panel.AddPage('Comp');
  AddSlider(Page, pidCompAmt, 'Amount',
    'Controls the amount of tape compression applied by the effect.', ssRotary);
  AddSlider(Page, pidCompAttack, 'Attack',
    'Controls the attack speed of the tape compression.', ssRotary);
  AddSlider(Page, pidCompRelease, 'Release',
    'Controls the release speed of the tape compression.', ssRotary);
  AddPower(Page, pidCompOnOff, 'Comp. On/Off', 'Turns the tape compression on or off.');

  Page := Panel.AddPage('Tone');
  AddSlider(Page, pidTreble, 'Treble',
    'Controls the treble response of the pre/post-emphasis filters.', ssRotary);
  AddSlider(Page, pidBass, 'Bass',
    'Controls the bass response of the pre/post-emphasis filters.', ssRotary);
  AddSlider(Page, pidTFreq, 'Frequency',
    'Controls the transition frequency between the bass and treble sections of the EQ.',
    ssRotary);
  AddPower(Page, pidToneOnOff, 'Tone On/Off',
    'Turns the tone control processing on or off.');

  // --- panel 3: degradation ----------------------------------------------
  Panel := TTapeTabbedPanel.Create(Self);
  AddTop(Panel);
  FPanels.Add(Panel);

  Page := Panel.AddPage('Loss');
  AddSlider(Page, pidGap, 'Gap [microns]',
    'Sets the width of the playhead gap.', ssLinearHorizontal);
  AddSlider(Page, pidThick, 'Thickness [microns]',
    'Sets the thickness of the tape. Thicker tape has a more muted high-frequency response.',
    ssLinearHorizontal);
  AddSlider(Page, pidSpacing, 'Spacing [microns]',
    'Sets the spacing between the tape and the playhead.', ssLinearHorizontal);
  AddSlider(Page, pidAzimuth, 'Azimuth [degrees]',
    'Sets the azimuth angle between the playhead and the tape. (Stereo only)',
    ssLinearHorizontal);
  AddSlider(Page, pidSpeed, 'Speed [ips]',
    'Sets the speed of the tape as it affects the playhead loss effects.',
    ssLinearHorizontal);

  { the loss sliders are the only ones in gui.xml with
    caption-placement="top-left"; everywhere else the caption is centred }
  for I := 0 to Page.Controls.Count - 1 do
    TTapeSlider(Page.Controls[I]).CaptionPlacement := cpTopLeft;

  Speeds[0] := 3.75;
  Speeds[1] := 7.5;
  Speeds[2] := 15.0;
  Speeds[3] := 30.0;
  for I := 0 to 3 do
  begin
    SpeedText := FormatFloat('0.##', Speeds[I]);
    Btn := TTapeActionButton.Create(Self, SpeedText, MakeSpeedHandler(Speeds[I]));
    Btn.Name := SpeedText + ' ips';
    Btn.Tooltip := 'Snaps the tape speed to ' + SpeedText + ' inches per second.';
    Page.Controls.Add(Btn);
  end;
  AddPower(Page, pidLossOnOff, 'Loss On/Off', 'Turns the loss filters on or off.');

  Page := Panel.AddPage('Degrade');
  // drawn first so it sits behind: the original groups Depth and its 0.1x
  // button on a darker panel
  Page.Controls.Add(TTapeFilledPanel.Create(Self, clPanelDark));
  AddSlider(Page, pidDegDepth, 'Depth', 'Sets the depth of the tape degradation.',
    ssLinearHorizontal);
  AddToggle(Page, pidDegPoint1x, '0.1x', '0.1x', '0.1x',
    'Scales the Depth value by 0.1 to allow for more subtle degradation.');
  AddSlider(Page, pidDegAmt, 'Amount',
    'Sets the amount of the tape that is degraded.', ssLinearHorizontal);
  AddSlider(Page, pidDegVar, 'Variance',
    'Sets the variance of the tape degradation.', ssLinearHorizontal);
  AddSlider(Page, pidDegEnv, 'Envelope',
    'Sets the amount of amplitude envelope applied to the tape degradation.',
    ssLinearHorizontal);
  AddPower(Page, pidDegOnOff, 'Degrade On/Off',
    'Turns the degradation processing on or off.');

  Page := Panel.AddPage('CHEW');
  AddSlider(Page, pidChewDepth, 'Depth',
    'Controls how intensely the tape has been chewed up.', ssRotary);
  AddSlider(Page, pidChewFreq, 'Frequency',
    'Controls the amount of time in between chewed-up sections of tape.', ssRotary);
  AddSlider(Page, pidChewVar, 'Variance',
    'Controls the amount of variance in the chew frequency.', ssRotary);
  AddPower(Page, pidChewOnOff, 'Chew On/Off', 'Turns the chew processing on or off.');

  // --- panel 4: wow & flutter --------------------------------------------
  Panel := TTapeTabbedPanel.Create(Self);
  AddTop(Panel);
  FPanels.Add(Panel);

  Page := Panel.AddPage('Flutter');
  Combo := TTapeComboBox.Create(Self, nil, '', csPlain);
  Combo.DisplayText := 'Flutter Sync';
  Combo.Name := 'Flutter Sync';
  Combo.Tooltip := 'Snaps the flutter rate to a synchronized value.';
  Combo.TextColour := clWhite;
  Combo.OnClick := procedure
    begin
      ShowSyncMenu(True);
    end;
  Page.Controls.Add(Combo);

  AddSlider(Page, pidFlutterDepth, 'Depth', 'Sets depth of the tape flutter.', ssRotary);
  AddSlider(Page, pidFlutterRate, 'Rate', 'Sets the rate of the tape flutter.', ssRotary);
  Page.Controls.Add(TTapeLightMeter.Create(Self,
    function: Single
    begin
      Result := FProcessor.Flutter.FlutterMeter;
    end));
  AddPower(Page, pidFlutterOnOff, 'Wow/Flutter On/Off',
    'Turns the wow and flutter processing on or off.');

  Page := Panel.AddPage('Wow');
  Combo := TTapeComboBox.Create(Self, nil, '', csPlain);
  Combo.DisplayText := 'Wow Sync';
  Combo.Name := 'Wow Sync';
  Combo.Tooltip := 'Snaps the wow rate to a synchronized value.';
  Combo.TextColour := clWhite;
  Combo.OnClick := procedure
    begin
      ShowSyncMenu(False);
    end;
  Page.Controls.Add(Combo);

  AddSlider(Page, pidWowDepth, 'Depth', 'Sets the depth of the tape wow.',
    ssLinearHorizontal);
  AddSlider(Page, pidWowRate, 'Rate', 'Sets the rate of the tape wow.',
    ssLinearHorizontal);
  AddSlider(Page, pidWowVar, 'Variance', 'Sets the amount of variance in the tape wow.',
    ssLinearHorizontal);
  AddSlider(Page, pidWowDrift, 'Drift', 'Sets the amount of drift in the tape wow.',
    ssLinearHorizontal);
  Page.Controls.Add(TTapeLightMeter.Create(Self,
    function: Single
    begin
      Result := FProcessor.Flutter.WowMeter;
    end));
  AddPower(Page, pidFlutterOnOff, 'Wow/Flutter On/Off',
    'Turns the wow and flutter processing on or off.');

  // --- tooltip bar --------------------------------------------------------
  FTooltipBar := TTapeTooltipBar.Create(Self);
  AddTop(FTooltipBar);

  // --- bottom bar ---------------------------------------------------------
  { the strip behind the oversampling, mode, mix-group and preset controls.
    gui.xml gives it margin="0", so unlike everything else it runs the full
    width of the root and sits flush with its bottom edge. }
  FBarBackground := TTapeFilledPanel.Create(Self, clPanel, 0.0);
  AddTop(FBarBackground);

  FBottomBarIndex := FControls.Count;

  Combo := TTapeComboBox.Create(Self, nil, 'Oversampling', csLabelled);
  Combo.Name := 'Oversampling';
  Combo.Tooltip := 'Sets the amount of oversampling used for the hysteresis processing.';
  Combo.OnClick := procedure
    begin
      ShowOversamplingMenu;
    end;
  AddTop(Combo);
  FOversamplingCombo := Combo;

  Combo := TTapeComboBox.Create(Self, P.ByID(pidMode), 'Hysteresis Mode', csLabelled);
  Combo.Name := 'Hysteresis Mode';
  Combo.Tooltip := 'Selects the mode to use for hysteresis processing.';
  AddTop(Combo);
  FModeCombo := Combo;

  Combo := TTapeComboBox.Create(Self, P.ByID(pidMixGroup), 'Mix Group', csLabelled);
  Combo.Name := 'Mix Group';
  Combo.Tooltip := 'Adds this plugin to a mix group so that its parameters stay in sync.';
  AddTop(Combo);
  FMixGroupCombo := Combo;

  AddTop(TTapeMixGroupViz.Create(Self, P.ByID(pidMixGroup)));

  FPrevPresetBtn := TTapeArrowButton.Create(Self, False,
    procedure
    begin
      StepPreset(False);
    end);
  FPrevPresetBtn.Name := 'Previous Preset';
  FPrevPresetBtn.Tooltip := 'Steps to the previous preset.';
  AddTop(FPrevPresetBtn);

  FPresetsCombo := TTapeComboBox.Create(Self, nil, '', csPresets);
  FPresetsCombo.Name := 'Presets';
  FPresetsCombo.Tooltip := 'Selects a preset. A trailing * means the preset has been edited.';
  FPresetsCombo.DisplayText := FProcessor.Presets.DisplayName;
  FPresetsCombo.OnClick := procedure
    begin
      ShowPresetsMenu;
    end;
  AddTop(FPresetsCombo);

  FNextPresetBtn := TTapeArrowButton.Create(Self, True,
    procedure
    begin
      StepPreset(True);
    end);
  FNextPresetBtn.Name := 'Next Preset';
  FNextPresetBtn.Tooltip := 'Steps to the next preset.';
  AddTop(FNextPresetBtn);

  Icon := TTapeIconButton.Create(Self,
    procedure
    begin
      ShowSettingsMenu;
    end);
  Icon.Name := 'Settings';
  Icon.Tooltip := 'Opens the plugin settings menu.';
  AddTop(Icon);

  { last, so it paints over everything and wins the hit test }
  FResizeGrip := TTapeResizeGrip.Create(Self,
    procedure
    begin
      FResizeBaseW := FWidth;
      FResizeBaseH := FHeight;
    end,
    procedure(DX, DY: Single)
    begin
      SetEditorSize(FResizeBaseW + Round(DX), FResizeBaseH + Round(DY));
    end);
  FResizeGrip.Name := 'Resize';
  AddTop(FResizeGrip);
end;

{ ---------------------------------------------------------------------------
  Layout
  --------------------------------------------------------------------------- }

{ "Hysteresis Mode: " is much the longest of the three labels along the bottom
  bar, so letting each box pick its own size leaves that one visibly smaller
  than its neighbours. They all take the smallest of the three instead. }
procedure TTapeEditor.SyncBarFontSize(G: TGPGraphics);
var
  Size: Single;
begin
  if (FOversamplingCombo = nil) or (FModeCombo = nil) or (FMixGroupCombo = nil) then
    Exit;

  Size := Min(FOversamplingCombo.PreferredFontSize(G),
          Min(FModeCombo.PreferredFontSize(G), FMixGroupCombo.PreferredFontSize(G)));

  FOversamplingCombo.FontOverride := Size;
  FModeCombo.FontOverride := Size;
  FMixGroupCombo.FontOverride := Size;
end;


function TTapeEditor.SettingsFilePath: string;
begin
  Result := TPath.Combine(TPath.Combine(TPath.GetHomePath, 'ChowdhuryDSP'),
    TPath.Combine('ChowTape', 'Settings.txt'));
end;

procedure TTapeEditor.LoadSettings;
var
  Line: string;
begin
  try
    if not TFile.Exists(SettingsFilePath) then
      Exit;
    for Line in TFile.ReadAllLines(SettingsFilePath) do
      if StartsText('glow=', Line) then
        GlowEnabled := Trim(Copy(Line, 6, MaxInt)) <> '0';
  except
    // a settings file that cannot be read is not worth failing the editor for
  end;
end;

procedure TTapeEditor.SaveSettings;
begin
  try
    TDirectory.CreateDirectory(TPath.GetDirectoryName(SettingsFilePath));
    TFile.WriteAllText(SettingsFilePath, 'glow=' + IntToStr(Ord(GlowEnabled)) + sLineBreak);
  except
    // ditto
  end;
end;

procedure TTapeEditor.SetEditorSize(W, H: Integer);
begin
  W := EnsureRange(W, EditorMinWidth, EditorMaxWidth);
  H := EnsureRange(H, EditorMinHeight, EditorMaxHeight);
  if (W = FWidth) and (H = FHeight) then
    Exit;

  FWidth := W;
  FHeight := H;
  FProcessor.EditorWidth := W;
  FProcessor.EditorHeight := H;

  { the host owns the window the editor was opened into, so it has to be asked
    first; whether or not it obliges, the child window and the layout follow }
  if Assigned(FOnResized) then
    FOnResized(Self, W, H);

  if FHwnd <> 0 then
    SetWindowPos(FHwnd, 0, 0, 0, W, H,
      SWP_NOMOVE or SWP_NOZORDER or SWP_NOACTIVATE);

  DoLayout;

  if FHwnd <> 0 then
    RequestRepaint;
end;

procedure TTapeEditor.DoLayout;
var
  Root, TopArea, MainArea, TipArea, BarArea: TRectF;
  Rows, Cols, Cells, Sub: TArray<TRectF>;
  Panel: TTapeTabbedPanel;
  Page: TTapeTabPage;
  Content: TRectF;
  I, Idx: Integer;
  TitleCol: TArray<TRectF>;
  SpeedRow: TArray<TRectF>;
  DegradeTop: TArray<TRectF>;
  PresetRow: TArray<TRectF>;
  M, Pad, TabBtn, Nudge, DepthMax, PowerH: Single;
  DegradeBox: TRectF;
begin
  if FControls.Count = 0 then
    Exit;

  { foleys' defaults. Almost every gap in the original comes from one of these
    rather than from anything the layout spells out, so they are named once. }
  M := FoleysMargin * FScale;
  Pad := FoleysPadding * FScale;
  TabBtn := 50 * FScale;    // Types gives TextButton and ComboBox max-height 50
  { the preset block sits a little left of where the bar's proportions put it,
    to open the gap between it and the cog }
  Nudge := 4 * FScale;
  { the power buttons: see PowerH below }

  { the root view takes the default margin too: the red card is inset from the
    window on every side and the host's background shows in the gap }
  Root := RectF(0, 0, FWidth, FHeight).Reduced(M);

  Rows := Flex(Root, True, [FC(0, 100 * FScale, 100 * FScale),
                            FC(1.0),
                            FC(0.13, 40 * FScale, 63 * FScale),
                            FC(0.04, 34 * FScale, 40 * FScale)]);
  TopArea := Rows[0];
  MainArea := Rows[1];
  TipArea := Rows[2];
  BarArea := Rows[3];

  // header: title column + scope
  Cols := Flex(TopArea, False, [FC(0.75), FC(1.0)]);
  TitleCol := Flex(Cols[0].Reduced(0, 2 * FScale), True,
    [FC(0.15), FC(1.0), FC(0.8), FC(0.15)]);
  { both start on the same edge as the first tabbed panel below them, which is
    inset from the root by its own margin }
  FControls[0].Bounds := TitleCol[1].Reduced(M, 0);  // title
  FControls[1].Bounds := TitleCol[2].Reduced(M, 0);  // info line
  FControls[2].Bounds := Cols[1].Reduced(M);         // scope

  // main row: four tabbed panels, each inset by its own margin so that ten
  // pixels of the background show between neighbours
  Cols := Flex(MainArea, False, [FC(1.5), FC(1.5), FC(1.5), FC(1.0)]);
  for I := 0 to FPanels.Count - 1 do
  begin
    FPanels[I].Bounds := Cols[I].Reduced(M);
    FPanels[I].TabHeight := 40 * FScale;
  end;

  { gui.xml puts the power buttons between 20 and 30 high, and at the design
    size the flex would starve them to the 20. Pinning them to the 30 instead
    fixed the size but froze it, so they shrank against everything else as the
    window grew. They follow the panel now -- the fraction is the one that
    reproduces that 30 at the design size -- between bounds that stop them
    disappearing on a small window or turning into dinner plates on a huge
    one. All four panels are the same height, so one value does for all. }
  PowerH := EnsureRange(FPanels[0].ContentArea.H * 0.083,
    24 * FScale, 48 * FScale);

  // panel 1
  Panel := FPanels[0];
  Content := Panel.ContentArea;

  Page := Panel.Pages[0]; // Gain -- the tab view keeps the default margin,
                          // its three sliders set margin="0" padding="0"
  { gui.xml hands the whole tab to the three knobs, with none of the leading
    gap the other three-knob tabs start on, so they sit flush against the tab
    bar. That gap is added here. There is no power button to end on, though,
    so the row it would take is left to the knobs instead of being held empty:
    they come out a little larger than the tape, comp and tone ones. }
  Cells := Flex(Content.Reduced(M, 0), True, [FC(0.05), FC(1.0), FC(1.0),
    FC(1.0), FC(0.05)]);
  for I := 0 to 2 do
    Page.Controls[I].Bounds := Cells[I + 1];

  Page := Panel.Pages[1]; // Filters -- margin="0" on the tab, but the two cut
                          // sliders take both defaults, so they inset by ten
  Cells := Flex(Content, True, [FC(1.0), FC(1.0), FC(0.35, 0, TabBtn),
    FC(0.1, PowerH, PowerH)]);
  Page.Controls[0].Bounds := Cells[0].Reduced(M + Pad);
  Page.Controls[1].Bounds := Cells[1].Reduced(M + Pad);
  Page.Controls[2].Bounds := Cells[2];   // makeup: margin="0", padding drawn in
  Page.Controls[3].Bounds := Cells[3];   // power:  margin="0" padding="0"

  Page := Panel.Pages[2]; // Stereo
  Cells := Flex(Content.Reduced(M, 0), True, [FC(0.35, 0, TabBtn), FC(0.2),
    FC(1.0), FC(0.2), FC(0.35, 0, TabBtn)]);
  Page.Controls[0].Bounds := Cells[0];
  Page.Controls[1].Bounds := Cells[2].Reduced(Pad);   // balance: padding="5"
  Page.Controls[2].Bounds := Cells[4];

  // panels 2: three pages, all "three knobs + power"
  Panel := FPanels[1];
  Content := Panel.ContentArea;   // all three tabs are margin="0" padding="0"
  for Idx := 0 to 2 do
  begin
    Page := Panel.Pages[Idx];
    Cells := Flex(Content, True, [FC(0.05), FC(1.0), FC(1.0), FC(1.0),
      FC(0.1, PowerH, PowerH)]);
    for I := 0 to 3 do
      Page.Controls[I].Bounds := Cells[I + 1];
  end;

  // panel 3
  Panel := FPanels[2];
  Content := Panel.ContentArea;

  Page := Panel.Pages[0]; // Loss
  Cells := Flex(Content, True, [FC(1.0), FC(1.0), FC(1.0), FC(1.0), FC(1.0),
    FC(0.53), FC(0.01), FC(0.1, PowerH, PowerH)]);
  { the five loss sliders only set padding="0", so each keeps its margin: that
    is what puts air between one slider's value read-out and the next one's
    caption instead of stacking them straight on top of each other. The tracks
    take the padding as well, so they start ten pixels in from the panel edge
    like the degrade group's does. }
  for I := 0 to 4 do
    Page.Controls[I].Bounds := Cells[I].Reduced(M + Pad, M);
  SpeedRow := Flex(Cells[5].Reduced(2 * FScale, 2 * FScale), False,
    [FC(1.0), FC(1.0), FC(1.0), FC(1.0)]);
  for I := 0 to 3 do
    Page.Controls[5 + I].Bounds := SpeedRow[I];
  Page.Controls[9].Bounds := Cells[7];

  Page := Panel.Pages[1]; // Degrade
  Cells := Flex(Content, True, [FC(2.0, 0, 140 * FScale), FC(0.05, 0, 15 * FScale),
    FC(1.0), FC(0.05, 0, 15 * FScale), FC(1.0), FC(0.05, 0, 15 * FScale), FC(1.0),
    FC(0.1, 0, 15 * FScale), FC(0.1, PowerH, PowerH)]);
  { Depth is capped at 70 high in the original; without that it eats the space
    its 0.1x button needs and ends up twice the height of the sliders below it.
    That cap is absolute, though, so on a window shorter than the design size
    it stops being a cap and becomes a floor -- Depth keeps its 70 while the
    group around it shrinks, and the button is left with single digits. It
    yields once there is less than thirty pixels left for the rest. }
  DegradeBox := Cells[0].Reduced(M);
  DepthMax := JMinF(70 * FScale,
    JMaxF(20 * FScale, DegradeBox.H - 30 * FScale));
  DegradeTop := Flex(DegradeBox, True,
    [FC(0.05, 0, 5 * FScale), FC(2.5, 0, DepthMax), FC(0.35, 0, TabBtn)]);
  Page.Controls[0].Bounds := Cells[0].Reduced(M);  // group background
  { gui.xml gives the depth slider margin="0" padding="", so its track runs
    edge to edge of the dark group box. Inset it by the five pixels the 0.1x
    button below it already takes from its own padding, so the two line up. }
  Page.Controls[1].Bounds := DegradeTop[1].Reduced(Pad, 0);   // depth
  Page.Controls[2].Bounds := DegradeTop[2];                   // 0.1x
  { amount, variance and envelope set margin="0" and keep the default padding,
    widened to the same ten pixels the depth slider above them ends up with }
  Page.Controls[3].Bounds := Cells[2].Reduced(M + Pad, Pad);
  Page.Controls[4].Bounds := Cells[4].Reduced(M + Pad, Pad);
  Page.Controls[5].Bounds := Cells[6].Reduced(M + Pad, Pad);
  Page.Controls[6].Bounds := Cells[8];             // power

  Page := Panel.Pages[2]; // Chew
  Cells := Flex(Content, True, [FC(0.05), FC(1.0), FC(1.0), FC(1.0),
    FC(0.1, PowerH, PowerH)]);
  for I := 0 to 3 do
    Page.Controls[I].Bounds := Cells[I + 1];

  // panel 4
  Panel := FPanels[3];
  Content := Panel.ContentArea;

  { gui.xml insets the flutter tab by ten and the wow tab by three, which
    leaves the two wow/flutter plots different widths and the flutter power
    button riding higher than every other section's. Both tabs use the wow
    inset here, and neither takes a vertical one, so all four power buttons
    line up on the same baseline. }
  Page := Panel.Pages[0]; // Flutter
  Cells := Flex(Content.Reduced(3 * FScale, 0), True, [FC(0.25, 46 * FScale, 65 * FScale),
    FC(0.1, 0, 15 * FScale),
    { gui.xml caps every wow and flutter control at 150. That works on the wow
      tab, where four sliders between them hold 600 before the plot starts
      taking the slack, but the flutter tab has only two -- so on a tall window
      they stop at 300 and the plot swallows the rest, ending up twice the size
      of the wow tab's. Two knobs are allowed to hold what four sliders do. }
    FC(1.0, 0, 300 * FScale), FC(1.0, 0, 300 * FScale),
    { 0.8 in gui.xml, trimmed so the plot comes out the same height as the wow
      tab's rather than four pixels taller }
    FC(0.74), FC(0.1, PowerH, PowerH)]);
  { gui.xml gives the sync menu no margin of its own and leans on the tab's,
    which is gone here so that the power buttons line up across the four
    sections. It takes the same inset as the plot at the bottom of the tab
    instead, so the two line up down the edge of the panel. }
  Page.Controls[0].Bounds := Cells[0].Reduced(M, 5 * FScale);
  Page.Controls[1].Bounds := Cells[2];
  Page.Controls[2].Bounds := Cells[3];
  Page.Controls[3].Bounds := Cells[4].Reduced(M);   // the plot keeps its margin
  Page.Controls[4].Bounds := Cells[5];

  Page := Panel.Pages[1]; // Wow -- margin="3" padding="0"
  Cells := Flex(Content.Reduced(3 * FScale, 0), True, [FC(0.35, 46 * FScale, 65 * FScale),
    FC(0.1), FC(1.0, 0, 150 * FScale), FC(1.0, 0, 150 * FScale),
    FC(1.0, 0, 150 * FScale), FC(1.0, 0, 150 * FScale), FC(1.45),
    FC(0.1, PowerH, PowerH)]);
  { gui.xml gives the sync menu no margin of its own and leans on the tab's,
    which is gone here so that the power buttons line up across the four
    sections. It takes the same inset as the plot at the bottom of the tab
    instead, so the two line up down the edge of the panel. }
  Page.Controls[0].Bounds := Cells[0].Reduced(M, 5 * FScale);
  { the wow tab is inset three, so seven more puts these tracks the same ten
    pixels in from the panel edge as the loss and degrade ones }
  for I := 1 to 4 do
    Page.Controls[I].Bounds := Cells[I + 1].Reduced(7 * FScale, 0);
  Page.Controls[5].Bounds := Cells[6].Reduced(M);
  Page.Controls[6].Bounds := Cells[7];

  // tooltip bar
  FTooltipBar.Bounds := TipArea.Reduced(M);

  // bottom bar: oversampling, mode, mix group, viz, [<] presets [>], settings
  FBarBackground.Bounds := BarArea;

  { gui.xml gives these slots 1.2, 1.0 and 0.85, which relies on JUCE
    condensing "Hysteresis Mode: " to fit -- GDI+ will not do that, and one
    label shrinking on its own looks wrong next to the other two. The three are
    re-proportioned to their label lengths instead, so a single size fits them
    all; the total is unchanged, so nothing else on the bar moves. }
  Sub := Flex(BarArea, False, [FC(0.05), FC(1.0), FC(1.25), FC(0.1), FC(0.8),
    FC(0.3), FC(1.95), FC(0.06, 25 * FScale, 40 * FScale)]);

  // the preset slot is shared by the two step arrows and the name in between
  PresetRow := Flex(Sub[6].Reduced(M).Moved(-Nudge, 0), False,
    [FC(0.0, 16 * FScale, 22 * FScale), FC(1.0), FC(0.0, 16 * FScale, 22 * FScale)]);

  Idx := FBottomBarIndex;
  FControls[Idx + 0].Bounds := Sub[1];                       // oversampling
  FControls[Idx + 1].Bounds := Sub[2];                       // mode
  FControls[Idx + 2].Bounds := Sub[4];                       // mix group
  FControls[Idx + 3].Bounds := Sub[5].Reduced(M);            // viz
  FControls[Idx + 4].Bounds := PresetRow[0];                 // previous preset
  FControls[Idx + 5].Bounds := PresetRow[1];                 // preset name
  FControls[Idx + 6].Bounds := PresetRow[2];                 // next preset
  FControls[Idx + 7].Bounds := Sub[7].Moved(-Nudge, 0);      // settings

  { juce::AudioProcessorEditor puts the corner grip in the bottom right of the
    whole editor, outside the root's margin }
  FResizeGrip.Bounds := RectF(FWidth - ResizeGripSize, FHeight - ResizeGripSize,
    ResizeGripSize, ResizeGripSize);
end;

procedure TTapeEditor.UpdateEnabledStates;
var
  IsStereo: Boolean;
  Page: TTapeTabPage;
  I: Integer;

  { OnOffManager greys out a section's controls when its power button is off,
    leaving the button itself live. It works by name in the original; here the
    pages are built in this unit, so the controls are named by position. }
  procedure GateSection(APanel, APage, First, Last: Integer; const ParamID: string);
  var
    Target: TTapeTabPage;
    Param: TParameter;
    IsOn: Boolean;
    N: Integer;
  begin
    Param := FProcessor.Params.ByID(ParamID);
    if Param = nil then
      Exit;
    Target := FPanels[APanel].Pages[APage];
    IsOn := Param.GetBool;
    for N := First to Last do
      if N < Target.Controls.Count then
        Target.Controls[N].Enabled := IsOn;
  end;

begin
  if FPanels.Count < 4 then
    Exit;

  IsStereo := FProcessor.NumChannels = 2;

  GateSection(0, 1, 0, 2, pidIFiltOnOff);   // low cut, high cut, makeup
  GateSection(1, 0, 0, 2, pidHystOnOff);    // bias, saturation, drive
  GateSection(1, 1, 0, 2, pidCompOnOff);    // amount, attack, release
  GateSection(1, 2, 0, 2, pidToneOnOff);    // treble, bass, frequency
  GateSection(2, 0, 0, 8, pidLossOnOff);    // five sliders and the four speeds
  GateSection(2, 1, 1, 5, pidDegOnOff);     // depth, 0.1x, amount, var, envelope
  GateSection(2, 2, 0, 2, pidChewOnOff);    // depth, frequency, variance
  { the original leaves the sync menus and the plots live either way }
  GateSection(3, 0, 1, 2, pidFlutterOnOff); // flutter depth and rate
  GateSection(3, 1, 1, 4, pidFlutterOnOff); // wow depth, rate, variance, drift

  // Stereo tab
  Page := FPanels[0].Pages[2];
  for I := 0 to Page.Controls.Count - 1 do
    Page.Controls[I].Enabled := IsStereo;

  // Azimuth is stereo-only on top of the loss section's own switch
  Page := FPanels[2].Pages[0];
  Page.Controls[3].Enabled := Page.Controls[3].Enabled and IsStereo;
end;

{ ---------------------------------------------------------------------------
  Painting
  --------------------------------------------------------------------------- }

procedure TTapeEditor.EnsureBackBuffer(W, H: Integer);
var
  DC: HDC;
begin
  if (FBackDC <> 0) and (FBackW = W) and (FBackH = H) then
    Exit;

  if FBackDC <> 0 then
  begin
    DeleteDC(FBackDC);
    FBackDC := 0;
  end;
  if FBackBitmap <> 0 then
  begin
    DeleteObject(FBackBitmap);
    FBackBitmap := 0;
  end;
  if FStaticDC <> 0 then
  begin
    DeleteDC(FStaticDC);
    FStaticDC := 0;
  end;
  if FStaticBitmap <> 0 then
  begin
    DeleteObject(FStaticBitmap);
    FStaticBitmap := 0;
  end;

  DC := GetDC(FHwnd);
  try
    FBackBitmap := CreateCompatibleBitmap(DC, W, H);
    FBackDC := CreateCompatibleDC(DC);
    SelectObject(FBackDC, FBackBitmap);

    FStaticBitmap := CreateCompatibleBitmap(DC, W, H);
    FStaticDC := CreateCompatibleDC(DC);
    SelectObject(FStaticDC, FStaticBitmap);
  finally
    ReleaseDC(FHwnd, DC);
  end;

  FBackW := W;
  FBackH := H;
  FStaticValid := False;
  FDirty := True;
end;

{ The slow pass: the background, the four panels and everything else that only
  changes when the user or the host changes something. }
procedure TTapeEditor.PaintStaticTo(DC: HDC);
var
  G: TGPGraphics;
  I: Integer;
  Freq, T0, TBg, TSetup, TA, TB, TEnd: Int64;
  Panels, Scope, Other: Double;

  { DEBUG -- see DebugShowPaintStats in ChowTape.GUI.Graphics }
  function Ms(From, Till: Int64): Double;
  begin
    if Freq > 0 then
      Result := 1000.0 * (Till - From) / Freq
    else
      Result := 0.0;
  end;

begin
  QueryPerformanceFrequency(Freq);
  QueryPerformanceCounter(T0);

  Panels := 0.0;
  Scope := 0.0;
  Other := 0.0;

  G := TGPGraphics.Create(DC);
  try
    G.SetSmoothingMode(SmoothingModeAntiAlias);
    { ClearType's subpixel filtering thins white text on these dark panels; JUCE
      renders greyscale-antialiased, and this matches its weight much better }
    G.SetTextRenderingHint(TextRenderingHintAntiAliasGridFit);
    G.SetPixelOffsetMode(PixelOffsetModeHalf);

    { the root view has foleys' default margin and radius, so the red card is
      inset and rounded and the host's own background shows around it }
    FillRectC(G, RectF(0, 0, FWidth, FHeight), clBlack);
    FillRoundedRectGradient(G, RectF(0, 0, FWidth, FHeight).Reduced(FoleysMargin * FScale),
      PanelRadius, clTapeBackTop, clTapeBackBottom, True);
    QueryPerformanceCounter(TBg);

    { a section's controls grey out with its power button, and the change can
      come from the host as easily as from the editor, so it is settled here
      rather than hooked to any one of the places a parameter can move }
    UpdateEnabledStates;

    { needs a Graphics to measure with, so it cannot be settled in DoLayout }
    SyncBarFontSize(G);
    QueryPerformanceCounter(TSetup);

    for I := 0 to FControls.Count - 1 do
    begin
      QueryPerformanceCounter(TA);
      FControls[I].PaintStatic(G);
      QueryPerformanceCounter(TB);

      { DEBUG -- bucket the cost by what drew it }
      if FControls[I] is TTapeTabbedPanel then
        Panels := Panels + Ms(TA, TB)
      else if FControls[I] is TTapeScopeView then
        Scope := Scope + Ms(TA, TB)
      else
        Other := Other + Ms(TA, TB);
    end;
  finally
    G.Free;
  end;

  { DEBUG -- the breakdown holds its last full-pass values, so it says what a
    full repaint costs rather than what the steady state costs }
  QueryPerformanceCounter(TEnd);
  DebugBgMs := Ms(T0, TBg);
  DebugSetupMs := Ms(TBg, TSetup);
  DebugPanelsMs := Panels;
  DebugScopeMs := Scope;
  DebugOtherMs := Other;
  DebugFullMs := Ms(T0, TEnd);
end;

{ The fast pass: the scope and whichever wow/flutter light is on show. }
procedure TTapeEditor.PaintAnimatedTo(DC: HDC);
var
  G: TGPGraphics;
  I: Integer;
begin
  G := TGPGraphics.Create(DC);
  try
    G.SetSmoothingMode(SmoothingModeAntiAlias);
    G.SetTextRenderingHint(TextRenderingHintAntiAliasGridFit);
    G.SetPixelOffsetMode(PixelOffsetModeHalf);

    for I := 0 to FControls.Count - 1 do
      FControls[I].PaintAnimated(G);
  finally
    G.Free;
  end;
end;

{ Blits the parts of the snapshot the animated controls are about to draw over
  back into the working buffer. The rectangles are grown by a few pixels: a
  glow is stroked with a pen wider than the shape, so it reaches outside the
  control's own bounds. }
procedure TTapeEditor.RestoreAnimatedRegions;
const
  Bleed = 10;
var
  Rects: TArray<TRectF>;
  I, L, T, W, H: Integer;
begin
  if (FStaticDC = 0) or (FBackDC = 0) then
    Exit;

  SetLength(Rects, 0);
  for I := 0 to FControls.Count - 1 do
    FControls[I].CollectAnimatedBounds(Rects);

  for I := 0 to High(Rects) do
  begin
    L := Trunc(Rects[I].X) - Bleed;
    T := Trunc(Rects[I].Y) - Bleed;
    W := Ceil(Rects[I].W) + 2 * Bleed;
    H := Ceil(Rects[I].H) + 2 * Bleed;
    if L < 0 then begin Inc(W, L); L := 0; end;
    if T < 0 then begin Inc(H, T); T := 0; end;
    if L + W > FBackW then W := FBackW - L;
    if T + H > FBackH then H := FBackH - T;
    if (W > 0) and (H > 0) then
      BitBlt(FBackDC, L, T, W, H, FStaticDC, L, T, SRCCOPY);
  end;
end;

{ Host automation and mix-group peers move parameters without the editor
  hearing about it, so rather than trying to hook every path the values are
  simply compared against what was last drawn. Forty-odd floats a frame. }
function TTapeEditor.ParametersChanged: Boolean;
var
  I: Integer;
begin
  Result := False;
  if Length(FParamSnapshot) <> FProcessor.Params.Count then
  begin
    SetLength(FParamSnapshot, FProcessor.Params.Count);
    Result := True;
  end;

  for I := 0 to FProcessor.Params.Count - 1 do
    if FParamSnapshot[I] <> FProcessor.Params[I].Normalised then
    begin
      FParamSnapshot[I] := FProcessor.Params[I].Normalised;
      Result := True;
    end;
end;

procedure TTapeEditor.PaintTo(DC: HDC);
var
  Freq, T0, T1: Int64;
begin
  QueryPerformanceFrequency(Freq);
  QueryPerformanceCounter(T0);

  if FDirty or not FStaticValid then
  begin
    PaintStaticTo(DC);
    BitBlt(FStaticDC, 0, 0, FWidth, FHeight, DC, 0, 0, SRCCOPY);
    FStaticValid := True;
    FDirty := False;
    FFramesSinceFull := 0;
  end
  else
    RestoreAnimatedRegions;

  PaintAnimatedTo(DC);

  { DEBUG -- shown by TTapeScopeView.Paint when DebugShowPaintStats is on }
  QueryPerformanceCounter(T1);
  if Freq > 0 then
    DebugPaintMs := DebugPaintMs * 0.9 + (1000.0 * (T1 - T0) / Freq) * 0.1;
end;

{ ---------------------------------------------------------------------------
  Hit testing and input
  --------------------------------------------------------------------------- }

function TTapeEditor.ControlAt(X, Y: Single): TTapeControl;
var
  I: Integer;
  C: TTapeControl;
  Panel: TTapeTabbedPanel;
begin
  Result := nil;
  for I := FControls.Count - 1 downto 0 do
  begin
    C := FControls[I];
    if not C.HitTest(X, Y) then
      Continue;

    if C is TTapeTabbedPanel then
    begin
      Panel := TTapeTabbedPanel(C);
      Result := Panel.ControlAt(X, Y);
      if Result = nil then
        Result := Panel;
      Exit;
    end;

    Exit(C);
  end;
end;

function TTapeEditor.WndProc(Msg: UINT; WP: WPARAM; LP: LPARAM): LRESULT;
var
  PS: TPaintStruct;
  DC: HDC;
  X, Y: Single;
  C: TTapeControl;
  Pt: TPoint;
begin
  Result := 0;

  case Msg of
    WM_PAINT:
      begin
        DC := BeginPaint(FHwnd, PS);
        try
          EnsureBackBuffer(FWidth, FHeight);
          PaintTo(FBackDC);
          BitBlt(DC, 0, 0, FWidth, FHeight, FBackDC, 0, 0, SRCCOPY);
        finally
          EndPaint(FHwnd, PS);
        end;
        Exit;
      end;

    WM_ERASEBKGND:
      Exit(1);

    { the owner-drawn menus are measured and painted through the window that
      opened them, which is this one }
    WM_MEASUREITEM:
      if TTapeMenu.MeasureItem(LP) then
      begin
        Result := 1;
        Exit;
      end;

    WM_DRAWITEM:
      if TTapeMenu.DrawItem(LP) then
      begin
        Result := 1;
        Exit;
      end;

    WM_TIMER:
      begin
        if FOversamplingCombo <> nil then
          FOversamplingCombo.DisplayText :=
            FProcessor.Params.ByID(pidOSFactor).GetText;
        if FPresetsCombo <> nil then
        begin
          if FPresetsCombo.DisplayText <> FProcessor.Presets.DisplayName then
            FDirty := True;
          FPresetsCombo.DisplayText := FProcessor.Presets.DisplayName;
        end;

        { anything the editor did not do itself }
        if ParametersChanged then
          FDirty := True;

        { and a backstop, in case something changes state without saying so:
          a stale snapshot then lasts a second rather than for ever }
        Inc(FFramesSinceFull);
        if FFramesSinceFull >= 30 then
          FDirty := True;

        InvalidateRect(FHwnd, nil, False);
        Exit;
      end;

    WM_LBUTTONDOWN, WM_RBUTTONDOWN:
      begin
        X := SmallInt(LOWORD(LP));
        Y := SmallInt(HIWORD(LP));
        C := ControlAt(X, Y);
        if C <> nil then
        begin
          SetTooltip(C.Name, C.Tooltip);
          if (Msg = WM_LBUTTONDOWN) and C.WantsMouseCapture then
          begin
            FCaptured := C;
            SetCapture(FHwnd);
          end;
          C.MouseDown(X, Y, Msg = WM_RBUTTONDOWN);
        end;
        RequestRepaint;
        Exit;
      end;

    WM_LBUTTONDBLCLK:
      begin
        X := SmallInt(LOWORD(LP));
        Y := SmallInt(HIWORD(LP));
        C := ControlAt(X, Y);
        if C <> nil then
          C.MouseDoubleClick(X, Y);
        RequestRepaint;
        Exit;
      end;

    WM_MOUSEMOVE:
      begin
        X := SmallInt(LOWORD(LP));
        Y := SmallInt(HIWORD(LP));
        if FCaptured <> nil then
          FCaptured.MouseDrag(X, Y)
        else
        begin
          C := ControlAt(X, Y);
          if C <> FHovered then
          begin
            if FHovered <> nil then
              FHovered.Hovered := False;
            FHovered := C;
            if C <> nil then
            begin
              { a disabled control still explains itself in the tooltip bar,
                but it must not light up: nothing there responds to a click }
              C.Hovered := C.Enabled;
              SetTooltip(C.Name, C.Tooltip);
            end
            else
              SetTooltip('', '');
            RequestRepaint;
          end;
        end;
        Exit;
      end;

    WM_LBUTTONUP:
      begin
        X := SmallInt(LOWORD(LP));
        Y := SmallInt(HIWORD(LP));
        if FCaptured <> nil then
        begin
          FCaptured.MouseUp(X, Y);
          FCaptured := nil;
          ReleaseCapture;
        end;
        RequestRepaint;
        Exit;
      end;

    WM_CAPTURECHANGED:
      begin
        FCaptured := nil;
        Exit;
      end;

    WM_MOUSEWHEEL:
      begin
        Pt.X := SmallInt(LOWORD(LP));
        Pt.Y := SmallInt(HIWORD(LP));
        Winapi.Windows.ScreenToClient(FHwnd, Pt);
        C := ControlAt(Pt.X, Pt.Y);
        if C <> nil then
          C.MouseWheel(SmallInt(HIWORD(WP)));
        RequestRepaint;
        Exit;
      end;
  end;

  Result := DefWindowProc(FHwnd, Msg, WP, LP);
end;

{ ---------------------------------------------------------------------------
  Menus
  --------------------------------------------------------------------------- }

procedure TTapeEditor.SetSpeed(Speed: Single);
var
  P: TParameter;
begin
  P := FProcessor.Params.ByID(pidSpeed);
  BeginGesture(P);
  P.SetValue(Speed);
  NotifyParamChanged(P);
  EndGesture(P);
  RequestRepaint;
end;

procedure TTapeEditor.SetRateValue(IsFlutter: Boolean; Value: Single);
var
  P: TParameter;
begin
  if IsFlutter then
    P := FProcessor.Params.ByID(pidFlutterRate)
  else
    P := FProcessor.Params.ByID(pidWowRate);

  BeginGesture(P);
  P.Normalised := EnsureRange(Value, 0.0, 1.0);
  NotifyParamChanged(P);
  EndGesture(P);
  RequestRepaint;
end;

procedure TTapeEditor.ShowSyncMenu(IsFlutter: Boolean);

  function FlutterFreqToParam(Freq: Single): Single;
  begin
    Result := 0.144765 * Ln(10.0 * Freq);
  end;

  function WowFreqToParam(Freq: Single): Single;
  begin
    Result := 0.664859 * Ln(Freq + 1.0);
  end;

  procedure SyncToRhythm(MultipleOfQuarterNote: Single);
  var
    QuarterNoteTime, NewFreq, NewRate: Single;
  begin
    QuarterNoteTime := 60.0 / FProcessor.Bpm;
    NewFreq := 1.0 / (QuarterNoteTime * MultipleOfQuarterNote);
    if IsFlutter then
      NewRate := FlutterFreqToParam(NewFreq)
    else
      NewRate := WowFreqToParam(NewFreq);
    SetRateValue(IsFlutter, NewRate);
  end;

var
  Menu: TTapeMenu;
  Cmd: Integer;
  Pt: TPoint;
  SpeedIps, MotorFreq, NewRate: Single;
begin
  Menu := TTapeMenu.Create;
  try
    Menu.AddItem('Sync to tape speed', 1);
    if IsFlutter then
    begin
      Menu.AddItem('Sync to eighth note', 2);
      Menu.AddItem('Sync to quarter note', 3);
      Menu.AddItem('Sync to half note', 4);
      Menu.AddItem('Sync to whole note', 5);
    end
    else
    begin
      Menu.AddItem('Sync to one bar', 2);
      Menu.AddItem('Sync to two bars', 3);
      Menu.AddItem('Sync to four bars', 4);
      Menu.AddItem('Sync to eight bars', 5);
    end;

    GetCursorPos(Pt);
    Cmd := Menu.Popup(FHwnd, Pt.X, Pt.Y);

    { the host may have torn the editor down while the menu was up }
    if FClosing then
      Exit;

    case Cmd of
      1:
        begin
          SpeedIps := FProcessor.Params.ValueOf(pidSpeed);
          MotorFreq := SpeedIps / (6.0 * PiS);
          if IsFlutter then
            NewRate := FlutterFreqToParam(MotorFreq)
          else
            NewRate := WowFreqToParam(Sqrt(MotorFreq));
          SetRateValue(IsFlutter, NewRate);
        end;
      2: if IsFlutter then SyncToRhythm(0.125) else SyncToRhythm(1.0);
      3: if IsFlutter then SyncToRhythm(0.25) else SyncToRhythm(2.0);
      4: if IsFlutter then SyncToRhythm(0.5) else SyncToRhythm(4.0);
      5: if IsFlutter then SyncToRhythm(1.0) else SyncToRhythm(8.0);
    end;
  finally
    Menu.Free;
  end;
end;

procedure TTapeEditor.ShowOversamplingMenu;
var
  Menu: TTapeMenu;
  Cmd, I: Integer;
  Pt: TPoint;
  FactorParam, ModeParam: TParameter;
begin
  FactorParam := FProcessor.Params.ByID(pidOSFactor);
  ModeParam := FProcessor.Params.ByID(pidOSMode);

  Menu := TTapeMenu.Create;
  try
    for I := 0 to High(FactorParam.Choices) do
      Menu.AddItem(FactorParam.Choices[I], 100 + I, I = FactorParam.GetIndex);

    Menu.AddSeparator;

    for I := 0 to High(ModeParam.Choices) do
      Menu.AddItem(ModeParam.Choices[I], 200 + I, I = ModeParam.GetIndex);

    Menu.AddSeparator;
    Menu.AddItem(Format('Latency: %.2f ms',
      [FProcessor.Hysteresis.OSManager.GetLatencyMilliseconds]), 300, False, False);

    GetCursorPos(Pt);
    Cmd := Menu.Popup(FHwnd, Pt.X, Pt.Y);

    { the host may have torn the editor down while the menu was up }
    if FClosing then
      Exit;

    if (Cmd >= 100) and (Cmd < 200) then
    begin
      BeginGesture(FactorParam);
      FactorParam.SetValue(Cmd - 100);
      NotifyParamChanged(FactorParam);
      EndGesture(FactorParam);
    end
    else if (Cmd >= 200) and (Cmd < 300) then
    begin
      BeginGesture(ModeParam);
      ModeParam.SetValue(Cmd - 200);
      NotifyParamChanged(ModeParam);
      EndGesture(ModeParam);
    end;

    RequestRepaint;
  finally
    Menu.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  Presets
  --------------------------------------------------------------------------- }

procedure TTapeEditor.NotifyAllParamsChanged;
var
  I: Integer;
begin
  // The host has no idea a preset moved anything, so tell it about every
  // parameter rather than leaving its automation lanes stale.
  if not Assigned(FOnParamEdit) then
    Exit;
  for I := 0 to FProcessor.Params.Count - 1 do
    FOnParamEdit(Self, FProcessor.Params[I]);
end;

procedure TTapeEditor.StepPreset(Forward: Boolean);
begin
  if Forward then
    FProcessor.Presets.SelectNext
  else
    FProcessor.Presets.SelectPrevious;

  NotifyAllParamsChanged;
  UpdateEnabledStates;
  RequestRepaint;
end;

procedure TTapeEditor.ShowPresetsMenu;
const
  CmdResetDefault = 9001;
  CmdSaveAs       = 9002;
  CmdResave       = 9003;
  CmdDelete       = 9004;
  CmdGoToFolder   = 9005;
  CmdChooseFolder = 9006;
var
  Menu, FactoryMenu, UserMenu: TTapeMenu;
  FactoryCats, UserCats: TStringList;
  FactorySubs, UserSubs: TList<TTapeMenu>;
  Library_: TPresetLibrary;
  Entry: TPresetEntry;
  I, Cmd: Integer;
  Pt: TPoint;
  HasUser, CanEdit: Boolean;

  { Presets are grouped by the category their file gives them; a preset with no
    category goes in a submenu named after the bank it came from. }
  procedure AddEntry(Cats: TStringList;
    Subs: TList<TTapeMenu>; const Category, Name: string;
    Index: Integer; Ticked: Boolean);
  var
    Idx: Integer;
  begin
    Idx := Cats.IndexOf(Category);
    if Idx < 0 then
    begin
      Cats.Add(Category);
      { the submenu is attached later, once its caption is known }
      Subs.Add(TTapeMenu.Create);
      Idx := Cats.Count - 1;
    end;
    Subs[Idx].AddItem(Name, Index + 1, Ticked);
  end;

  procedure AttachCategories(Target: TTapeMenu; Cats: TStringList;
    Subs: TList<TTapeMenu>; const FlatLabel: string);
  var
    J: Integer;
    Caption: string;
    Child: TTapeMenu;
  begin
    for J := 0 to Cats.Count - 1 do
    begin
      if Cats[J] = '' then
        Caption := FlatLabel
      else
        Caption := Cats[J];

      Child := Target.AddSubMenu(Caption);
      Subs[J].MoveItemsTo(Child);
    end;
  end;

begin
  Library_ := FProcessor.Presets;
  Library_.Refresh;

  Menu := TTapeMenu.Create;
  FactoryCats := TStringList.Create;
  UserCats := TStringList.Create;
  FactorySubs := TObjectList<TTapeMenu>.Create(True);
  UserSubs := TObjectList<TTapeMenu>.Create(True);
  try
    HasUser := False;
    for I := 0 to Library_.Count - 1 do
    begin
      Entry := Library_[I];
      if Entry.IsFactory then
        AddEntry(FactoryCats, FactorySubs, Entry.Category, Entry.Name, I,
          I = Library_.CurrentIndex)
      else
      begin
        HasUser := True;
        AddEntry(UserCats, UserSubs, Entry.Category, Entry.Name, I,
          I = Library_.CurrentIndex);
      end;
    end;

    FactoryMenu := Menu.AddSubMenu('Factory');
    AttachCategories(FactoryMenu, FactoryCats, FactorySubs, 'Factory');

    if HasUser then
    begin
      UserMenu := Menu.AddSubMenu('User');
      AttachCategories(UserMenu, UserCats, UserSubs, 'User');
    end
    else
      Menu.AddItem('User (none saved yet)', 0, False, False);

    Menu.AddSeparator;
    Menu.AddItem('Save Preset As...', CmdSaveAs);

    // Resave and Delete only make sense for a preset backed by a file
    CanEdit := Library_.CurrentIsUserPreset;
    Menu.AddItem('Resave Preset', CmdResave, False, CanEdit);
    Menu.AddItem('Delete Preset', CmdDelete, False, CanEdit);

    Menu.AddSeparator;
    Menu.AddItem('Go to Preset Folder...', CmdGoToFolder);
    Menu.AddItem('Choose Preset Folder...', CmdChooseFolder);
    Menu.AddSeparator;
    Menu.AddItem('Reset to Default', CmdResetDefault);

    GetCursorPos(Pt);
    Cmd := Menu.Popup(FHwnd, Pt.X, Pt.Y);

    { the host may have torn the editor down while the menu was up }
    if FClosing then
      Exit;

    if (Cmd >= 1) and (Cmd <= Library_.Count) then
    begin
      Library_.LoadPreset(Cmd - 1);
      NotifyAllParamsChanged;
    end
    else
      case Cmd of
        CmdResetDefault:
          begin
            FProcessor.Params.ResetAllToDefault;
            Library_.SelectByName('Default');
            Library_.MarkClean;
            NotifyAllParamsChanged;
          end;
        CmdSaveAs:       SavePresetAs;
        CmdResave:       ResaveCurrentPreset;
        CmdDelete:       DeleteCurrentPreset;
        CmdGoToFolder:   GoToPresetFolder;
        CmdChooseFolder: ChoosePresetFolder;
      end;

    UpdateEnabledStates;
    RequestRepaint;
  finally
    UserSubs.Free;
    FactorySubs.Free;
    UserCats.Free;
    FactoryCats.Free;
    Menu.Free;
  end;
end;

procedure TTapeEditor.SavePresetAs;
var
  OFN: TOpenFilename;
  FileName: array[0..MAX_PATH] of Char;
  Folder, PresetName: string;
begin
  Folder := FProcessor.Presets.UserFolder;
  if not DirectoryExists(Folder) then
    ForceDirectories(Folder);

  FillChar(FileName, SizeOf(FileName), 0);
  StrPCopy(FileName, FProcessor.Presets.CurrentName);

  FillChar(OFN, SizeOf(OFN), 0);
  OFN.lStructSize := SizeOf(OFN);
  OFN.hwndOwner := FHwnd;
  OFN.lpstrFilter := 'CHOW Tape preset'#0'*.chowpreset'#0#0;
  OFN.lpstrFile := FileName;
  OFN.nMaxFile := MAX_PATH;
  OFN.lpstrInitialDir := PChar(Folder);
  OFN.lpstrDefExt := 'chowpreset';
  OFN.lpstrTitle := 'Save Preset As';
  OFN.Flags := OFN_OVERWRITEPROMPT or OFN_PATHMUSTEXIST;

  if not GetSaveFileName(OFN) then
    Exit;

  // the preset is named after the file, the way the original does it
  PresetName := ChangeFileExt(ExtractFileName(FileName), '');
  FProcessor.Presets.SavePresetFile(FileName, PresetName);
end;

procedure TTapeEditor.ResaveCurrentPreset;
begin
  if not FProcessor.Presets.CurrentIsUserPreset then
    Exit;
  FProcessor.Presets.SavePresetFile(FProcessor.Presets.CurrentFilePath,
    FProcessor.Presets.CurrentName);
end;

procedure TTapeEditor.DeleteCurrentPreset;
var
  Prompt: string;
begin
  if not FProcessor.Presets.CurrentIsUserPreset then
    Exit;

  Prompt := 'Delete the preset "' + FProcessor.Presets.CurrentName + '"?' + sLineBreak +
    sLineBreak + FProcessor.Presets.CurrentFilePath;

  if MessageBox(FHwnd, PChar(Prompt), 'Delete Preset',
    MB_YESNO or MB_ICONWARNING or MB_DEFBUTTON2) <> IDYES then
    Exit;

  FProcessor.Presets.DeletePreset(FProcessor.Presets.CurrentIndex);
end;

procedure TTapeEditor.GoToPresetFolder;
var
  Folder: string;
begin
  Folder := FProcessor.Presets.UserFolder;
  if not DirectoryExists(Folder) then
    ForceDirectories(Folder);
  ShellExecute(FHwnd, 'open', PChar(Folder), nil, nil, SW_SHOWNORMAL);
end;

procedure TTapeEditor.ChoosePresetFolder;
var
  Info: TBrowseInfo;
  IdList: PItemIDList;
  Buf: array[0..MAX_PATH] of Char;
  Title: string;
  NeedsUninit: Boolean;
begin
  // SHBrowseForFolder is a shell (COM) call. Hosts usually have COM up on the
  // GUI thread already, in which case CoInitialize returns S_FALSE and we
  // still have to balance it.
  NeedsUninit := Succeeded(CoInitialize(nil));

  Title := 'Choose the folder to keep user presets in';
  FillChar(Info, SizeOf(Info), 0);
  Info.hwndOwner := FHwnd;
  Info.pszDisplayName := Buf;
  Info.lpszTitle := PChar(Title);
  Info.ulFlags := BIF_RETURNONLYFSDIRS or BIF_NEWDIALOGSTYLE;

  try
    IdList := SHBrowseForFolder(Info);
    if IdList = nil then
      Exit;

    try
      if SHGetPathFromIDList(IdList, Buf) then
        FProcessor.Presets.UserFolder := Buf;
    finally
      CoTaskMemFree(IdList);
    end;
  finally
    if NeedsUninit then
      CoUninitialize;
  end;
end;

procedure TTapeEditor.ShowSettingsMenu;
var
  Menu: TTapeMenu;
  Cmd, I: Integer;
  Pt: TPoint;
begin
  Menu := TTapeMenu.Create;
  try
    { the two things the menu actually does, before the read-outs }
    Menu.AddItem('Reset All Parameters', 1);
    { the dot in the check column stands for the glow itself }
    Menu.AddItem('Glow', 10, GlowEnabled);
    Menu.AddSeparator;
    Menu.AddItem(Format('Latency: %d samples', [FProcessor.LatencySamples]),
      2, False, False);
    Menu.AddItem(Format('Sample rate: %.0f Hz', [FProcessor.SampleRate]),
      3, False, False);

    // Resource status. Both are linked into the DLL now, but each can still be
    // overridden by loose files, so report what is actually in use.
    Menu.AddSeparator;
    Menu.AddItem('Font: ' + TapeFontFamily + ' (' + TapeFontSource + ')',
      6, False, False);

    if STNModelsAvailable then
      Menu.AddItem(Format('STN models: %d/%d (%s)',
        [STNModelsLoadedCount, STNModelTotal, STNModelsSource]), 7, False, False)
    else
      Menu.AddItem('STN models: NOT FOUND - STN mode falls back to RK4',
        7, False, False);

    Menu.AddSeparator;
    Menu.AddItem('Chow Tape Model - Delphi VST 2.4 port - by JM-DG',
      4, False, False);

    GetCursorPos(Pt);
    Cmd := Menu.Popup(FHwnd, Pt.X, Pt.Y);

    { the host may have torn the editor down while the menu was up }
    if FClosing then
      Exit;

    if Cmd = 1 then
    begin
      FProcessor.Params.ResetAllToDefault;
      for I := 0 to FProcessor.Params.Count - 1 do
        if Assigned(FOnParamEdit) then
          FOnParamEdit(Self, FProcessor.Params[I]);
      RequestRepaint;
    end
    else if Cmd = 10 then
    begin
      GlowEnabled := not GlowEnabled;
      SaveSettings;
      RequestRepaint;
    end;
  finally
    Menu.Free;
  end;
end;

initialization

finalization
  StopGdiPlus;
  DoneTapeFonts;

end.
