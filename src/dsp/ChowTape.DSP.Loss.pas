unit ChowTape.DSP.Loss;

{ Playhead loss effects.

  A linear-phase FIR is designed on the fly from the physical spacing /
  thickness / gap losses, followed by a "head bump" peaking filter and an
  azimuth misalignment delay. Two filter instances are kept so a parameter
  change can be crossfaded instead of clicking. }

interface

uses
  System.Math, ChowTape.DSP.Types, ChowTape.DSP.Filters, ChowTape.DSP.DelayLine,
  ChowTape.DSP.Basics, ChowTape.Params;

type
  TAzimuthProc = class
  private
    FDelays: array[0..1] of TDelayLine;
    FDelaySampSmooth: array[0..1] of TSmoothedValueLinear;
    FFs: Single;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Prepare(SampleRate: Double; SamplesPerBlock: Integer);
    procedure SetAzimuthAngle(AngleDeg, TapeSpeedIps: Single);
    procedure ProcessBlock(Buffer: TAudioBuffer);
  end;

  TLossFilter = class
  private
    FOnOff, FSpeed, FSpacing, FThickness, FGap, FAzimuth: TParameter;

    FFilters: array[0..1] of TFIRFilter;
    FBumpFilter: array[0..1] of TMultiChannelBiquad;
    FActiveFilter: Integer;
    FFadeCount: Integer;
    FFadeLength: Integer;
    FFadeBuffer: TAudioBuffer;

    FPrevSpeed, FPrevSpacing, FPrevThickness, FPrevGap: Single;

    FFs: Single;
    FFsFactor: Single;
    FBinWidth: Single;

    FOrder: Integer;
    FCurOrder: Integer;
    FCurrentCoefs: TFloatArray;
    FHCoefs: TFloatArray;

    FAzimuthProc: TAzimuthProc;
    FBypass: TBypassProcessor;

    procedure CalcCoefs(Filter: TMultiChannelBiquad);
    procedure CalcHeadBumpFilter(SpeedIps, GapMeters: Single; Fs: Double;
      Filter: TMultiChannelBiquad);
  public
    constructor Create(AParams: TParameterSet; AOrder: Integer = 64);
    destructor Destroy; override;
    procedure Prepare(SampleRate: Single; SamplesPerBlock, NumChannels: Integer);
    procedure ProcessBlock(Buffer: TAudioBuffer);
    function GetLatencySamples: Single;
  end;

implementation

{ TAzimuthProc }

function Inches2Meters(Inches: Single): Single; inline;
begin
  Result := Inches / 39.370078740157;
end;

function Deg2Rad(Deg: Single): Single; inline;
begin
  Result := Deg * PiS / 180.0;
end;

const
  TapeWidthMeters = 0.25 / 39.370078740157;

constructor TAzimuthProc.Create;
begin
  inherited Create;
  FFs := 48000.0;
end;

destructor TAzimuthProc.Destroy;
var
  I: Integer;
begin
  for I := 0 to 1 do
    FDelays[I].Free;
  inherited Destroy;
end;

procedure TAzimuthProc.Prepare(SampleRate: Double; SamplesPerBlock: Integer);
var
  Ch: Integer;
begin
  FFs := SampleRate;

  for Ch := 0 to 1 do
  begin
    FDelays[Ch].Free;
    FDelays[Ch] := TDelayLine.Create(1 shl 18, diLagrange3rd);
    FDelays[Ch].Prepare(1);
    FDelaySampSmooth[Ch].Reset(SampleRate, 0.05);
  end;
end;

procedure TAzimuthProc.SetAzimuthAngle(AngleDeg, TapeSpeedIps: Single);
var
  DelayIdx: Integer;
  TapeSpeed, AzimuthAngle, DelayDist, DelaySamp: Single;
begin
  DelayIdx := Ord(AngleDeg < 0.0);
  TapeSpeed := Inches2Meters(TapeSpeedIps);
  AzimuthAngle := Deg2Rad(Abs(AngleDeg));

  DelayDist := TapeWidthMeters * Sin(AzimuthAngle);
  DelaySamp := (DelayDist * TapeSpeed) * FFs;

  FDelaySampSmooth[DelayIdx].SetTargetValue(DelaySamp);
  FDelaySampSmooth[1 - DelayIdx].SetTargetValue(0.0);
end;

procedure TAzimuthProc.ProcessBlock(Buffer: TAudioBuffer);
var
  Ch, N: Integer;
  X: PSingleArray;
begin
  if Buffer.NumChannels <> 2 then
    Exit;

  for Ch := 0 to 1 do
  begin
    X := PSingleArray(Buffer.Channels[Ch]);
    if FDelaySampSmooth[Ch].IsSmoothing then
    begin
      for N := 0 to Buffer.NumSamples - 1 do
      begin
        FDelays[Ch].SetDelay(FDelaySampSmooth[Ch].GetNextValue);
        FDelays[Ch].PushSample(0, X^[N]);
        X^[N] := FDelays[Ch].PopSample(0);
      end;
    end
    else
    begin
      for N := 0 to Buffer.NumSamples - 1 do
      begin
        FDelays[Ch].PushSample(0, X^[N]);
        X^[N] := FDelays[Ch].PopSample(0);
      end;
    end;
  end;
end;

{ TLossFilter }

constructor TLossFilter.Create(AParams: TParameterSet; AOrder: Integer);
var
  I: Integer;
begin
  inherited Create;
  FSpeed := AParams.ByID(pidSpeed);
  FSpacing := AParams.ByID(pidSpacing);
  FThickness := AParams.ByID(pidThick);
  FGap := AParams.ByID(pidGap);
  FAzimuth := AParams.ByID(pidAzimuth);
  FOnOff := AParams.ByID(pidLossOnOff);

  FOrder := AOrder;
  FCurOrder := AOrder;
  FFs := 44100.0;
  FFsFactor := 1.0;
  FActiveFilter := 0;
  FFadeCount := 0;
  FFadeLength := 1024;

  for I := 0 to 1 do
  begin
    FFilters[I] := TFIRFilter.Create(AOrder);
    FBumpFilter[I] := TMultiChannelBiquad.Create;
  end;

  FFadeBuffer := TAudioBuffer.Create;
  FAzimuthProc := TAzimuthProc.Create;
  FBypass := TBypassProcessor.Create;
end;

destructor TLossFilter.Destroy;
var
  I: Integer;
begin
  for I := 0 to 1 do
  begin
    FFilters[I].Free;
    FBumpFilter[I].Free;
  end;
  FFadeBuffer.Free;
  FAzimuthProc.Free;
  FBypass.Free;
  inherited Destroy;
end;

function TLossFilter.GetLatencySamples: Single;
begin
  if FOnOff.GetBool then
    Result := FCurOrder / 2.0
  else
    Result := 0.0;
end;

procedure TLossFilter.Prepare(SampleRate: Single; SamplesPerBlock, NumChannels: Integer);
var
  I: Integer;
begin
  FFs := SampleRate;
  FFadeBuffer.SetSize(NumChannels, SamplesPerBlock);
  FFadeLength := Max(1024, SamplesPerBlock);

  FFsFactor := FFs / 44100.0;
  FCurOrder := Trunc(FOrder * FFsFactor);
  SetLength(FCurrentCoefs, FCurOrder);
  SetLength(FHCoefs, FCurOrder);

  for I := 0 to 1 do
  begin
    FBumpFilter[I].Prepare(NumChannels);
    FBumpFilter[I].Reset;
  end;
  CalcCoefs(FBumpFilter[FActiveFilter]);

  for I := 0 to 1 do
  begin
    FFilters[I].SetOrder(FCurOrder);
    FFilters[I].Prepare(NumChannels);
    FFilters[I].SetCoefficients(@FCurrentCoefs[0]);
  end;

  FPrevSpeed := FSpeed.GetValue;
  FPrevSpacing := FSpacing.GetValue;
  FPrevThickness := FThickness.GetValue;
  FPrevGap := FGap.GetValue;

  FAzimuthProc.Prepare(SampleRate, SamplesPerBlock);
  FBypass.Prepare(SamplesPerBlock, NumChannels, FOnOff.GetBool);
end;

procedure TLossFilter.CalcHeadBumpFilter(SpeedIps, GapMeters: Single; Fs: Double;
  Filter: TMultiChannelBiquad);
var
  BumpFreq, Gain: Single;
begin
  BumpFreq := SpeedIps * 0.0254 / (GapMeters * 500.0);
  Gain := JMaxF(1.5 * (1000.0 - Abs(BumpFreq - 100.0)) / 1000.0, 1.0);
  Filter.MakePeakFilter(Fs, BumpFreq, 2.0, Gain);
end;

procedure TLossFilter.CalcCoefs(Filter: TMultiChannelBiquad);
var
  K, N, Idx: Integer;
  Freq, WaveNumber, ThickTimesK, KGapOverTwo: Single;
  SpeedVal, SpacingVal, ThickVal, GapVal: Single;
  Acc: Single;
begin
  SpeedVal := FSpeed.GetValue;
  SpacingVal := FSpacing.GetValue;
  ThickVal := FThickness.GetValue;
  GapVal := FGap.GetValue;

  // frequency-domain magnitude response
  FBinWidth := FFs / FCurOrder;
  for K := 0 to FCurOrder div 2 - 1 do
  begin
    Freq := K * FBinWidth;
    WaveNumber := TwoPiS * JMaxF(Freq, 20.0) / (SpeedVal * 0.0254);
    ThickTimesK := WaveNumber * (ThickVal * 1.0e-6);
    KGapOverTwo := WaveNumber * (GapVal * 1.0e-6) / 2.0;

    FHCoefs[K] := Exp(-WaveNumber * (SpacingVal * 1.0e-6));      // spacing loss
    FHCoefs[K] := FHCoefs[K] * (1.0 - Exp(-ThickTimesK)) / ThickTimesK;  // thickness loss
    FHCoefs[K] := FHCoefs[K] * Sin(KGapOverTwo) / KGapOverTwo;   // gap loss
    FHCoefs[FCurOrder - K - 1] := FHCoefs[K];
  end;

  // inverse DFT into a symmetric linear-phase impulse response
  for N := 0 to FCurOrder - 1 do
    FCurrentCoefs[N] := 0.0;

  for N := 0 to FCurOrder div 2 - 1 do
  begin
    Idx := FCurOrder div 2 + N;
    Acc := 0.0;
    for K := 0 to FCurOrder - 1 do
      Acc := Acc + FHCoefs[K] * Cos(TwoPiS * K * N / FCurOrder);

    Acc := Acc / FCurOrder;
    FCurrentCoefs[Idx] := Acc;
    FCurrentCoefs[FCurOrder div 2 - N] := Acc;
  end;

  CalcHeadBumpFilter(SpeedVal, GapVal * 1.0e-6, FFs, Filter);
end;

procedure TLossFilter.ProcessBlock(Buffer: TAudioBuffer);
var
  NumChannels, NumSamples, Ch, Other: Integer;
  StartGain, EndGain: Single;
  SamplesToFade: Integer;
begin
  NumChannels := Buffer.NumChannels;
  NumSamples := Buffer.NumSamples;

  if not FBypass.ProcessBlockIn(Buffer, FOnOff.GetBool) then
    Exit;

  Other := 1 - FActiveFilter;

  if ((FSpeed.GetValue <> FPrevSpeed) or (FSpacing.GetValue <> FPrevSpacing) or
      (FThickness.GetValue <> FPrevThickness) or (FGap.GetValue <> FPrevGap)) and
     (FFadeCount = 0) then
  begin
    CalcCoefs(FBumpFilter[Other]);
    FFilters[Other].SetCoefficients(@FCurrentCoefs[0]);
    FBumpFilter[Other].Reset;

    FFadeCount := FFadeLength;
    FPrevSpeed := FSpeed.GetValue;
    FPrevSpacing := FSpacing.GetValue;
    FPrevThickness := FThickness.GetValue;
    FPrevGap := FGap.GetValue;
  end;

  if FFadeCount > 0 then
    FFadeBuffer.CopyFrom(Buffer, True)
  else
    FFilters[Other].ProcessBufferBypassed(Buffer);

  FFilters[FActiveFilter].ProcessBuffer(Buffer);
  FBumpFilter[FActiveFilter].ProcessBuffer(Buffer);

  if FFadeCount > 0 then
  begin
    FFilters[Other].ProcessBuffer(FFadeBuffer);
    FBumpFilter[Other].ProcessBuffer(FFadeBuffer);

    StartGain := FFadeCount / FFadeLength;
    SamplesToFade := Min(FFadeCount, NumSamples);
    Dec(FFadeCount, SamplesToFade);
    EndGain := FFadeCount / FFadeLength;

    Buffer.ApplyGainRamp(0, SamplesToFade, StartGain, EndGain);
    Buffer.ApplyGain(SamplesToFade, NumSamples - SamplesToFade, EndGain);

    for Ch := 0 to NumChannels - 1 do
      Buffer.AddFromWithRamp(Ch, 0, FFadeBuffer.Channels[Ch], SamplesToFade,
        1.0 - StartGain, 1.0 - EndGain);

    if FFadeCount = 0 then
      FActiveFilter := 1 - FActiveFilter;
  end;

  FAzimuthProc.SetAzimuthAngle(FAzimuth.GetValue, FSpeed.GetValue);
  FAzimuthProc.ProcessBlock(Buffer);

  FBypass.ProcessBlockOut(Buffer, FOnOff.GetBool);
end;

end.
