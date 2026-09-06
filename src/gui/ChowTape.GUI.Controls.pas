unit ChowTape.GUI.Controls;

{
  The widget set behind the editor: knobs, linear sliders, toggle and power
  buttons, combo boxes, tab bars, the oscilloscope and the wow/flutter lights.

  Everything draws itself into a GDI+ surface owned by the editor; there are no
  child HWNDs except the transient edit box used for typing a value.
}

interface

uses
  Winapi.Windows, Winapi.Messages, Winapi.GDIPAPI, Winapi.GDIPOBJ,
  System.SysUtils, System.Classes, System.Math, System.Generics.Collections,
  ChowTape.GUI.Graphics, ChowTape.GUI.Menu, ChowTape.Params, ChowTape.DSP.Types,
  ChowTape.DSP.Scope;

type
  TTapeControl = class;

  ITapeEditorHost = interface
    ['{4E6B1C42-5C64-4C3E-9C1B-2A0B8D8A1F01}']
    procedure RequestRepaint;
    procedure SetTooltip(const AName, AText: string);
    procedure BeginGesture(P: TParameter);
    procedure NotifyParamChanged(P: TParameter);
    procedure EndGesture(P: TParameter);
    function HostWindow: HWND;
    function ScaleFactor: Single;
    { True once the host has asked for the editor to close. A menu's modal loop
      can be running while that happens, so anything that resumes after a popup
      has to check before touching the editor again. }
    function IsClosing: Boolean;
  end;

  TTapeControl = class
  private
    FBounds: TRectF;
  protected
    FHost: ITapeEditorHost;
  public
    Name: string;
    Tooltip: string;
    Enabled: Boolean;
    Visible: Boolean;
    { Maintained by the editor as the mouse moves. }
    Hovered: Boolean;

    constructor Create(AHost: ITapeEditorHost);
    procedure Paint(G: TGPGraphics); virtual;

    { The editor keeps a snapshot of everything that does not move and blits it
      back each frame, so only these are redrawn between changes. }
    function IsAnimated: Boolean; virtual;
    procedure PaintStatic(G: TGPGraphics); virtual;
    procedure PaintAnimated(G: TGPGraphics); virtual;
    { Appends the bounds of everything this control animates, so the editor
      knows which parts of the snapshot to restore. }
    procedure CollectAnimatedBounds(var List: TArray<TRectF>); virtual;

    function HitTest(X, Y: Single): Boolean; virtual;
    { Controls that open a popup must not grab the mouse: the menu's modal loop
      swallows the button-up that would otherwise release it. }
    function WantsMouseCapture: Boolean; virtual;
    procedure MouseDown(X, Y: Single; RightButton: Boolean); virtual;
    procedure MouseDrag(X, Y: Single); virtual;
    procedure MouseUp(X, Y: Single); virtual;
    procedure MouseWheel(Delta: Integer); virtual;
    procedure MouseDoubleClick(X, Y: Single); virtual;

    property Bounds: TRectF read FBounds write FBounds;
  end;

  TControlList = TObjectList<TTapeControl>;

  { ---------------------------------------------------------------------- }
  TTapeSliderStyle = (ssRotary, ssLinearHorizontal);
  TCaptionPlacement = (cpBelowCentred, cpTopLeft);

  TTapeSlider = class(TTapeControl)
  private
    FParam: TParameter;
    FCaption: string;
    FStyle: TTapeSliderStyle;
    FTrackColour: Cardinal;
    FCaptionPlacement: TCaptionPlacement;
    FTextHeight: Single;
    FCaptionSize: Single;
    FDefaultHeight: Single;
    FDragging: Boolean;
    FDragStartY: Single;
    FDragStartX: Single;
    FDragStartValue: Single;
    function CaptionBand: Single;
    function TextBand: Single;
    function SliderArea: TRectF;
    function TextArea: TRectF;
    function CaptionArea: TRectF;
  public
    constructor Create(AHost: ITapeEditorHost; AParam: TParameter;
      const ACaption: string; AStyle: TTapeSliderStyle = ssRotary);
    procedure Paint(G: TGPGraphics); override;
    procedure MouseDown(X, Y: Single; RightButton: Boolean); override;
    procedure MouseDrag(X, Y: Single); override;
    procedure MouseUp(X, Y: Single); override;
    procedure MouseWheel(Delta: Integer); override;
    procedure MouseDoubleClick(X, Y: Single); override;
    function WantsMouseCapture: Boolean; override;

    property Param: TParameter read FParam;
    property TrackColour: Cardinal read FTrackColour write FTrackColour;
    property CaptionPlacement: TCaptionPlacement read FCaptionPlacement write FCaptionPlacement;
    property TextHeight: Single read FTextHeight write FTextHeight;
    property CaptionSize: Single read FCaptionSize write FCaptionSize;
    { gui.xml's default-height: the height the caption size and the value box
      height were written for. ModSliderItem scales both by how far the slider
      has actually been stretched from it. }
    property DefaultHeight: Single read FDefaultHeight write FDefaultHeight;
  end;

  { ---------------------------------------------------------------------- }
  TTapeTextButton = class(TTapeControl)
  private
    FParam: TParameter;
    FTextOff: string;
    FTextOn: string;
    FDown: Boolean;
  public
    constructor Create(AHost: ITapeEditorHost; AParam: TParameter;
      const ATextOff, ATextOn: string);
    procedure Paint(G: TGPGraphics); override;
    procedure MouseDown(X, Y: Single; RightButton: Boolean); override;
    procedure MouseUp(X, Y: Single); override;
    function WantsMouseCapture: Boolean; override;
  end;

  { A borderless button used for the discrete tape-speed shortcuts. }
  TTapeActionButton = class(TTapeControl)
  private
    FText: string;
    FOnClick: TProc;
    FDown: Boolean;
  public
    constructor Create(AHost: ITapeEditorHost; const AText: string; AOnClick: TProc);
    procedure Paint(G: TGPGraphics); override;
    procedure MouseDown(X, Y: Single; RightButton: Boolean); override;
    procedure MouseUp(X, Y: Single); override;
    function WantsMouseCapture: Boolean; override;
  end;

  TTapePowerButton = class(TTapeControl)
  private
    FParam: TParameter;
  public
    constructor Create(AHost: ITapeEditorHost; AParam: TParameter);
    procedure Paint(G: TGPGraphics); override;
    procedure MouseDown(X, Y: Single; RightButton: Boolean); override;
  end;

  { ---------------------------------------------------------------------- }
  TComboStyle = (csLabelled, csPresets, csPlain);

  TTapeComboBox = class(TTapeControl)
  private
    FParam: TParameter;
    FLabel: string;
    FStyle: TComboStyle;
    FTextColour: Cardinal;
    FItems: TStringList;
    FOnSelect: TProc<Integer>;
    FOnClick: TProc;
    FDisplayText: string;
    FFontOverride: Single;
    procedure ShowMenu;
  public
    constructor Create(AHost: ITapeEditorHost; AParam: TParameter;
      const ALabel: string; AStyle: TComboStyle = csLabelled);
    destructor Destroy; override;
    procedure Paint(G: TGPGraphics); override;
    procedure MouseDown(X, Y: Single; RightButton: Boolean); override;
    { The size this box would need for its label and value to fit on one line. }
    function PreferredFontSize(G: TGPGraphics): Single;

    property Items: TStringList read FItems;
    property OnSelect: TProc<Integer> read FOnSelect write FOnSelect;
    { When assigned, clicking runs this instead of the built-in item list. }
    property OnClick: TProc read FOnClick write FOnClick;
    property DisplayText: string read FDisplayText write FDisplayText;
    { Set to draw at a size other than the one the box would pick for itself:
      the three boxes along the bottom bar share one size so that a long label
      does not end up visibly smaller than its neighbours. Zero means "choose". }
    property FontOverride: Single read FFontOverride write FFontOverride;
    property TextColour: Cardinal read FTextColour write FTextColour;
  end;

  { ---------------------------------------------------------------------- }
  TTapeTabPage = class
  public
    Caption: string;
    Controls: TControlList;
    constructor Create(const ACaption: string);
    destructor Destroy; override;
  end;

  TTapeTabbedPanel = class(TTapeControl)
  private
    FPages: TObjectList<TTapeTabPage>;
    FCurrentPage: Integer;
    FTabHeight: Single;
    FTabWidths: TArray<Single>;
    procedure MeasureTabs(G: TGPGraphics);
    function TabRect(Index: Integer): TRectF;
    procedure PaintChrome(G: TGPGraphics);
    function VisiblePage: TTapeTabPage;
  public
    procedure PaintStatic(G: TGPGraphics); override;
    procedure PaintAnimated(G: TGPGraphics); override;
    procedure CollectAnimatedBounds(var List: TArray<TRectF>); override;
    constructor Create(AHost: ITapeEditorHost);
    destructor Destroy; override;
    function AddPage(const ACaption: string): TTapeTabPage;
    function ContentArea: TRectF;
    procedure Paint(G: TGPGraphics); override;
    procedure MouseDown(X, Y: Single; RightButton: Boolean); override;
    function ControlAt(X, Y: Single): TTapeControl;
    property Pages: TObjectList<TTapeTabPage> read FPages;
    property CurrentPage: Integer read FCurrentPage write FCurrentPage;
    property TabHeight: Single read FTabHeight write FTabHeight;
  end;

  { ---------------------------------------------------------------------- }
  TTapeScopeView = class(TTapeControl)
  private
    FScope: TTapeScope;
    FTrace: TFloatArray;
  public
    constructor Create(AHost: ITapeEditorHost; AScope: TTapeScope);
    function IsAnimated: Boolean; override;
    procedure Paint(G: TGPGraphics); override;
  end;

  TTapeLightMeter = class(TTapeControl)
  private
    FGetValue: TFunc<Single>;
  public
    constructor Create(AHost: ITapeEditorHost; AGetValue: TFunc<Single>);
    function IsAnimated: Boolean; override;
    procedure Paint(G: TGPGraphics); override;
  end;

  { A plain filled rectangle. The original groups the Degrade depth control and
    its 0.1x button on a darker background; this draws it. }
  TTapeFilledPanel = class(TTapeControl)
  private
    FColour: Cardinal;
    FRadius: Single;
  public
    constructor Create(AHost: ITapeEditorHost; AColour: Cardinal;
      ARadius: Single = PanelRadius);
    procedure Paint(G: TGPGraphics); override;
    function HitTest(X, Y: Single): Boolean; override;
  end;

  TTapeTitle = class(TTapeControl)
  private
    FTitle: string;
    FSubtitle: string;
    FFontSize: Single;
  public
    constructor Create(AHost: ITapeEditorHost; const ATitle, ASubtitle: string;
      AFontSize: Single);
    procedure Paint(G: TGPGraphics); override;
  end;

  { A run of text in one colour, for the line under the title. }
  TTapeInfoSegment = record
    Text: string;
    Colour: Cardinal;
  end;

  { InfoComp sets most of the line in the accent colour and picks out the
    version number in white; this draws any number of such runs end to end. }
  TTapeInfoLine = class(TTapeControl)
  private
    FSegments: TArray<TTapeInfoSegment>;
  public
    constructor Create(AHost: ITapeEditorHost);
    procedure Add(const AText: string; AColour: Cardinal);
    procedure Paint(G: TGPGraphics); override;
  end;

  TTapeMixGroupViz = class(TTapeControl)
  private
    FParam: TParameter;
  public
    constructor Create(AHost: ITapeEditorHost; AParam: TParameter);
    procedure Paint(G: TGPGraphics); override;
  end;

  TTapeTooltipBar = class(TTapeControl)
  private
    FName: string;
    FText: string;
  public
    constructor Create(AHost: ITapeEditorHost);
    procedure SetContent(const AName, AText: string);
    procedure Paint(G: TGPGraphics); override;
  end;

  TTapeIconButton = class(TTapeControl)
  private
    FOnClick: TProc;
  public
    constructor Create(AHost: ITapeEditorHost; AOnClick: TProc);
    procedure Paint(G: TGPGraphics); override;
    procedure MouseDown(X, Y: Single; RightButton: Boolean); override;
  end;

  { The preset step buttons flanking the preset name. }
  TTapeArrowButton = class(TTapeControl)
  private
    FPointsRight: Boolean;
    FOnClick: TProc;
    FDown: Boolean;
  public
    constructor Create(AHost: ITapeEditorHost; APointsRight: Boolean; AOnClick: TProc);
    procedure Paint(G: TGPGraphics); override;
    procedure MouseDown(X, Y: Single; RightButton: Boolean); override;
    procedure MouseUp(X, Y: Single); override;
    function WantsMouseCapture: Boolean; override;
  end;

  { The corner grip foleys puts in the bottom right for resizable="1"
    resize-corner="1", drawn the way LookAndFeel_V2::drawCornerResizer does. }
  TTapeResizeGrip = class(TTapeControl)
  private
    FOnBegin: TProc;
    FOnDrag: TProc<Single, Single>;
    FDown: Boolean;
    FDragX, FDragY: Single;
  public
    constructor Create(AHost: ITapeEditorHost; AOnBegin: TProc;
      AOnDrag: TProc<Single, Single>);
    procedure Paint(G: TGPGraphics); override;
    procedure MouseDown(X, Y: Single; RightButton: Boolean); override;
    procedure MouseDrag(X, Y: Single); override;
    procedure MouseUp(X, Y: Single); override;
    function WantsMouseCapture: Boolean; override;
  end;

implementation

{ TTapeControl }

constructor TTapeControl.Create(AHost: ITapeEditorHost);
begin
  inherited Create;
  FHost := AHost;
  Enabled := True;
  Visible := True;
end;

procedure TTapeControl.Paint(G: TGPGraphics);
begin
end;

function TTapeControl.HitTest(X, Y: Single): Boolean;
begin
  Result := Visible and FBounds.Contains(X, Y);
end;

function TTapeControl.WantsMouseCapture: Boolean;
begin
  Result := False;
end;

procedure TTapeControl.MouseDown(X, Y: Single; RightButton: Boolean);
begin
end;

function TTapeControl.IsAnimated: Boolean;
begin
  Result := False;
end;

procedure TTapeControl.PaintStatic(G: TGPGraphics);
begin
  if not IsAnimated then
    Paint(G);
end;

procedure TTapeControl.PaintAnimated(G: TGPGraphics);
begin
  if IsAnimated then
    Paint(G);
end;

procedure TTapeControl.CollectAnimatedBounds(var List: TArray<TRectF>);
begin
  if IsAnimated and Visible then
  begin
    SetLength(List, Length(List) + 1);
    List[High(List)] := Bounds;
  end;
end;

procedure TTapeControl.MouseDrag(X, Y: Single);
begin
end;

procedure TTapeControl.MouseUp(X, Y: Single);
begin
end;

procedure TTapeControl.MouseWheel(Delta: Integer);
begin
end;

procedure TTapeControl.MouseDoubleClick(X, Y: Single);
begin
end;

{ TTapeSlider }

constructor TTapeSlider.Create(AHost: ITapeEditorHost; AParam: TParameter;
  const ACaption: string; AStyle: TTapeSliderStyle);
begin
  inherited Create(AHost);
  FParam := AParam;
  FCaption := ACaption;
  FStyle := AStyle;
  FTrackColour := clSliderTrack;
  FTextHeight := 17.0;
  FCaptionSize := 21.25;
  FDefaultHeight := 120.0;
  { caption-placement is a per-item property in gui.xml -- only the loss
    sliders set it to top-left -- so it does not follow from the style }
  FCaptionPlacement := cpBelowCentred;
  if AStyle = ssLinearHorizontal then
  begin
    FTextHeight := 15.0;
    FDefaultHeight := 60.0;
  end;
  Name := ACaption;
end;

{ ModSliderItem::resized sizes the value box as a proportion of the slider's
  own height rather than in absolute pixels, and the caption follows it. A knob
  given twice the room -- the stereo Balance one -- gets a label to match. }
function TTapeSlider.CaptionBand: Single;
begin
  Result := FCaptionSize;
  if (FDefaultHeight > 0.0) and (Bounds.H > 0.0) then
    Result := Result * Bounds.H / FDefaultHeight;
end;

function TTapeSlider.TextBand: Single;
begin
  Result := FTextHeight;
  if (FDefaultHeight > 0.0) and (Bounds.H > 0.0) then
    Result := Result * Bounds.H / FDefaultHeight;
end;

function TTapeSlider.CaptionArea: TRectF;
begin
  if FCaptionPlacement = cpTopLeft then
    Result := RectF(Bounds.X, Bounds.Y, Bounds.W, CaptionBand * 0.75)
  else
    Result := RectF(Bounds.X, Bounds.Y, Bounds.W, CaptionBand);
end;

function TTapeSlider.TextArea: TRectF;
var
  H: Single;
begin
  H := TextBand;
  if FStyle = ssLinearHorizontal then
    { MyLNF::getSliderLayout pulls the box back to the track's left edge }
    Result := RectF(Bounds.X, Bounds.Bottom - H, Bounds.W, H)
  else
    { ModSliderItem asks for three quarters of the slider's width }
    Result := RectF(Bounds.CentreX - Bounds.W * 0.375, Bounds.Bottom - H,
      Bounds.W * 0.75, H);
end;

function TTapeSlider.SliderArea: TRectF;
var
  Top, Bot: Single;
begin
  Top := CaptionArea.Bottom;
  Bot := Bounds.Bottom - TextBand - 1;
  Result := RectF(Bounds.X, Top, Bounds.W, JMaxF(0.0, Bot - Top));
end;

procedure TTapeSlider.Paint(G: TGPGraphics);
var
  Area, Text, Cap, Thumb: TRectF;
  Alpha, Pos, TrackWidth, KX, ThumbSize: Single;
  StartX, EndX, MidY: Single;
  GlowPts: array[0 .. 1] of TGPPointF;
  Pen: TGPPen;
begin
  if not Visible then
    Exit;

  if Enabled then
    Alpha := 1.0
  else
    Alpha := 0.4;

  Pos := FParam.Normalised;
  Cap := CaptionArea;
  Area := SliderArea;
  Text := TextArea;

  if FCaption <> '' then
  begin
    if FCaptionPlacement = cpTopLeft then
      DrawTextC(G, FCaption, Cap, Cap.H * 0.95, WithAlpha(clWhite, Alpha), True, 0, 1)
    else
      DrawTextC(G, FCaption, Cap, Cap.H * 0.72, WithAlpha(clWhite, Alpha), True, 1, 1);
  end;

  if FStyle = ssRotary then
  begin
    DrawRotaryArc(G, Area, Pos, Alpha, FTrackColour);
    Thumb := RectF(Area.CentreX - Min(Area.W, Area.H) * 0.375,
                   Area.CentreY - Min(Area.W, Area.H) * 0.375,
                   Min(Area.W, Area.H) * 0.75, Min(Area.W, Area.H) * 0.75);
    DrawKnobBody(G, Thumb, Alpha);
    DrawKnobPointer(G, Thumb, Pos, Alpha);
  end
  else
  begin
    TrackWidth := Min(10.0, Area.H * 0.25);
    MidY := Area.CentreY;
    StartX := Area.X + TrackWidth * 0.5;
    EndX := Area.Right - TrackWidth * 0.5;

    Pen := TGPPen.Create(WithAlpha(clSliderBack, Alpha), TrackWidth);
    try
      Pen.SetStartCap(LineCapRound);
      Pen.SetEndCap(LineCapRound);
      G.DrawLine(Pen, StartX, MidY, EndX, MidY);
    finally
      Pen.Free;
    end;

    KX := StartX + (EndX - StartX) * Pos;

    GlowPts[0].X := StartX;
    GlowPts[0].Y := MidY;
    GlowPts[1].X := KX;
    GlowPts[1].Y := MidY;
    DrawGlowPolyline(G, PGPPointF(@GlowPts[0]), 2,
      WithAlpha(FTrackColour, Alpha), TrackWidth, 2.5);

    // LookAndFeel_V4 caps the thumb radius at 12, so in practice the thumb is
    // always trackWidth * 2.5 whatever the slider's height. Scaling it with the
    // height, as this did, made a tall slider grow an absurd knob.
    ThumbSize := Max(TrackWidth * 2.5, Min(12.0, Area.H * 0.5));
    Thumb := RectF(KX - ThumbSize * 0.5, MidY - ThumbSize * 0.5, ThumbSize, ThumbSize);
    DrawKnobBody(G, Thumb, Alpha);
  end;

  if FStyle = ssLinearHorizontal then
    DrawTextC(G, FParam.GetText, Text, Text.H * 0.85, WithAlpha(clWhite, Alpha), False, 0, 1)
  else
    DrawTextC(G, FParam.GetText, Text, Text.H * 0.85, WithAlpha(clWhite, Alpha), False, 1, 1);
end;

function TTapeSlider.WantsMouseCapture: Boolean;
begin
  Result := True;
end;

procedure TTapeSlider.MouseDown(X, Y: Single; RightButton: Boolean);
begin
  if not Enabled then
    Exit;
  FHost.SetTooltip(Name, Tooltip);
  if RightButton then
    Exit;

  FDragging := True;
  FDragStartX := X;
  FDragStartY := Y;
  FDragStartValue := FParam.Normalised;
  FHost.BeginGesture(FParam);
end;

procedure TTapeSlider.MouseDrag(X, Y: Single);
var
  Delta, Sensitivity, NewValue: Single;
begin
  if not FDragging then
    Exit;

  Sensitivity := 200.0;
  if GetKeyState(VK_CONTROL) < 0 then
    Sensitivity := 1500.0;

  if FStyle = ssRotary then
    Delta := (FDragStartY - Y) / Sensitivity
  else
    Delta := (X - FDragStartX) / Max(40.0, SliderArea.W);

  NewValue := EnsureRange(FDragStartValue + Delta, 0.0, 1.0);
  if NewValue <> FParam.Normalised then
  begin
    FParam.Normalised := NewValue;
    FHost.NotifyParamChanged(FParam);
    FHost.RequestRepaint;
  end;
end;

procedure TTapeSlider.MouseUp(X, Y: Single);
begin
  if FDragging then
  begin
    FDragging := False;
    FHost.EndGesture(FParam);
  end;
end;

procedure TTapeSlider.MouseWheel(Delta: Integer);
var
  Step, NewValue: Single;
begin
  if not Enabled then
    Exit;
  Step := 0.02;
  if GetKeyState(VK_CONTROL) < 0 then
    Step := 0.002;
  NewValue := EnsureRange(FParam.Normalised + Sign(Delta) * Step, 0.0, 1.0);
  if NewValue <> FParam.Normalised then
  begin
    FHost.BeginGesture(FParam);
    FParam.Normalised := NewValue;
    FHost.NotifyParamChanged(FParam);
    FHost.EndGesture(FParam);
    FHost.RequestRepaint;
  end;
end;

procedure TTapeSlider.MouseDoubleClick(X, Y: Single);
begin
  if not Enabled then
    Exit;
  FHost.BeginGesture(FParam);
  FParam.ResetToDefault;
  FHost.NotifyParamChanged(FParam);
  FHost.EndGesture(FParam);
  FHost.RequestRepaint;
end;

{ TTapeTextButton }

constructor TTapeTextButton.Create(AHost: ITapeEditorHost; AParam: TParameter;
  const ATextOff, ATextOn: string);
begin
  inherited Create(AHost);
  FParam := AParam;
  FTextOff := ATextOff;
  FTextOn := ATextOn;
end;

procedure TTapeTextButton.Paint(G: TGPGraphics);
var
  R: TRectF;
  Colour: Cardinal;
  Caption: string;
  Alpha: Single;
begin
  if not Visible then
    Exit;

  if Enabled then Alpha := 1.0 else Alpha := 0.5;

  { padding="5" in gui.xml: the button component is the padded rectangle, and
    everything below -- the shape, the font height -- is measured against it }
  R := Bounds.Reduced(5.0);
  if FParam.GetBool then
  begin
    Colour := clButtonOn;
    Caption := FTextOn;
  end
  else
  begin
    Colour := clButton;
    Caption := FTextOff;
  end;

  DrawButtonShapeV3(G, R, Colour, Enabled, FDown, Hovered);
  { LookAndFeel_V2::getTextButtonFont, which LookAndFeel_V3 does not override }
  DrawTextC(G, Caption, R, Min(16.0, R.H * 0.6), WithAlpha(clWhite, Alpha), False, 1, 1);
end;

function TTapeTextButton.WantsMouseCapture: Boolean;
begin
  Result := True;
end;

procedure TTapeTextButton.MouseDown(X, Y: Single; RightButton: Boolean);
begin
  if not Enabled then
    Exit;
  FHost.SetTooltip(Name, Tooltip);
  if RightButton then
    Exit;
  FDown := True;
  FHost.RequestRepaint;
end;

procedure TTapeTextButton.MouseUp(X, Y: Single);
begin
  if not FDown then
    Exit;
  FDown := False;
  if Bounds.Contains(X, Y) then
  begin
    FHost.BeginGesture(FParam);
    if FParam.GetBool then
      FParam.Normalised := 0.0
    else
      FParam.Normalised := 1.0;
    FHost.NotifyParamChanged(FParam);
    FHost.EndGesture(FParam);
  end;
  FHost.RequestRepaint;
end;

{ TTapeActionButton }

constructor TTapeActionButton.Create(AHost: ITapeEditorHost; const AText: string;
  AOnClick: TProc);
begin
  inherited Create(AHost);
  FText := AText;
  FOnClick := AOnClick;
end;

procedure TTapeActionButton.Paint(G: TGPGraphics);
var
  R: TRectF;
  Base: Cardinal;
  Alpha: Single;
begin
  if not Visible then
    Exit;

  { the loss section greys these out with its power button, the same 0.4 the
    look-and-feel fades a disabled slider by }
  if Enabled then Alpha := 1.0 else Alpha := 0.4;

  { padding="2" in gui.xml, then snapped so the one-pixel outline is crisp and
    the label is centred on exactly the box that gets drawn }
  R := SnapForStroke(Bounds.Reduced(2.0));
  if not Enabled then
    Base := $00000000
  else if FDown then
    Base := $33FFFFFF
  else if Hovered then
    Base := $1AFFFFFF
  else
    Base := $00000000;

  FillRoundedRect(G, R, 8.0, Base);
  StrokeRoundedRect(G, R, 8.0, 1.0, WithAlpha(clTabBarBack, Alpha));
  DrawTextC(G, FText, R, Min(18.0, R.H * 0.6), WithAlpha(clWhite, Alpha), False, 1, 1);
end;

function TTapeActionButton.WantsMouseCapture: Boolean;
begin
  Result := True;
end;

procedure TTapeActionButton.MouseDown(X, Y: Single; RightButton: Boolean);
begin
  if not Enabled then
    Exit;
  FHost.SetTooltip(Name, Tooltip);
  if RightButton then
    Exit;
  FDown := True;
  FHost.RequestRepaint;
end;

procedure TTapeActionButton.MouseUp(X, Y: Single);
begin
  if not FDown then
    Exit;
  FDown := False;
  if Bounds.Contains(X, Y) and Assigned(FOnClick) then
    FOnClick();
  FHost.RequestRepaint;
end;

{ TTapePowerButton }

constructor TTapePowerButton.Create(AHost: ITapeEditorHost; AParam: TParameter);
begin
  inherited Create(AHost);
  FParam := AParam;
end;

procedure TTapePowerButton.Paint(G: TGPGraphics);
var
  R: TRectF;
  Size: Single;
begin
  if not Visible then
    Exit;

  { PowerButtonItem::resized indents the drawable by a fifth of the shorter
    side on every edge, which would leave a square of 0.6 * min(w, h). That
    reads as too slight against the rest of the panel, so the indent is cut
    to a seventh: 21 pixels on the 30-pixel row the buttons sit in. }
  Size := Min(Bounds.W, Bounds.H) * 0.71;
  R := RectF(Bounds.CentreX - Size * 0.5, Bounds.CentreY - Size * 0.5, Size, Size);

  { only the lit state glows: a halo round the slate-grey off state would just
    look like a smudge }
  if FParam.GetBool then
  begin
    DrawPowerSymbol(G, R, clAccent, True);
    Exit;
  end;

  DrawPowerSymbol(G, R, clSliderBack);
end;

procedure TTapePowerButton.MouseDown(X, Y: Single; RightButton: Boolean);
begin
  FHost.SetTooltip(Name, Tooltip);
  if RightButton then
    Exit;

  FHost.BeginGesture(FParam);
  if FParam.GetBool then
    FParam.Normalised := 0.0
  else
    FParam.Normalised := 1.0;
  FHost.NotifyParamChanged(FParam);
  FHost.EndGesture(FParam);
  FHost.RequestRepaint;
end;

{ TTapeComboBox }

constructor TTapeComboBox.Create(AHost: ITapeEditorHost; AParam: TParameter;
  const ALabel: string; AStyle: TComboStyle);
var
  I: Integer;
begin
  inherited Create(AHost);
  FParam := AParam;
  FLabel := ALabel;
  FStyle := AStyle;
  FTextColour := clAccent;
  FItems := TStringList.Create;
  Name := ALabel;

  if FParam <> nil then
    for I := 0 to High(FParam.Choices) do
      FItems.Add(FParam.Choices[I]);
end;

destructor TTapeComboBox.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

procedure TTapeComboBox.Paint(G: TGPGraphics);
var
  R, NameBox, ValueBox: TRectF;
  FontSize: Single;
  Text: string;
begin
  if not Visible then
    Exit;

  R := Bounds;
  FontSize := Min(28.0, R.H * 0.48);

  if FStyle = csPresets then
  begin
    FillRoundedRect(G, R, 5.0, clPresetBack);
    FontSize := Min(28.0, R.H * 0.55);
    DrawTextC(G, FDisplayText, R.Reduced(6.0, 1.0), FontSize, clWhite, True, 1, 1);
    Exit;
  end;

  if FStyle = csPlain then
  begin
    { WowFlutterMenuLNF::drawComboBox: the background is transparent, so all
      that marks the menu out is a FF595C6B outline inset by a pixel, with the
      menu's own name centred in bold white inside it. The outline is snapped
      to the pixel grid and the name is centred on the snapped box, so the two
      cannot disagree by the half pixel the flex layout leaves behind. }
    NameBox := SnapForStroke(R.Reduced(1.0));
    StrokeRoundedRect(G, NameBox, 5.0, 1.0, clSliderBack);
    { WowFlutterMenuLNF sizes the name at 0.48 of the height, which on a box
      this wide leaves the label all but touching the sides; a little under
      that, with ten pixels kept clear at each end, sits better. The width is
      what runs out first when the panel narrows, so it is fitted to that. }
    FontSize := FitFontSize(G, FDisplayText, Min(28.0, R.H * 0.40),
      NameBox.W - 20.0, True);
    DrawTextC(G, FDisplayText, NameBox, FontSize, clWhite, True, 1, 1);
    Exit;
  end;

  if FParam <> nil then
    Text := FParam.GetText
  else
    Text := FDisplayText;

  if FLabel <> '' then
  begin
    { ComboBoxLNF splits the box seven-three between the name and the value. }
    NameBox := RectF(R.X, R.Y, R.W * 0.7, R.H);
    ValueBox := RectF(R.X + R.W * 0.7, R.Y, R.W * 0.3, R.H);
    if FFontOverride > 0.0 then
      FontSize := FFontOverride
    else
      FontSize := PreferredFontSize(G);
    DrawTextC(G, FLabel + ': ', NameBox, FontSize, clWhite, True, 2, 1);
    DrawTextC(G, Text, ValueBox, FontSize, FTextColour, True, 1, 1);
  end
  else
    DrawTextC(G, Text, R, FontSize, FTextColour, True, 1, 1);
end;

{ Neither half of a labelled box is wide enough for "Hysteresis Mode: " at the
  nominal size, and JUCE would condense the glyphs rather than truncate. This
  brings the point size down instead, taking the smaller of what the two halves
  need so they stay the same size as each other. }
function TTapeComboBox.PreferredFontSize(G: TGPGraphics): Single;
var
  R: TRectF;
  Text: string;
begin
  R := Bounds;
  Result := Min(28.0, R.H * 0.48);
  if (FStyle <> csLabelled) or (FLabel = '') then
    Exit;

  if FParam <> nil then
    Text := FParam.GetText
  else
    Text := FDisplayText;

  Result := Min(FitFontSize(G, FLabel + ': ', Result, R.W * 0.7 - 2.0, True),
                FitFontSize(G, Text, Result, R.W * 0.3 - 2.0, True));
end;

procedure TTapeComboBox.ShowMenu;
var
  Menu: TTapeMenu;
  I, Cmd, Selected: Integer;
  Pt: TPoint;
begin
  Menu := TTapeMenu.Create;
  try
    if FParam <> nil then
      Selected := FParam.GetIndex
    else
      Selected := -1;

    for I := 0 to FItems.Count - 1 do
      if FItems[I] = '-' then
        Menu.AddSeparator
      else
        Menu.AddItem(FItems[I], I + 1, I = Selected);

    { at the pointer, as the sync, oversampling, preset and settings menus all
      are. Anchoring to the box's own left edge is the usual thing for a combo,
      but these stretch with the window, and on a wide one the menu came up a
      long way from the click that opened it. }
    GetCursorPos(Pt);

    Cmd := Menu.Popup(FHost.HostWindow, Pt.X, Pt.Y);

    { the host may have torn the editor down while the menu was up }
    if FHost.IsClosing then
      Exit;

    if Cmd > 0 then
    begin
      if Assigned(FOnSelect) then
        FOnSelect(Cmd - 1)
      else if FParam <> nil then
      begin
        FHost.BeginGesture(FParam);
        FParam.SetValue(Cmd - 1);
        FHost.NotifyParamChanged(FParam);
        FHost.EndGesture(FParam);
      end;
      FHost.RequestRepaint;
    end;
  finally
    Menu.Free;
  end;
end;

procedure TTapeComboBox.MouseDown(X, Y: Single; RightButton: Boolean);
begin
  FHost.SetTooltip(Name, Tooltip);
  if RightButton or not Enabled then
    Exit;
  if Assigned(FOnClick) then
    FOnClick()
  else
    ShowMenu;
end;

{ TTapeTabPage }

constructor TTapeTabPage.Create(const ACaption: string);
begin
  inherited Create;
  Caption := ACaption;
  Controls := TControlList.Create(True);
end;

destructor TTapeTabPage.Destroy;
begin
  Controls.Free;
  inherited Destroy;
end;

{ TTapeTabbedPanel }

constructor TTapeTabbedPanel.Create(AHost: ITapeEditorHost);
begin
  inherited Create(AHost);
  FPages := TObjectList<TTapeTabPage>.Create(True);
  FCurrentPage := 0;
  FTabHeight := 26.0;
end;

destructor TTapeTabbedPanel.Destroy;
begin
  FPages.Free;
  inherited Destroy;
end;

function TTapeTabbedPanel.AddPage(const ACaption: string): TTapeTabPage;
begin
  Result := TTapeTabPage.Create(ACaption);
  FPages.Add(Result);
end;

function TTapeTabbedPanel.ContentArea: TRectF;
begin
  Result := RectF(Bounds.X, Bounds.Y + FTabHeight, Bounds.W, Bounds.H - FTabHeight);
end;

{ TabbedButtonBar asks the look and feel for each tab's best width and lays
  them out from that, so a long caption gets a wider tab. Dividing the bar
  equally instead left "Degrade" filling nine tenths of its cell while "Loss"
  beside it filled half, which reads as a misplaced divider. }
procedure TTapeTabbedPanel.MeasureTabs(G: TGPGraphics);
const
  { what a tab gets on top of its caption, before everything is scaled to fit }
  TabPadding = 20.0;
var
  I: Integer;
  Total, FontSize: Single;
begin
  SetLength(FTabWidths, FPages.Count);
  if FPages.Count = 0 then
    Exit;

  FontSize := (FTabHeight - 4.0) * 0.45;
  Total := 0.0;
  for I := 0 to FPages.Count - 1 do
  begin
    FTabWidths[I] := MeasureTextWidth(G, FPages[I].Caption, FontSize, True) +
      TabPadding;
    Total := Total + FTabWidths[I];
  end;

  if Total <= 0.0 then
    Exit;

  { and then stretched to fill the bar exactly, so the last tab ends on the
    panel's edge }
  for I := 0 to FPages.Count - 1 do
    FTabWidths[I] := FTabWidths[I] * Bounds.W / Total;
end;

function TTapeTabbedPanel.TabRect(Index: Integer): TRectF;
var
  I: Integer;
  X, W: Single;
begin
  if FPages.Count = 0 then
    Exit(RectF(0, 0, 0, 0));

  { equal shares until the first paint has had a chance to measure }
  if Length(FTabWidths) <> FPages.Count then
  begin
    W := Bounds.W / FPages.Count;
    Exit(RectF(Bounds.X + Index * W, Bounds.Y, W, FTabHeight));
  end;

  X := Bounds.X;
  for I := 0 to Index - 1 do
    X := X + FTabWidths[I];
  Result := RectF(X, Bounds.Y, FTabWidths[Index], FTabHeight);
end;

procedure TTapeTabbedPanel.PaintChrome(G: TGPGraphics);
const
  { the front tab's rule stops short of the dividers on either side of it --
    they are a pixel wide, so two clears them with one to spare }
  UnderlineInset = 2.0;
var
  I: Integer;
  R, Shadow: TRectF;
  Colour: Cardinal;
  BarY: Single;
  GlowPts: array[0 .. 1] of TGPPointF;
begin
  if not Visible then
    Exit;

  { the tabbed view is a foleys item like any other: its background is a
    rounded rectangle, and the radius is foleys' default of 5 }
  FillRoundedRect(G, Bounds, PanelRadius, clPanel);

  MeasureTabs(G);

  { every tab in gui.xml carries tab-color="", so the gradient MyLNF paints
    behind an unselected tab is drawn in transparent black and the panel shows
    through unchanged. What actually marks the bar out is the shadow
    LookAndFeel_V2 lays across the bottom fifth of it and the outline along
    its lower edge; the front tab is told apart by the colour of its text. }
  Shadow := RectF(Bounds.X, Bounds.Y + FTabHeight * 0.8, Bounds.W, FTabHeight * 0.2);
  FillGradientRect(G, Shadow, $00000000, $40000000, False);
  FillRectC(G, RectF(Bounds.X, Bounds.Y + FTabHeight - 1, Bounds.W, 1), clTabOutline);

  for I := 0 to FPages.Count - 1 do
  begin
    R := TabRect(I);

    { a rule the full height of the bar between neighbours. The tab widths
      come out of a text measurement, so it is snapped to a whole pixel. }
    if I > 0 then
      FillRectC(G, RectF(Round(R.X), R.Y, 1.0, FTabHeight), clTabOutline);

    if I = FCurrentPage then
    begin
      Colour := clWhite;
      { and the front tab is picked out by an accent rule just above the
        outline that runs the width of the bar, haloed like everything else
        the accent is used for. The clip stops at the underside of the rule,
        so the halo blooms up into the tab and nothing spills onto the line
        below it or across the dividers to either side. }
      BarY := Round(R.Y + FTabHeight) - 3.0;
      GlowPts[0].X := R.X + UnderlineInset;
      GlowPts[0].Y := BarY;
      GlowPts[1].X := R.X + R.W - UnderlineInset;
      GlowPts[1].Y := BarY;

      G.SetClip(MakeRect(R.X, R.Y, R.W, BarY + 1.0 - R.Y));
      try
        DrawGlowPolyline(G, PGPPointF(@GlowPts[0]), 2, clAccent, 2.0, 2.5);
      finally
        G.ResetClip;
      end;
    end
    else
      Colour := $99FFFFFF;   // Colours::white with the 0.6 alpha MyLNF applies

    { MyLNF centres the caption in the active area, which LookAndFeel_V2 takes
      four pixels off the top of -- that reads as sitting low here, so it is
      centred in the whole tab instead }
    DrawTextC(G, FPages[I].Caption, R, (FTabHeight - 4.0) * 0.45,
      Colour, True, 1, 1);
  end;
end;

function TTapeTabbedPanel.VisiblePage: TTapeTabPage;
begin
  if Visible and (FCurrentPage >= 0) and (FCurrentPage < FPages.Count) then
    Result := FPages[FCurrentPage]
  else
    Result := nil;
end;

procedure TTapeTabbedPanel.Paint(G: TGPGraphics);
var
  Page: TTapeTabPage;
  J: Integer;
begin
  PaintChrome(G);
  Page := VisiblePage;
  if Page = nil then
    Exit;
  for J := 0 to Page.Controls.Count - 1 do
    Page.Controls[J].Paint(G);
end;

procedure TTapeTabbedPanel.PaintStatic(G: TGPGraphics);
var
  Page: TTapeTabPage;
  J: Integer;
begin
  PaintChrome(G);
  Page := VisiblePage;
  if Page = nil then
    Exit;
  for J := 0 to Page.Controls.Count - 1 do
    Page.Controls[J].PaintStatic(G);
end;

procedure TTapeTabbedPanel.PaintAnimated(G: TGPGraphics);
var
  Page: TTapeTabPage;
  J: Integer;
begin
  Page := VisiblePage;
  if Page = nil then
    Exit;
  for J := 0 to Page.Controls.Count - 1 do
    Page.Controls[J].PaintAnimated(G);
end;

procedure TTapeTabbedPanel.CollectAnimatedBounds(var List: TArray<TRectF>);
var
  Page: TTapeTabPage;
  J: Integer;
begin
  Page := VisiblePage;
  if Page = nil then
    Exit;
  for J := 0 to Page.Controls.Count - 1 do
    Page.Controls[J].CollectAnimatedBounds(List);
end;

procedure TTapeTabbedPanel.MouseDown(X, Y: Single; RightButton: Boolean);
var
  I: Integer;
begin
  if Y < Bounds.Y + FTabHeight then
  begin
    for I := 0 to FPages.Count - 1 do
      if TabRect(I).Contains(X, Y) then
      begin
        FCurrentPage := I;
        FHost.RequestRepaint;
        Exit;
      end;
  end;
end;

function TTapeTabbedPanel.ControlAt(X, Y: Single): TTapeControl;
var
  I: Integer;
  Page: TTapeTabPage;
begin
  Result := nil;
  if (FCurrentPage < 0) or (FCurrentPage >= FPages.Count) then
    Exit;
  Page := FPages[FCurrentPage];
  for I := Page.Controls.Count - 1 downto 0 do
    if Page.Controls[I].HitTest(X, Y) then
      Exit(Page.Controls[I]);
end;

{ TTapeScopeView }

constructor TTapeScopeView.Create(AHost: ITapeEditorHost; AScope: TTapeScope);
begin
  inherited Create(AHost);
  FScope := AScope;
end;

function TTapeScopeView.IsAnimated: Boolean;
begin
  Result := True;
end;

procedure TTapeScopeView.Paint(G: TGPGraphics);
const
  { xPad in TapeScope, widened from the three pixels it was so the read-outs
    clear the rounded corners and the border rather than sitting against them }
  LabelInset = 7.0;
var
  R: TRectF;
  N, NumPoints: Integer;
  Pts: array of TGPPointF;
  MidY, HalfH: Single;
  LabelBand: TRectF;
  InLabel, OutLabel: string;
begin
  if not Visible then
    Exit;

  R := Bounds;
  FillRoundedRect(G, R, PanelRadius, clScopeBack);
  StrokeRoundedRect(G, SnapForStroke(R, clWellOutlineWidth), PanelRadius,
    clWellOutlineWidth, clWellOutline);

  NumPoints := Max(16, Round(R.W));
  FScope.GetTrace(FTrace, NumPoints);

  MidY := R.CentreY;
  HalfH := R.H * 0.5;

  SetLength(Pts, NumPoints);
  for N := 0 to NumPoints - 1 do
  begin
    Pts[N].X := R.X + R.W * N / (NumPoints - 1);
    Pts[N].Y := MidY - EnsureRange(FTrace[N], -1.0, 1.0) * HalfH * 0.9;
  end;

  { the trace runs the full width of the panel and its halo is stroked wider
    than the line, so it is kept inside the border rather than the background:
    clipping to the background alone still lets it draw over the border, which
    is stroked on that same edge }
  ClipToRoundedRect(G, R.Reduced(clWellOutlineWidth),
    JMaxF(0.0, PanelRadius - clWellOutlineWidth));
  try
    DrawGlowPolyline(G, PGPPointF(@Pts[0]), NumPoints, clAccent, 1.5, 2.5);
  finally
    G.ResetClip;
  end;

  InLabel := Format('IN: %.1f dB', [FScope.GetInputDb]);
  OutLabel := Format('OUT: %.1f dB', [FScope.GetOutputDb]);

  { TapeScope::createPlotPaths puts the readouts in the top fifth of the plot,
    vertically centred in it. That leaves the glyph tops right up against the
    edge, so they are nudged down here -- about six pixels at the default size,
    scaled with the rest of the GUI. }
  LabelBand := RectF(R.X, R.Y + R.H * 0.06, R.W, R.H * 0.2);

  DrawTextC(G, InLabel,
    RectF(LabelBand.X + LabelInset, LabelBand.Y, R.W * 0.5, LabelBand.H),
    R.H * 0.18, clWhite, False, 0, 1);
  DrawTextC(G, OutLabel,
    RectF(R.CentreX, LabelBand.Y, R.W * 0.5 - LabelInset, LabelBand.H),
    R.H * 0.18, clWhite, False, 2, 1);

  { DEBUG -- where the last repaint went, live in the corner. Off by default;
    the switch is DebugShowPaintStats in ChowTape.GUI.Graphics. }
  if DebugShowPaintStats then
    DrawTextC(G, Format('avg %.1f ms/frame     [last full repaint %.1f = bg %.1f + pan %.1f + ui %.1f]',
        [DebugPaintMs, DebugFullMs, DebugBgMs, DebugPanelsMs,
         DebugSetupMs + DebugScopeMs + DebugOtherMs]),
      RectF(R.X + 4, R.Bottom - R.H * 0.22, R.W - 8, R.H * 0.2),
      R.H * 0.14, $99FFFFFF, False, 0, 1);
end;

{ TTapeLightMeter }

constructor TTapeLightMeter.Create(AHost: ITapeEditorHost; AGetValue: TFunc<Single>);
begin
  inherited Create(AHost);
  FGetValue := AGetValue;
end;

function TTapeLightMeter.IsAnimated: Boolean;
begin
  Result := True;
end;

procedure TTapeLightMeter.Paint(G: TGPGraphics);
var
  R: TRectF;
  Diameter, MaxDiameter: Single;
  Brush: TGPSolidBrush;
  Pen: TGPPen;
begin
  if not Visible then
    Exit;

  R := Bounds;
  FillRoundedRect(G, R, PanelRadius, clPanelDark);

  MaxDiameter := Min(R.W, R.H);
  Diameter := MaxDiameter * EnsureRange(FGetValue(), 0.0, 1.0);

  if Diameter > 0.5 then
  begin
    Brush := TGPSolidBrush.Create(clPlotFill);
    Pen := TGPPen.Create(clAccent, 1.5);
    try
      G.FillEllipse(Brush, R.CentreX - Diameter * 0.5, R.CentreY - Diameter * 0.5,
        Diameter, Diameter);
      G.DrawEllipse(Pen, R.CentreX - Diameter * 0.5, R.CentreY - Diameter * 0.5,
        Diameter, Diameter);
    finally
      Pen.Free;
      Brush.Free;
    end;
  end;
end;

{ TTapeFilledPanel }

constructor TTapeFilledPanel.Create(AHost: ITapeEditorHost; AColour: Cardinal;
  ARadius: Single);
begin
  inherited Create(AHost);
  FColour := AColour;
  FRadius := ARadius;
end;

procedure TTapeFilledPanel.Paint(G: TGPGraphics);
begin
  if not Visible then
    Exit;
  if FRadius > 0.0 then
    FillRoundedRect(G, Bounds, FRadius, FColour)
  else
    FillRectC(G, Bounds, FColour);
end;

function TTapeFilledPanel.HitTest(X, Y: Single): Boolean;
begin
  // decoration only: never claim the mouse or a tooltip
  Result := False;
end;

{ TTapeTitle }

constructor TTapeTitle.Create(AHost: ITapeEditorHost; const ATitle, ASubtitle: string;
  AFontSize: Single);
begin
  inherited Create(AHost);
  FTitle := ATitle;
  FSubtitle := ASubtitle;
  FFontSize := AFontSize;
end;

procedure TTapeTitle.Paint(G: TGPGraphics);
var
  R: TRectF;
  W, Size: Single;
begin
  if not Visible then
    Exit;

  R := Bounds;

  { the title column narrows with the window while the point size does not, so
    the size comes down until the whole title fits rather than running on over
    the scope beside it }
  Size := FitFontSize(G, FTitle + ' ' + FSubtitle, FFontSize, R.W, True);

  W := MeasureTextWidth(G, FTitle + ' ', Size, True);
  DrawTextC(G, FTitle + ' ', RectF(R.X, R.Y, W, R.H), Size, clWhite, True, 0, 1);

  if FSubtitle <> '' then
    DrawTextC(G, FSubtitle, RectF(R.X + W, R.Y, R.W - W, R.H), Size,
      $FF808080, True, 0, 1);
end;

{ TTapeInfoLine }

constructor TTapeInfoLine.Create(AHost: ITapeEditorHost);
begin
  inherited Create(AHost);
end;

procedure TTapeInfoLine.Add(const AText: string; AColour: Cardinal);
var
  N: Integer;
begin
  N := Length(FSegments);
  SetLength(FSegments, N + 1);
  FSegments[N].Text := AText;
  FSegments[N].Colour := AColour;
end;

procedure TTapeInfoLine.Paint(G: TGPGraphics);
var
  I: Integer;
  X, Right, FontSize, W, Total: Single;
begin
  if not Visible then
    Exit;

  FontSize := Min(14.0, Bounds.H * 0.7);

  { the line carries the architecture, the version and a byline, which is long
    enough to run past the title column at the nominal size, so it is measured
    first and brought down until the whole of it fits }
  Total := 0.0;
  for I := 0 to High(FSegments) do
    Total := Total + MeasureTextWidth(G, FSegments[I].Text, FontSize, False);
  if (Total > Bounds.W) and (Total > 0.0) then
    FontSize := JMaxF(6.0, FontSize * Bounds.W / Total);

  X := Bounds.X;
  Right := Bounds.Right;

  for I := 0 to High(FSegments) do
  begin
    if X >= Right then
      Break;
    W := MeasureTextWidth(G, FSegments[I].Text, FontSize, False);
    DrawTextC(G, FSegments[I].Text, RectF(X, Bounds.Y, Min(W, Right - X), Bounds.H),
      FontSize, FSegments[I].Colour, False, 0, 1);
    X := X + W;
  end;
end;

{ TTapeMixGroupViz }

constructor TTapeMixGroupViz.Create(AHost: ITapeEditorHost; AParam: TParameter);
begin
  inherited Create(AHost);
  FParam := AParam;
end;

procedure TTapeMixGroupViz.Paint(G: TGPGraphics);
var
  Colour: Cardinal;
  Size: Single;
  Brush: TGPSolidBrush;
begin
  if not Visible then
    Exit;

  case FParam.GetIndex of
    1: Colour := $FF8B3232;
    2: Colour := $FFEAA92C;
    3: Colour := $FF9CBCBD;
    4: Colour := $FFBDB09C;
  else
    Exit;
  end;

  Size := Min(Bounds.W, Bounds.H);
  Brush := TGPSolidBrush.Create(Colour);
  try
    G.FillEllipse(Brush, Bounds.CentreX - Size * 0.5, Bounds.CentreY - Size * 0.5,
      Size, Size);
  finally
    Brush.Free;
  end;
end;

{ TTapeTooltipBar }

constructor TTapeTooltipBar.Create(AHost: ITapeEditorHost);
begin
  inherited Create(AHost);
end;

procedure TTapeTooltipBar.SetContent(const AName, AText: string);
begin
  FName := AName;
  FText := AText;
end;

procedure TTapeTooltipBar.Paint(G: TGPGraphics);
var
  R, NameRect, TextRect: TRectF;
  NameWidth, FontSize: Single;
begin
  if not Visible then
    Exit;

  { the well is drawn whether or not there is anything to say, so the space
    does not look empty between hints. The same translucent black the scope
    sits on, so it picks up the red behind it the same way. }
  FillRoundedRect(G, Bounds, PanelRadius, clScopeBack);

  if (FName = '') and (FText = '') then
    Exit;

  R := Bounds.Reduced(10.0, 2.0);
  FontSize := Min(15.0, R.H * 0.42);

  NameWidth := MeasureTextWidth(G, FName + ': ', FontSize, True);
  NameRect := RectF(R.X, R.Y, NameWidth, R.H);
  TextRect := RectF(R.X + NameWidth, R.Y, R.W - NameWidth, R.H);

  DrawTextC(G, FName + ': ', NameRect, FontSize, clAccent, True, 0, 1);
  DrawTextC(G, FText, TextRect, FontSize, clWhite, False, 0, 1);
end;

{ TTapeIconButton }

constructor TTapeIconButton.Create(AHost: ITapeEditorHost; AOnClick: TProc);
begin
  inherited Create(AHost);
  FOnClick := AOnClick;
end;

procedure TTapeIconButton.Paint(G: TGPGraphics);
var
  Size: Single;
begin
  if not Visible then
    Exit;

  { DrawableButton::ImageFitted with the five-pixel padding gui.xml gives the
    settings button; the cog itself is Font Awesome's solid one. }
  Size := Min(Bounds.W, Bounds.H) - 2.0 * FoleysPadding;
  if Size <= 0.0 then
    Size := Min(Bounds.W, Bounds.H);

  DrawCog(G, RectF(Bounds.CentreX - Size * 0.5, Bounds.CentreY - Size * 0.5,
    Size, Size), clWhite);
end;

procedure TTapeIconButton.MouseDown(X, Y: Single; RightButton: Boolean);
begin
  FHost.SetTooltip(Name, Tooltip);
  if RightButton then
    Exit;
  if Assigned(FOnClick) then
    FOnClick();
end;

{ TTapeArrowButton }

constructor TTapeArrowButton.Create(AHost: ITapeEditorHost; APointsRight: Boolean;
  AOnClick: TProc);
begin
  inherited Create(AHost);
  FPointsRight := APointsRight;
  FOnClick := AOnClick;
end;

function TTapeArrowButton.WantsMouseCapture: Boolean;
begin
  Result := True;
end;

procedure TTapeArrowButton.Paint(G: TGPGraphics);
var
  Path: TGPGraphicsPath;
  Brush: TGPSolidBrush;
  Pts: array[0..2] of TGPPointF;
  CX, CY, HalfW, HalfH: Single;
  Colour: Cardinal;
begin
  if not Visible then
    Exit;

  CX := Bounds.CentreX;
  CY := Bounds.CentreY;
  HalfW := Min(Bounds.W, Bounds.H) * 0.22;
  HalfH := Min(Bounds.W, Bounds.H) * 0.30;

  if FDown then
    Colour := clAccent
  else if Hovered then
    Colour := clWhite
  else
    Colour := $B3FFFFFF;

  if FPointsRight then
  begin
    Pts[0] := MakePoint(CX - HalfW, CY - HalfH);
    Pts[1] := MakePoint(CX + HalfW, CY);
    Pts[2] := MakePoint(CX - HalfW, CY + HalfH);
  end
  else
  begin
    Pts[0] := MakePoint(CX + HalfW, CY - HalfH);
    Pts[1] := MakePoint(CX - HalfW, CY);
    Pts[2] := MakePoint(CX + HalfW, CY + HalfH);
  end;

  Path := TGPGraphicsPath.Create;
  Brush := TGPSolidBrush.Create(Colour);
  try
    Path.AddPolygon(PGPPointF(@Pts[0]), 3);
    G.FillPath(Brush, Path);
  finally
    Brush.Free;
    Path.Free;
  end;
end;

procedure TTapeArrowButton.MouseDown(X, Y: Single; RightButton: Boolean);
begin
  FHost.SetTooltip(Name, Tooltip);
  if RightButton then
    Exit;
  FDown := True;
  FHost.RequestRepaint;
end;

procedure TTapeArrowButton.MouseUp(X, Y: Single);
begin
  if not FDown then
    Exit;
  FDown := False;
  if Bounds.Contains(X, Y) and Assigned(FOnClick) then
    FOnClick();
  FHost.RequestRepaint;
end;

{ TTapeResizeGrip }

constructor TTapeResizeGrip.Create(AHost: ITapeEditorHost; AOnBegin: TProc;
  AOnDrag: TProc<Single, Single>);
begin
  inherited Create(AHost);
  FOnBegin := AOnBegin;
  FOnDrag := AOnDrag;
end;

procedure TTapeResizeGrip.Paint(G: TGPGraphics);
var
  Pen: TGPPen;
  W, H, I, Thickness: Single;
  Colour: Cardinal;
  Pass: Integer;
begin
  if not Visible then
    Exit;

  W := Bounds.W;
  H := Bounds.H;
  if (W <= 0) or (H <= 0) then
    Exit;

  { LookAndFeel_V2 swaps between a black and a white grip depending on whether
    the mouse is over it, which leaves it invisible against the bar underneath
    for most of the time. Both are drawn here instead, one offset from the
    other, so the corner reads on any background and never disappears. }
  Thickness := Min(W, H) * 0.075;
  for Pass := 0 to 1 do
  begin
    if Pass = 0 then
      Colour := $99000000
    else
      Colour := $CCFFFFFF;

    Pen := TGPPen.Create(Colour, Thickness);
    try
      I := 0.0;
      while I < 1.0 do
      begin
        G.DrawLine(Pen,
          Bounds.X + W * I - Pass, Bounds.Y + H + 1.0 - Pass,
          Bounds.X + W + 1.0 - Pass, Bounds.Y + H * I - Pass);
        I := I + 0.3;
      end;
    finally
      Pen.Free;
    end;
  end;
end;

function TTapeResizeGrip.WantsMouseCapture: Boolean;
begin
  Result := True;
end;

procedure TTapeResizeGrip.MouseDown(X, Y: Single; RightButton: Boolean);
begin
  if RightButton then
    Exit;
  FDown := True;
  FDragX := X;
  FDragY := Y;
  if Assigned(FOnBegin) then
    FOnBegin();
end;

procedure TTapeResizeGrip.MouseDrag(X, Y: Single);
begin
  if FDown and Assigned(FOnDrag) then
    FOnDrag(X - FDragX, Y - FDragY);
end;

procedure TTapeResizeGrip.MouseUp(X, Y: Single);
begin
  FDown := False;
end;

end.
