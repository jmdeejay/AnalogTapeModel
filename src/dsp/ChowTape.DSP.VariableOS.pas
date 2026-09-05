unit ChowTape.DSP.VariableOS;

{ chowdsp::VariableOversampling -- keeps one oversampler per (mode, factor)
  combination so switching is glitch-free and latency can be reported for the
  selected one. }

interface

uses
  System.Generics.Collections, ChowTape.DSP.Types, ChowTape.DSP.Oversampling,
  ChowTape.Params;

const
  NumOSFactors = 5;   // 1x 2x 4x 8x 16x
  NumOSModes = 2;     // minimum phase, linear phase

type
  TVariableOversampling = class
  private
    FOversamplers: TObjectList<TOversampling>;
    FFactorParam, FModeParam: TParameter;
    FCurOS, FPrevOS: Integer;
    FSampleRate: Single;
    FUseIntegerLatency: Boolean;
    FBuiltChannels: Integer;
    FBuiltBlockSize: Integer;
    function GetOSIndex(FactorIdx, ModeIdx: Integer): Integer; inline;
  public
    constructor Create(AParams: TParameterSet; AUseIntegerLatency: Boolean = False);
    destructor Destroy; override;

    procedure PrepareToPlay(SampleRate: Double; SamplesPerBlock, NumChannels: Integer);
    procedure Reset;
    function HasBeenPrepared: Boolean; inline;
    function GetOSFactor: Integer;
    function GetLatencySamples: Single;
    function GetLatencyMilliseconds(OSIndex: Integer = -1): Single;
    { Returns True when the selected oversampler changed. }
    function UpdateOSFactor: Boolean;

    function ProcessSamplesUp(Input: TAudioBufferD): TAudioBufferD;
    procedure ProcessSamplesDown(Output: TAudioBufferD);
  end;

implementation

constructor TVariableOversampling.Create(AParams: TParameterSet;
  AUseIntegerLatency: Boolean);
begin
  inherited Create;
  FOversamplers := TObjectList<TOversampling>.Create(True);
  FFactorParam := AParams.ByID(pidOSFactor);
  FModeParam := AParams.ByID(pidOSMode);
  FUseIntegerLatency := AUseIntegerLatency;
  FCurOS := 0;
  FPrevOS := 0;
  FBuiltChannels := 0;
  FBuiltBlockSize := 0;
end;

destructor TVariableOversampling.Destroy;
begin
  FOversamplers.Free;
  inherited Destroy;
end;

function TVariableOversampling.GetOSIndex(FactorIdx, ModeIdx: Integer): Integer;
begin
  Result := ModeIdx * NumOSFactors + FactorIdx;
end;

procedure TVariableOversampling.PrepareToPlay(SampleRate: Double;
  SamplesPerBlock, NumChannels: Integer);
var
  ModeIdx, FactorIdx: Integer;
  FilterType: TOSFilterType;
  I: Integer;
begin
  // The oversamplers only depend on the channel count and block size; designing
  // ten of them is expensive, so skip it when nothing relevant changed.
  if (FOversamplers.Count > 0) and (FBuiltChannels = NumChannels) and
     (FBuiltBlockSize = SamplesPerBlock) then
  begin
    FSampleRate := SampleRate;
    FCurOS := GetOSIndex(FFactorParam.GetIndex, FModeParam.GetIndex);
    FPrevOS := FCurOS;
    Reset;
    Exit;
  end;

  FOversamplers.Clear;

  for ModeIdx := 0 to NumOSModes - 1 do
  begin
    if ModeIdx = 1 then
      FilterType := osEquirippleFIR   // linear phase
    else
      FilterType := osPolyphaseIIR;   // minimum phase

    for FactorIdx := 0 to NumOSFactors - 1 do
      FOversamplers.Add(TOversampling.Create(NumChannels, FactorIdx, FilterType,
        True, FUseIntegerLatency));
  end;

  for I := 0 to FOversamplers.Count - 1 do
    FOversamplers[I].InitProcessing(SamplesPerBlock);

  FSampleRate := SampleRate;
  FBuiltChannels := NumChannels;
  FBuiltBlockSize := SamplesPerBlock;
  FCurOS := GetOSIndex(FFactorParam.GetIndex, FModeParam.GetIndex);
  FPrevOS := FCurOS;
end;

procedure TVariableOversampling.Reset;
var
  I: Integer;
begin
  for I := 0 to FOversamplers.Count - 1 do
    FOversamplers[I].Reset;
end;

function TVariableOversampling.HasBeenPrepared: Boolean;
begin
  Result := FOversamplers.Count > 0;
end;

function TVariableOversampling.GetOSFactor: Integer;
begin
  if not HasBeenPrepared then
    Exit(1);
  Result := FOversamplers[FCurOS].GetOversamplingFactor;
end;

function TVariableOversampling.GetLatencySamples: Single;
begin
  if not HasBeenPrepared then
    Exit(0.0);
  Result := FOversamplers[FCurOS].GetLatencyInSamples;
end;

function TVariableOversampling.GetLatencyMilliseconds(OSIndex: Integer): Single;
begin
  if not HasBeenPrepared then
    Exit(0.0);
  if OSIndex < 0 then
    OSIndex := FCurOS;
  if (OSIndex < 0) or (OSIndex >= FOversamplers.Count) then
    Exit(0.0);
  Result := (FOversamplers[OSIndex].GetLatencyInSamples / FSampleRate) * 1000.0;
end;

function TVariableOversampling.UpdateOSFactor: Boolean;
begin
  FCurOS := GetOSIndex(FFactorParam.GetIndex, FModeParam.GetIndex);

  if FCurOS <> FPrevOS then
  begin
    FPrevOS := FCurOS;
    Exit(True);
  end;

  Result := False;
end;

function TVariableOversampling.ProcessSamplesUp(Input: TAudioBufferD): TAudioBufferD;
begin
  Result := FOversamplers[FCurOS].ProcessSamplesUp(Input);
end;

procedure TVariableOversampling.ProcessSamplesDown(Output: TAudioBufferD);
begin
  FOversamplers[FCurOS].ProcessSamplesDown(Output);
end;

end.
