unit ChowTape.DSP.Basics;

{ Gain, dry/wet mixing and the smooth-bypass helper used by every processor. }

interface

uses
  System.Math, ChowTape.DSP.Types;

type
  TGainProcessor = class
  private
    FCurGain: Single;
    FOldGain: Single;
  public
    constructor Create;
    procedure PrepareToPlay;
    procedure ProcessBlock(Buffer: TAudioBuffer);
    procedure SetGain(Gain: Single);
    function GetGain: Single; inline;
  end;

  { juce::dsp::Gain -- a per-sample ramped gain. }
  TSmoothGain = class
  private
    FGain: TSmoothedValueLinear;
  public
    procedure Prepare(SampleRate: Double; RampSeconds: Double);
    procedure SetGainLinear(NewGain: Single);
    procedure SetGainDecibels(NewGainDb: Single);
    procedure ProcessChannel(Data: PSingle; NumSamples: Integer);
  end;

  TDryWetProcessor = class
  private
    FDryWet: Single;
    FLastDryWet: Single;
  public
    constructor Create;
    procedure SetDryWet(NewDryWet: Single); inline;
    function GetDryWet: Single; inline;
    procedure Reset;
    { Mixes DryBuffer into WetBuffer in place. }
    procedure ProcessBlock(DryBuffer, WetBuffer: TAudioBuffer);
  end;

  { Crossfades a processor in and out so toggling it never clicks. }
  TBypassProcessor = class
  private
    FPrevOnOff: Boolean;
    FBufferCopied: Boolean;
    FFadeBuffer: TAudioBuffer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Prepare(SamplesPerBlock, NumChannels: Integer; OnOff: Boolean);
    { Returns False when the processor can be skipped entirely. }
    function ProcessBlockIn(Block: TAudioBuffer; OnOff: Boolean): Boolean;
    procedure ProcessBlockOut(Block: TAudioBuffer; OnOff: Boolean);
  end;

implementation

{ TGainProcessor }

constructor TGainProcessor.Create;
begin
  inherited Create;
  FCurGain := 1.0;
  FOldGain := 0.0;
end;

procedure TGainProcessor.PrepareToPlay;
begin
  FOldGain := FCurGain;
end;

procedure TGainProcessor.ProcessBlock(Buffer: TAudioBuffer);
begin
  if FCurGain <> FOldGain then
  begin
    Buffer.ApplyGainRamp(0, Buffer.NumSamples, FOldGain, FCurGain);
    FOldGain := FCurGain;
    Exit;
  end;
  Buffer.ApplyGain(FCurGain);
end;

procedure TGainProcessor.SetGain(Gain: Single);
begin
  if Gain = FCurGain then
    Exit;
  FOldGain := FCurGain;
  FCurGain := Gain;
end;

function TGainProcessor.GetGain: Single;
begin
  Result := FCurGain;
end;

{ TSmoothGain }

procedure TSmoothGain.Prepare(SampleRate, RampSeconds: Double);
begin
  FGain.SetCurrentAndTargetValue(1.0);
  FGain.Reset(SampleRate, RampSeconds);
end;

procedure TSmoothGain.SetGainLinear(NewGain: Single);
begin
  FGain.SetTargetValue(NewGain);
end;

procedure TSmoothGain.SetGainDecibels(NewGainDb: Single);
begin
  SetGainLinear(DecibelsToGain(NewGainDb));
end;

procedure TSmoothGain.ProcessChannel(Data: PSingle; NumSamples: Integer);
var
  N: Integer;
  P: PSingleArray;
  G: Single;
begin
  P := PSingleArray(Data);
  if not FGain.IsSmoothing then
  begin
    G := FGain.GetTargetValue;
    if G = 1.0 then
      Exit;
    for N := 0 to NumSamples - 1 do
      P^[N] := P^[N] * G;
  end
  else
  begin
    for N := 0 to NumSamples - 1 do
      P^[N] := P^[N] * FGain.GetNextValue;
  end;
end;

{ TDryWetProcessor }

constructor TDryWetProcessor.Create;
begin
  inherited Create;
  FDryWet := 0.0;
  FLastDryWet := 0.0;
end;

procedure TDryWetProcessor.SetDryWet(NewDryWet: Single);
begin
  FDryWet := NewDryWet;
end;

function TDryWetProcessor.GetDryWet: Single;
begin
  Result := FDryWet;
end;

procedure TDryWetProcessor.Reset;
begin
  FLastDryWet := FDryWet;
end;

procedure TDryWetProcessor.ProcessBlock(DryBuffer, WetBuffer: TAudioBuffer);
var
  Ch: Integer;
begin
  if FLastDryWet = FDryWet then
  begin
    WetBuffer.ApplyGain(FDryWet);
    for Ch := 0 to WetBuffer.NumChannels - 1 do
      WetBuffer.AddFrom(Ch, 0, DryBuffer.Channels[Ch], WetBuffer.NumSamples, 1.0 - FDryWet);
  end
  else
  begin
    for Ch := 0 to WetBuffer.NumChannels - 1 do
    begin
      WetBuffer.ApplyGainRamp(Ch, 0, WetBuffer.NumSamples, FLastDryWet, FDryWet);
      WetBuffer.AddFromWithRamp(Ch, 0, DryBuffer.Channels[Ch], WetBuffer.NumSamples,
        1.0 - FLastDryWet, 1.0 - FDryWet);
    end;
    FLastDryWet := FDryWet;
  end;
end;

{ TBypassProcessor }

constructor TBypassProcessor.Create;
begin
  inherited Create;
  FFadeBuffer := TAudioBuffer.Create;
  FPrevOnOff := False;
  FBufferCopied := False;
end;

destructor TBypassProcessor.Destroy;
begin
  FFadeBuffer.Free;
  inherited Destroy;
end;

procedure TBypassProcessor.Prepare(SamplesPerBlock, NumChannels: Integer; OnOff: Boolean);
begin
  FPrevOnOff := OnOff;
  FFadeBuffer.SetSize(NumChannels, SamplesPerBlock);
  FBufferCopied := False;
end;

function TBypassProcessor.ProcessBlockIn(Block: TAudioBuffer; OnOff: Boolean): Boolean;
begin
  if (not OnOff) and (not FPrevOnOff) then
    Exit(False);

  if OnOff <> FPrevOnOff then
  begin
    FFadeBuffer.CopyFrom(Block, True);
    FBufferCopied := True;
  end;

  Result := True;
end;

procedure TBypassProcessor.ProcessBlockOut(Block: TAudioBuffer; OnOff: Boolean);
var
  Ch, NumSamples: Integer;
  StartGain, EndGain: Single;
begin
  if OnOff = FPrevOnOff then
    Exit;

  // The parameter changed mid-buffer; wait for the next one.
  if not FBufferCopied then
    Exit;

  NumSamples := Block.NumSamples;

  if not OnOff then
    StartGain := 1.0   // fade out
  else
    StartGain := 0.0;  // fade in
  EndGain := 1.0 - StartGain;

  Block.ApplyGainRamp(0, NumSamples, StartGain, EndGain);
  for Ch := 0 to Block.NumChannels - 1 do
    Block.AddFromWithRamp(Ch, 0, FFadeBuffer.Channels[Ch], NumSamples,
      1.0 - StartGain, 1.0 - EndGain);

  FPrevOnOff := OnOff;
  FBufferCopied := False;
end;

end.
