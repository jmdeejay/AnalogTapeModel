unit ChowTape.PresetLibrary;

{
  Preset library: the compiled-in factory presets plus whatever the user has
  saved, merged into one list for the editor's menu.

  User presets are .chowpreset XML, the same format the original plug-in uses,
  so libraries move between the two in both directions. The reader also applies
  the same legacy fix-ups as tools\gen_presets.py, which means files written by
  older versions (spacing/thickness/gap in metres, dry/wet as a percentage,
  the pre-2.11 "os" parameter) load correctly.

  XML is parsed by hand rather than through Xml.XMLDoc: the schema is four
  elements deep and the MSXML backend would drag COM initialisation into a
  plug-in DLL for no benefit.
}

interface

uses
  System.SysUtils, System.StrUtils, System.Classes, System.IOUtils, System.Math,
  System.Generics.Collections,
  ChowTape.Params, ChowTape.Presets;

type
  TPresetEntry = record
    Name: string;
    Vendor: string;
    Category: string;
    IsFactory: Boolean;
    FactoryIndex: Integer;   // -1 for user presets
    FilePath: string;        // '' for factory presets
  end;

  TPresetLibrary = class
  private
    FParams: TParameterSet;
    FEntries: TList<TPresetEntry>;
    FUserFolder: string;
    FCurrentIndex: Integer;
    FSnapshot: array of Single;

    function ConfigFilePath: string;
    function DefaultUserFolder: string;
    procedure LoadConfig;
    procedure SaveConfig;
    procedure ScanUserFolder;
    procedure SetUserFolder(const Value: string);
    function GetEntry(Index: Integer): TPresetEntry;
    function GetCount: Integer;
  public
    constructor Create(AParams: TParameterSet);
    destructor Destroy; override;

    { Rebuilds the list from the factory table plus the user folder. }
    procedure Refresh;

    { Applies an entry to the parameter set. Returns False if the file has
      gone missing since the last scan. }
    function LoadPreset(Index: Integer): Boolean;
    function LoadPresetFile(const FileName: string): Boolean;

    { Writes the current parameter values as .chowpreset XML. }
    function SavePresetFile(const FileName, PresetName: string): Boolean;
    function DeletePreset(Index: Integer): Boolean;

    procedure SelectNext;
    procedure SelectPrevious;
    procedure SelectByName(const AName: string);

    { The name to show, with a trailing '*' once a control has been moved. }
    function DisplayName: string;
    { The name on its own, for saving in the plug-in state. }
    function CurrentName: string;
    function IsDirty: Boolean;
    { Remembers the current parameter values as the clean state. }
    procedure MarkClean;
    { Forces the modified marker on, used when restoring a session that was
      saved with unsaved changes. }
    procedure MarkDirty;

    function CurrentIsUserPreset: Boolean;
    function CurrentFilePath: string;

    property UserFolder: string read FUserFolder write SetUserFolder;
    property CurrentIndex: Integer read FCurrentIndex;
    property Count: Integer read GetCount;
    property Entries[Index: Integer]: TPresetEntry read GetEntry; default;
  end;

const
  PresetFileExtension = '.chowpreset';

implementation

const
  PluginTag = 'CHOWTapeModel';
  PresetVersion = '1.0.0';
  SkipParams: array[0..3] of string =
    ('preset', 'os_render_factor', 'os_render_mode', 'os_render_like_realtime');

{ ---------------------------------------------------------------------------
  Minimal XML helpers
  --------------------------------------------------------------------------- }

function XmlEscape(const S: string): string;
var
  I: Integer;
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    for I := 1 to Length(S) do
      case S[I] of
        '&': SB.Append('&amp;');
        '<': SB.Append('&lt;');
        '>': SB.Append('&gt;');
        '"': SB.Append('&quot;');
        '''': SB.Append('&apos;');
      else
        SB.Append(S[I]);
      end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function XmlUnescape(const S: string): string;
begin
  Result := S;
  Result := StringReplace(Result, '&lt;', '<', [rfReplaceAll]);
  Result := StringReplace(Result, '&gt;', '>', [rfReplaceAll]);
  Result := StringReplace(Result, '&quot;', '"', [rfReplaceAll]);
  Result := StringReplace(Result, '&apos;', '''', [rfReplaceAll]);
  // ampersand last, so "&amp;lt;" does not turn into "<"
  Result := StringReplace(Result, '&amp;', '&', [rfReplaceAll]);
end;

{ Reads Attr="..." from Source starting at or after StartPos. Returns False
  when the attribute is not present before the end of the element. }
function GetAttribute(const Source, Attr: string; StartPos, LimitPos: Integer;
  out Value: string): Boolean;
var
  P, Q: Integer;
  Needle: string;
begin
  Result := False;
  Value := '';
  Needle := Attr + '="';

  P := PosEx(Needle, Source, StartPos);
  if (P <= 0) or ((LimitPos > 0) and (P > LimitPos)) then
    Exit;

  Inc(P, Length(Needle));
  Q := PosEx('"', Source, P);
  if Q <= 0 then
    Exit;

  Value := XmlUnescape(Copy(Source, P, Q - P));
  Result := True;
end;

{ ---------------------------------------------------------------------------
  Legacy fix-ups, mirroring tools\gen_presets.py so that files written by any
  version of the original plug-in load correctly.
  --------------------------------------------------------------------------- }

function ShouldSkipParam(const ID: string): Boolean;
var
  I: Integer;
begin
  for I := Low(SkipParams) to High(SkipParams) do
    if SameText(ID, SkipParams[I]) then
      Exit(True);
  Result := False;
end;

procedure FixUpLegacyValue(var ID: string; var Value: Single);
begin
  // pre-2.11 oversampling parameter
  if SameText(ID, 'os') then
  begin
    ID := pidOSFactor;
    Value := EnsureRange(Round(Value), 0, 4);
    Exit;
  end;

  // dry/wet used to be a percentage
  if SameText(ID, pidDryWet) and (Value > 1.5) then
  begin
    Value := Value / 100.0;
    Exit;
  end;

  // spacing / thickness / gap used to be in metres, now microns. The two
  // ranges do not overlap, so the magnitude is enough to tell them apart.
  if SameText(ID, pidSpacing) or SameText(ID, pidThick) or SameText(ID, pidGap) then
    if Abs(Value) < 1.0e-3 then
      Value := Value * 1.0e6;
end;

{ TPresetLibrary }

constructor TPresetLibrary.Create(AParams: TParameterSet);
begin
  inherited Create;
  FParams := AParams;
  FEntries := TList<TPresetEntry>.Create;
  FCurrentIndex := -1;
  LoadConfig;
  Refresh;
  MarkClean;
end;

destructor TPresetLibrary.Destroy;
begin
  FEntries.Free;
  inherited Destroy;
end;

function TPresetLibrary.GetCount: Integer;
begin
  Result := FEntries.Count;
end;

function TPresetLibrary.GetEntry(Index: Integer): TPresetEntry;
begin
  Result := FEntries[Index];
end;

{ ---------------------------------------------------------------------------
  User folder, remembered in a config file the way the original does it
  --------------------------------------------------------------------------- }

function TPresetLibrary.ConfigFilePath: string;
begin
  Result := TPath.Combine(TPath.Combine(TPath.GetHomePath, 'ChowdhuryDSP'),
    TPath.Combine('ChowTape', 'UserPresets.txt'));
end;

function TPresetLibrary.DefaultUserFolder: string;
begin
  Result := TPath.Combine(TPath.Combine(TPath.GetHomePath, 'ChowdhuryDSP'),
    TPath.Combine('ChowTape', 'Presets'));
end;

procedure TPresetLibrary.LoadConfig;
var
  Path: string;
  Lines: TArray<string>;
begin
  FUserFolder := DefaultUserFolder;

  Path := ConfigFilePath;
  if not TFile.Exists(Path) then
    Exit;

  try
    Lines := TFile.ReadAllLines(Path);
    if (Length(Lines) > 0) and (Trim(Lines[0]) <> '') then
      FUserFolder := Trim(Lines[0]);
  except
    // an unreadable config is not worth failing over; use the default
  end;
end;

procedure TPresetLibrary.SaveConfig;
var
  Path: string;
begin
  Path := ConfigFilePath;
  try
    if not TDirectory.Exists(ExtractFileDir(Path)) then
      TDirectory.CreateDirectory(ExtractFileDir(Path));
    TFile.WriteAllText(Path, FUserFolder);
  except
    // read-only profile, roaming disabled, ... -- keep the folder for this
    // session and carry on
  end;
end;

procedure TPresetLibrary.SetUserFolder(const Value: string);
begin
  if SameText(Value, FUserFolder) then
    Exit;
  FUserFolder := Value;
  SaveConfig;
  Refresh;
end;

{ ---------------------------------------------------------------------------
  Building the list
  --------------------------------------------------------------------------- }

procedure TPresetLibrary.ScanUserFolder;
var
  Files: TArray<string>;
  FileName, Body, Value: string;
  Entry: TPresetEntry;
  P: Integer;
begin
  if not TDirectory.Exists(FUserFolder) then
    Exit;

  try
    Files := TDirectory.GetFiles(FUserFolder, '*' + PresetFileExtension,
      TSearchOption.soAllDirectories);
  except
    Exit;
  end;

  TArray.Sort<string>(Files);

  for FileName in Files do
  begin
    try
      Body := TFile.ReadAllText(FileName);
    except
      Continue;
    end;

    P := Pos('<Preset', Body);
    if P <= 0 then
      Continue;

    Entry.IsFactory := False;
    Entry.FactoryIndex := -1;
    Entry.FilePath := FileName;

    if not GetAttribute(Body, 'name', P, 0, Entry.Name) then
      Entry.Name := TPath.GetFileNameWithoutExtension(FileName);
    if not GetAttribute(Body, 'vendor', P, 0, Entry.Vendor) then
      Entry.Vendor := 'User';

    // group by the sub-folder it sits in, so a tidy folder gives a tidy menu
    Value := ExtractFileDir(FileName);
    if SameText(Value, ExcludeTrailingPathDelimiter(FUserFolder)) then
      Entry.Category := ''
    else
      Entry.Category := ExtractFileName(Value);

    FEntries.Add(Entry);
  end;
end;

procedure TPresetLibrary.Refresh;
var
  I: Integer;
  Entry: TPresetEntry;
  PreviousName: string;
begin
  PreviousName := '';
  if (FCurrentIndex >= 0) and (FCurrentIndex < FEntries.Count) then
    PreviousName := FEntries[FCurrentIndex].Name;

  FEntries.Clear;

  for I := 0 to FactoryPresetCount - 1 do
  begin
    Entry.Name := GetFactoryPresetName(I);
    Entry.Vendor := '';
    Entry.Category := GetFactoryPresetCategory(I);
    Entry.IsFactory := True;
    Entry.FactoryIndex := I;
    Entry.FilePath := '';
    FEntries.Add(Entry);
  end;

  ScanUserFolder;

  FCurrentIndex := -1;
  if PreviousName <> '' then
    SelectByName(PreviousName);
end;

procedure TPresetLibrary.SelectByName(const AName: string);
var
  I: Integer;
begin
  for I := 0 to FEntries.Count - 1 do
    if SameText(FEntries[I].Name, AName) then
    begin
      FCurrentIndex := I;
      Exit;
    end;
end;

{ ---------------------------------------------------------------------------
  Loading and saving
  --------------------------------------------------------------------------- }

function TPresetLibrary.LoadPreset(Index: Integer): Boolean;
begin
  Result := False;
  if (Index < 0) or (Index >= FEntries.Count) then
    Exit;

  if FEntries[Index].IsFactory then
  begin
    ApplyPreset(FParams, GetFactoryPreset(FEntries[Index].FactoryIndex));
    FCurrentIndex := Index;
    MarkClean;
    Exit(True);
  end;

  if not TFile.Exists(FEntries[Index].FilePath) then
    Exit;

  Result := LoadPresetFile(FEntries[Index].FilePath);
  if Result then
    FCurrentIndex := Index;
end;

function TPresetLibrary.LoadPresetFile(const FileName: string): Boolean;
var
  Body, ID, ValueStr, PresetName: string;
  P, ElementEnd: Integer;
  Value: Double;
  FS: TFormatSettings;
  Param: TParameter;
  V: Single;
begin
  Result := False;
  try
    Body := TFile.ReadAllText(FileName);
  except
    Exit;
  end;

  if Pos('<Preset', Body) <= 0 then
    Exit;

  FS := TFormatSettings.Invariant;
  FParams.ResetAllToDefault;

  P := 1;
  repeat
    P := PosEx('<PARAM', Body, P);
    if P <= 0 then
      Break;

    ElementEnd := PosEx('>', Body, P);
    if ElementEnd <= 0 then
      Break;

    if GetAttribute(Body, 'id', P, ElementEnd, ID)
      and GetAttribute(Body, 'value', P, ElementEnd, ValueStr)
      and TryStrToFloat(ValueStr, Value, FS)
      and (not ShouldSkipParam(ID)) then
    begin
      V := Value;
      FixUpLegacyValue(ID, V);
      Param := FParams.ByID(ID);
      if Param <> nil then
        Param.SetValue(V);
    end;

    P := ElementEnd + 1;
  until False;

  // remember which entry this was, if it is one we know about
  if GetAttribute(Body, 'name', Pos('<Preset', Body), 0, PresetName) then
    SelectByName(PresetName);

  MarkClean;
  Result := True;
end;

function TPresetLibrary.SavePresetFile(const FileName, PresetName: string): Boolean;
var
  SB: TStringBuilder;
  I: Integer;
  FS: TFormatSettings;
  Param: TParameter;
begin
  Result := False;
  FS := TFormatSettings.Invariant;

  SB := TStringBuilder.Create;
  try
    SB.AppendLine('<?xml version="1.0" encoding="UTF-8"?>');
    SB.AppendLine;
    SB.AppendLine(Format('<Preset name="%s" plugin="%s" vendor="User" category="" version="%s">',
      [XmlEscape(PresetName), PluginTag, PresetVersion]));
    SB.AppendLine('  <Parameters>');

    for I := 0 to FParams.Count - 1 do
    begin
      Param := FParams[I];
      SB.AppendLine(Format('    <PARAM id="%s" value="%s"/>',
        [XmlEscape(Param.ID), FloatToStr(Param.GetValue, FS)]));
    end;

    SB.AppendLine('  </Parameters>');
    SB.AppendLine('</Preset>');

    try
      if not TDirectory.Exists(ExtractFileDir(FileName)) then
        TDirectory.CreateDirectory(ExtractFileDir(FileName));
      TFile.WriteAllText(FileName, SB.ToString, TEncoding.UTF8);
      Result := True;
    except
      Exit;
    end;
  finally
    SB.Free;
  end;

  Refresh;
  SelectByName(PresetName);
  MarkClean;
end;

function TPresetLibrary.DeletePreset(Index: Integer): Boolean;
begin
  Result := False;
  if (Index < 0) or (Index >= FEntries.Count) then
    Exit;
  if FEntries[Index].IsFactory then
    Exit;

  try
    TFile.Delete(FEntries[Index].FilePath);
    Result := True;
  except
    Exit;
  end;

  Refresh;
end;

{ ---------------------------------------------------------------------------
  Navigation and dirty state
  --------------------------------------------------------------------------- }

procedure TPresetLibrary.SelectNext;
begin
  if FEntries.Count = 0 then
    Exit;
  LoadPreset((FCurrentIndex + 1) mod FEntries.Count);
end;

procedure TPresetLibrary.SelectPrevious;
begin
  if FEntries.Count = 0 then
    Exit;
  if FCurrentIndex <= 0 then
    LoadPreset(FEntries.Count - 1)
  else
    LoadPreset(FCurrentIndex - 1);
end;

procedure TPresetLibrary.MarkClean;
var
  I: Integer;
begin
  SetLength(FSnapshot, FParams.Count);
  for I := 0 to FParams.Count - 1 do
    FSnapshot[I] := FParams[I].Normalised;
end;

function TPresetLibrary.IsDirty: Boolean;
var
  I: Integer;
begin
  if Length(FSnapshot) <> FParams.Count then
    Exit(True);

  for I := 0 to FParams.Count - 1 do
    if FSnapshot[I] <> FParams[I].Normalised then
      Exit(True);

  Result := False;
end;

function TPresetLibrary.CurrentName: string;
begin
  if (FCurrentIndex >= 0) and (FCurrentIndex < FEntries.Count) then
    Result := FEntries[FCurrentIndex].Name
  else
    Result := 'Default';
end;

function TPresetLibrary.DisplayName: string;
begin
  Result := CurrentName;
  if IsDirty then
    Result := Result + '*';
end;

procedure TPresetLibrary.MarkDirty;
begin
  // an empty snapshot never matches, so IsDirty reports true
  SetLength(FSnapshot, 0);
end;

function TPresetLibrary.CurrentIsUserPreset: Boolean;
begin
  Result := (FCurrentIndex >= 0) and (FCurrentIndex < FEntries.Count)
    and (not FEntries[FCurrentIndex].IsFactory);
end;

function TPresetLibrary.CurrentFilePath: string;
begin
  if CurrentIsUserPreset then
    Result := FEntries[FCurrentIndex].FilePath
  else
    Result := '';
end;

end.
