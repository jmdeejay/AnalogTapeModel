unit ChowTape.DSP.Compression;

{ The gentle "tape compression" stage: a soft knee applied in the dB domain,
  oversampled 2x, with the slew applied to the gain rather than the level (which
  is why attack and release are swapped when the limiter is configured). }

interface

uses
  System.SysUtils, System.Math, System.Generics.Collections, ChowTape.DSP.Types,
  ChowTape.DSP.Oversampling, ChowTape.DSP.Utils, ChowTape.DSP.Basics,
  ChowTape.Params;

type
  TCompressionProcessor = class
  private
    FOnOff, FAmountParam, FAttackParam, FReleaseParam: TParameter;
    FSlewLimiter: TObjectList<TLevelDetector>;
    FBypass: TBypassProcessor;
    FOversample: TOversampling;
    FDbPlusSmooth: TSmoothedLinearArray;
    FXDBVec: array of Single;
    FCompGainVec: array of Single;
    FDoubleBuffer: TAudioBufferD;
    FNumChannels: Integer;
  public
    constructor Create(AParams: TParameterSet);
    destructor Destroy; override;
    procedure Prepare(SampleRate: Double; SamplesPerBlock, NumChannels: Integer);
    procedure ProcessBlock(Buffer: TAudioBuffer);
    function GetLatencySamples: Single;
  end;

implementation

function CompressionDB(XDB, DbPlus: Single): Single;
var
  Window: Single;
begin
  if DbPlus <= 0.0 then
    Exit(DbPlus);

  Window := 2.0 * DbPlus;
  if XDB < -Window then
    Result := DbPlus
  else
    Result := Ln(XDB + Window + 1.0) - DbPlus - XDB;
end;

constructor TCompressionProcessor.Create(AParams: TParameterSet);
begin
  inherited Create;
  FOnOff := AParams.ByID(pidCompOnOff);
  FAmountParam := AParams.ByID(pidCompAmt);
  FAttackParam := AParams.ByID(pidCompAttack);
  FReleaseParam := AParams.ByID(pidCompRelease);

  FSlewLimiter := TObjectList<TLevelDetector>.Create(True);
  FBypass := TBypassProcessor.Create;
  FDoubleBuffer := TAudioBufferD.Create;
end;

destructor TCompressionProcessor.Destroy;
begin
  FSlewLimiter.Free;
  FBypass.Free;
  FOversample.Free;
  FDoubleBuffer.Free;
  inherited Destroy;
end;

procedure TCompressionProcessor.Prepare(SampleRate: Double;
  SamplesPerBlock, NumChannels: Integer);
var
  Ch, OSFactor: Integer;
begin
  FNumChannels := NumChannels;

  FreeAndNil(FOversample);
  FOversample := TOversampling.Create(NumChannels, 1, osPolyphaseIIR, True, True);
  FOversample.InitProcessing(SamplesPerBlock);
  OSFactor := FOversample.GetOversamplingFactor;

  FBypass.Prepare(SamplesPerBlock, NumChannels, FOnOff.GetBool);

  FSlewLimiter.Clear;
  SetLength(FDbPlusSmooth, NumChannels);
  for Ch := 0 to NumChannels - 1 do
  begin
    FSlewLimiter.Add(TLevelDetector.Create);
    FSlewLimiter[Ch].Prepare(SampleRate, SamplesPerBlock);
    FDbPlusSmooth[Ch].Reset(SampleRate, 0.05);
  end;

  SetLength(FXDBVec, OSFactor * SamplesPerBlock);
  SetLength(FCompGainVec, OSFactor * SamplesPerBlock);
  FDoubleBuffer.SetSize(NumChannels, SamplesPerBlock);
end;

function TCompressionProcessor.GetLatencySamples: Single;
begin
  if FOversample = nil then
    Exit(0.0);
  if FOnOff.GetBool then
    Result := FOversample.GetLatencyInSamples
  else
    Result := 0.0;
end;

procedure TCompressionProcessor.ProcessBlock(Buffer: TAudioBuffer);
var
  OSBlock: TAudioBufferD;
  NumSamples, Ch, N: Integer;
  X: PDoubleBuf;
  CompDB, G: Single;
begin
  if not FBypass.ProcessBlockIn(Buffer, FOnOff.GetBool) then
    Exit;

  FDoubleBuffer.CopyFromFloat(Buffer);
  OSBlock := FOversample.ProcessSamplesUp(FDoubleBuffer);
  NumSamples := OSBlock.NumSamples;

  for Ch := 0 to Buffer.NumChannels - 1 do
  begin
    FDbPlusSmooth[Ch].SetTargetValue(FAmountParam.GetValue);

    X := PDoubleBuf(OSBlock.Channels[Ch]);

    for N := 0 to NumSamples - 1 do
    begin
      FXDBVec[N] := GainToDecibels(Abs(X^[N]));
      CompDB := CompressionDB(FXDBVec[N], FDbPlusSmooth[Ch].GetNextValue);
      FCompGainVec[N] := DecibelsToGain(CompDB);
    end;

    // the slew acts on the gain, so attack and release swap over
    FSlewLimiter[Ch].SetParameters(FReleaseParam.GetValue, FAttackParam.GetValue);
    for N := 0 to NumSamples - 1 do
    begin
      G := FSlewLimiter[Ch].ProcessSample(FCompGainVec[N]);
      if G < FCompGainVec[N] then
        FCompGainVec[N] := G;
    end;

    for N := 0 to NumSamples - 1 do
      X^[N] := X^[N] * FCompGainVec[N];
  end;

  FDoubleBuffer.NumSamples := Buffer.NumSamples;
  FOversample.ProcessSamplesDown(FDoubleBuffer);
  FDoubleBuffer.CopyToFloat(Buffer);

  FBypass.ProcessBlockOut(Buffer, FOnOff.GetBool);
end;

end.
