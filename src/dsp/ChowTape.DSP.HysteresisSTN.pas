unit ChowTape.DSP.HysteresisSTN;

{
  "State Transition Network" solver for the hysteresis state-space formulation
  (Parker et al., DAFx 2019).

  Each model is the same tiny dense network the original ships:
      5 -> Dense(4) -> tanh -> Dense(4) -> tanh -> Dense(1)
  and there are 11 (bias width) x 21 (saturation) of them.

  They are linked into the DLL as a packed float64 blob (STN_MODELS, built by
  tools\gen_stn_models.py) rather than the original JSON: the JSON is eleven
  times larger than the numbers it carries and parsing a megabyte of it on
  every instantiation is wasted work.

  A loose STN_Models folder next to the DLL still wins if one is present, so
  retrained networks can be dropped in without a rebuild.
}

interface

uses
  {$IFDEF MSWINDOWS} Winapi.Windows, {$ENDIF}
  System.SysUtils, System.Classes, System.Math, System.JSON, System.IOUtils,
  System.SyncObjs, System.Generics.Collections,
  ChowTape.DSP.FastMath;

const
  STNNumWidthModels = 11;
  STNNumSatModels = 21;
  STNDiffMakeup = 1.0 / 6.0e4;
  STNValuesPerModel = 49;

type
  { One 5-4-4-1 network with tanh activations. }
  TSTNModel = record
    W1: array[0..3, 0..4] of Double; // layer 1 weights [out, in]
    B1: array[0..3] of Double;
    W2: array[0..3, 0..3] of Double;
    B2: array[0..3] of Double;
    W3: array[0..3] of Double;
    B3: Double;
    Loaded: Boolean;
    function Forward(const Input: array of Double): Double;
  end;

  THysteresisSTN = class
  private
    FSampleRateCorr: Double;
    FWidthIdx: Integer;
    FSatIdx: Integer;
  public
    constructor Create;
    procedure Prepare(SampleRate: Double);
    procedure SetParams(Saturation, Width: Single);
    { Not inlined: the model table lives in the implementation section. }
    function Process(const Input: array of Double): Double;
  end;

{ Overrides the folder searched for loose hyst_width_*.json files. Leave empty
  to look next to the DLL. Set before the first plug-in instance is created. }
var
  STNModelDirectory: string = '';

function STNModelsAvailable: Boolean;
{ How many of the STNModelTotal networks loaded successfully. }
function STNModelsLoadedCount: Integer;
function STNModelTotal: Integer;
{ Human-readable description of where the networks came from, for the
  settings menu: "embedded", "override: <folder>", or "not found". }
function STNModelsSource: string;

implementation

type
  TSTNModelArray = array[0..STNNumWidthModels - 1, 0..STNNumSatModels - 1] of TSTNModel;

var
  GModels: TSTNModelArray;
  GModelsLoaded: Boolean = False;
  GModelsSource: string = 'not found';
  GLoadLock: TCriticalSection = nil;

const
  WidthTags: array[0..STNNumWidthModels - 1] of string =
    ('0', '10', '20', '30', '40', '50', '60', '70', '80', '90', '100');
  SatTags: array[0..STNNumSatModels - 1] of string =
    ('0', '5', '10', '15', '20', '25', '30', '35', '40', '45', '50', '55',
     '60', '65', '70', '75', '80', '85', '90', '95', '100');

  ResourceName = 'STN_MODELS';
  BlobMagic = 'CTSN';
  BlobVersion = 1;

{ TSTNModel }

function TSTNModel.Forward(const Input: array of Double): Double;
var
  H1: array[0..3] of Double;
  H2: array[0..3] of Double;
  I, J: Integer;
  Acc: Double;
begin
  if not Loaded then
    Exit(0.0);

  for I := 0 to 3 do
  begin
    Acc := B1[I];
    for J := 0 to 4 do
      Acc := Acc + W1[I, J] * Input[J];
{$IFDEF CHOWTAPE_RTL_MATH}
    H1[I] := Tanh(Acc);
{$ELSE}
    H1[I] := FastTanh(Acc);
{$ENDIF}
  end;

  for I := 0 to 3 do
  begin
    Acc := B2[I];
    for J := 0 to 3 do
      Acc := Acc + W2[I, J] * H1[J];
{$IFDEF CHOWTAPE_RTL_MATH}
    H2[I] := Tanh(Acc);
{$ELSE}
    H2[I] := FastTanh(Acc);
{$ENDIF}
  end;

  Acc := B3;
  for J := 0 to 3 do
    Acc := Acc + W3[J] * H2[J];

  Result := Acc;
end;

{ ---------------------------------------------------------------------------
  Embedded blob

  Header: 'CTSN', uint32 version, uint32 widths, uint32 sats, uint32 per-model,
  then the values width-major in the same order Forward reads them.
  --------------------------------------------------------------------------- }

procedure ReadModelValues(Stream: TStream; var Model: TSTNModel);
var
  Values: array[0..STNValuesPerModel - 1] of Double;
  I, J, N: Integer;
begin
  Stream.ReadBuffer(Values[0], SizeOf(Values));

  N := 0;
  for I := 0 to 3 do
    for J := 0 to 4 do
    begin
      Model.W1[I, J] := Values[N];
      Inc(N);
    end;
  for I := 0 to 3 do
  begin
    Model.B1[I] := Values[N];
    Inc(N);
  end;

  for I := 0 to 3 do
    for J := 0 to 3 do
    begin
      Model.W2[I, J] := Values[N];
      Inc(N);
    end;
  for I := 0 to 3 do
  begin
    Model.B2[I] := Values[N];
    Inc(N);
  end;

  for I := 0 to 3 do
  begin
    Model.W3[I] := Values[N];
    Inc(N);
  end;
  Model.B3 := Values[N];

  Model.Loaded := True;
end;

function LoadFromResource: Boolean;
var
  Stream: TResourceStream;
  Magic: array[0..3] of AnsiChar;
  Version, Widths, Sats, PerModel: Cardinal;
  W, S: Integer;
begin
  Result := False;
  if FindResource(HInstance, ResourceName, RT_RCDATA) = 0 then
    Exit;

  Stream := TResourceStream.Create(HInstance, ResourceName, RT_RCDATA);
  try
    if Stream.Size < 20 then
      Exit;

    Stream.ReadBuffer(Magic[0], 4);
    if Magic <> BlobMagic then
      Exit;

    Stream.ReadBuffer(Version, SizeOf(Version));
    Stream.ReadBuffer(Widths, SizeOf(Widths));
    Stream.ReadBuffer(Sats, SizeOf(Sats));
    Stream.ReadBuffer(PerModel, SizeOf(PerModel));

    if (Version <> BlobVersion) or (Widths <> STNNumWidthModels)
      or (Sats <> STNNumSatModels) or (PerModel <> STNValuesPerModel) then
      Exit;

    if Stream.Size - Stream.Position <
       Int64(Widths) * Sats * PerModel * SizeOf(Double) then
      Exit;

    for W := 0 to STNNumWidthModels - 1 do
      for S := 0 to STNNumSatModels - 1 do
        ReadModelValues(Stream, GModels[W, S]);

    Result := True;
  finally
    Stream.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  Loose JSON override

  The files were exported by RTNeural's Keras helper. Each model is an object
  with a "layers" array; every layer carries a "type" ("dense"), an
  "activation" ("tanh", or empty for the output layer) and a "weights" pair
  holding the weight matrix followed by the bias vector. The weight matrix is
  indexed [input][output], which is the transpose of what Forward wants.
  --------------------------------------------------------------------------- }

function JsonToDouble(V: TJSONValue): Double;
begin
  if V is TJSONNumber then
    Result := TJSONNumber(V).AsDouble
  else
    Result := 0.0;
end;

procedure LoadDenseLayer(Weights: TJSONArray; var Model: TSTNModel; LayerIndex: Integer);
var
  W, B: TJSONArray;
  Row: TJSONArray;
  I, J: Integer;
begin
  if (Weights = nil) or (Weights.Count < 2) then
    Exit;

  W := Weights.Items[0] as TJSONArray;
  B := Weights.Items[1] as TJSONArray;

  case LayerIndex of
    0:
      begin
        for I := 0 to W.Count - 1 do
        begin
          Row := W.Items[I] as TJSONArray;
          for J := 0 to Row.Count - 1 do
            Model.W1[J, I] := JsonToDouble(Row.Items[J]);
        end;
        for I := 0 to B.Count - 1 do
          Model.B1[I] := JsonToDouble(B.Items[I]);
      end;
    1:
      begin
        for I := 0 to W.Count - 1 do
        begin
          Row := W.Items[I] as TJSONArray;
          for J := 0 to Row.Count - 1 do
            Model.W2[J, I] := JsonToDouble(Row.Items[J]);
        end;
        for I := 0 to B.Count - 1 do
          Model.B2[I] := JsonToDouble(B.Items[I]);
      end;
    2:
      begin
        for I := 0 to W.Count - 1 do
        begin
          Row := W.Items[I] as TJSONArray;
          if Row.Count > 0 then
            Model.W3[I] := JsonToDouble(Row.Items[0]);
        end;
        if B.Count > 0 then
          Model.B3 := JsonToDouble(B.Items[0]);
      end;
  end;
end;

procedure LoadModelFromJson(ModelJson: TJSONObject; var Model: TSTNModel);
var
  Layers: TJSONArray;
  Layer: TJSONObject;
  LayerType: string;
  I, DenseIndex: Integer;
begin
  Model.Loaded := False;
  if ModelJson = nil then
    Exit;

  Layers := ModelJson.GetValue('layers') as TJSONArray;
  if Layers = nil then
    Exit;

  DenseIndex := 0;
  for I := 0 to Layers.Count - 1 do
  begin
    Layer := Layers.Items[I] as TJSONObject;
    LayerType := '';
    if Layer.GetValue('type') <> nil then
      LayerType := LowerCase(Layer.GetValue('type').Value);

    if LayerType = 'dense' then
    begin
      LoadDenseLayer(Layer.GetValue('weights') as TJSONArray, Model, DenseIndex);
      Inc(DenseIndex);
    end;
  end;

  Model.Loaded := DenseIndex >= 3;
end;

function ModuleDirectory: string;
var
  Buf: array[0..1023] of Char;
begin
  {$IFDEF MSWINDOWS}
  if GetModuleFileName(HInstance, Buf, Length(Buf)) > 0 then
    Exit(ExtractFilePath(Buf));
  {$ENDIF}
  Result := ExtractFilePath(ParamStr(0));
end;

function OverrideDirectory: string;
begin
  if STNModelDirectory <> '' then
    Result := STNModelDirectory
  else
    Result := TPath.Combine(ModuleDirectory, 'STN_Models');
end;

function LoadFromFolder(const Dir: string): Boolean;
var
  WidthIdx, SatIdx: Integer;
  FileName, Tag, Text: string;
  Root, ModelObj: TJSONObject;
  Any: Boolean;
begin
  Any := False;

  for WidthIdx := 0 to STNNumWidthModels - 1 do
  begin
    FileName := TPath.Combine(Dir, 'hyst_width_' + WidthTags[WidthIdx] + '.json');
    if not TFile.Exists(FileName) then
      Continue;

    Text := TFile.ReadAllText(FileName, TEncoding.UTF8);
    Root := TJSONObject.ParseJSONValue(Text) as TJSONObject;
    if Root = nil then
      Continue;
    try
      for SatIdx := 0 to STNNumSatModels - 1 do
      begin
        Tag := 'drive_' + SatTags[SatIdx] + '_' + WidthTags[WidthIdx];
        ModelObj := Root.GetValue(Tag) as TJSONObject;
        LoadModelFromJson(ModelObj, GModels[WidthIdx, SatIdx]);
        if GModels[WidthIdx, SatIdx].Loaded then
          Any := True;
      end;
    finally
      Root.Free;
    end;
  end;

  Result := Any;
end;

procedure LoadAllModels;
var
  Dir: string;
begin
  // A loose folder wins, so retrained networks can be tried without a rebuild.
  Dir := OverrideDirectory;
  if TDirectory.Exists(Dir) and LoadFromFolder(Dir) then
  begin
    GModelsSource := 'override: ' + Dir;
    GModelsLoaded := True;
    Exit;
  end;

  if LoadFromResource then
    GModelsSource := 'embedded'
  else
    GModelsSource := 'not found';

  GModelsLoaded := True;
end;

procedure EnsureModelsLoaded;
begin
  if GModelsLoaded then
    Exit;
  GLoadLock.Enter;
  try
    if not GModelsLoaded then
      LoadAllModels;
  finally
    GLoadLock.Leave;
  end;
end;

function STNModelsAvailable: Boolean;
begin
  EnsureModelsLoaded;
  Result := GModels[0, 0].Loaded;
end;

function STNModelsLoadedCount: Integer;
var
  W, S: Integer;
begin
  EnsureModelsLoaded;
  Result := 0;
  for W := 0 to STNNumWidthModels - 1 do
    for S := 0 to STNNumSatModels - 1 do
      if GModels[W, S].Loaded then
        Inc(Result);
end;

function STNModelTotal: Integer;
begin
  Result := STNNumWidthModels * STNNumSatModels;
end;

function STNModelsSource: string;
begin
  EnsureModelsLoaded;
  Result := GModelsSource;
end;

{ THysteresisSTN }

constructor THysteresisSTN.Create;
begin
  inherited Create;
  FSampleRateCorr := 1.0;
  FWidthIdx := 0;
  FSatIdx := 0;
  EnsureModelsLoaded;
end;

procedure THysteresisSTN.Prepare(SampleRate: Double);
const
  TrainingSampleRate = 96.0e3;
begin
  FSampleRateCorr := TrainingSampleRate / SampleRate;
end;

procedure THysteresisSTN.SetParams(Saturation, Width: Single);
var
  Idx: Integer;
begin
  Idx := Trunc((STNNumSatModels - 1) * Saturation);
  FSatIdx := EnsureRange(Idx, 0, STNNumSatModels - 1);

  Idx := Trunc((STNNumWidthModels - 1) * Width);
  FWidthIdx := EnsureRange(Idx, 0, STNNumWidthModels - 1);
end;

function THysteresisSTN.Process(const Input: array of Double): Double;
begin
  Result := GModels[FWidthIdx, FSatIdx].Forward(Input) * FSampleRateCorr;
end;

initialization
  GLoadLock := TCriticalSection.Create;

finalization
  GLoadLock.Free;

end.
