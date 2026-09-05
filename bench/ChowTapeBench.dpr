program ChowTapeBench;

{
  DSP benchmark for the Delphi CHOW Tape Model port.

  Times the hysteresis solver on its own (where nearly all the cost is) and the
  whole chain, for every tape mode and oversampling factor, and reports the
  result as a fraction of real time. Also micro-benchmarks the transcendentals
  the solver leans on, so an optimisation can be judged against a number rather
  than an opinion.

  Build the Release configuration and run it from a console. Results are only
  meaningful in Release: the Debug build has range and overflow checks on.
}

{$APPTYPE CONSOLE}

uses
  Winapi.Windows,
  System.SysUtils,
  System.Math,
  System.IOUtils,
  ChowTape.DSP.Types in '..\src\dsp\ChowTape.DSP.Types.pas',
  ChowTape.DSP.FastMath in '..\src\dsp\ChowTape.DSP.FastMath.pas',
  ChowTape.DSP.Filters in '..\src\dsp\ChowTape.DSP.Filters.pas',
  ChowTape.DSP.DelayLine in '..\src\dsp\ChowTape.DSP.DelayLine.pas',
  ChowTape.DSP.Oversampling in '..\src\dsp\ChowTape.DSP.Oversampling.pas',
  ChowTape.DSP.VariableOS in '..\src\dsp\ChowTape.DSP.VariableOS.pas',
  ChowTape.DSP.Utils in '..\src\dsp\ChowTape.DSP.Utils.pas',
  ChowTape.DSP.Basics in '..\src\dsp\ChowTape.DSP.Basics.pas',
  ChowTape.DSP.HysteresisSTN in '..\src\dsp\ChowTape.DSP.HysteresisSTN.pas',
  ChowTape.DSP.Hysteresis in '..\src\dsp\ChowTape.DSP.Hysteresis.pas',
  ChowTape.DSP.HysteresisProcessor in '..\src\dsp\ChowTape.DSP.HysteresisProcessor.pas',
  ChowTape.DSP.ToneControl in '..\src\dsp\ChowTape.DSP.ToneControl.pas',
  ChowTape.DSP.Compression in '..\src\dsp\ChowTape.DSP.Compression.pas',
  ChowTape.DSP.InputFilters in '..\src\dsp\ChowTape.DSP.InputFilters.pas',
  ChowTape.DSP.MidSide in '..\src\dsp\ChowTape.DSP.MidSide.pas',
  ChowTape.DSP.Chew in '..\src\dsp\ChowTape.DSP.Chew.pas',
  ChowTape.DSP.Degrade in '..\src\dsp\ChowTape.DSP.Degrade.pas',
  ChowTape.DSP.Loss in '..\src\dsp\ChowTape.DSP.Loss.pas',
  ChowTape.DSP.WowFlutter in '..\src\dsp\ChowTape.DSP.WowFlutter.pas',
  ChowTape.DSP.Scope in '..\src\dsp\ChowTape.DSP.Scope.pas',
  ChowTape.Params in '..\src\params\ChowTape.Params.pas',
  ChowTape.Presets in '..\src\params\ChowTape.Presets.pas',
  ChowTape.PresetLibrary in '..\src\params\ChowTape.PresetLibrary.pas',
  ChowTape.Processor in '..\src\ChowTape.Processor.pas';

const
  SampleRate = 96000.0;
  BlockSize = 512;
  NumChannels = 2;
  SecondsPerRun = 5.0;

  ModeNames: array[0..5] of string = ('RK2', 'RK4', 'NR4', 'NR8', 'STN', 'V1');
  OSNames: array[0..4] of string = ('1x', '2x', '4x', '8x', '16x');

var
  GFreq: Int64;

{ --------------------------------------------------------------------------- }

function Now64: Int64; inline;
begin
  QueryPerformanceCounter(Result);
end;

function ElapsedMs(const StartTick: Int64): Double; inline;
begin
  Result := (Now64 - StartTick) * 1000.0 / GFreq;
end;

{ Locates resources\STN_Models by walking up from the executable, so the STN
  mode can be measured without linking the resource into this project. }
procedure PointSTNAtRepo;
var
  Dir, Candidate: string;
  I: Integer;
begin
  Dir := ExtractFilePath(ParamStr(0));
  for I := 0 to 6 do
  begin
    Candidate := TPath.Combine(Dir, 'resources\STN_Models');
    if TDirectory.Exists(Candidate) then
    begin
      STNModelDirectory := Candidate;
      Exit;
    end;
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if Dir = '' then
      Break;
  end;
end;

{ A sine sweep at -6 dBFS: exercises the whole hysteresis curve rather than
  parking the solver at one operating point. }
procedure FillTestSignal(Buffer: TAudioBuffer; TotalSamples: Integer);
var
  N, Ch: Integer;
  T, Freq, Phase, Value: Double;
begin
  Phase := 0.0;
  for N := 0 to TotalSamples - 1 do
  begin
    T := N / TotalSamples;
    Freq := 50.0 * Power(8000.0 / 50.0, T);
    Phase := Phase + 2.0 * Pi * Freq / SampleRate;
    Value := 0.5 * Sin(Phase);
    for Ch := 0 to Buffer.NumChannels - 1 do
      PSingleArray(Buffer.Channels[Ch])^[N] := Value;
  end;
end;

procedure Report(const Label_: string; MsElapsed, AudioSeconds: Double);
var
  MsPerSecond, RealtimeFactor, CpuPercent: Double;
begin
  MsPerSecond := MsElapsed / AudioSeconds;
  CpuPercent := MsPerSecond / 10.0;
  if MsPerSecond > 0 then
    RealtimeFactor := 1000.0 / MsPerSecond
  else
    RealtimeFactor := 0;

  Writeln(Format('  %-16s %9.2f ms/s %9.1f x RT %8.2f %% CPU',
    [Label_, MsPerSecond, RealtimeFactor, CpuPercent]));
end;

{ ---------------------------------------------------------------------------
  Hysteresis alone -- the part that actually costs
  --------------------------------------------------------------------------- }
procedure BenchHysteresis;
var
  Params: TParameterSet;
  Proc: THysteresisProcessor;
  Source, Work: TAudioBuffer;
  ModeIdx, OSIdx, TotalSamples, NumBlocks: Integer;
  StartTick: Int64;
  Elapsed: Double;

  procedure RunBlocks(Count: Integer);
  var
    B, C: Integer;
  begin
    for B := 0 to Count - 1 do
    begin
      for C := 0 to NumChannels - 1 do
        Move(PSingleArray(Source.Channels[C])^[B * BlockSize],
          Work.Channels[C]^, BlockSize * SizeOf(Single));
      Proc.ProcessBlock(Work);
    end;
  end;

begin
  Writeln;
  Writeln('Hysteresis solver only');
  Writeln('  ----------------------------------------------------------------');

  TotalSamples := Round(SampleRate * SecondsPerRun);
  NumBlocks := TotalSamples div BlockSize;

  Params := CreateTapeParameters;
  Source := TAudioBuffer.Create(NumChannels, TotalSamples);
  Work := TAudioBuffer.Create(NumChannels, BlockSize);

  // One processor for every configuration: preparing it builds all ten
  // oversamplers, and the mode and factor are plain parameters that the
  // processor picks up per block anyway.
  Proc := THysteresisProcessor.Create(Params);
  try
    FillTestSignal(Source, TotalSamples);
    Proc.PrepareToPlay(SampleRate, BlockSize, NumChannels);

    for ModeIdx := 0 to High(ModeNames) do
    begin
      for OSIdx := 0 to High(OSNames) do
      begin
        Params.ByID(pidMode).SetValue(ModeIdx);
        Params.ByID(pidOSFactor).SetValue(OSIdx);

        // warm up: lets the smoothing ramps settle and the caches fill, and
        // gives the oversampler switch somewhere to happen
        RunBlocks(10);

        StartTick := Now64;
        RunBlocks(NumBlocks);
        Elapsed := ElapsedMs(StartTick);

        Report(ModeNames[ModeIdx] + ' ' + OSNames[OSIdx], Elapsed,
          NumBlocks * BlockSize / SampleRate);
      end;
      Writeln;
    end;
  finally
    Proc.Free;
    Work.Free;
    Source.Free;
    Params.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  Per-section costs

  With the solver sped up, most of the cost at ordinary oversampling factors is
  everything else. This times each processor on its own so we can see which.
  All at 1x: the only sections with internal oversampling are compression
  (fixed 2x) and hysteresis, which has its own table above.
  --------------------------------------------------------------------------- }
procedure BenchSections;
var
  Params: TParameterSet;
  Source, Work: TAudioBuffer;
  TotalSamples, NumBlocks: Integer;

  InFilt: TInputFilters;
  MidSide: TMidSideProcessor;
  Tone: TToneControl;
  Comp: TCompressionProcessor;
  Chew: TChewProcessor;
  Degrade: TDegradeProcessor;
  Loss: TLossFilter;
  Flutter: TWowFlutterProcessor;
  DryDelay: TDelayLine;
  Scope: TTapeScope;

  procedure Refill(B: Integer);
  var
    C: Integer;
  begin
    for C := 0 to NumChannels - 1 do
      Move(PSingleArray(Source.Channels[C])^[B * BlockSize],
        Work.Channels[C]^, BlockSize * SizeOf(Single));
  end;

  procedure Measure(const Name: string; const DoWork: TProc);
  var
    B: Integer;
    Tick: Int64;
  begin
    for B := 0 to 9 do
    begin
      Refill(B);
      DoWork();
    end;

    Tick := Now64;
    for B := 0 to NumBlocks - 1 do
    begin
      Refill(B);
      DoWork();
    end;
    Report(Name, ElapsedMs(Tick), NumBlocks * BlockSize / SampleRate);
  end;

begin
  Writeln;
  Writeln('Per-section cost at 1x (subtract the copy-only row)');
  Writeln('  ----------------------------------------------------------------');

  TotalSamples := Round(SampleRate * SecondsPerRun);
  NumBlocks := TotalSamples div BlockSize;

  Params := CreateTapeParameters;
  Source := TAudioBuffer.Create(NumChannels, TotalSamples);
  Work := TAudioBuffer.Create(NumChannels, BlockSize);

  // configure every section to do real work rather than idle
  Params.ByID(pidIFiltOnOff).SetValue(1);
  Params.ByID(pidIFiltLow).SetValue(200);
  Params.ByID(pidIFiltHigh).SetValue(8000);
  Params.ByID(pidIFiltMakeup).SetValue(1);
  Params.ByID(pidMidSide).SetValue(1);
  Params.ByID(pidStereoBalance).SetValue(0.3);
  Params.ByID(pidToneOnOff).SetValue(1);
  Params.ByID(pidBass).SetValue(0.5);
  Params.ByID(pidTreble).SetValue(-0.5);
  Params.ByID(pidCompOnOff).SetValue(1);
  Params.ByID(pidCompAmt).SetValue(6);
  Params.ByID(pidChewOnOff).SetValue(1);
  Params.ByID(pidChewDepth).SetValue(0.5);
  Params.ByID(pidChewFreq).SetValue(0.5);
  Params.ByID(pidChewVar).SetValue(0.5);
  Params.ByID(pidDegOnOff).SetValue(1);
  Params.ByID(pidDegDepth).SetValue(0.5);
  Params.ByID(pidDegAmt).SetValue(0.5);
  Params.ByID(pidDegVar).SetValue(0.5);
  Params.ByID(pidDegEnv).SetValue(0.5);
  Params.ByID(pidLossOnOff).SetValue(1);
  Params.ByID(pidFlutterOnOff).SetValue(1);
  Params.ByID(pidFlutterDepth).SetValue(0.5);
  Params.ByID(pidWowDepth).SetValue(0.5);
  Params.ByID(pidWowVar).SetValue(0.5);

  InFilt := TInputFilters.Create(Params);
  MidSide := TMidSideProcessor.Create(Params);
  Tone := TToneControl.Create(Params);
  Comp := TCompressionProcessor.Create(Params);
  Chew := TChewProcessor.Create(Params);
  Degrade := TDegradeProcessor.Create(Params);
  Loss := TLossFilter.Create(Params);
  Flutter := TWowFlutterProcessor.Create(Params);
  DryDelay := TDelayLine.Create(1 shl 21, diLagrange5th);
  Scope := TTapeScope.Create;
  try
    FillTestSignal(Source, TotalSamples);

    InFilt.PrepareToPlay(SampleRate, BlockSize, NumChannels);
    InFilt.SetMakeupDelay(64.0);
    MidSide.Prepare(SampleRate, BlockSize);
    Tone.Prepare(SampleRate, NumChannels);
    Comp.Prepare(SampleRate, BlockSize, NumChannels);
    Chew.Prepare(SampleRate, BlockSize, NumChannels);
    Degrade.PrepareToPlay(SampleRate, BlockSize, NumChannels);
    Loss.Prepare(SampleRate, BlockSize, NumChannels);
    Flutter.PrepareToPlay(SampleRate, BlockSize, NumChannels);
    DryDelay.Prepare(NumChannels);
    DryDelay.SetDelay(64.0);
    Scope.PrepareToPlay(SampleRate, BlockSize);

    Writeln(Format('  loss filter FIR order at this rate: %d taps per channel',
      [Trunc(64 * SampleRate / 44100.0)]));
    Writeln;

    Measure('(copy only)',   procedure begin end);
    Measure('input filters', procedure begin InFilt.ProcessBlock(Work);
                                             InFilt.ProcessBlockMakeup(Work); end);
    Measure('mid/side',      procedure begin MidSide.ProcessInput(Work);
                                             MidSide.ProcessOutput(Work); end);
    Measure('tone control',  procedure begin Tone.ProcessBlockIn(Work);
                                             Tone.ProcessBlockOut(Work); end);
    Measure('compression',   procedure begin Comp.ProcessBlock(Work); end);
    Measure('chew',          procedure begin Chew.ProcessBlock(Work); end);
    Measure('degrade',       procedure begin Degrade.ProcessBlock(Work); end);
    Measure('wow/flutter',   procedure begin Flutter.ProcessBlock(Work); end);
    Measure('loss filter',   procedure begin Loss.ProcessBlock(Work); end);
    Measure('dry delay',     procedure begin DryDelay.ProcessBuffer(Work); end);
    Measure('scope',         procedure begin Scope.PushInput(Work);
                                             Scope.PushOutput(Work); end);
  finally
    Scope.Free;
    DryDelay.Free;
    Flutter.Free;
    Loss.Free;
    Degrade.Free;
    Chew.Free;
    Comp.Free;
    Tone.Free;
    MidSide.Free;
    InFilt.Free;
    Work.Free;
    Source.Free;
    Params.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  The whole chain, for context
  --------------------------------------------------------------------------- }
procedure BenchFullChain;
var
  Proc: TChowTapeProcessor;
  Source, InBuf, OutBuf: TAudioBuffer;
  // System.PSingle, not the bare name: Winapi.Windows redeclares PSingle, and
  // being later in the uses clause it would win -- giving a type that will not
  // assign from TAudioBuffer.Channels.
  InPtrs, OutPtrs: array[0..NumChannels - 1] of System.PSingle;
  TotalSamples, NumBlocks, Ch, OSIdx: Integer;
  StartTick: Int64;
  Elapsed: Double;

  procedure RunBlocks(Count: Integer);
  var
    B, C: Integer;
  begin
    for B := 0 to Count - 1 do
    begin
      for C := 0 to NumChannels - 1 do
        Move(PSingleArray(Source.Channels[C])^[B * BlockSize],
          InBuf.Channels[C]^, BlockSize * SizeOf(Single));
      Proc.ProcessBlock(@InPtrs[0], @OutPtrs[0], NumChannels, BlockSize);
    end;
  end;

  procedure Measure(const Label_: string);
  begin
    RunBlocks(10);
    StartTick := Now64;
    RunBlocks(NumBlocks);
    Elapsed := ElapsedMs(StartTick);
    Report(Label_, Elapsed, NumBlocks * BlockSize / SampleRate);
  end;

  procedure EnableEverything;
  begin
    Proc.Params.ByID(pidIFiltOnOff).SetValue(1);
    Proc.Params.ByID(pidCompOnOff).SetValue(1);
    Proc.Params.ByID(pidChewOnOff).SetValue(1);
    Proc.Params.ByID(pidDegOnOff).SetValue(1);
    Proc.Params.ByID(pidChewDepth).SetValue(0.5);
    Proc.Params.ByID(pidChewFreq).SetValue(0.5);
    Proc.Params.ByID(pidDegDepth).SetValue(0.5);
    Proc.Params.ByID(pidDegAmt).SetValue(0.5);
    Proc.Params.ByID(pidFlutterDepth).SetValue(0.5);
    Proc.Params.ByID(pidWowDepth).SetValue(0.5);
  end;

begin
  Writeln;
  Writeln('Whole chain (RK2 tape mode)');
  Writeln('  ----------------------------------------------------------------');

  TotalSamples := Round(SampleRate * SecondsPerRun);
  NumBlocks := TotalSamples div BlockSize;

  Source := TAudioBuffer.Create(NumChannels, TotalSamples);
  InBuf := TAudioBuffer.Create(NumChannels, BlockSize);
  OutBuf := TAudioBuffer.Create(NumChannels, BlockSize);
  Proc := TChowTapeProcessor.Create;
  try
    FillTestSignal(Source, TotalSamples);
    for Ch := 0 to NumChannels - 1 do
    begin
      InPtrs[Ch] := InBuf.Channels[Ch];
      OutPtrs[Ch] := OutBuf.Channels[Ch];
    end;

    Proc.PrepareToPlay(SampleRate, BlockSize, NumChannels);

    for OSIdx := 0 to High(OSNames) do
    begin
      Proc.Params.ByID(pidOSFactor).SetValue(OSIdx);
      Measure('default ' + OSNames[OSIdx]);
    end;

    Writeln;
    EnableEverything;
    for OSIdx := 0 to High(OSNames) do
    begin
      Proc.Params.ByID(pidOSFactor).SetValue(OSIdx);
      Measure('everything ' + OSNames[OSIdx]);
    end;
  finally
    Proc.Free;
    OutBuf.Free;
    InBuf.Free;
    Source.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  Transcendentals

  The solver's only transcendental is coth, called 2x per sample for RK2, 4x
  for RK4, 5x for NR4 and 9x for NR8 -- per channel, at the oversampled rate.
  --------------------------------------------------------------------------- }
procedure BenchTranscendentals;
const
  Iterations = 2000000;
var
  I: Integer;
  StartTick: Int64;
  Acc, X: Double;
  Inputs: array of Double;

  procedure Show(const Name: string; Ms, Checksum: Double);
  begin
    Writeln(Format('  %-24s %8.2f ns   (checksum %.6f)',
      [Name, Ms * 1.0e6 / Iterations, Checksum]));
  end;

begin
  Writeln;
  Writeln('Transcendentals (ns per call, latency-bound)');
  Writeln('  ----------------------------------------------------------------');

  // spread over the range the solver actually sees for Q
  SetLength(Inputs, 1024);
  for I := 0 to High(Inputs) do
    Inputs[I] := -8.0 + 16.0 * I / High(Inputs);

  Acc := 0;
  StartTick := Now64;
  for I := 0 to Iterations - 1 do
    Acc := Acc + Tanh(Inputs[I and 1023]);
  Show('System.Math.Tanh', ElapsedMs(StartTick), Acc);

  Acc := 0;
  StartTick := Now64;
  for I := 0 to Iterations - 1 do
    Acc := Acc + FastTanh(Inputs[I and 1023]);
  Show('FastTanh', ElapsedMs(StartTick), Acc);

  Acc := 0;
  StartTick := Now64;
  for I := 0 to Iterations - 1 do
    Acc := Acc + 1.0 / Tanh(Inputs[I and 1023]);
  Show('1.0 / System.Math.Tanh', ElapsedMs(StartTick), Acc);

  Acc := 0;
  StartTick := Now64;
  for I := 0 to Iterations - 1 do
    Acc := Acc + FastCoth(Inputs[I and 1023]);
  Show('FastCoth', ElapsedMs(StartTick), Acc);

  Acc := 0;
  StartTick := Now64;
  for I := 0 to Iterations - 1 do
    Acc := Acc + Exp(Inputs[I and 1023]);
  Show('System.Math.Exp', ElapsedMs(StartTick), Acc);

  Acc := 0;
  StartTick := Now64;
  for I := 0 to Iterations - 1 do
    Acc := Acc + FastExp(Inputs[I and 1023]);
  Show('FastExp', ElapsedMs(StartTick), Acc);

  // the compressor's dB conversions, once per oversampled sample per channel
  Acc := 0;
  StartTick := Now64;
  for I := 0 to Iterations - 1 do
    Acc := Acc + Log10(Abs(Inputs[I and 1023]) + 0.5);
  Show('System.Math.Log10', ElapsedMs(StartTick), Acc);

  Acc := 0;
  StartTick := Now64;
  for I := 0 to Iterations - 1 do
    Acc := Acc + FastLog(Abs(Inputs[I and 1023]) + 0.5);
  Show('FastLog', ElapsedMs(StartTick), Acc);

  Acc := 0;
  StartTick := Now64;
  for I := 0 to Iterations - 1 do
    Acc := Acc + Power(10.0, Inputs[I and 1023] * 0.05);
  Show('Power(10, x)', ElapsedMs(StartTick), Acc);

  // four of these per sample per channel in the wow/flutter oscillators
  Acc := 0;
  StartTick := Now64;
  for I := 0 to Iterations - 1 do
    Acc := Acc + Cos(Inputs[I and 1023]);
  Show('System.Cos', ElapsedMs(StartTick), Acc);

  Acc := 0;
  StartTick := Now64;
  for I := 0 to Iterations - 1 do
    Acc := Acc + FastCos(Inputs[I and 1023]);
  Show('FastCos', ElapsedMs(StartTick), Acc);

  Acc := 0;
  StartTick := Now64;
  for I := 0 to Iterations - 1 do
  begin
    X := Inputs[I and 1023];
    Acc := Acc + 1.0 / (X + 16.0);
  end;
  Show('double divide', ElapsedMs(StartTick), Acc);
end;

{ ---------------------------------------------------------------------------
  Accuracy

  Fast is worthless without close: these values feed a stiff ODE solver, and
  the Newton-Raphson modes differentiate them.
  --------------------------------------------------------------------------- }
procedure BenchAccuracy;
const
  Samples = 400000;
  Lo = -25.0;
  Hi = 25.0;
var
  I: Integer;
  X, Ref, Got, AbsErr, RelErr: Double;
  MaxAbsExp, MaxRelExp: Double;
  MaxAbsTanh, MaxRelTanh: Double;
  MaxAbsCoth, MaxRelCoth: Double;
  MaxRelLog, MaxAbsCos: Double;
begin
  Writeln;
  Writeln('Accuracy against System.Math, sampled over [-25, 25]');
  Writeln('  ----------------------------------------------------------------');

  MaxAbsExp := 0; MaxRelExp := 0;
  MaxAbsTanh := 0; MaxRelTanh := 0;
  MaxAbsCoth := 0; MaxRelCoth := 0;
  MaxRelLog := 0;
  MaxAbsCos := 0;

  for I := 0 to Samples do
  begin
    X := Lo + (Hi - Lo) * I / Samples;

    // exp: only compare where the RTL itself is in range
    if Abs(X) < 300.0 then
    begin
      Ref := Exp(X);
      Got := FastExp(X);
      AbsErr := Abs(Got - Ref);
      if AbsErr > MaxAbsExp then MaxAbsExp := AbsErr;
      if Ref <> 0 then
      begin
        RelErr := AbsErr / Abs(Ref);
        if RelErr > MaxRelExp then MaxRelExp := RelErr;
      end;
    end;

    Ref := Tanh(X);
    Got := FastTanh(X);
    AbsErr := Abs(Got - Ref);
    if AbsErr > MaxAbsTanh then MaxAbsTanh := AbsErr;
    if Ref <> 0 then
    begin
      RelErr := AbsErr / Abs(Ref);
      if RelErr > MaxRelTanh then MaxRelTanh := RelErr;
    end;

    // cos is judged on absolute error: it crosses zero, so relative is
    // meaningless there
    AbsErr := Abs(FastCos(X) - Cos(X));
    if AbsErr > MaxAbsCos then MaxAbsCos := AbsErr;

    // log over the gain range the compressor actually sees
    Got := Abs(X) * 0.04 + 1.0e-6;
    Ref := Ln(Got);
    if Ref <> 0 then
    begin
      RelErr := Abs(FastLog(Got) - Ref) / Abs(Ref);
      if RelErr > MaxRelLog then MaxRelLog := RelErr;
    end;

    // coth blows up at the origin, so skip a small neighbourhood
    if Abs(X) > 1.0e-3 then
    begin
      Ref := 1.0 / Tanh(X);
      Got := FastCoth(X);
      AbsErr := Abs(Got - Ref);
      if AbsErr > MaxAbsCoth then MaxAbsCoth := AbsErr;
      RelErr := AbsErr / Abs(Ref);
      if RelErr > MaxRelCoth then MaxRelCoth := RelErr;
    end;
  end;

  Writeln(Format('  FastExp    max abs %.3e   max rel %.3e', [MaxAbsExp, MaxRelExp]));
  Writeln(Format('  FastTanh   max abs %.3e   max rel %.3e', [MaxAbsTanh, MaxRelTanh]));
  Writeln(Format('  FastCoth   max abs %.3e   max rel %.3e', [MaxAbsCoth, MaxRelCoth]));
  Writeln(Format('  FastLog                          max rel %.3e', [MaxRelLog]));
  Writeln(Format('  FastCos    max abs %.3e', [MaxAbsCos]));
  Writeln;
  Writeln('  For reference, a double holds ~2.2e-16 and the tape model''s own');
  Writeln('  parameters are known to about two significant figures.');
end;

procedure PrintHeader;
begin
  Writeln('CHOW Tape Model - Delphi port, DSP benchmark');
  Writeln('============================================');
  Writeln;
  {$IFDEF WIN64}
  Writeln('  Platform     : Win64');
  {$ELSE}
  Writeln('  Platform     : Win32');
  {$ENDIF}
  {$IFOPT O+}
  Writeln('  Optimisation : ON');
  {$ELSE}
  Writeln('  Optimisation : OFF  <-- build Release for meaningful numbers');
  {$ENDIF}
  {$IFOPT R+}
  Writeln('  Range checks : ON   <-- build Release for meaningful numbers');
  {$ENDIF}
  Writeln(Format('  Sample rate  : %.0f Hz', [SampleRate]));
  Writeln(Format('  Block size   : %d', [BlockSize]));
  Writeln(Format('  Channels     : %d', [NumChannels]));
  Writeln(Format('  Audio/run    : %.1f s', [SecondsPerRun]));
  Writeln('  STN models   : ' + STNModelsSource);
{$IFDEF CHOWTAPE_RTL_MATH}
  Writeln('  Solver math  : System.Math (CHOWTAPE_RTL_MATH defined)');
{$ELSE}
  Writeln('  Solver math  : ChowTape.DSP.FastMath');
{$ENDIF}
  Writeln('  Fast math    : ' + FastMathExpBackend);

  Writeln;
  Writeln('  "x RT" is how many real-time streams one core could sustain.');
end;

begin
  try
    QueryPerformanceFrequency(GFreq);
    SetExceptionMask(exAllArithmeticExceptions);
    SetPriorityClass(GetCurrentProcess, HIGH_PRIORITY_CLASS);

    PointSTNAtRepo;
    PrintHeader;

    BenchTranscendentals;
    BenchAccuracy;
    BenchHysteresis;
    BenchSections;
    BenchFullChain;

    Writeln;
    Writeln('Done.');
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;

  if ParamCount = 0 then
  begin
    Writeln;
    Write('Press Enter to close...');
    Readln;
  end;
end.
