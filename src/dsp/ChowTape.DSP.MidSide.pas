unit ChowTape.DSP.MidSide;

{ Optional mid/side encoding around the tape chain, plus a stereo balance
  control that can be undone at the output. }

interface

uses
  System.Math, ChowTape.DSP.Types, ChowTape.DSP.Basics, ChowTape.Params;

type
  TMidSideProcessor = class
  private
    FMidSideParam, FBalanceParam, FMakeupParam: TParameter;
    FCurMS: Boolean;
    FPrevMS: Boolean;
    FFadeSmooth: TSmoothedValueLinear;
    FInBalanceGain: array[0..1] of TSmoothGain;
    FOutBalanceGain: array[0..1] of TSmoothGain;
  public
    constructor Create(AParams: TParameterSet);
    destructor Destroy; override;
    procedure Prepare(SampleRate: Double; SamplesPerBlock: Integer);
    procedure ProcessInput(Buffer: TAudioBuffer);
    procedure ProcessOutput(Buffer: TAudioBuffer);
  end;

implementation

const
  BalanceGainDb = 6.0;

constructor TMidSideProcessor.Create(AParams: TParameterSet);
var
  I: Integer;
begin
  inherited Create;
  FMidSideParam := AParams.ByID(pidMidSide);
  FBalanceParam := AParams.ByID(pidStereoBalance);
  FMakeupParam := AParams.ByID(pidStereoMakeup);
  for I := 0 to 1 do
  begin
    FInBalanceGain[I] := TSmoothGain.Create;
    FOutBalanceGain[I] := TSmoothGain.Create;
  end;
end;

destructor TMidSideProcessor.Destroy;
var
  I: Integer;
begin
  for I := 0 to 1 do
  begin
    FInBalanceGain[I].Free;
    FOutBalanceGain[I].Free;
  end;
  inherited Destroy;
end;

procedure TMidSideProcessor.Prepare(SampleRate: Double; SamplesPerBlock: Integer);
var
  I: Integer;
begin
  FFadeSmooth.Reset(SampleRate, 0.04);

  for I := 0 to 1 do
  begin
    FInBalanceGain[I].Prepare(SampleRate, 0.05);
    FOutBalanceGain[I].Prepare(SampleRate, 0.05);
  end;

  FCurMS := FMidSideParam.GetBool;
  FPrevMS := FCurMS;
end;

procedure TMidSideProcessor.ProcessInput(Buffer: TAudioBuffer);
var
  NumSamples: Integer;
  CurBalance: Single;
begin
  if Buffer.NumChannels <> 2 then
    Exit;

  NumSamples := Buffer.NumSamples;

  if FCurMS then
  begin
    // ch0 = L + R = mid, ch1 = L - R = side
    Buffer.AddFrom(0, 0, Buffer, 1, 0, NumSamples);
    Buffer.ApplyGain(1, 0, NumSamples, 2.0);
    Buffer.AddFrom(1, 0, Buffer, 0, 0, NumSamples, -1.0);
    Buffer.ApplyGain(1, 0, NumSamples, -1.0);

    Buffer.ApplyGain(DecibelsToGain(-3.0)); // normalisation
  end;

  CurBalance := FBalanceParam.GetValue;

  FInBalanceGain[0].SetGainDecibels(CurBalance * BalanceGainDb);
  FInBalanceGain[0].ProcessChannel(Buffer.Channels[0], NumSamples);

  FInBalanceGain[1].SetGainDecibels(CurBalance * -BalanceGainDb);
  FInBalanceGain[1].ProcessChannel(Buffer.Channels[1], NumSamples);
end;

procedure TMidSideProcessor.ProcessOutput(Buffer: TAudioBuffer);
var
  NumSamples: Integer;
  CurBalance, StartGain, EndGain: Single;
begin
  if Buffer.NumChannels <> 2 then
    Exit;

  NumSamples := Buffer.NumSamples;

  if (FPrevMS <> FMidSideParam.GetBool) and (not FFadeSmooth.IsSmoothing) then
  begin
    FFadeSmooth.SetCurrentAndTargetValue(1.0);
    FFadeSmooth.SetTargetValue(0.0);
  end;

  if FMakeupParam.GetBool then
  begin
    CurBalance := FBalanceParam.GetValue;

    FOutBalanceGain[0].SetGainDecibels(CurBalance * -BalanceGainDb);
    FOutBalanceGain[0].ProcessChannel(Buffer.Channels[0], NumSamples);

    FOutBalanceGain[1].SetGainDecibels(CurBalance * BalanceGainDb);
    FOutBalanceGain[1].ProcessChannel(Buffer.Channels[1], NumSamples);
  end;

  if FCurMS then
  begin
    Buffer.ApplyGain(DecibelsToGain(3.0)); // undo normalisation

    Buffer.ApplyGain(1, 0, NumSamples, -1.0);
    Buffer.AddFrom(0, 0, Buffer, 1, 0, NumSamples, -1.0);
    Buffer.ApplyGain(0, 0, NumSamples, 0.5);
    Buffer.AddFrom(1, 0, Buffer, 0, 0, NumSamples);
  end;

  if FFadeSmooth.IsSmoothing then
  begin
    StartGain := FFadeSmooth.GetCurrentValue;
    EndGain := FFadeSmooth.Skip(NumSamples);

    Buffer.ApplyGainRamp(0, NumSamples, StartGain, EndGain);

    if EndGain = 0.0 then
    begin
      FFadeSmooth.SetTargetValue(1.0);

      // flip mode at the bottom of the fade
      FCurMS := FMidSideParam.GetBool;
      FPrevMS := FCurMS;
    end;
  end;
end;

end.
