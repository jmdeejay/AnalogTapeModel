unit ChowTape.GUI.Menu;

{
  Owner-drawn popup menus, so every menu in the plug-in -- the sync menus, the
  oversampling and hysteresis lists, the mix group, the presets and the
  settings -- looks like the rest of the editor rather than like the host's
  system menus.

  ComboBoxLNF in the original sets PopupMenu::backgroundColourId to FF31323A
  and highlightedBackgroundColourId to a half-transparent EAA92C, which is what
  is reproduced here. A ticked item gets the same lit dot the settings menu
  uses for the glow switch, in place of a check mark.

  Win32 sends WM_MEASUREITEM and WM_DRAWITEM to the window passed to
  TrackPopupMenu, so the editor forwards those two messages to the class
  methods below. The item data is a pointer to the item object, which is why
  they can be handled without knowing which menu the item came from.
}

interface

uses
  Winapi.Windows, Winapi.GDIPAPI, Winapi.GDIPOBJ,
  System.Generics.Collections, ChowTape.GUI.Graphics;

type
  TTapeMenu = class;

  TTapeMenuItem = class
  public
    Text: string;
    Id: Integer;
    Separator: Boolean;
    Checked: Boolean;
    Enabled: Boolean;
    HasSubMenu: Boolean;
  end;

  TTapeMenu = class
  private
    FHandle: HMENU;
    FItems: TObjectList<TTapeMenuItem>;
    FChildren: TObjectList<TTapeMenu>;
    FBackBrush: HBRUSH;
    FOwnsHandle: Boolean;
    procedure Insert(Item: TTapeMenuItem; SubMenu: HMENU);
  public
    constructor Create;
    destructor Destroy; override;

    procedure AddItem(const AText: string; AId: Integer;
      AChecked: Boolean = False; AEnabled: Boolean = True);
    procedure AddSeparator;
    { The child is owned by this menu and lives until it is freed. }
    function AddSubMenu(const AText: string): TTapeMenu;
    { Copies this menu's items into another. The preset categories have to be
      filled before their captions are known, so they are gathered in a loose
      menu and handed over once the real submenu exists. }
    procedure MoveItemsTo(Target: TTapeMenu);

    { Returns the chosen command id, or 0. }
    function Popup(AOwner: HWND; X, Y: Integer): Integer;

    { Forwarded from the owning window's WndProc; both return True when the
      message was for one of our items. }
    class function MeasureItem(LP: LPARAM): Boolean;
    class function DrawItem(LP: LPARAM): Boolean;

    property Handle: HMENU read FHandle;
  end;

{ True while a popup's modal loop is running on this thread. TrackPopupMenu
  pumps messages from inside whatever window procedure opened it, so the host
  can call back into the plug-in -- effEditClose included -- while that frame
  is still live. Anything that would pull the ground out from under it has to
  check this first. }
function MenuIsModal: Boolean;
{ Asks any open popup to close, so the modal loop unwinds. }
procedure DismissMenus;


implementation

var
  GModalDepth: Integer = 0;

function MenuIsModal: Boolean;
begin
  Result := GModalDepth > 0;
end;

procedure DismissMenus;
begin
  if GModalDepth > 0 then
    EndMenu;
end;

const
  { the two colours ComboBoxLNF sets on the popup, and the metrics that go
    with the editor's own type sizes }
  MenuBackColour   = clPanel;
  MenuHighlight    = $7FEAA92C;
  MenuTextColour   = clWhite;
  MenuFontSize     = 14.0;
  MenuItemHeight   = 24;
  MenuSepHeight    = 7;
  MenuGutterWidth  = 26;
  MenuRightPad     = 28;

{ TTapeMenu }

constructor TTapeMenu.Create;
var
  Info: TMenuInfo;
begin
  inherited Create;
  FItems := TObjectList<TTapeMenuItem>.Create(True);
  FChildren := TObjectList<TTapeMenu>.Create(True);
  FHandle := CreatePopupMenu;
  FOwnsHandle := True;

  { owner drawing only covers the item rectangles; the strip around them is
    the menu window's own background, which is what this brush replaces }
  FBackBrush := CreateSolidBrush(RGB((MenuBackColour shr 16) and $FF,
    (MenuBackColour shr 8) and $FF, MenuBackColour and $FF));

  FillChar(Info, SizeOf(Info), 0);
  Info.cbSize := SizeOf(Info);
  Info.fMask := MIM_BACKGROUND or MIM_APPLYTOSUBMENUS;
  Info.hbrBack := FBackBrush;
  SetMenuInfo(FHandle, Info);
end;

destructor TTapeMenu.Destroy;
begin
  { DestroyMenu on the root frees the attached submenu handles as well, so
    only an unattached menu destroys its own }
  if FOwnsHandle and (FHandle <> 0) then
    DestroyMenu(FHandle);
  FChildren.Free;
  FItems.Free;
  if FBackBrush <> 0 then
    DeleteObject(FBackBrush);
  inherited;
end;

procedure TTapeMenu.Insert(Item: TTapeMenuItem; SubMenu: HMENU);
var
  MII: TMenuItemInfo;
begin
  FillChar(MII, SizeOf(MII), 0);
  MII.cbSize := SizeOf(MII);
  MII.fMask := MIIM_FTYPE or MIIM_ID or MIIM_DATA or MIIM_STATE;
  MII.fType := MFT_OWNERDRAW;
  MII.wID := Item.Id;
  MII.dwItemData := ULONG_PTR(NativeUInt(Item));

  if Item.Enabled then
    MII.fState := MFS_ENABLED
  else
    MII.fState := MFS_GRAYED;

  if SubMenu <> 0 then
  begin
    MII.fMask := MII.fMask or MIIM_SUBMENU;
    MII.hSubMenu := SubMenu;
  end;

  InsertMenuItem(FHandle, Cardinal(-1), True, MII);
end;

procedure TTapeMenu.AddItem(const AText: string; AId: Integer;
  AChecked, AEnabled: Boolean);
var
  Item: TTapeMenuItem;
begin
  Item := TTapeMenuItem.Create;
  Item.Text := AText;
  Item.Id := AId;
  Item.Checked := AChecked;
  Item.Enabled := AEnabled;
  FItems.Add(Item);
  Insert(Item, 0);
end;

procedure TTapeMenu.AddSeparator;
var
  Item: TTapeMenuItem;
begin
  { nothing to separate yet, and two in a row would leave a gap }
  if (FItems.Count = 0) or FItems[FItems.Count - 1].Separator then
    Exit;

  Item := TTapeMenuItem.Create;
  Item.Separator := True;
  Item.Enabled := False;
  FItems.Add(Item);
  Insert(Item, 0);
end;

function TTapeMenu.AddSubMenu(const AText: string): TTapeMenu;
var
  Item: TTapeMenuItem;
begin
  Result := TTapeMenu.Create;
  FChildren.Add(Result);

  Item := TTapeMenuItem.Create;
  Item.Text := AText;
  Item.Enabled := True;
  Item.HasSubMenu := True;
  FItems.Add(Item);
  Insert(Item, Result.Handle);
  Result.FOwnsHandle := False;
end;

procedure TTapeMenu.MoveItemsTo(Target: TTapeMenu);
var
  I: Integer;
begin
  for I := 0 to FItems.Count - 1 do
    if FItems[I].Separator then
      Target.AddSeparator
    else
      Target.AddItem(FItems[I].Text, FItems[I].Id, FItems[I].Checked,
        FItems[I].Enabled);
end;

function TTapeMenu.Popup(AOwner: HWND; X, Y: Integer): Integer;
begin
  Inc(GModalDepth);
  try
    Result := Integer(TrackPopupMenu(FHandle, TPM_LEFTALIGN or TPM_TOPALIGN or
      TPM_RETURNCMD or TPM_NONOTIFY, X, Y, 0, AOwner, nil));
  finally
    Dec(GModalDepth);
  end;
end;

class function TTapeMenu.MeasureItem(LP: LPARAM): Boolean;
var
  MIS: PMeasureItemStruct;
  Item: TTapeMenuItem;
  DC: HDC;
  G: TGPGraphics;
begin
  MIS := PMeasureItemStruct(LP);
  Result := (MIS <> nil) and (MIS.CtlType = ODT_MENU) and (MIS.itemData <> 0);
  if not Result then
    Exit;

  Item := TTapeMenuItem(MIS.itemData);

  if Item.Separator then
  begin
    MIS.itemWidth := MenuGutterWidth;
    MIS.itemHeight := MenuSepHeight;
    Exit;
  end;

  DC := GetDC(0);
  try
    G := TGPGraphics.Create(DC);
    try
      MIS.itemWidth := MenuGutterWidth + MenuRightPad +
        Round(MeasureTextWidth(G, Item.Text, MenuFontSize, False));
    finally
      G.Free;
    end;
  finally
    ReleaseDC(0, DC);
  end;
  MIS.itemHeight := MenuItemHeight;
end;

class function TTapeMenu.DrawItem(LP: LPARAM): Boolean;
var
  DIS: PDrawItemStruct;
  Item: TTapeMenuItem;
  G: TGPGraphics;
  R, Dot, TextRect: TRectF;
  Y: Single;
  Colour: Cardinal;
begin
  DIS := PDrawItemStruct(LP);
  Result := (DIS <> nil) and (DIS.CtlType = ODT_MENU) and (DIS.itemData <> 0);
  if not Result then
    Exit;

  Item := TTapeMenuItem(DIS.itemData);
  R := RectF(DIS.rcItem.Left, DIS.rcItem.Top,
    DIS.rcItem.Right - DIS.rcItem.Left, DIS.rcItem.Bottom - DIS.rcItem.Top);

  G := TGPGraphics.Create(DIS.hDC);
  try
    G.SetSmoothingMode(SmoothingModeAntiAlias);
    G.SetTextRenderingHint(TextRenderingHintAntiAliasGridFit);
    G.SetPixelOffsetMode(PixelOffsetModeHalf);

    FillRectC(G, R, MenuBackColour);

    if Item.Separator then
    begin
      Y := R.Y + R.H * 0.5;
      FillRectC(G, RectF(R.X + 8, Y, R.W - 16, 1.0), clSliderBack);
      Exit;
    end;

    if (DIS.itemState and ODS_SELECTED) <> 0 then
      FillRectC(G, R, MenuHighlight);

    if Item.Checked then
    begin
      Dot := RectF(R.X + 4, R.CentreY - 8, 16, 16);
      DrawGlowDot(G, Dot, True);
    end;

    if Item.Enabled then
      Colour := MenuTextColour
    else
      Colour := WithAlpha(MenuTextColour, 0.45);

    TextRect := RectF(R.X + MenuGutterWidth, R.Y,
      R.W - MenuGutterWidth - 6, R.H);
    DrawTextC(G, Item.Text, TextRect, MenuFontSize, Colour, False, 0, 1);

    { The submenu arrow is left to Windows. It draws its own over the right of
      the item after WM_DRAWITEM returns, in COLOR_MENUTEXT, and no flag
      suppresses it -- so drawing one here only ever puts ours underneath
      theirs. Subclassing the popup window and repainting afterwards was tried
      and is worse: the repaint lands after the menu has already presented its
      own arrow, so it flickers black on every hover. }
  finally
    G.Free;
  end;
end;

end.
