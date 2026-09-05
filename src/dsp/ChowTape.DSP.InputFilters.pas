unit ChowTape.DSP.InputFilters;

{ Pre-processing low/high cut filters, with an optional "makeup" path that adds
  the removed signal back in after the tape stage. }

interface

uses
  System.Math, ChowTape.DSP.Types, ChowTape.DSP.Filters, ChowTape.DSP.DelayLine,
  ChowTape.DSP.Basics, ChowTape.Params;

type
  TInputFilters = class
  private
    FParams: TParameterSet;
    FOnOff, FMakeup: TParameter;
    FLowCut, FHighCut: TParameter;

    FFs: Single;
    FLowCutFilter: TLinkwitzRileyFilter;
    FHighCutFilter: TLinkwitzRileyFilter;
    FMakeupDelay: TDelayLine;

    FLowCutBuffer, FHighCutBuffer, FMakeupBuffer: TAudioBuffer;
    FBypass, FMakeupBypass: TBypassProcessor;
  public
    constructor Create(AParams: TParameterSet);
    destructor Destroy; override;

    procedure PrepareToPlay(SampleRate: Double; SamplesPerBlock, NumChannels: Integer);
    procedure SetMakeupDelay(NewDelaySamples: Single);
    procedure ProcessBlock(Buffer: TAudioBuffer);
    procedure ProcessBlockMakeup(Buffer: TAudioBuffer);
  end;

implementation

constructor TInputFilters.Create(AParams: TParameterSet);
begin
  inherited Create;
  FParams := AParams;
  FOnOff := AParams.ByID(pidIFiltOnOff);
  FMakeup := AParams.ByID(pidIFiltMakeup);
  FLowCut := AParams.ByID(pidIFiltLow);
  FHighCut := AParams.ByID(pidIFiltHigh);

  FLowCutFilter := TLinkwitzRileyFilter.Create;
  FHighCutFilter := TLinkwitzRileyFilter.Create;
  FMakeupDelay := TDelayLine.Create(1 shl 21, diLagrange3rd);

  FLowCutBuffer := TAudioBuffer.Create;
  FHighCutBuffer := TAudioBuffer.Create;
  FMakeupBuffer := TAudioBuffer.Create;

  FBypass := TBypassProcessor.Create;
  FMakeupBypass := TBypassProcessor.Create;
end;

destructor TInputFilters.Destroy;
begin
  FLowCutFilter.Free;
  FHighCutFilter.Free;
  FMakeupDelay.Free;
  FLowCutBuffer.Free;
  FHighCutBuffer.Free;
  FMakeupBuffer.Free;
  FBypass.Free;
  FMakeupBypass.Free;
  inherited Destroy;
end;

procedure TInputFilters.PrepareToPlay(SampleRate: Double;
  SamplesPerBlock, NumChannels: Integer);
begin
  FFs := SampleRate;

  FLowCutFilter.Prepare(SampleRate, NumChannels);
  FHighCutFilter.Prepare(SampleRate, NumChannels);
  FMakeupDelay.Prepare(NumChannels);

  FLowCutBuffer.SetSize(NumChannels, SamplesPerBlock);
  FHighCutBuffer.SetSize(NumChannels, SamplesPerBlock);
  FMakeupBuffer.SetSize(NumChannels, SamplesPerBlock);

  FBypass.Prepare(SamplesPerBlock, NumChannels, FOnOff.GetBool);
  FMakeupBypass.Prepare(SamplesPerBlock, NumChannels, FOnOff.GetBool);
end;

procedure TInputFilters.SetMakeupDelay(NewDelaySamples: Single);
begin
  FMakeupDelay.SetDelay(NewDelaySamples);
end;

procedure TInputFilters.ProcessBlock(Buffer: TAudioBuffer);
var
  Ch, N: Integer;
  Data, CutLow, CutHigh: PSingleArray;
  Low, High: Single;
begin
  if not FBypass.ProcessBlockIn(Buffer, FOnOff.GetBool) then
    Exit;

  FLowCutFilter.SetCutoff(FLowCut.GetValue);
  FHighCutFilter.SetCutoff(JMinF(FHighCut.GetValue, FFs * 0.48));

  for Ch := 0 to Buffer.NumChannels - 1 do
  begin
    Data := PSingleArray(Buffer.Channels[Ch]);
    CutLow := PSingleArray(FLowCutBuffer.Channels[Ch]);
    CutHigh := PSingleArray(FHighCutBuffer.Channels[Ch]);

    for N := 0 to Buffer.NumSamples - 1 do
    begin
      FLowCutFilter.ProcessSample(Ch, Data^[N], Low, High);
      CutLow^[N] := Low;
      Data^[N] := High;

      FHighCutFilter.ProcessSample(Ch, Data^[N], Low, High);
      Data^[N] := Low;
      CutHigh^[N] := High;
    end;
  end;

  FBypass.ProcessBlockOut(Buffer, FOnOff.GetBool);

  FLowCutFilter.SnapToZeroState;
  FHighCutFilter.SnapToZeroState;
end;

procedure TInputFilters.ProcessBlockMakeup(Buffer: TAudioBuffer);
var
  Ch, N: Integer;
  M, L, H, Out_: PSingleArray;
begin
  if not FMakeupBypass.ProcessBlockIn(Buffer, FOnOff.GetBool) then
    Exit;

  if not FMakeup.GetBool then
  begin
    FMakeupBypass.ProcessBlockOut(Buffer, FOnOff.GetBool);
    Exit;
  end;

  FMakeupBuffer.SetSize(Buffer.NumChannels, Buffer.NumSamples, False, False, True);

  // sum of what the two cut filters removed
  for Ch := 0 to Buffer.NumChannels - 1 do
  begin
    M := PSingleArray(FMakeupBuffer.Channels[Ch]);
    L := PSingleArray(FLowCutBuffer.Channels[Ch]);
    H := PSingleArray(FHighCutBuffer.Channels[Ch]);
    for N := 0 to Buffer.NumSamples - 1 do
      M^[N] := L^[N] + H^[N];
  end;

  // delay it so it lines up with the processed signal
  FMakeupDelay.ProcessBuffer(FMakeupBuffer);

  for Ch := 0 to Buffer.NumChannels - 1 do
  begin
    M := PSingleArray(FMakeupBuffer.Channels[Ch]);
    Out_ := PSingleArray(Buffer.Channels[Ch]);
    for N := 0 to Buffer.NumSamples - 1 do
      Out_^[N] := Out_^[N] + M^[N];
  end;

  FMakeupBypass.ProcessBlockOut(Buffer, FOnOff.GetBool);
end;

end.
