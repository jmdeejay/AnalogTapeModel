unit ChowTape.GUI.Graphics;

{
  GDI+ drawing helpers and the plug-in's visual vocabulary.

  The original ships its knob, pointer, power switch and background as SVGs.
  They are all simple vector shapes, so they are reproduced here directly rather
  than pulling in an SVG renderer.
}

interface

uses
  Winapi.Windows, Winapi.GDIPAPI, Winapi.GDIPOBJ, System.SysUtils, System.Classes,
  System.Math, System.Generics.Collections;

const
  // palette, taken from gui.xml
  clTapeBackTop     = $FF8B3232;
  clTapeBackBottom  = $FF7D2424;
  clPanel           = $FF31323A;
  clPanelDark       = $FF1E1F22;
  clAccent          = $FFEAA92C;
  clSliderBack      = $FF595C6B;
  { gui.xml sets the filled part of a knob or a track to FF9CBCBD, a pale cyan
    that is the only cool colour in an otherwise red, amber and slate palette.
    The accent is used instead, so the value indicators belong to the same
    family as the power buttons, the scope trace and the read-outs. Put the
    original value back here to undo it. }
  clSliderTrack     = $FFEAA92C;
  clButton          = $FF33343D;
  clButtonOn        = $FFB41717;
  clTabOutline      = $FF595C6B;
  clWhite           = $FFFFFFFF;
  clBlack           = $FF000000;
  clScopeBack       = $33000000;
  clPlotFill        = $CC8B3232;
  { PresetsLNF fills the preset slot with the ComboBox background colour that
    the presets component leaves at juce::Colours::grey }
  clPresetBack      = $FF808080;

  { foleys gives every item a five-pixel margin, a five-pixel padding and a
    five-pixel corner radius unless gui.xml overrides them. Those defaults are
    what separates the four tabbed sections from each other and rounds them
    off, so they are named here rather than sprinkled through the layout. }
  { GDI+ has neither a blur nor an additive blend, so a glow is faked by
    stroking the same shape a few times over, each pass wider and fainter than
    the last, with the crisp one on top. On a bright thin shape against a dark
    panel that reads convincingly, and it costs only a handful of strokes.
    Alpha falls off as one over the square of the layer. }
  GlowLayers    = 3;
  GlowAlpha     = 0.22;

  FoleysMargin  = 5.0;
  FoleysPadding = 5.0;
  PanelRadius   = 5.0;
  clTabBarBack      = $FF838590;

  KnobFillTop       = $FFB5B5BF;
  KnobFillBottom    = $FF606068;
  KnobStrokeTop     = $80FFFFFF;
  KnobStrokeBottom  = $80383844;

type
  TRectF = record
    X, Y, W, H: Single;
    function CentreX: Single; inline;
    function CentreY: Single; inline;
    function Right: Single; inline;
    function Bottom: Single; inline;
    function Reduced(Amount: Single): TRectF; overload; inline;
    function Reduced(DX, DY: Single): TRectF; overload; inline;
    function WithHeight(NewH: Single): TRectF; inline;
    function WithY(NewY: Single): TRectF; inline;
    function Contains(PX, PY: Single): Boolean; inline;
  end;

function RectF(X, Y, W, H: Single): TRectF; inline;
{ Snaps a rectangle so that a one-pixel outline stroked on it lands on whole
  pixels instead of being smeared across two rows at half intensity. A blurred
  edge does not fall equally on the two sides of a fractional rectangle, which
  is enough to make a box look a pixel off centre around its own label. }
function SnapForStroke(const R: TRectF): TRectF;

{ Loads the Roboto Condensed faces linked into the DLL so the UI matches the
  original's typography. Falls back to a condensed system face. }
procedure InitTapeFonts;
procedure DoneTapeFonts;
function TapeFontFamily: string;
{ True when the bundled faces were registered. }
function TapeFontsLoaded: Boolean;
{ Where the faces came from, for the settings menu. }
function TapeFontSource: string;
{ The folder the plug-in would look in for loose overrides (its own folder). }
function TapeResourceDirectory: string;

procedure FillGradientRect(G: TGPGraphics; const R: TRectF; ColourA, ColourB: Cardinal;
  Diagonal: Boolean = True);
procedure FillRoundedRect(G: TGPGraphics; const R: TRectF; Radius: Single; Colour: Cardinal);
procedure FillRoundedRectGradient(G: TGPGraphics; const R: TRectF; Radius: Single;
  ColourA, ColourB: Cardinal; Diagonal: Boolean = False);
procedure StrokeRoundedRect(G: TGPGraphics; const R: TRectF; Radius, Thickness: Single;
  Colour: Cardinal);
procedure FillRectC(G: TGPGraphics; const R: TRectF; Colour: Cardinal);

procedure DrawTextC(G: TGPGraphics; const Text: string; const R: TRectF;
  FontSize: Single; Colour: Cardinal; Bold: Boolean = False;
  HAlign: Integer = 1; VAlign: Integer = 1);
function MeasureTextWidth(G: TGPGraphics; const Text: string; FontSize: Single;
  Bold: Boolean): Single;

{ juce::Graphics::drawFittedText squeezes text horizontally rather than letting
  it run past its box; GDI+ has no equivalent, so the point size comes down
  instead. Returns the largest size at which Text fits MaxWidth. }
function FitFontSize(G: TGPGraphics; const Text: string; FontSize, MaxWidth: Single;
  Bold: Boolean): Single;

{ The knob body from knob.svg: a circle with a diagonal grey gradient and a
  half-transparent gradient outline. }
procedure DrawKnobBody(G: TGPGraphics; const R: TRectF; Alpha: Single);
{ The white pointer from pointer.svg, rotated to the given normalised value. }
procedure DrawKnobPointer(G: TGPGraphics; const R: TRectF; SliderPos, Alpha: Single);
{ Background and value arcs drawn behind a rotary slider. }
procedure DrawRotaryArc(G: TGPGraphics; const R: TRectF; SliderPos, Alpha: Single;
  Colour: Cardinal);
var
  { Switched from the settings menu. The halo costs GlowLayers extra strokes
    per element and nothing else, so turning it off leaves every shape drawn
    exactly as it was before the glow existed. }
  GlowEnabled: Boolean = True;

  { TEMPORARY -- paint cost, written by the editor at the end of every repaint
    and drawn into the corner of the scope so it can be watched live. Delete
    these two along with the read-out in TTapeScopeView.Paint. }
  DebugPaintMs: Double = 0.0;        // last frame
  DebugPaintMsAvg: Double = 0.0;     // smoothed

{ A polyline with a halo around it: GlowLayers widening, fading strokes, then
  the line itself at Thickness. Spread is how much wider each layer gets. }
procedure DrawGlowPolyline(G: TGPGraphics; Points: PGPPointF; Count: Integer;
  Colour: Cardinal; Thickness, Spread: Single);

{ The power symbol from powerswitch.svg, sized so the ring and the bar fill R:
  JUCE fits a Drawable by its own bounding box, not by the SVG viewbox, so the
  glyph comes out larger than a naive 256-unit mapping would give. }
procedure DrawPowerSymbol(G: TGPGraphics; const R: TRectF; Colour: Cardinal;
  Glow: Boolean = False);
{ The solid cog from cog-solid.svg: eight teeth around a disc with a hole. }
procedure DrawCog(G: TGPGraphics; const R: TRectF; Colour: Cardinal);

function WithAlpha(Colour: Cardinal; Alpha: Single): Cardinal; inline;

{ LookAndFeel_V3's button shape: a vertical gradient running from a brightened
  to a darkened base colour, a faint white highlight along the top and a dark
  outline. gui.xml asks for LookAndFeel_V3 on the Makeup, Mid/Side and 0.1x
  buttons, and it is the gradient and the outline that make them read as
  buttons at all -- a flat FF33343D fill is invisible against the FF31323A
  panel behind it. }
procedure DrawButtonShapeV3(G: TGPGraphics; const R: TRectF; BaseColour: Cardinal;
  Enabled, Down, Highlighted: Boolean);

implementation

var
  { The faces are added to a GDI+ private collection rather than registered
    process-wide: GDI+ will not reliably see fonts added through the GDI-level
    AddFontMemResourceEx, but it always sees its own collections. }
  GFontCollection: TGPPrivateFontCollection = nil;
  GFontFamilyObj: TGPFontFamily = nil;
  GFontData: array of TBytes;      // must outlive the collection
  GFontCache: TObjectDictionary<Integer, TGPFont> = nil;
  { One string format per alignment pair, plus one for measuring. These were
    being cloned off GenericTypographic on every call: at fifty-odd labels a
    frame that is a lot of native objects created and thrown away. }
  GFormatCache: array[0 .. 2, 0 .. 2] of TGPStringFormat;
  GMeasureFormat: TGPStringFormat = nil;
  GFontFamily: string = 'Arial Narrow';
  GFontSource: string = 'not loaded';
  GFontsLoaded: Boolean = False;

{ TRectF }

function RectF(X, Y, W, H: Single): TRectF;
begin
  Result.X := X;
  Result.Y := Y;
  Result.W := W;
  Result.H := H;
end;

function SnapForStroke(const R: TRectF): TRectF;
begin
  Result.X := Round(R.X) + 0.5;
  Result.Y := Round(R.Y) + 0.5;
  Result.W := Round(R.X + R.W) - 0.5 - Result.X;
  Result.H := Round(R.Y + R.H) - 0.5 - Result.Y;
  if Result.W < 0.0 then
    Result.W := 0.0;
  if Result.H < 0.0 then
    Result.H := 0.0;
end;

function TRectF.CentreX: Single;
begin
  Result := X + W * 0.5;
end;

function TRectF.CentreY: Single;
begin
  Result := Y + H * 0.5;
end;

function TRectF.Right: Single;
begin
  Result := X + W;
end;

function TRectF.Bottom: Single;
begin
  Result := Y + H;
end;

function TRectF.Reduced(Amount: Single): TRectF;
begin
  Result := Reduced(Amount, Amount);
end;

function TRectF.Reduced(DX, DY: Single): TRectF;
begin
  Result.X := X + DX;
  Result.Y := Y + DY;
  Result.W := W - 2 * DX;
  Result.H := H - 2 * DY;
  if Result.W < 0 then Result.W := 0;
  if Result.H < 0 then Result.H := 0;
end;

function TRectF.WithHeight(NewH: Single): TRectF;
begin
  Result := Self;
  Result.H := NewH;
end;

function TRectF.WithY(NewY: Single): TRectF;
begin
  Result := Self;
  Result.Y := NewY;
end;

function TRectF.Contains(PX, PY: Single): Boolean;
begin
  Result := (PX >= X) and (PX < X + W) and (PY >= Y) and (PY < Y + H);
end;

{ Fonts }

function ModuleDirectory: string;
var
  Buf: array[0..1023] of Char;
begin
  if GetModuleFileName(HInstance, Buf, Length(Buf)) > 0 then
    Result := ExtractFilePath(Buf)
  else
    Result := ExtractFilePath(ParamStr(0));
end;

{ Adds one embedded face to the private collection, keeping its bytes alive. }
function AddEmbeddedFont(const ResName: string): Boolean;
var
  Stream: TResourceStream;
  Data: TBytes;
begin
  Result := False;
  if FindResource(HInstance, PChar(ResName), RT_RCDATA) = 0 then
    Exit;

  Stream := TResourceStream.Create(HInstance, ResName, RT_RCDATA);
  try
    SetLength(Data, Stream.Size);
    if Length(Data) = 0 then
      Exit;
    Stream.ReadBuffer(Data[0], Length(Data));
  finally
    Stream.Free;
  end;

  SetLength(GFontData, Length(GFontData) + 1);
  GFontData[High(GFontData)] := Data;

  Result := GFontCollection.AddMemoryFont(@GFontData[High(GFontData)][0],
    Length(Data)) = Ok;
end;

procedure InitTapeFonts;
var
  Loaded: Integer;
begin
  if GFontsLoaded then
    Exit;
  GFontsLoaded := True;

  GFontCache := TObjectDictionary<Integer, TGPFont>.Create([doOwnsValues]);
  GFontCollection := TGPPrivateFontCollection.Create;

  Loaded := 0;
  if AddEmbeddedFont('ROBOTO_REGULAR') then Inc(Loaded);
  if AddEmbeddedFont('ROBOTO_BOLD') then Inc(Loaded);

  if Loaded > 0 then
  begin
    GFontFamilyObj := TGPFontFamily.Create('Roboto Condensed', GFontCollection);
    if GFontFamilyObj.IsAvailable then
    begin
      GFontFamily := 'Roboto Condensed';
      GFontSource := 'embedded';
      Exit;
    end;
    FreeAndNil(GFontFamilyObj);
  end;

  // Nothing embedded (or GDI+ refused it): fall back to a condensed system face
  GFontFamilyObj := TGPFontFamily.Create('Arial Narrow');
  if not GFontFamilyObj.IsAvailable then
  begin
    FreeAndNil(GFontFamilyObj);
    GFontFamilyObj := TGPFontFamily.Create('Arial');
    GFontFamily := 'Arial';
  end
  else
    GFontFamily := 'Arial Narrow';

  GFontSource := 'FALLBACK - embedded face unavailable';
end;

procedure DoneTapeFonts;
var
  H, V: Integer;
begin
  for H := 0 to 2 do
    for V := 0 to 2 do
      FreeAndNil(GFormatCache[H, V]);
  FreeAndNil(GMeasureFormat);
  FreeAndNil(GFontCache);
  FreeAndNil(GFontFamilyObj);
  FreeAndNil(GFontCollection);
  SetLength(GFontData, 0);
  GFontsLoaded := False;
  GFontSource := 'not loaded';
end;

{ Fonts were previously built per draw call, which at 30 fps across every label
  was a lot of churn; they are cached by size and weight instead. }
function GetCachedFont(FontSize: Single; Bold: Boolean): TGPFont;
var
  Key, Style: Integer;
begin
  InitTapeFonts;

  if Bold then
    Style := FontStyleBold
  else
    Style := FontStyleRegular;

  Key := Round(FontSize * 4.0) * 2 + Ord(Bold);
  if GFontCache.TryGetValue(Key, Result) then
    Exit;

  Result := TGPFont.Create(GFontFamilyObj, FontSize, Style, UnitPixel);
  GFontCache.Add(Key, Result);
end;

function TapeFontFamily: string;
begin
  Result := GFontFamily;
end;

function TapeFontsLoaded: Boolean;
begin
  Result := GFontSource = 'embedded';
end;

function TapeFontSource: string;
begin
  Result := GFontSource;
end;

function TapeResourceDirectory: string;
begin
  Result := ModuleDirectory;
end;

{ Drawing }

function WithAlpha(Colour: Cardinal; Alpha: Single): Cardinal;
var
  A: Cardinal;
begin
  A := Round(((Colour shr 24) and $FF) * Alpha);
  Result := (Colour and $00FFFFFF) or (A shl 24);
end;

procedure FillRectC(G: TGPGraphics; const R: TRectF; Colour: Cardinal);
var
  Brush: TGPSolidBrush;
begin
  if (R.W <= 0) or (R.H <= 0) or ((Colour shr 24) = 0) then
    Exit;
  Brush := TGPSolidBrush.Create(Colour);
  try
    G.FillRectangle(Brush, R.X, R.Y, R.W, R.H);
  finally
    Brush.Free;
  end;
end;

procedure FillGradientRect(G: TGPGraphics; const R: TRectF; ColourA, ColourB: Cardinal;
  Diagonal: Boolean);
var
  Brush: TGPLinearGradientBrush;
  P1, P2: TGPPointF;
begin
  if (R.W <= 0) or (R.H <= 0) then
    Exit;

  P1.X := R.X;
  P1.Y := R.Y;
  if Diagonal then
  begin
    P2.X := R.X + R.W;
    P2.Y := R.Y + R.H;
  end
  else
  begin
    P2.X := R.X;
    P2.Y := R.Y + R.H;
  end;

  Brush := TGPLinearGradientBrush.Create(P1, P2, ColourA, ColourB);
  try
    G.FillRectangle(Brush, R.X, R.Y, R.W, R.H);
  finally
    Brush.Free;
  end;
end;

procedure BuildRoundedPath(Path: TGPGraphicsPath; const R: TRectF; Radius: Single);
var
  D: Single;
begin
  D := Radius * 2;
  if D > R.W then D := R.W;
  if D > R.H then D := R.H;
  if D <= 0 then
  begin
    Path.AddRectangle(MakeRect(R.X, R.Y, R.W, R.H));
    Exit;
  end;

  Path.StartFigure;
  Path.AddArc(R.X, R.Y, D, D, 180, 90);
  Path.AddArc(R.X + R.W - D, R.Y, D, D, 270, 90);
  Path.AddArc(R.X + R.W - D, R.Y + R.H - D, D, D, 0, 90);
  Path.AddArc(R.X, R.Y + R.H - D, D, D, 90, 90);
  Path.CloseFigure;
end;

procedure FillRoundedRect(G: TGPGraphics; const R: TRectF; Radius: Single; Colour: Cardinal);
var
  Path: TGPGraphicsPath;
  Brush: TGPSolidBrush;
begin
  if (R.W <= 0) or (R.H <= 0) or ((Colour shr 24) = 0) then
    Exit;
  Path := TGPGraphicsPath.Create;
  Brush := TGPSolidBrush.Create(Colour);
  try
    BuildRoundedPath(Path, R, Radius);
    G.FillPath(Brush, Path);
  finally
    Brush.Free;
    Path.Free;
  end;
end;

procedure StrokeRoundedRect(G: TGPGraphics; const R: TRectF; Radius, Thickness: Single;
  Colour: Cardinal);
var
  Path: TGPGraphicsPath;
  Pen: TGPPen;
begin
  if (R.W <= 0) or (R.H <= 0) then
    Exit;
  Path := TGPGraphicsPath.Create;
  Pen := TGPPen.Create(Colour, Thickness);
  try
    BuildRoundedPath(Path, R, Radius);
    G.DrawPath(Pen, Path);
  finally
    Pen.Free;
    Path.Free;
  end;
end;

{ Just as much of juce::Colour as LookAndFeel_V3 needs. The channel arithmetic
  truncates rather than rounds, as JUCE's uint8 casts do. }

function Clamp8(V: Single): Cardinal;
begin
  if V <= 0.0 then
    Result := 0
  else if V >= 255.0 then
    Result := 255
  else
    Result := Cardinal(Trunc(V));
end;

function MaxChannel(Colour: Cardinal): Integer;
var
  C: Integer;
begin
  Result := Integer((Colour shr 16) and $FF);
  C := Integer((Colour shr 8) and $FF);
  if C > Result then
    Result := C;
  C := Integer(Colour and $FF);
  if C > Result then
    Result := C;
end;

{ Colour::withMultipliedSaturation. Scaling every channel's distance from the
  largest one leaves the HSV hue and brightness untouched, which is what the
  round trip through HSB does. }
function ColourWithMultipliedSaturation(Colour: Cardinal; K: Single): Cardinal;
var
  M: Integer;
begin
  M := MaxChannel(Colour);
  Result := (Colour and $FF000000) or
    (Clamp8(M - K * (M - Integer((Colour shr 16) and $FF))) shl 16) or
    (Clamp8(M - K * (M - Integer((Colour shr 8) and $FF))) shl 8) or
    Clamp8(M - K * (M - Integer(Colour and $FF)));
end;

function ColourBrighter(Colour: Cardinal; Amount: Single): Cardinal;
var
  F: Single;
begin
  F := 1.0 / (1.0 + Amount);
  Result := (Colour and $FF000000) or
    (Clamp8(255.0 - F * (255 - Integer((Colour shr 16) and $FF))) shl 16) or
    (Clamp8(255.0 - F * (255 - Integer((Colour shr 8) and $FF))) shl 8) or
    Clamp8(255.0 - F * (255 - Integer(Colour and $FF)));
end;

function ColourDarker(Colour: Cardinal; Amount: Single): Cardinal;
var
  F: Single;
begin
  F := 1.0 / (1.0 + Amount);
  Result := (Colour and $FF000000) or
    (Clamp8(F * ((Colour shr 16) and $FF)) shl 16) or
    (Clamp8(F * ((Colour shr 8) and $FF)) shl 8) or
    Clamp8(F * (Colour and $FF));
end;

{ Colour::contrasting: overlay black or white at the given alpha, whichever
  stands out against the colour's perceived brightness. }
function ColourContrasting(Colour: Cardinal; Amount: Single): Cardinal;
var
  Rd, Gr, Bl, Over: Single;
begin
  Rd := ((Colour shr 16) and $FF) / 255.0;
  Gr := ((Colour shr 8) and $FF) / 255.0;
  Bl := (Colour and $FF) / 255.0;
  if Sqrt(0.241 * Rd * Rd + 0.691 * Gr * Gr + 0.068 * Bl * Bl) >= 0.5 then
    Over := 0.0
  else
    Over := 255.0;
  Result := (Colour and $FF000000) or
    (Clamp8(Over * Amount + ((Colour shr 16) and $FF) * (1.0 - Amount)) shl 16) or
    (Clamp8(Over * Amount + ((Colour shr 8) and $FF) * (1.0 - Amount)) shl 8) or
    Clamp8(Over * Amount + (Colour and $FF) * (1.0 - Amount));
end;

procedure FillRoundedRectGradient(G: TGPGraphics; const R: TRectF; Radius: Single;
  ColourA, ColourB: Cardinal; Diagonal: Boolean);
var
  Path: TGPGraphicsPath;
  Brush: TGPLinearGradientBrush;
  P1, P2: TGPPointF;
begin
  if (R.W <= 0) or (R.H <= 0) then
    Exit;

  { the endpoints sit half a pixel outside the shape: GDI+ tiles a gradient
    beyond its own extent, which otherwise shows on the first and last row }
  P1.X := R.X;
  P1.Y := R.Y - 0.5;
  if Diagonal then
    P2.X := R.X + R.W + 0.5
  else
    P2.X := R.X;
  P2.Y := R.Y + R.H + 0.5;

  Path := TGPGraphicsPath.Create;
  Brush := TGPLinearGradientBrush.Create(P1, P2, ColourA, ColourB);
  try
    BuildRoundedPath(Path, R, Radius);
    G.FillPath(Brush, Path);
  finally
    Brush.Free;
    Path.Free;
  end;
end;

procedure DrawButtonShapeV3(G: TGPGraphics; const R: TRectF; BaseColour: Cardinal;
  Enabled, Down, Highlighted: Boolean);
const
  CornerSize = 4.0;
var
  Base: Cardinal;
  Shape, Highlight: TRectF;
  MainAlpha, Bright, Squash: Single;
begin
  if (R.W <= 1.0) or (R.H <= 1.6) then
    Exit;

  Base := ColourWithMultipliedSaturation(BaseColour, 0.9);
  if Enabled then
    Base := WithAlpha(Base, 0.9)
  else
    Base := WithAlpha(Base, 0.5);

  if Down then
    Base := ColourContrasting(Base, 0.2)
  else if Highlighted then
    Base := ColourContrasting(Base, 0.1);

  { the outline is stroked on the path itself, so it costs a pixel of width
    and height and starts half a pixel in }
  Shape := RectF(R.X + 0.5, R.Y + 0.5, R.W - 1.0, R.H - 1.0);

  FillRoundedRectGradient(G, Shape, CornerSize,
    ColourBrighter(Base, 0.2), ColourDarker(Base, 0.25));

  MainAlpha := ((Base shr 24) and $FF) / 255.0;
  Bright := MaxChannel(Base) / 255.0;
  Squash := (Shape.H - 1.6) / Shape.H;
  Highlight := RectF(Shape.X, Shape.Y + 1.0, Shape.W, Shape.H * Squash);
  StrokeRoundedRect(G, Highlight, CornerSize, 1.0,
    WithAlpha(clWhite, 0.4 * MainAlpha * Bright * Bright));

  StrokeRoundedRect(G, Shape, CornerSize, 1.0, WithAlpha(clBlack, 0.4 * MainAlpha));
end;

{ The default string format reserves about a sixth of an em on each side of a
  line, which scales with the point size: a 35px title and a 16px subtitle set
  flush left against the same edge end up three pixels apart. The typographic
  format has no such bearings, so text starts exactly where it is put. }
function MakeTextFormat: TGPStringFormat;
begin
  Result := TGPStringFormat.Create(TGPStringFormat.GenericTypographic);
  Result.SetFormatFlags(Result.GetFormatFlags or StringFormatFlagsNoWrap);
end;

function CachedTextFormat(HAlign, VAlign: Integer): TGPStringFormat;
const
  Alignments: array[0 .. 2] of TStringAlignment =
    (StringAlignmentNear, StringAlignmentCenter, StringAlignmentFar);
begin
  if (HAlign < 0) or (HAlign > 2) then HAlign := 1;
  if (VAlign < 0) or (VAlign > 2) then VAlign := 1;

  Result := GFormatCache[HAlign, VAlign];
  if Result <> nil then
    Exit;

  Result := MakeTextFormat;
  Result.SetAlignment(Alignments[HAlign]);
  Result.SetLineAlignment(Alignments[VAlign]);
  Result.SetTrimming(StringTrimmingEllipsisCharacter);
  GFormatCache[HAlign, VAlign] := Result;
end;

function CachedMeasureFormat: TGPStringFormat;
begin
  if GMeasureFormat = nil then
  begin
    GMeasureFormat := MakeTextFormat;
    GMeasureFormat.SetFormatFlags(GMeasureFormat.GetFormatFlags or
      StringFormatFlagsMeasureTrailingSpaces);
  end;
  Result := GMeasureFormat;
end;

procedure DrawTextC(G: TGPGraphics; const Text: string; const R: TRectF;
  FontSize: Single; Colour: Cardinal; Bold: Boolean; HAlign, VAlign: Integer);
var
  Font: TGPFont;
  Brush: TGPSolidBrush;
  Fmt: TGPStringFormat;
begin
  if (Text = '') or (FontSize <= 0.5) then
    Exit;

  { the alignment arguments are 0 near, 1 centred, 2 far, which is the order
    the cache is keyed in }
  Font := GetCachedFont(FontSize, Bold);
  Fmt := CachedTextFormat(HAlign, VAlign);
  Brush := TGPSolidBrush.Create(Colour);
  try
    G.DrawString(Text, -1, Font, MakeRect(R.X, R.Y, R.W, R.H), Fmt, Brush);
  finally
    Brush.Free;   // the font and the format are owned by their caches
  end;
end;

function MeasureTextWidth(G: TGPGraphics; const Text: string; FontSize: Single;
  Bold: Boolean): Single;
var
  Font: TGPFont;
  Fmt: TGPStringFormat;
  Bounds: TGPRectF;
begin
  Font := GetCachedFont(FontSize, Bold);
  Fmt := CachedMeasureFormat;
  // The literals must be floats: MakeRect's integer overload returns a
  // TGPRect, and no MeasureString overload takes one.
  G.MeasureString(Text, -1, Font, MakeRect(0.0, 0.0, 10000.0, 1000.0), Fmt, Bounds);
  Result := Bounds.Width;
end;

function FitFontSize(G: TGPGraphics; const Text: string; FontSize, MaxWidth: Single;
  Bold: Boolean): Single;
var
  W: Single;
  Pass: Integer;
begin
  Result := FontSize;
  if (Text = '') or (MaxWidth <= 0) then
    Exit;

  { two passes: the first scales by the measured overshoot, the second mops up
    the error it leaves behind, since glyph advances are not quite linear in
    the point size }
  for Pass := 0 to 1 do
  begin
    W := MeasureTextWidth(G, Text, Result, Bold);
    if W <= MaxWidth then
      Break;
    Result := Result * MaxWidth / W;
  end;

  if Result < 6.0 then
    Result := 6.0;
end;

procedure DrawKnobBody(G: TGPGraphics; const R: TRectF; Alpha: Single);
var
  Brush: TGPLinearGradientBrush;
  Pen: TGPPen;
  P1, P2: TGPPointF;
  Scale, CX, CY, Radius, StrokeW: Single;
  Bounds: TRectF;
begin
  // knob.svg: r = 27.248 centred at (40.2539, 40.7441) inside an 81x81 box
  Scale := Min(R.W, R.H) / 81.0;
  CX := R.X + R.W * 0.5;
  CY := R.Y + R.H * 0.5;
  Radius := 27.248 * Scale;
  StrokeW := Max(1.0, 1.75794 * Scale);

  Bounds := RectF(CX - Radius, CY - Radius, Radius * 2, Radius * 2);

  // the SVG gradient runs from (13.0059, 13.4961) to (67.502, 67.9921)
  P1.X := R.X + 13.0059 * Scale;
  P1.Y := R.Y + 13.4961 * Scale;
  P2.X := R.X + 67.502 * Scale;
  P2.Y := R.Y + 67.9921 * Scale;

  Brush := TGPLinearGradientBrush.Create(P1, P2,
    WithAlpha(KnobFillTop, Alpha), WithAlpha(KnobFillBottom, Alpha));
  try
    G.FillEllipse(Brush, Bounds.X, Bounds.Y, Bounds.W, Bounds.H);
  finally
    Brush.Free;
  end;

  Brush := TGPLinearGradientBrush.Create(P1, P2,
    WithAlpha(KnobStrokeTop, Alpha), WithAlpha(KnobStrokeBottom, Alpha));
  Pen := TGPPen.Create(Brush, StrokeW);
  try
    G.DrawEllipse(Pen, Bounds.X, Bounds.Y, Bounds.W, Bounds.H);
  finally
    Pen.Free;
    Brush.Free;
  end;
end;

procedure DrawKnobPointer(G: TGPGraphics; const R: TRectF; SliderPos, Alpha: Single);
var
  Path: TGPGraphicsPath;
  Brush: TGPSolidBrush;
  State: GraphicsState;
  Scale, CX, CY, HalfW, TopY, BottomY, Radius: Single;
begin
  // pointer.svg: a rounded bar from y=12.964 to y=43.0672, x 38.496..42.0119,
  // pivoting about the knob centre (40.2539, 40.7441)
  Scale := Min(R.W, R.H) / 81.0;
  CX := R.X + R.W * 0.5;
  CY := R.Y + R.H * 0.5;

  HalfW := (42.0119 - 38.496) * 0.5 * Scale;
  TopY := CY - (40.7441 - 12.964) * Scale;
  BottomY := CY + (43.0672 - 40.7441) * Scale;
  Radius := HalfW;

  Path := TGPGraphicsPath.Create;
  Brush := TGPSolidBrush.Create(WithAlpha(clWhite, Alpha));
  try
    Path.StartFigure;
    Path.AddLine(CX - HalfW, TopY, CX + HalfW, TopY);
    Path.AddLine(CX + HalfW, TopY, CX + HalfW, BottomY - Radius);
    Path.AddArc(CX - Radius, BottomY - 2 * Radius, 2 * Radius, 2 * Radius, 0, 180);
    Path.CloseFigure;

    State := G.Save;
    try
      G.TranslateTransform(CX, CY);
      G.RotateTransform((SliderPos - 0.5) * 300.0);
      G.TranslateTransform(-CX, -CY);
      G.FillPath(Brush, Path);
    finally
      G.Restore(State);
    end;
  finally
    Brush.Free;
    Path.Free;
  end;
end;

procedure DrawRotaryArc(G: TGPGraphics; const R: TRectF; SliderPos, Alpha: Single;
  Colour: Cardinal);
const
  ArcFactor = 0.9;
var
  Path: TGPGraphicsPath;
  Brush: TGPSolidBrush;
  Pen: TGPPen;
  Diameter, InnerDiameter, CX, CY: Single;
  StartDeg, SweepDeg, ToDeg: Single;
  GlowR, BandWidth: Single;
  Outer, Inner: TRectF;
  I: Integer;

  procedure AddPieSegment(P: TGPGraphicsPath; AStartDeg, ASweepDeg: Single);
  begin
    if Abs(ASweepDeg) < 0.01 then
      Exit;
    P.StartFigure;
    P.AddArc(Outer.X, Outer.Y, Outer.W, Outer.H, AStartDeg, ASweepDeg);
    P.AddArc(Inner.X, Inner.Y, Inner.W, Inner.H, AStartDeg + ASweepDeg, -ASweepDeg);
    P.CloseFigure;
  end;

begin
  Diameter := Min(R.W, R.H);
  if Diameter < 16 then
    Exit;

  CX := R.X + R.W * 0.5;
  CY := R.Y + R.H * 0.5;
  InnerDiameter := Diameter * ArcFactor;

  Outer := RectF(CX - Diameter * 0.5, CY - Diameter * 0.5, Diameter, Diameter);
  Inner := RectF(CX - InnerDiameter * 0.5, CY - InnerDiameter * 0.5,
    InnerDiameter, InnerDiameter);

  // GDI+ measures angles clockwise from 3 o'clock; the slider runs from
  // -150 to +150 degrees measured from 12 o'clock.
  StartDeg := -90.0 - 150.0;
  SweepDeg := 300.0;
  ToDeg := SweepDeg * SliderPos;

  Path := TGPGraphicsPath.Create;
  Brush := TGPSolidBrush.Create(WithAlpha(clSliderBack, Alpha));
  try
    AddPieSegment(Path, StartDeg, SweepDeg);
    G.FillPath(Brush, Path);
  finally
    Brush.Free;
    Path.Free;
  end;

  { The halo, stroked along the middle of the band the wedge will occupy so it
    blooms evenly to either side of it.

    The innermost layer is skipped here, unlike everywhere else. It is narrow
    and strong, which on a ten-pixel track widens the bar by a quarter and
    reads as a halo -- but the arc band is under four pixels, so the same layer
    widens it by two thirds and reads as a fatter, blurrier arc instead. The
    arc keeps the wide faint layers only, so the band itself stays crisp. }
  if GlowEnabled and (Abs(ToDeg) >= 0.01) then
  begin
    GlowR := Diameter * 0.475;
    BandWidth := Diameter * (1.0 - ArcFactor);
    for I := GlowLayers + 1 downto 2 do
    begin
      Pen := TGPPen.Create(WithAlpha(Colour, Alpha * GlowAlpha / (I * I)),
        BandWidth + 2.5 * I);
      try
        Pen.SetStartCap(LineCapRound);
        Pen.SetEndCap(LineCapRound);
        G.DrawArc(Pen, CX - GlowR, CY - GlowR, GlowR * 2, GlowR * 2,
          StartDeg, ToDeg);
      finally
        Pen.Free;
      end;
    end;
  end;

  Path := TGPGraphicsPath.Create;
  Brush := TGPSolidBrush.Create(WithAlpha(Colour, Alpha));
  try
    AddPieSegment(Path, StartDeg, ToDeg);
    G.FillPath(Brush, Path);
  finally
    Brush.Free;
    Path.Free;
  end;
end;

procedure DrawGlowPolyline(G: TGPGraphics; Points: PGPPointF; Count: Integer;
  Colour: Cardinal; Thickness, Spread: Single);
var
  Pen: TGPPen;
  I: Integer;
begin
  if Count < 2 then
    Exit;

  if GlowEnabled then
    for I := GlowLayers downto 1 do
    begin
      Pen := TGPPen.Create(WithAlpha(Colour, GlowAlpha / (I * I)),
        Thickness + Spread * I);
      try
        Pen.SetStartCap(LineCapRound);
        Pen.SetEndCap(LineCapRound);
        Pen.SetLineJoin(LineJoinRound);
        G.DrawLines(Pen, Points, Count);
      finally
        Pen.Free;
      end;
    end;

  Pen := TGPPen.Create(Colour, Thickness);
  try
    Pen.SetStartCap(LineCapRound);
    Pen.SetEndCap(LineCapRound);
    Pen.SetLineJoin(LineJoinRound);
    G.DrawLines(Pen, Points, Count);
  finally
    Pen.Free;
  end;
end;

procedure DrawPowerSymbol(G: TGPGraphics; const R: TRectF; Colour: Cardinal;
  Glow: Boolean);
var
  Pen: TGPPen;
  Brush: TGPSolidBrush;
  Path: TGPGraphicsPath;
  S, CX, CY, ArcR, Thickness, BarHalf: Single;
  I: Integer;
begin
  S := Min(R.W, R.H);
  if S < 4 then
    Exit;

  CX := R.X + R.W * 0.5;
  CY := R.Y + R.H * 0.5;

  { powerswitch.svg draws on a 256 viewbox but only spans 184 of it, and JUCE
    stretches the drawable's own bounds over the button, so those 184 units are
    what maps to S: the ring's outer edge lands on R and the bar runs from the
    top of R down to the centre. }
  Thickness := S * (21.0 / 184.0);   // heavier than the svg, to read at 20-odd pixels
  if Thickness < 1.5 then
    Thickness := 1.5;
  ArcR := (S - Thickness) * 0.5;
  BarHalf := S * (9.75 / 184.0);

  if Glow and GlowEnabled then
  begin
    { the ring and the bar as one path, so the halo is continuous across the
      gap at the top rather than two separate blooms }
    Path := TGPGraphicsPath.Create;
    try
      Path.AddArc(CX - ArcR, CY - ArcR, ArcR * 2, ArcR * 2, -61.3, 302.6);
      Path.StartFigure;
      Path.AddLine(CX, CY - S * 0.5, CX, CY);
      for I := GlowLayers downto 1 do
      begin
        Pen := TGPPen.Create(WithAlpha(Colour, GlowAlpha / (I * I)),
          Thickness + 2.0 * I);
        try
          Pen.SetStartCap(LineCapRound);
          Pen.SetEndCap(LineCapRound);
          Pen.SetLineJoin(LineJoinRound);
          G.DrawPath(Pen, Path);
        finally
          Pen.Free;
        end;
      end;
    finally
      Path.Free;
    end;
  end;

  Pen := TGPPen.Create(Colour, Thickness);
  Brush := TGPSolidBrush.Create(Colour);
  try
    Pen.SetStartCap(LineCapRound);
    Pen.SetEndCap(LineCapRound);
    { the bar passes through the 57 degrees the svg leaves open at the top }
    G.DrawArc(Pen, CX - ArcR, CY - ArcR, ArcR * 2, ArcR * 2, -61.3, 302.6);
    G.FillRectangle(Brush, CX - BarHalf, CY - S * 0.5, BarHalf * 2, S * 0.5);
  finally
    Brush.Free;
    Pen.Free;
  end;
end;

procedure DrawCog(G: TGPGraphics; const R: TRectF; Colour: Cardinal);
const
  Teeth = 8;
  Steps = Teeth * 24;      // a multiple of Teeth, so the shape stays symmetric
var
  Path: TGPGraphicsPath;
  Brush: TGPSolidBrush;
  Pts: array[0 .. Steps - 1] of TGPPointF;
  S, CX, CY, TipR, RootR, HoleR, Angle, T, Rad: Single;
  I: Integer;
begin
  S := Min(R.W, R.H);
  if S < 6 then
    Exit;

  CX := R.X + R.W * 0.5;
  CY := R.Y + R.H * 0.5;
  TipR := S * 0.5;
  RootR := S * 0.37;
  HoleR := S * 0.165;

  for I := 0 to Steps - 1 do
  begin
    Angle := 2.0 * Pi * I / Steps;
    { one radius that swings between the root and the tip once per tooth. The
      cosine is squared off so the flanks come out steep and the tips flat,
      which is what the Font Awesome cog the original uses looks like. }
    T := (Cos(Teeth * Angle) + 1.0) * 0.5;
    T := (T - 0.30) / 0.40;
    if T < 0.0 then
      T := 0.0
    else if T > 1.0 then
      T := 1.0;
    T := T * T * (3.0 - 2.0 * T);
    Rad := RootR + (TipR - RootR) * T;
    Pts[I].X := CX + Cos(Angle) * Rad;
    Pts[I].Y := CY + Sin(Angle) * Rad;
  end;

  Path := TGPGraphicsPath.Create(FillModeAlternate);
  Brush := TGPSolidBrush.Create(Colour);
  try
    Path.AddPolygon(PGPPointF(@Pts[0]), Steps);
    Path.AddEllipse(CX - HoleR, CY - HoleR, HoleR * 2, HoleR * 2);
    G.FillPath(Brush, Path);
  finally
    Brush.Free;
    Path.Free;
  end;
end;

end.
