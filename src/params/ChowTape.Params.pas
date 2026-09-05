unit ChowTape.Params;

{
  The plug-in's parameter set.

  Ranges, defaults, skews and display strings all follow the originals so that
  a knob at the same position gives the same sound. Parameter *order* is also
  preserved because VST 2.4 addresses parameters by index.
}

interface

uses
  System.SysUtils, System.StrUtils, System.Classes, System.Math,
  System.Generics.Collections;

type
  TParamKind = (pkFloat, pkBool, pkChoice);

  TParamFormat = (pfFloat2, pfFloat4, pfPercent, pfBipolarPercent, pfGainDb,
    pfFreqHz, pfTimeMs, pfBool, pfChoice);

  TParameter = class
  private
    FID: string;
    FName: string;
    FKind: TParamKind;
    FRangeStart: Single;
    FRangeEnd: Single;
    FSkew: Single;
    FDefaultValue: Single;
    FChoices: TArray<string>;
    FFormat: TParamFormat;
    FNormalised: Single;
    FIndex: Integer;
  public
    constructor CreateFloat(const AID, AName: string; AStart, AEnd, ADefault: Single;
      AFormat: TParamFormat = pfFloat2; ACentre: Single = -1.0e9);
    constructor CreateBool(const AID, AName: string; ADefault: Boolean);
    constructor CreateChoice(const AID, AName: string; const AChoices: array of string;
      ADefaultIndex: Integer);

    function ConvertFrom0To1(Proportion: Single): Single;
    function ConvertTo0To1(Value: Single): Single;

    function GetValue: Single;                  // in real units
    procedure SetValue(NewValue: Single);
    function GetBool: Boolean; inline;
    function GetIndex: Integer; inline;

    function GetText: string; overload;
    function GetText(Value: Single): string; overload;
    function TextToValue(const S: string): Single;

    procedure ResetToDefault;

    property ID: string read FID;
    property Name: string read FName;
    property Kind: TParamKind read FKind;
    property Format: TParamFormat read FFormat;
    property RangeStart: Single read FRangeStart;
    property RangeEnd: Single read FRangeEnd;
    property DefaultValue: Single read FDefaultValue;
    property Choices: TArray<string> read FChoices;
    property Normalised: Single read FNormalised write FNormalised;
    property Index: Integer read FIndex write FIndex;
  end;

  TParameterSet = class
  private
    FList: TObjectList<TParameter>;
    FLookup: TDictionary<string, TParameter>;
    function GetItem(I: Integer): TParameter; inline;
    function GetCount: Integer; inline;
  public
    constructor Create;
    destructor Destroy; override;
    function Add(P: TParameter): TParameter;
    function ByID(const AID: string): TParameter;
    function ValueOf(const AID: string): Single;
    function BoolOf(const AID: string): Boolean;
    function IndexOf(const AID: string): Integer;
    procedure ResetAllToDefault;
    property Items[I: Integer]: TParameter read GetItem; default;
    property Count: Integer read GetCount;
  end;

{ Parameter IDs, gathered here so processors and the editor agree. }
const
  pidInGain        = 'ingain';
  pidOutGain       = 'outgain';
  pidDryWet        = 'drywet';

  pidIFiltOnOff    = 'ifilt_onoff';
  pidIFiltLow      = 'ifilt_low';
  pidIFiltHigh     = 'ifilt_high';
  pidIFiltMakeup   = 'ifilt_makeup';

  pidToneOnOff     = 'tone_onoff';
  pidBass          = 'h_bass';
  pidTreble        = 'h_treble';
  pidTFreq         = 'h_tfreq';

  pidCompOnOff     = 'comp_onoff';
  pidCompAmt       = 'comp_amt';
  pidCompAttack    = 'comp_attack';
  pidCompRelease   = 'comp_release';

  pidHystOnOff     = 'hyst_onoff';
  pidDrive         = 'drive';
  pidSat           = 'sat';
  pidWidth         = 'width';
  pidMode          = 'mode';
  pidOSFactor      = 'os_factor';
  pidOSMode        = 'os_mode';

  pidLossOnOff     = 'loss_onoff';
  pidSpeed         = 'speed';
  pidSpacing       = 'spacing';
  pidThick         = 'thick';
  pidGap           = 'gap';
  pidAzimuth       = 'azimuth';

  pidFlutterOnOff  = 'flutter_onoff';
  pidFlutterRate   = 'rate';
  pidFlutterDepth  = 'depth';
  pidWowRate       = 'wow_rate';
  pidWowDepth      = 'wow_depth';
  pidWowVar        = 'wow_var';
  pidWowDrift      = 'wow_drift';

  pidDegPoint1x    = 'deg_point1x';
  pidDegOnOff      = 'deg_onoff';
  pidDegDepth      = 'deg_depth';
  pidDegAmt        = 'deg_amt';
  pidDegVar        = 'deg_var';
  pidDegEnv        = 'deg_env';

  pidChewOnOff     = 'chew_onoff';
  pidChewDepth     = 'chew_depth';
  pidChewFreq      = 'chew_freq';
  pidChewVar       = 'chew_var';

  pidMidSide       = 'mid_side';
  pidStereoBalance = 'stereo_balance';
  pidStereoMakeup  = 'stereo_makeup';

  pidMixGroup      = 'mix_group';

{ Builds the full parameter set in the canonical order. }
function CreateTapeParameters: TParameterSet;

implementation

function SkewForCentre(RangeStart, RangeEnd, Centre: Single): Single;
begin
  Result := Ln(0.5) / Ln((Centre - RangeStart) / (RangeEnd - RangeStart));
end;

{ TParameter }

constructor TParameter.CreateFloat(const AID, AName: string;
  AStart, AEnd, ADefault: Single; AFormat: TParamFormat; ACentre: Single);
begin
  inherited Create;
  FID := AID;
  FName := AName;
  FKind := pkFloat;
  FRangeStart := AStart;
  FRangeEnd := AEnd;
  FDefaultValue := ADefault;
  FFormat := AFormat;
  if ACentre > -1.0e8 then
    FSkew := SkewForCentre(AStart, AEnd, ACentre)
  else
    FSkew := 1.0;
  ResetToDefault;
end;

constructor TParameter.CreateBool(const AID, AName: string; ADefault: Boolean);
begin
  inherited Create;
  FID := AID;
  FName := AName;
  FKind := pkBool;
  FRangeStart := 0.0;
  FRangeEnd := 1.0;
  FSkew := 1.0;
  FFormat := pfBool;
  if ADefault then
    FDefaultValue := 1.0
  else
    FDefaultValue := 0.0;
  ResetToDefault;
end;

constructor TParameter.CreateChoice(const AID, AName: string;
  const AChoices: array of string; ADefaultIndex: Integer);
var
  I: Integer;
begin
  inherited Create;
  FID := AID;
  FName := AName;
  FKind := pkChoice;
  SetLength(FChoices, Length(AChoices));
  for I := 0 to High(AChoices) do
    FChoices[I] := AChoices[I];
  FRangeStart := 0.0;
  FRangeEnd := Length(AChoices) - 1;
  FSkew := 1.0;
  FFormat := pfChoice;
  FDefaultValue := ADefaultIndex;
  ResetToDefault;
end;

function TParameter.ConvertFrom0To1(Proportion: Single): Single;
begin
  Proportion := EnsureRange(Proportion, 0.0, 1.0);

  case FKind of
    pkBool:
      Exit(Ord(Proportion >= 0.5));
    pkChoice:
      Exit(EnsureRange(Round(Proportion * FRangeEnd), 0, Round(FRangeEnd)));
  end;

  if (FSkew <> 1.0) and (Proportion > 0.0) then
    Proportion := Exp(Ln(Proportion) / FSkew);

  Result := FRangeStart + (FRangeEnd - FRangeStart) * Proportion;
end;

function TParameter.ConvertTo0To1(Value: Single): Single;
var
  Proportion: Single;
begin
  case FKind of
    pkBool:
      Exit(Ord(Value >= 0.5));
    pkChoice:
      begin
        if FRangeEnd <= 0 then
          Exit(0.0);
        Exit(EnsureRange(Value / FRangeEnd, 0.0, 1.0));
      end;
  end;

  Proportion := EnsureRange((Value - FRangeStart) / (FRangeEnd - FRangeStart), 0.0, 1.0);
  if FSkew <> 1.0 then
    Proportion := Power(Proportion, FSkew);
  Result := Proportion;
end;

function TParameter.GetValue: Single;
begin
  Result := ConvertFrom0To1(FNormalised);
end;

procedure TParameter.SetValue(NewValue: Single);
begin
  FNormalised := ConvertTo0To1(NewValue);
end;

function TParameter.GetBool: Boolean;
begin
  Result := FNormalised >= 0.5;
end;

function TParameter.GetIndex: Integer;
begin
  Result := Round(GetValue);
end;

procedure TParameter.ResetToDefault;
begin
  SetValue(FDefaultValue);
end;

function TParameter.GetText: string;
begin
  Result := GetText(GetValue);
end;

function TParameter.GetText(Value: Single): string;
var
  FS: TFormatSettings;
  Idx: Integer;
begin
  FS := TFormatSettings.Invariant;

  case FFormat of
    pfFloat2:
      Result := FormatFloat('0.00', Value, FS);
    pfFloat4:
      Result := FormatFloat('0.0000', Value, FS);
    pfPercent:
      Result := IntToStr(Trunc(Value * 100.0)) + '%';
    pfBipolarPercent:
      Result := IntToStr(Trunc(Value * 100.0)) + '%';
    pfGainDb:
      Result := FormatFloat('0.00', Value, FS) + ' dB';
    pfFreqHz:
      if Value <= 1000.0 then
        Result := FormatFloat('0.00', Value, FS) + ' Hz'
      else
        Result := FormatFloat('0.00', Value / 1000.0, FS) + ' kHz';
    pfTimeMs:
      if Value < 1000.0 then
        Result := FormatFloat('0.00', Value, FS) + ' ms'
      else
        Result := FormatFloat('0.00', Value / 1000.0, FS) + ' s';
    pfBool:
      if Value >= 0.5 then Result := 'On' else Result := 'Off';
    pfChoice:
      begin
        Idx := EnsureRange(Round(Value), 0, High(FChoices));
        if Length(FChoices) > 0 then
          Result := FChoices[Idx]
        else
          Result := '';
      end;
  else
    Result := FormatFloat('0.00', Value, FS);
  end;
end;

function TParameter.TextToValue(const S: string): Single;
var
  FS: TFormatSettings;
  Trimmed: string;
  I: Integer;
  Num: string;
  V: Double;
begin
  FS := TFormatSettings.Invariant;
  Trimmed := Trim(S);

  if FKind = pkChoice then
  begin
    for I := 0 to High(FChoices) do
      if SameText(FChoices[I], Trimmed) then
        Exit(I);
    Exit(GetValue);
  end;

  if FKind = pkBool then
  begin
    if SameText(Trimmed, 'on') or SameText(Trimmed, 'true') or SameText(Trimmed, '1') then
      Exit(1.0);
    if SameText(Trimmed, 'off') or SameText(Trimmed, 'false') or SameText(Trimmed, '0') then
      Exit(0.0);
    Exit(GetValue);
  end;

  Num := '';
  for I := 1 to Length(Trimmed) do
    if CharInSet(Trimmed[I], ['0'..'9', '.', '-', '+', 'e', 'E']) then
      Num := Num + Trimmed[I]
    else
      Break;

  if not TryStrToFloat(Num, V, FS) then
    Exit(GetValue);

  if FFormat = pfFreqHz then
    if (Pos('k', Trimmed) > 0) or (Pos('K', Trimmed) > 0) then
      V := V * 1000.0;

  if FFormat = pfTimeMs then
    if EndsText(' s', Trimmed) or EndsText(' seconds', Trimmed) then
      V := V * 1000.0;

  if FFormat in [pfPercent, pfBipolarPercent] then
    V := V / 100.0;

  Result := EnsureRange(V, Min(FRangeStart, FRangeEnd), Max(FRangeStart, FRangeEnd));
end;

{ TParameterSet }

constructor TParameterSet.Create;
begin
  inherited Create;
  FList := TObjectList<TParameter>.Create(True);
  FLookup := TDictionary<string, TParameter>.Create;
end;

destructor TParameterSet.Destroy;
begin
  FLookup.Free;
  FList.Free;
  inherited Destroy;
end;

function TParameterSet.Add(P: TParameter): TParameter;
begin
  P.Index := FList.Count;
  FList.Add(P);
  FLookup.AddOrSetValue(P.ID, P);
  Result := P;
end;

function TParameterSet.ByID(const AID: string): TParameter;
begin
  if not FLookup.TryGetValue(AID, Result) then
    Result := nil;
end;

function TParameterSet.ValueOf(const AID: string): Single;
var
  P: TParameter;
begin
  P := ByID(AID);
  if P <> nil then
    Result := P.GetValue
  else
    Result := 0.0;
end;

function TParameterSet.BoolOf(const AID: string): Boolean;
var
  P: TParameter;
begin
  P := ByID(AID);
  Result := (P <> nil) and P.GetBool;
end;

function TParameterSet.IndexOf(const AID: string): Integer;
var
  P: TParameter;
begin
  P := ByID(AID);
  if P <> nil then
    Result := P.GetIndex
  else
    Result := 0;
end;

procedure TParameterSet.ResetAllToDefault;
var
  I: Integer;
begin
  for I := 0 to FList.Count - 1 do
    FList[I].ResetToDefault;
end;

function TParameterSet.GetItem(I: Integer): TParameter;
begin
  Result := FList[I];
end;

function TParameterSet.GetCount: Integer;
begin
  Result := FList.Count;
end;

{ ---------------------------------------------------------------------------
  The parameter list
  --------------------------------------------------------------------------- }
function CreateTapeParameters: TParameterSet;
var
  P: TParameterSet;
begin
  P := TParameterSet.Create;

  // main gains
  P.Add(TParameter.CreateFloat(pidInGain, 'Input Gain', -30.0, 6.0, 0.0, pfGainDb));
  P.Add(TParameter.CreateFloat(pidOutGain, 'Output Gain', -30.0, 30.0, 0.0, pfGainDb));
  P.Add(TParameter.CreateFloat(pidDryWet, 'Dry/Wet', 0.0, 1.0, 1.0, pfPercent));

  // input filters
  P.Add(TParameter.CreateBool(pidIFiltOnOff, 'Input Filters On/Off', False));
  P.Add(TParameter.CreateFloat(pidIFiltLow, 'Input Low Cut', 20.0, 2000.0, 20.0, pfFreqHz, 250.0));
  P.Add(TParameter.CreateFloat(pidIFiltHigh, 'Input High Cut', 2000.0, 22000.0, 22000.0, pfFreqHz, 10000.0));
  P.Add(TParameter.CreateBool(pidIFiltMakeup, 'Input Cut Makeup', False));

  // tone control
  P.Add(TParameter.CreateBool(pidToneOnOff, 'Tone On/Off', True));
  P.Add(TParameter.CreateFloat(pidBass, 'Tone Bass', -1.0, 1.0, 0.0, pfFloat2));
  P.Add(TParameter.CreateFloat(pidTreble, 'Tone Treble', -1.0, 1.0, 0.0, pfFloat2));
  P.Add(TParameter.CreateFloat(pidTFreq, 'Tone Transition Frequency', 100.0, 4000.0, 500.0, pfFreqHz, 500.0));

  // compression
  P.Add(TParameter.CreateBool(pidCompOnOff, 'Compression On/Off', False));
  P.Add(TParameter.CreateFloat(pidCompAmt, 'Compression Amount', 0.0, 9.0, 0.0, pfGainDb, 3.0));
  P.Add(TParameter.CreateFloat(pidCompAttack, 'Compression Attack', 0.1, 50.0, 5.0, pfTimeMs, 10.0));
  P.Add(TParameter.CreateFloat(pidCompRelease, 'Compression Release', 10.0, 1000.0, 200.0, pfTimeMs, 100.0));

  // hysteresis
  P.Add(TParameter.CreateBool(pidHystOnOff, 'Tape On/Off', True));
  P.Add(TParameter.CreateFloat(pidDrive, 'Tape Drive', 0.0, 1.0, 0.5, pfFloat2));
  P.Add(TParameter.CreateFloat(pidSat, 'Tape Saturation', 0.0, 1.0, 0.5, pfFloat2));
  P.Add(TParameter.CreateFloat(pidWidth, 'Tape Bias', 0.0, 1.0, 0.5, pfFloat2));
  P.Add(TParameter.CreateChoice(pidMode, 'Tape Mode',
    ['RK2', 'RK4', 'NR4', 'NR8', 'STN', 'V1'], 0));
  P.Add(TParameter.CreateChoice(pidOSFactor, 'Oversampling Factor',
    ['1x', '2x', '4x', '8x', '16x'], 1));
  P.Add(TParameter.CreateChoice(pidOSMode, 'Oversampling Mode',
    ['Min. Phase', 'Linear Phase'], 0));

  // loss effects
  P.Add(TParameter.CreateBool(pidLossOnOff, 'Loss On/Off', True));
  P.Add(TParameter.CreateFloat(pidSpeed, 'Tape Speed', 1.0, 50.0, 30.0, pfFloat2, 15.0));
  P.Add(TParameter.CreateFloat(pidSpacing, 'Tape Spacing', 0.1, 20.0, 0.1, pfFloat4, 10.0));
  P.Add(TParameter.CreateFloat(pidThick, 'Tape Thickness', 0.1, 50.0, 0.1, pfFloat4, 15.0));
  P.Add(TParameter.CreateFloat(pidGap, 'Playhead Gap', 1.0, 50.0, 1.0, pfFloat4, 10.0));
  P.Add(TParameter.CreateFloat(pidAzimuth, 'Azimuth', -75.0, 75.0, 0.0, pfFloat2));

  // wow & flutter
  P.Add(TParameter.CreateBool(pidFlutterOnOff, 'Wow/Flutter On/Off', True));
  P.Add(TParameter.CreateFloat(pidFlutterRate, 'Flutter Rate', 0.0, 1.0, 0.3, pfFloat2));
  P.Add(TParameter.CreateFloat(pidFlutterDepth, 'Flutter Depth', 0.0, 1.0, 0.0, pfFloat2));
  P.Add(TParameter.CreateFloat(pidWowRate, 'Wow Rate', 0.0, 1.0, 0.25, pfFloat2));
  P.Add(TParameter.CreateFloat(pidWowDepth, 'Wow Depth', 0.0, 1.0, 0.0, pfFloat2));
  P.Add(TParameter.CreateFloat(pidWowVar, 'Wow Variance', 0.0, 1.0, 0.0, pfFloat2));
  P.Add(TParameter.CreateFloat(pidWowDrift, 'Wow Drift', 0.0, 1.0, 0.0, pfFloat2));

  // degrade
  P.Add(TParameter.CreateBool(pidDegPoint1x, 'Degrade Point1x', False));
  P.Add(TParameter.CreateBool(pidDegOnOff, 'Degrade On/Off', False));
  P.Add(TParameter.CreateFloat(pidDegDepth, 'Degrade Depth', 0.0, 1.0, 0.0, pfFloat2));
  P.Add(TParameter.CreateFloat(pidDegAmt, 'Degrade Amount', 0.0, 1.0, 0.0, pfFloat2));
  P.Add(TParameter.CreateFloat(pidDegVar, 'Degrade Variance', 0.0, 1.0, 0.0, pfFloat2));
  P.Add(TParameter.CreateFloat(pidDegEnv, 'Degrade Envelope', 0.0, 1.0, 0.0, pfFloat2));

  // chew
  P.Add(TParameter.CreateBool(pidChewOnOff, 'Chew On/Off', False));
  P.Add(TParameter.CreateFloat(pidChewDepth, 'Chew Depth', 0.0, 1.0, 0.0, pfFloat2));
  P.Add(TParameter.CreateFloat(pidChewFreq, 'Chew Freq', 0.0, 1.0, 0.0, pfFloat2));
  P.Add(TParameter.CreateFloat(pidChewVar, 'Chew Variance', 0.0, 1.0, 0.0, pfFloat2));

  // stereo / mid-side
  P.Add(TParameter.CreateBool(pidMidSide, 'Mid/Side Mode', False));
  P.Add(TParameter.CreateFloat(pidStereoBalance, 'Stereo Balance', -1.0, 1.0, 0.0, pfBipolarPercent));
  P.Add(TParameter.CreateBool(pidStereoMakeup, 'Stereo Makeup', True));

  // mix groups
  P.Add(TParameter.CreateChoice(pidMixGroup, 'Mix Group', ['N/A', '1', '2', '3', '4'], 0));

  Result := P;
end;

end.
