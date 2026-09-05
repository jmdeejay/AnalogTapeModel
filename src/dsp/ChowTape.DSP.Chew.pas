unit ChowTape.DSP.Chew;

{ "Chewed-up tape": randomly alternating stretches of clean tape and dropouts,
  where a dropout is a waveshaper (|x|^p) plus a lowpass. }

interface

uses
  System.Math, System.Generics.Collections, ChowTape.DSP.Types,
  ChowTape.DSP.Filters, ChowTape.DSP.Basics, ChowTape.Params;

type
  TDropout = class
  private
    FMixSmooth: TSmoothedLinearArray;
    FPowerSmooth: TSmoothedLinearArray;
  public
    procedure Prepare(SampleRate: Double; NumChannels: Integer);
    procedure SetMix(NewMix: Single);
    procedure SetPower(NewPow: Single);
    procedure Process(Buffer: TAudioBuffer);
  end;

  TChewProcessor = class
  private
    FOnOff, FDepth, FFreq, FVar: TParameter;
    FMix: Single;
    FPower: Single;

    FDropout: TDropout;
    FFilt: TObjectList<TDegradeFilter>;

    FRandom: TRandom;
    FSamplesUntilChange: Integer;
    FIsCrinkled: Boolean;
    FSampleCounter: Integer;

    FSampleRate: Single;
    FBypass: TBypassProcessor;
    FShortBuffer: TAudioBuffer;

    function GetDryTime: Integer;
    function GetWetTime: Integer;
    procedure ProcessShortBlock(Buffer: TAudioBuffer);
  public
    constructor Create(AParams: TParameterSet);
    destructor Destroy; override;
    procedure Prepare(SampleRate: Double; SamplesPerBlock, NumChannels: Integer);
    procedure ProcessBlock(Buffer: TAudioBuffer);
  end;

implementation

{ TDropout }

procedure TDropout.Prepare(SampleRate: Double; NumChannels: Integer);
var
  I: Integer;
begin
  SetLength(FMixSmooth, NumChannels);
  SetLength(FPowerSmooth, NumChannels);
  for I := 0 to NumChannels - 1 do
  begin
    FMixSmooth[I].Reset(SampleRate, 0.01);
    FPowerSmooth[I].Reset(SampleRate, 0.005);
  end;
end;

procedure TDropout.SetMix(NewMix: Single);
var
  I: Integer;
begin
  for I := 0 to High(FMixSmooth) do
    FMixSmooth[I].SetTargetValue(NewMix);
end;

procedure TDropout.SetPower(NewPow: Single);
var
  I: Integer;
begin
  for I := 0 to High(FPowerSmooth) do
    FPowerSmooth[I].SetTargetValue(NewPow);
end;

procedure TDropout.Process(Buffer: TAudioBuffer);
var
  Ch, N: Integer;
  X: PSingleArray;
  Mix, Sgn, Shaped: Single;
begin
  if (FMixSmooth[0].GetTargetValue = 0.0) and (not FMixSmooth[0].IsSmoothing) then
    Exit;

  for Ch := 0 to Buffer.NumChannels - 1 do
  begin
    X := PSingleArray(Buffer.Channels[Ch]);
    for N := 0 to Buffer.NumSamples - 1 do
    begin
      Mix := FMixSmooth[Ch].GetNextValue;

      Sgn := SignOf(X^[N]);
      Shaped := Power(Abs(X^[N]), FPowerSmooth[Ch].GetNextValue) * Sgn;

      X^[N] := Mix * Shaped + (1.0 - Mix) * X^[N];
    end;
  end;
end;

{ TChewProcessor }

constructor TChewProcessor.Create(AParams: TParameterSet);
begin
  inherited Create;
  FDepth := AParams.ByID(pidChewDepth);
  FFreq := AParams.ByID(pidChewFreq);
  FVar := AParams.ByID(pidChewVar);
  FOnOff := AParams.ByID(pidChewOnOff);

  FDropout := TDropout.Create;
  FFilt := TObjectList<TDegradeFilter>.Create(True);
  FBypass := TBypassProcessor.Create;
  FShortBuffer := TAudioBuffer.Create;
  FRandom := CreateRandom;

  FSampleRate := 44100.0;
  FSamplesUntilChange := 1000;
  FIsCrinkled := False;
  FSampleCounter := 0;
end;

destructor TChewProcessor.Destroy;
begin
  FDropout.Free;
  FFilt.Free;
  FBypass.Free;
  FShortBuffer.Free;
  inherited Destroy;
end;

function TChewProcessor.GetDryTime: Integer;
var
  TScale, VarScale: Single;
  Lo, Hi: Integer;
begin
  TScale := Power(FFreq.GetValue, 0.1);
  VarScale := Power(FRandom.NextFloat * 2.0, FVar.GetValue);
  Lo := Trunc((1.0 - TScale) * FSampleRate * VarScale);
  Hi := Trunc((2.0 - 1.99 * TScale) * FSampleRate * VarScale);
  Result := FRandom.NextIntInRange(Lo, Hi);
end;

function TChewProcessor.GetWetTime: Integer;
var
  TScale, VarScale: Single;
  StartV, EndV: Double;
  Lo, Hi: Integer;
begin
  TScale := Power(FFreq.GetValue, 0.1);
  StartV := 0.2 + 0.8 * FDepth.GetValue;
  EndV := StartV - (0.001 + 0.01 * FDepth.GetValue);
  VarScale := Power(FRandom.NextFloat * 2.0, FVar.GetValue);

  Lo := Trunc((1.0 - TScale) * FSampleRate * VarScale);
  Hi := Trunc(((1.0 - TScale) + StartV - EndV * TScale) * FSampleRate * VarScale);
  Result := FRandom.NextIntInRange(Lo, Hi);
end;

procedure TChewProcessor.Prepare(SampleRate: Double; SamplesPerBlock, NumChannels: Integer);
var
  Ch: Integer;
  F: TDegradeFilter;
begin
  FSampleRate := SampleRate;

  FDropout.Prepare(SampleRate, NumChannels);

  FFilt.Clear;
  for Ch := 0 to NumChannels - 1 do
  begin
    F := TDegradeFilter.Create;
    F.Reset(FSampleRate, Trunc(SampleRate * 0.02));
    FFilt.Add(F);
  end;

  FIsCrinkled := False;
  FSamplesUntilChange := GetDryTime;
  FSampleCounter := 0;

  FBypass.Prepare(SamplesPerBlock, NumChannels, FOnOff.GetBool);
end;

procedure TChewProcessor.ProcessBlock(Buffer: TAudioBuffer);
const
  ShortBlockSize = 64;
var
  SampleIdx, Remaining, Ch: Integer;
  Ptrs: array of PSingle;
begin
  if not FBypass.ProcessBlockIn(Buffer, FOnOff.GetBool) then
    Exit;

  if Buffer.NumSamples <= ShortBlockSize then
    ProcessShortBlock(Buffer)
  else
  begin
    SetLength(Ptrs, Buffer.NumChannels);
    for Ch := 0 to Buffer.NumChannels - 1 do
      Ptrs[Ch] := Buffer.Channels[Ch];

    SampleIdx := 0;
    while SampleIdx + ShortBlockSize <= Buffer.NumSamples do
    begin
      FShortBuffer.SetDataToReferTo(Ptrs, Buffer.NumChannels, SampleIdx, ShortBlockSize);
      ProcessShortBlock(FShortBuffer);
      Inc(SampleIdx, ShortBlockSize);
    end;

    Remaining := Buffer.NumSamples - SampleIdx;
    if Remaining > 0 then
    begin
      FShortBuffer.SetDataToReferTo(Ptrs, Buffer.NumChannels, SampleIdx, Remaining);
      ProcessShortBlock(FShortBuffer);
    end;
  end;

  FBypass.ProcessBlockOut(Buffer, FOnOff.GetBool);
end;

procedure TChewProcessor.ProcessShortBlock(Buffer: TAudioBuffer);
var
  HighFreq, FreqChange, FilterFreq, FreqVal, DepthVal: Single;
  Ch: Integer;
begin
  HighFreq := JMinF(22000.0, 0.49 * FSampleRate);
  FreqChange := HighFreq - 5000.0;

  FreqVal := FFreq.GetValue;
  DepthVal := FDepth.GetValue;

  if FreqVal = 0.0 then
  begin
    FMix := 0.0;
    for Ch := 0 to FFilt.Count - 1 do
      FFilt[Ch].SetFreq(HighFreq);
  end
  else if FreqVal = 1.0 then
  begin
    FMix := 1.0;
    FPower := 3.0 * DepthVal;
    FilterFreq := HighFreq - FreqChange * DepthVal;
    for Ch := 0 to FFilt.Count - 1 do
      FFilt[Ch].SetFreq(FilterFreq);
  end
  else if FSampleCounter >= FSamplesUntilChange then
  begin
    FSampleCounter := 0;
    FIsCrinkled := not FIsCrinkled;

    if FIsCrinkled then
    begin
      // start of a chewed-up stretch
      FMix := 1.0;
      FPower := (1.0 + 2.0 * FRandom.NextFloat) * DepthVal;
      FilterFreq := HighFreq - FreqChange * DepthVal;
      for Ch := 0 to FFilt.Count - 1 do
        FFilt[Ch].SetFreq(FilterFreq);

      FSamplesUntilChange := GetWetTime;
    end
    else
    begin
      FMix := 0.0;
      for Ch := 0 to FFilt.Count - 1 do
        FFilt[Ch].SetFreq(HighFreq);
      FSamplesUntilChange := GetDryTime;
    end;
  end
  else
  begin
    FPower := (1.0 + 2.0 * FRandom.NextFloat) * DepthVal;
    if FIsCrinkled then
    begin
      FilterFreq := HighFreq - FreqChange * DepthVal;
      for Ch := 0 to FFilt.Count - 1 do
        FFilt[Ch].SetFreq(FilterFreq);
    end;
  end;

  FDropout.SetMix(FMix);
  FDropout.SetPower(1.0 + FPower);

  FDropout.Process(Buffer);
  for Ch := 0 to Buffer.NumChannels - 1 do
    FFilt[Ch].Process(Buffer.Channels[Ch], Buffer.NumSamples);

  Inc(FSampleCounter, Buffer.NumSamples);
end;

end.
