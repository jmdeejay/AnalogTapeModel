unit ChowTape.DSP.Hysteresis;

{
  Jiles-Atherton hysteresis model of tape magnetisation.

  See https://ccrma.stanford.edu/~jatin/420/tape/TapeModel_DAFx.pdf. This is a
  direct port of HysteresisOps.h / HysteresisProcessing.h; the original has a
  SIMD path that processes two channels at once, and this follows the scalar
  reference path instead -- same maths, one channel at a time.
}

interface

uses
  System.Math, ChowTape.DSP.Types, ChowTape.DSP.FastMath,
  ChowTape.DSP.HysteresisSTN;

type
  TSolverType = (stRK2, stRK4, stNR4, stNR8, stSTN);

const
  NumSolvers = 5;
  HysteresisAlpha = 1.6e-3;
  OneThird = 1.0 / 3.0;
  NegTwoOver15 = -2.0 / 15.0;

type
  THysteresisState = record
    // parameter values
    M_s: Double;
    A: Double;
    K: Double;
    C: Double;
    OneOverA: Double;   // A only changes in Cook, so the divide is hoisted

    // cached combinations of the above
    Nc: Double;
    M_s_oa: Double;
    M_s_oa_talpha: Double;
    M_s_oa_tc: Double;
    M_s_oa_tc_talpha: Double;
    M_s_oaSq_tc_talpha: Double;
    M_s_oaSq_tc_talphaSq: Double;

    // scratch shared between hysteresisFunc and its derivative
    Q, M_diff, L_prime, Kap1, F1Denom, F1, F2, F3: Double;
    Coth: Double;
    NearZero: Boolean;
    OneOverQ, OneOverQSq, OneOverQCubed, CothSq, OneOverF3, OneOverF1Denom: Double;
  end;

  THysteresisProcessing = class
  private
    FFs: Double;
    FT: Double;
    FTalpha: Double;
    FUpperLim: Double;

    FM_n1: Double;
    FH_n1: Double;
    FH_d_n1: Double;

    FSTN: THysteresisSTN;
    FState: THysteresisState;

    // Not inlined: they call helpers that live in the implementation section.
    function RK2Solver(H, H_d: Double): Double;
    function RK4Solver(H, H_d: Double): Double;
    function NRSolver(H, H_d: Double; NIterations: Integer): Double;
    function STNSolver(H, H_d: Double): Double;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Reset;
    procedure SetSampleRate(NewSR: Double);
    procedure Cook(Drive, Width, Sat: Double; V1: Boolean);
    function Process(Solver: TSolverType; H: Double): Double;
  end;

implementation

{ ---------------------------------------------------------------------------
  Langevin function and its first two derivatives.
  --------------------------------------------------------------------------- }

function Langevin(const HP: THysteresisState): Double; inline;
begin
  if not HP.NearZero then
    Result := HP.Coth - HP.OneOverQ
  else
    Result := HP.Q * OneThird;
end;

function LangevinD(const HP: THysteresisState): Double; inline;
begin
  if not HP.NearZero then
    Result := HP.OneOverQSq - HP.CothSq + 1.0
  else
    Result := OneThird;
end;

function LangevinD2(const HP: THysteresisState): Double; inline;
begin
  if not HP.NearZero then
    Result := 2.0 * HP.Coth * (HP.CothSq - 1.0) - (2.0 * HP.OneOverQCubed)
  else
    Result := NegTwoOver15 * HP.Q;
end;

{ Derivative by the alpha transform. }
function Deriv(X_n, X_n1, X_d_n1, T: Double): Double; inline;
const
  DAlpha = 0.75;
begin
  Result := (((1.0 + DAlpha) / T) * (X_n - X_n1)) - DAlpha * X_d_n1;
end;

{ dM/dt }
function HysteresisFunc(M, H, H_d: Double; var HP: THysteresisState): Double;
var
  Delta, DeltaM: Double;
begin
  HP.Q := (H + M * HysteresisAlpha) * HP.OneOverA;
  HP.OneOverQ := 1.0 / HP.Q;
  HP.OneOverQSq := HP.OneOverQ * HP.OneOverQ;
  HP.OneOverQCubed := HP.OneOverQ * HP.OneOverQSq;

  // Define CHOWTAPE_RTL_MATH in the project to fall back on System.Math and
  // compare; the fast path is ~3x quicker and agrees to about 1e-10.
{$IFDEF CHOWTAPE_RTL_MATH}
  HP.Coth := 1.0 / Tanh(HP.Q);
{$ELSE}
  HP.Coth := FastCoth(HP.Q);
{$ENDIF}
  HP.NearZero := (HP.Q < 0.001) and (HP.Q > -0.001);

  HP.CothSq := HP.Coth * HP.Coth;
  HP.M_diff := Langevin(HP) * HP.M_s - M;

  if H_d >= 0.0 then
    Delta := 1.0
  else
    Delta := -1.0;
  if SignOf(Delta) = SignOf(HP.M_diff) then
    DeltaM := 1.0
  else
    DeltaM := 0.0;
  HP.Kap1 := HP.Nc * DeltaM;

  HP.L_prime := LangevinD(HP);

  HP.F1Denom := (HP.Nc * Delta) * HP.K - HysteresisAlpha * HP.M_diff;
  HP.OneOverF1Denom := 1.0 / HP.F1Denom;
  HP.F1 := HP.Kap1 * HP.M_diff * HP.OneOverF1Denom;
  HP.F2 := HP.L_prime * HP.M_s_oa_tc;
  HP.F3 := 1.0 - (HP.L_prime * HP.M_s_oa_tc_talpha);
  HP.OneOverF3 := 1.0 / HP.F3;

  Result := H_d * (HP.F1 + HP.F2) * HP.OneOverF3;
end;

{ d(dM/dt)/dM -- relies on the values cached by HysteresisFunc. }
function HysteresisFuncPrime(H_d, DMdt: Double; var HP: THysteresisState): Double;
var
  L_prime2, M_diff2, F1_p, F2_p, F3_p: Double;
begin
  L_prime2 := LangevinD2(HP);
  M_diff2 := HP.L_prime * HP.M_s_oa_talpha - 1.0;

  F1_p := M_diff2 * HP.OneOverF1Denom;
  F1_p := F1_p + HP.M_diff * HysteresisAlpha * M_diff2 *
    (HP.OneOverF1Denom * HP.OneOverF1Denom);
  F1_p := F1_p * HP.Kap1;

  F2_p := L_prime2 * HP.M_s_oaSq_tc_talpha;
  F3_p := L_prime2 * (-HP.M_s_oaSq_tc_talphaSq);

  Result := (H_d * (F1_p + F2_p) - DMdt * F3_p) * HP.OneOverF3;
end;

{ THysteresisProcessing }

constructor THysteresisProcessing.Create;
begin
  inherited Create;
  FFs := 48000.0;
  FT := 1.0 / FFs;
  FTalpha := FT / 1.9;
  FUpperLim := 20.0;
  FSTN := THysteresisSTN.Create;

  FState.M_s := 1.0;
  FState.A := FState.M_s / 4.0;
  FState.K := 0.47875;
  FState.C := 1.7e-1;
  Cook(0.5, 0.5, 0.5, False);
  Reset;
end;

destructor THysteresisProcessing.Destroy;
begin
  FSTN.Free;
  inherited Destroy;
end;

procedure THysteresisProcessing.Reset;
begin
  FM_n1 := 0.0;
  FH_n1 := 0.0;
  FH_d_n1 := 0.0;
  FState.Coth := 0.0;
  FState.NearZero := False;
end;

procedure THysteresisProcessing.SetSampleRate(NewSR: Double);
begin
  FFs := NewSR;
  FT := 1.0 / FFs;
  FTalpha := FT / 1.9;
  FSTN.Prepare(NewSR);
end;

procedure THysteresisProcessing.Cook(Drive, Width, Sat: Double; V1: Boolean);
begin
  FSTN.SetParams(Sat, Width);

  FState.M_s := 0.5 + 1.5 * (1.0 - Sat);
  FState.A := FState.M_s / (0.01 + 6.0 * Drive);
  FState.C := Sqrt(1.0 - Width) - 0.01;
  FState.K := 0.47875;
  FUpperLim := 20.0;

  if V1 then
  begin
    FState.K := 27.0e3;
    FState.C := 1.7e-1;
    FState.M_s := FState.M_s * 50000.0;
    FState.A := FState.M_s / (0.01 + 40.0 * Drive);
    FUpperLim := 100000.0;
  end;

  FState.Nc := 1.0 - FState.C;
  FState.OneOverA := 1.0 / FState.A;
  FState.M_s_oa := FState.M_s / FState.A;
  FState.M_s_oa_talpha := HysteresisAlpha * FState.M_s_oa;
  FState.M_s_oa_tc := FState.C * FState.M_s_oa;
  FState.M_s_oa_tc_talpha := HysteresisAlpha * FState.M_s_oa_tc;
  FState.M_s_oaSq_tc_talpha := FState.M_s_oa_tc_talpha / FState.A;
  FState.M_s_oaSq_tc_talphaSq := HysteresisAlpha * FState.M_s_oaSq_tc_talpha;
end;

function THysteresisProcessing.RK2Solver(H, H_d: Double): Double;
var
  K1, K2: Double;
begin
  K1 := HysteresisFunc(FM_n1, FH_n1, FH_d_n1, FState) * FT;
  K2 := HysteresisFunc(FM_n1 + K1 * 0.5, (H + FH_n1) * 0.5,
    (H_d + FH_d_n1) * 0.5, FState) * FT;
  Result := FM_n1 + K2;
end;

function THysteresisProcessing.RK4Solver(H, H_d: Double): Double;
var
  H_1_2, H_d_1_2, K1, K2, K3, K4: Double;
const
  OneSixth = 1.0 / 6.0;
begin
  H_1_2 := (H + FH_n1) * 0.5;
  H_d_1_2 := (H_d + FH_d_n1) * 0.5;

  K1 := HysteresisFunc(FM_n1, FH_n1, FH_d_n1, FState) * FT;
  K2 := HysteresisFunc(FM_n1 + K1 * 0.5, H_1_2, H_d_1_2, FState) * FT;
  K3 := HysteresisFunc(FM_n1 + K2 * 0.5, H_1_2, H_d_1_2, FState) * FT;
  K4 := HysteresisFunc(FM_n1 + K3, H, H_d, FState) * FT;

  Result := FM_n1 + K1 * OneSixth + K2 * OneThird + K3 * OneThird + K4 * OneSixth;
end;

function THysteresisProcessing.NRSolver(H, H_d: Double; NIterations: Integer): Double;
var
  M, LastDMdt, DMdt, DMdtPrime, DeltaNR: Double;
  N: Integer;
begin
  M := FM_n1;
  LastDMdt := HysteresisFunc(FM_n1, FH_n1, FH_d_n1, FState);

  for N := 1 to NIterations do
  begin
    DMdt := HysteresisFunc(M, H, H_d, FState);
    DMdtPrime := HysteresisFuncPrime(H_d, DMdt, FState);
    DeltaNR := (M - FM_n1 - FTalpha * (DMdt + LastDMdt)) /
      (1.0 - FTalpha * DMdtPrime);
    M := M - DeltaNR;
  end;

  Result := M;
end;

function THysteresisProcessing.STNSolver(H, H_d: Double): Double;
var
  Input: array[0..4] of Double;
  Scale: Double;
  I: Integer;
begin
  Input[0] := H;
  Input[1] := H_d * STNDiffMakeup;
  Input[2] := FH_n1;
  Input[3] := FH_d_n1 * STNDiffMakeup;
  Input[4] := FM_n1;

  // scale by the drive parameter (first four entries only)
  Scale := 0.7071 / FState.A;
  for I := 0 to 3 do
    Input[I] := Input[I] * Scale;

  Result := FSTN.Process(Input) + FM_n1;
end;

function THysteresisProcessing.Process(Solver: TSolverType; H: Double): Double;
var
  H_d, M: Double;
  IllCondition: Boolean;
begin
  H_d := Deriv(H, FH_n1, FH_d_n1, FT);

  case Solver of
    stRK2: M := RK2Solver(H, H_d);
    stRK4: M := RK4Solver(H, H_d);
    stNR4: M := NRSolver(H, H_d, 4);
    stNR8: M := NRSolver(H, H_d, 8);
    stSTN: M := STNSolver(H, H_d);
  else
    M := 0.0;
  end;

  // guard against the solver going unstable
  IllCondition := IsNan(M) or (M > FUpperLim);
  if IllCondition then
  begin
    M := 0.0;
    H_d := 0.0;
  end;

  FM_n1 := M;
  FH_n1 := H;
  FH_d_n1 := H_d;

  Result := M;
end;

end.
