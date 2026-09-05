unit ChowTape.DSP.ToneControl;

{ Pre/post-emphasis shelving EQ around the hysteresis stage. The output stage
  applies the inverse of the input stage, so the tone controls change how hard
  each band drives the tape rather than the overall response. }

interface

uses
  System.Math, System.Generics.Collections, ChowTape.DSP.Types,
  ChowTape.DSP.Filters, ChowTape.Params;

const
  ToneTransFreq = 500.0;

type
  TToneStage = class
  private
    FTone: TObjectList<TShelfFilter>;
    FLowGain, FHighGain, FTFreq: TSmoothedMulArray;
    FFs: Single;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Prepare(SampleRate: Double; NumChannels: Integer);
    procedure ProcessBlock(Buffer: TAudioBuffer);
    procedure SetLowGain(LowGainDB: Single);
    procedure SetHighGain(HighGainDB: Single);
    procedure SetTransFreq(NewTFreq: Single);
  end;

  TToneControl = class
  private
    FToneIn, FToneOut: TToneStage;
    FOnOffParam, FBassParam, FTrebleParam, FTFreqParam: TParameter;
    FDBScale: Single;
  public
    constructor Create(AParams: TParameterSet);
    destructor Destroy; override;
    procedure Prepare(SampleRate: Double; NumChannels: Integer);
    procedure SetDBScale(NewDBScale: Single);
    procedure ProcessBlockIn(Buffer: TAudioBuffer);
    procedure ProcessBlockOut(Buffer: TAudioBuffer);
  end;

implementation

const
  SlewTime = 0.05;

{ TToneStage }

constructor TToneStage.Create;
begin
  inherited Create;
  FTone := TObjectList<TShelfFilter>.Create(True);
  FFs := 44100.0;
end;

destructor TToneStage.Destroy;
begin
  FTone.Free;
  inherited Destroy;
end;

procedure TToneStage.Prepare(SampleRate: Double; NumChannels: Integer);
var
  Ch: Integer;
  Filt: TShelfFilter;
begin
  FFs := SampleRate;

  FTone.Clear;
  SetLength(FLowGain, NumChannels);
  SetLength(FHighGain, NumChannels);
  SetLength(FTFreq, NumChannels);

  for Ch := 0 to NumChannels - 1 do
  begin
    FLowGain[Ch].Reset(SampleRate, SlewTime);
    FLowGain[Ch].SetCurrentAndTargetValue(1.0);

    FHighGain[Ch].Reset(SampleRate, SlewTime);
    FHighGain[Ch].SetCurrentAndTargetValue(1.0);

    FTFreq[Ch].Reset(SampleRate, SlewTime);
    FTFreq[Ch].SetCurrentAndTargetValue(ToneTransFreq);

    Filt := TShelfFilter.Create;
    Filt.Prepare(1);
    Filt.Reset;
    Filt.CalcCoefs(FLowGain[Ch].GetTargetValue, FHighGain[Ch].GetTargetValue,
      FTFreq[Ch].GetTargetValue, FFs);
    FTone.Add(Filt);
  end;
end;

procedure SetSmoothValues(var Values: TSmoothedMulArray; NewValue: Single);
var
  I: Integer;
begin
  if Length(Values) = 0 then
    Exit;
  if NewValue = Values[0].GetTargetValue then
    Exit;
  for I := 0 to High(Values) do
    Values[I].SetTargetValue(NewValue);
end;

procedure TToneStage.SetLowGain(LowGainDB: Single);
begin
  SetSmoothValues(FLowGain, DecibelsToGain(LowGainDB));
end;

procedure TToneStage.SetHighGain(HighGainDB: Single);
begin
  SetSmoothValues(FHighGain, DecibelsToGain(HighGainDB));
end;

procedure TToneStage.SetTransFreq(NewTFreq: Single);
begin
  SetSmoothValues(FTFreq, NewTFreq);
end;

procedure TToneStage.ProcessBlock(Buffer: TAudioBuffer);
var
  Ch, N: Integer;
  Data: PSingleArray;
begin
  for Ch := 0 to Buffer.NumChannels - 1 do
  begin
    Data := PSingleArray(Buffer.Channels[Ch]);

    if FLowGain[Ch].IsSmoothing or FHighGain[Ch].IsSmoothing or FTFreq[Ch].IsSmoothing then
    begin
      for N := 0 to Buffer.NumSamples - 1 do
      begin
        FTone[Ch].CalcCoefs(FLowGain[Ch].GetNextValue, FHighGain[Ch].GetNextValue,
          FTFreq[Ch].GetNextValue, FFs);
        Data^[N] := FTone[Ch].ProcessSample(Data^[N]);
      end;
    end
    else
      FTone[Ch].ProcessBlock(Buffer.Channels[Ch], Buffer.NumSamples);
  end;
end;

{ TToneControl }

constructor TToneControl.Create(AParams: TParameterSet);
begin
  inherited Create;
  FToneIn := TToneStage.Create;
  FToneOut := TToneStage.Create;
  FOnOffParam := AParams.ByID(pidToneOnOff);
  FBassParam := AParams.ByID(pidBass);
  FTrebleParam := AParams.ByID(pidTreble);
  FTFreqParam := AParams.ByID(pidTFreq);
  FDBScale := 1.0;
end;

destructor TToneControl.Destroy;
begin
  FToneIn.Free;
  FToneOut.Free;
  inherited Destroy;
end;

procedure TToneControl.Prepare(SampleRate: Double; NumChannels: Integer);
begin
  FToneIn.Prepare(SampleRate, NumChannels);
  FToneOut.Prepare(SampleRate, NumChannels);
end;

procedure TToneControl.SetDBScale(NewDBScale: Single);
begin
  FDBScale := NewDBScale;
end;

procedure TToneControl.ProcessBlockIn(Buffer: TAudioBuffer);
begin
  if FOnOffParam.GetBool then
  begin
    FToneIn.SetLowGain(FDBScale * FBassParam.GetValue);
    FToneIn.SetHighGain(FDBScale * FTrebleParam.GetValue);
  end
  else
  begin
    FToneIn.SetLowGain(0.0);
    FToneIn.SetHighGain(0.0);
  end;
  FToneIn.SetTransFreq(FTFreqParam.GetValue);

  FToneIn.ProcessBlock(Buffer);
end;

procedure TToneControl.ProcessBlockOut(Buffer: TAudioBuffer);
begin
  if FOnOffParam.GetBool then
  begin
    FToneOut.SetLowGain(-1.0 * FDBScale * FBassParam.GetValue);
    FToneOut.SetHighGain(-1.0 * FDBScale * FTrebleParam.GetValue);
  end
  else
  begin
    FToneOut.SetLowGain(0.0);
    FToneOut.SetHighGain(0.0);
  end;
  FToneOut.SetTransFreq(FTFreqParam.GetValue);

  FToneOut.ProcessBlock(Buffer);
end;

end.
