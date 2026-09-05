unit ChowTape.DSP.Scope;

{ Data behind the oscilloscope at the top of the UI, plus the input and output
  level readouts drawn over it.

  The audio thread only writes here; the editor reads a snapshot on its timer. }

interface

uses
  System.Math, System.SyncObjs, ChowTape.DSP.Types;

type
  TTapeScope = class
  private
    FBuffer: array of Single;   // circular, mono sum
    FWritePos: Integer;
    FSize: Integer;
    FSampleRate: Double;

    FInputMeanSq: Double;
    FOutputMeanSq: Double;
    FMeterCoeff: Double;

    FLock: TCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;

    procedure PrepareToPlay(SampleRate: Double; SamplesPerBlock: Integer);
    procedure PushInput(Buffer: TAudioBuffer);
    procedure PushOutput(Buffer: TAudioBuffer);

    { Fills Dest with the most recent NumPoints samples, aligned to a rising
      zero crossing so the trace stands still. }
    procedure GetTrace(var Dest: TFloatArray; NumPoints: Integer);
    function GetInputDb: Single;
    function GetOutputDb: Single;
  end;

implementation

const
  RmsSeconds = 5.0;

constructor TTapeScope.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FSampleRate := 48000.0;
  FSize := 4096;
  SetLength(FBuffer, FSize);
  FMeterCoeff := 0.0;
end;

destructor TTapeScope.Destroy;
begin
  FLock.Free;
  inherited Destroy;
end;

procedure TTapeScope.PrepareToPlay(SampleRate: Double; SamplesPerBlock: Integer);
var
  I: Integer;
begin
  FSampleRate := SampleRate;

  // about a fifth of a second of history is plenty for the display
  FSize := 1;
  while FSize < Round(SampleRate * 0.2) do
    FSize := FSize * 2;

  FLock.Enter;
  try
    SetLength(FBuffer, FSize);
    for I := 0 to FSize - 1 do
      FBuffer[I] := 0.0;
    FWritePos := 0;
  finally
    FLock.Leave;
  end;

  FMeterCoeff := Exp(-1.0 / (RmsSeconds * SampleRate));
  FInputMeanSq := 0.0;
  FOutputMeanSq := 0.0;
end;

procedure TTapeScope.PushInput(Buffer: TAudioBuffer);
var
  N, Ch: Integer;
  Sum: Double;
  Acc: Double;
begin
  if Buffer.NumChannels = 0 then
    Exit;

  Acc := FInputMeanSq;
  for N := 0 to Buffer.NumSamples - 1 do
  begin
    Sum := 0.0;
    for Ch := 0 to Buffer.NumChannels - 1 do
      Sum := Sum + PSingleArray(Buffer.Channels[Ch])^[N];
    Sum := Sum / Buffer.NumChannels;
    Acc := FMeterCoeff * Acc + (1.0 - FMeterCoeff) * Sum * Sum;
  end;
  if IsNan(Acc) or IsInfinite(Acc) then
    Acc := 0.0;
  FInputMeanSq := Acc;
end;

procedure TTapeScope.PushOutput(Buffer: TAudioBuffer);
var
  N, Ch: Integer;
  Sum: Double;
  Acc: Double;
  Mono: Single;
begin
  if Buffer.NumChannels = 0 then
    Exit;

  Acc := FOutputMeanSq;

  FLock.Enter;
  try
    for N := 0 to Buffer.NumSamples - 1 do
    begin
      Sum := 0.0;
      for Ch := 0 to Buffer.NumChannels - 1 do
        Sum := Sum + PSingleArray(Buffer.Channels[Ch])^[N];
      Mono := Sum / Buffer.NumChannels;

      FBuffer[FWritePos] := Mono;
      FWritePos := (FWritePos + 1) and (FSize - 1);

      Acc := FMeterCoeff * Acc + (1.0 - FMeterCoeff) * Mono * Mono;
    end;
  finally
    FLock.Leave;
  end;

  if IsNan(Acc) or IsInfinite(Acc) then
    Acc := 0.0;
  FOutputMeanSq := Acc;
end;

procedure TTapeScope.GetTrace(var Dest: TFloatArray; NumPoints: Integer);
var
  I, Start, TrigPos, Search, Idx, Prev: Integer;
begin
  if NumPoints > FSize then
    NumPoints := FSize;
  if NumPoints < 2 then
    NumPoints := 2;
  if Length(Dest) <> NumPoints then
    SetLength(Dest, NumPoints);

  FLock.Enter;
  try
    // walk back from the write head looking for a rising zero crossing
    TrigPos := (FWritePos - NumPoints + FSize) and (FSize - 1);
    Search := 0;
    while Search < FSize div 4 do
    begin
      Idx := (TrigPos - Search + FSize) and (FSize - 1);
      Prev := (Idx - 1 + FSize) and (FSize - 1);
      if (FBuffer[Prev] <= 0.0) and (FBuffer[Idx] > 0.0) then
      begin
        TrigPos := Idx;
        Break;
      end;
      Inc(Search);
    end;

    Start := (TrigPos - NumPoints + FSize) and (FSize - 1);
    for I := 0 to NumPoints - 1 do
      Dest[I] := FBuffer[(Start + I) and (FSize - 1)];
  finally
    FLock.Leave;
  end;
end;

function TTapeScope.GetInputDb: Single;
begin
  Result := GainToDecibels(Sqrt(FInputMeanSq), -80.0);
end;

function TTapeScope.GetOutputDb: Single;
begin
  Result := GainToDecibels(Sqrt(FOutputMeanSq), -80.0);
end;

end.
