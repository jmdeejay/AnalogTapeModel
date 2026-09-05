unit ChowTape.DSP.DelayLine;

{
  Fractional delay lines with Lagrange interpolation, matching
  chowdsp::DelayLine / juce::dsp::DelayLine.

  The original doubles the storage so the interpolation window is always
  contiguous; here the indices wrap instead, which halves the memory footprint
  (the wow/flutter line alone asks for 2^21 samples per channel) and produces
  the same output.
}

interface

uses
  System.Math, ChowTape.DSP.Types;

type
  TDelayInterpolation = (diLagrange3rd, diLagrange5th);

  TDelayLine = class
  private
    FBuffer: array of Single;      // NumChannels * TotalSize
    FWritePos: array of Integer;
    FReadPos: array of Integer;
    FTotalSize: Integer;
    FNumChannels: Integer;
    FInterpolation: TDelayInterpolation;
    FDelay: Single;
    FDelayInt: Integer;
    FDelayFrac: Single;
    FOrder: Integer;               // number of taps the interpolator reads
    procedure UpdateInternalVariables;
  public
    constructor Create(MaximumDelayInSamples: Integer;
      AInterpolation: TDelayInterpolation);
    procedure Prepare(ANumChannels: Integer);
    procedure Reset;
    procedure SetDelay(NewDelayInSamples: Single);
    function GetDelay: Single; inline;
    procedure PushSample(Channel: Integer; Sample: Single); inline;
    function PopSample(Channel: Integer): Single;
    { Convenience: run a whole buffer through at the current delay. }
    procedure ProcessBuffer(Buffer: TAudioBuffer);
  end;

implementation

constructor TDelayLine.Create(MaximumDelayInSamples: Integer;
  AInterpolation: TDelayInterpolation);
begin
  inherited Create;
  FInterpolation := AInterpolation;
  if AInterpolation = diLagrange3rd then
    FOrder := 4
  else
    FOrder := 6;
  FTotalSize := MaximumDelayInSamples + FOrder + 1;
  if FTotalSize < 8 then
    FTotalSize := 8;
  FNumChannels := 0;
end;

procedure TDelayLine.Prepare(ANumChannels: Integer);
begin
  FNumChannels := ANumChannels;
  SetLength(FBuffer, ANumChannels * FTotalSize);
  SetLength(FWritePos, ANumChannels);
  SetLength(FReadPos, ANumChannels);
  Reset;
end;

procedure TDelayLine.Reset;
var
  I: Integer;
begin
  for I := 0 to High(FBuffer) do
    FBuffer[I] := 0.0;
  for I := 0 to FNumChannels - 1 do
  begin
    FWritePos[I] := 0;
    FReadPos[I] := 0;
  end;
end;

procedure TDelayLine.UpdateInternalVariables;
begin
  case FInterpolation of
    diLagrange3rd:
      if FDelayInt >= 1 then
      begin
        FDelayFrac := FDelayFrac + 1.0;
        Dec(FDelayInt);
      end;
    diLagrange5th:
      if FDelayInt >= 2 then
      begin
        FDelayFrac := FDelayFrac + 2.0;
        Dec(FDelayInt, 2);
      end;
  end;
end;

procedure TDelayLine.SetDelay(NewDelayInSamples: Single);
var
  UpperLimit: Single;
begin
  UpperLimit := FTotalSize - FOrder - 1;
  FDelay := JLimit(0.0, UpperLimit, NewDelayInSamples);

  // Trunc, not Floor: the clamp above guarantees FDelay >= 0, where the two
  // agree. Delphi's Floor is Trunc plus a Frac and a branch, and wow/flutter
  // calls this once per sample.
  FDelayInt := Trunc(FDelay);
  FDelayFrac := FDelay - FDelayInt;
  UpdateInternalVariables;
end;

function TDelayLine.GetDelay: Single;
begin
  Result := FDelay;
end;

procedure TDelayLine.PushSample(Channel: Integer; Sample: Single);
var
  Base, W: Integer;
begin
  Base := Channel * FTotalSize;
  W := FWritePos[Channel];
  FBuffer[Base + W] := Sample;

  // The write head only ever steps back by one, so a compare beats the
  // modulo this used to do -- FTotalSize is not a power of two, which made
  // that a real integer division in the inner loop.
  if W = 0 then
    FWritePos[Channel] := FTotalSize - 1
  else
    FWritePos[Channel] := W - 1;
end;

function TDelayLine.PopSample(Channel: Integer): Single;
var
  Base, Index, I, R: Integer;
  Buf: PSingleArray;
  V: array[0..5] of Single;
  D1, D2, D3, D4, D5: Single;
  C1, C2, C3, C4, C5, C6: Single;
begin
  Base := Channel * FTotalSize;

  // ReadPos < TotalSize and DelayInt <= TotalSize - Order - 1, so the sum is
  // below 2*TotalSize and one conditional subtract normalises it. Each
  // subsequent tap advances by one, so it can wrap at most once more.
  Index := FReadPos[Channel] + FDelayInt;
  if Index >= FTotalSize then
    Dec(Index, FTotalSize);

  Buf := PSingleArray(@FBuffer[Base]);
  for I := 0 to FOrder - 1 do
  begin
    V[I] := Buf^[Index];
    Inc(Index);
    if Index >= FTotalSize then
      Index := 0;
  end;

  if FInterpolation = diLagrange3rd then
  begin
    D1 := FDelayFrac - 1.0;
    D2 := FDelayFrac - 2.0;
    D3 := FDelayFrac - 3.0;

    C1 := -D1 * D2 * D3 / 6.0;
    C2 := D2 * D3 * 0.5;
    C3 := -D1 * D3 * 0.5;
    C4 := D1 * D2 / 6.0;

    Result := V[0] * C1 + FDelayFrac * (V[1] * C2 + V[2] * C3 + V[3] * C4);
  end
  else
  begin
    D1 := FDelayFrac - 1.0;
    D2 := FDelayFrac - 2.0;
    D3 := FDelayFrac - 3.0;
    D4 := FDelayFrac - 4.0;
    D5 := FDelayFrac - 5.0;

    C1 := -D1 * D2 * D3 * D4 * D5 / 120.0;
    C2 := D2 * D3 * D4 * D5 / 24.0;
    C3 := -D1 * D3 * D4 * D5 / 12.0;
    C4 := D1 * D2 * D4 * D5 / 12.0;
    C5 := -D1 * D2 * D3 * D5 / 24.0;
    C6 := D1 * D2 * D3 * D4 / 120.0;

    Result := V[0] * C1 + FDelayFrac * (V[1] * C2 + V[2] * C3 + V[3] * C4 +
      V[4] * C5 + V[5] * C6);
  end;

  R := FReadPos[Channel];
  if R = 0 then
    FReadPos[Channel] := FTotalSize - 1
  else
    FReadPos[Channel] := R - 1;
end;

procedure TDelayLine.ProcessBuffer(Buffer: TAudioBuffer);
var
  Ch, N: Integer;
  P: PSingleArray;
begin
  for Ch := 0 to Buffer.NumChannels - 1 do
  begin
    P := PSingleArray(Buffer.Channels[Ch]);
    for N := 0 to Buffer.NumSamples - 1 do
    begin
      PushSample(Ch, P^[N]);
      P^[N] := PopSample(Ch);
    end;
  end;
end;

end.
