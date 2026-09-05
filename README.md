# CHOW Tape Model — Delphi VST 2.4 port

A Delphi port of Jatin Chowdhury's [AnalogTapeModel](https://github.com/jatinchowdhury18/AnalogTapeModel),
which is written in C++ on top of JUCE. This project reimplements the whole
plug-in — DSP, parameters, factory presets and editor — in Object Pascal with no
external dependencies beyond the Delphi RTL, the Win32 API and GDI+, and exposes
it as a VST 2.4 DLL.

Like the original, it is licensed under the **GPLv3**.

---

## Building

Open `ChowTapeModel.dproj` in Delphi (10.4 Sydney or newer; it uses inline
variables-free code but does rely on generics, anonymous methods and the
`System.JSON` unit) and build the `Release` configuration.

Both platforms are configured:

| Platform | Output |
| --- | --- |
| Win32 | `bin\Win32\Release\ChowTapeModel.dll` |
| Win64 | `bin\Win64\Release\ChowTapeModel.dll` |

From the command line:

```
msbuild ChowTapeModel.dproj /p:Config=Release /p:Platform=Win64
msbuild ChowTapeModel.dproj /p:Config=Release /p:Platform=Win32
```

The DLL exports both `VSTPluginMain` and the legacy `main` entry point, so old
and new hosts can both load it.

## Deploying

Copy `ChowTapeModel.dll` into your VST folder. That is the whole job: the STN
networks and the two Roboto Condensed faces are linked into the DLL, so there
is nothing to place alongside it.

`deploy.cmd <target folder> [Win32|Win64]` does it for you.

### Overriding the STN networks

If a folder named `STN_Models` sits next to the DLL containing
`hyst_width_*.json` files, those are loaded in preference to the embedded
copies. That is only useful for trying retrained networks without rebuilding;
normal installs should not have one.

### Checking what loaded

The **cog button** at the bottom right reports what is actually in use:

```
Font: Roboto Condensed (embedded)
STN models: 231/231 (embedded)          <- or "(override: C:\...)"
```

`231` is 11 bias widths x 21 saturation steps. If the networks ever fail to
load, the STN tape mode falls back to RK4 rather than going silent, and the
menu says so.

## Layout

```
ChowTapeModel.dpr / .dproj      VST 2.4 DLL project
src\
  vst\
    ChowTape.VST2.Intf.pas          VST 2.4 ABI (AEffect, opcodes) — no SDK needed
    ChowTape.VST2.Plugin.pas        host <-> processor/editor glue
  dsp\
    ChowTape.DSP.Types.pas          audio buffers, smoothed values, JUCE-compatible PRNG
    ChowTape.DSP.FastMath.pas       exp/log/cos/tanh/coth for the hot paths
    ChowTape.DSP.Filters.pas        IIR/shelf/Linkwitz-Riley/SVF/FIR/DC blocker
    ChowTape.DSP.DelayLine.pas      Lagrange 3rd/5th order fractional delay
    ChowTape.DSP.Oversampling.pas   half-band filter design + 2x oversampling stages
    ChowTape.DSP.VariableOS.pas     1x..16x, minimum or linear phase
    ChowTape.DSP.Utils.pas          level detector, Gaussian noise
    ChowTape.DSP.Basics.pas         gain, dry/wet, smooth bypass
    ChowTape.DSP.Hysteresis*.pas    Jiles-Atherton model, solvers, STN network
    ChowTape.DSP.ToneControl.pas    pre/post-emphasis shelving EQ
    ChowTape.DSP.Compression.pas    tape compression
    ChowTape.DSP.InputFilters.pas   low/high cut with makeup path
    ChowTape.DSP.MidSide.pas        mid/side encode + stereo balance
    ChowTape.DSP.Chew.pas           dropouts
    ChowTape.DSP.Degrade.pas        noise / lowpass / level loss
    ChowTape.DSP.Loss.pas           playhead loss FIR, head bump, azimuth
    ChowTape.DSP.WowFlutter.pas     wow & flutter LFOs + Ornstein-Uhlenbeck drift
    ChowTape.DSP.Scope.pas          oscilloscope and I/O meters
  params\
    ChowTape.Params.pas             parameter definitions, ranges, formatting
    ChowTape.Presets.pas            95 factory presets (generated)
    ChowTape.PresetLibrary.pas      user presets, .chowpreset XML, dirty state
  gui\
    ChowTape.GUI.Graphics.pas       GDI+ helpers, palette, knob/pointer/power drawing
    ChowTape.GUI.Controls.pas       sliders, buttons, combos, tabs, scope, meters
    ChowTape.GUI.Editor.pas         window, flex layout, menus
  ChowTape.Processor.pas            the full signal chain
ChowTapeResources.rc            links the networks and fonts into the DLL
resources\                      inputs to the .rc, plus the JSON they came from
tools\gen_presets.py            regenerates ChowTape.Presets.pas
tools\gen_stn_models.py         regenerates resources\stn_models.bin
Manual\ Notes\ Paper\           reference material kept from the original
```

`Manual`, `Notes` and `Paper` are carried over from the C++ project: the manual
describes the same controls this port has, and the notes and DAFx paper are the
derivation behind the hysteresis model in `ChowTape.DSP.Hysteresis.pas`. Nothing
in the build depends on them.

`src\params\ChowTape.Presets.pas` is generated: all 95 presets are already
compiled in, and the build does not need anything else. `tools\gen_presets.py`
only has to be run again if the upstream presets change or the unit conversion
does. It reads the original's `.chowpreset` files, which are not part of this
repository, so fetch them first:

```
git clone https://github.com/jatinchowdhury18/AnalogTapeModel ../upstream
python3 tools/gen_presets.py ../upstream/Plugin/Source/Presets/PresetConfigs
```

## Performance

Measured with `bench\ChowTapeBench.dproj` at 96 kHz, stereo, as a percentage of
one core. Halve these for 48 kHz.

| | Win64 | Win32 |
| --- | --- | --- |
| Defaults, 2x oversampling | 15% | 18% |
| Defaults, 16x | 47% | 113% |
| Every section on, 2x | 25% | 32% |
| Every section on, 16x | 57% | 127% |

Tape modes at 16x oversampling, solver only, Win64: RK2 38%, STN 50%, RK4 69%,
NR4 85%, NR8 158%. Win32 runs roughly twice the cost of Win64 throughout --
32-bit Delphi computes on the x87 with `Extended` intermediates, and dcc32 has
no SSE2 mode to switch to.

### Where the time went

Profiling moved the chain about 25% faster than the first working version. The
changes worth knowing about, because they shape the code:

* **`ChowTape.DSP.FastMath`.** `System.Math.Tanh` clears the floating-point
  status word and classifies the operand's IEEE bits before doing any
  arithmetic. `HysteresisFunc` calls it four to nine times per sample per
  channel at the oversampled rate, which measured ~45% of the entire solver.
  Replacing it with a table-assisted exp reduction took the solver down 27% on
  Win64. The same unit's log and cos replace `Log10`/`Power` in the decibel
  conversions and `Cos` in the wow/flutter oscillators.
* **x86 uses the RTL instead.** Three separate times a software polynomial lost
  to the x87's hardware `F2XM1`, `FYL2X` and `FCOS`. `QuickExp`, `QuickLog` and
  `QuickCos` dispatch on the target; everything internal goes through those.
* **The delay lines had a modulo per tap.** `FTotalSize` is not a power of two,
  so that was a real integer division four to six times per sample. The index
  can only ever exceed the buffer once, so a conditional subtract replaces it.
* **The loss filter's FIR** indexed dynamic arrays directly, which made the
  compiler reload their pointers every tap, and accumulated into one variable,
  which serialised on floating-point add latency. Hoisting the pointers and
  splitting across four accumulators cut it 69% on Win32 and 32% on Win64.

Accuracy of the fast routines is checked against the RTL by the benchmark on
every run: relative error is around 1e-10 or better, against a double's 2.2e-16
and a tape model whose parameters are known to two significant figures.

Defining `CHOWTAPE_RTL_MATH` in the project reverts the solver and the STN
network to `System.Math`, if you ever want to rule the fast versions out.

## Benchmarking

`bench\ChowTapeBench.dproj` is a console program that times the DSP. Build and
run the **Release** configuration -- the Debug build has range and overflow
checking on and the numbers are meaningless.

It reports four things: the transcendentals against their fast replacements,
the accuracy of those replacements, every tape mode against every oversampling
factor, and each processor in the chain measured on its own.

```
bench\bin\Win64\Release\ChowTapeBench.exe
```

The STN networks are found by walking up from the executable to
`resources\STN_Models`, so the benchmark does not need the resource blob.

## Signal chain

Identical ordering to the original `PluginProcessor::processAudioBlock`:

```
input gain -> input filters -> [mid/side encode] -> tone in -> compression
  -> hysteresis -> tone out -> chew -> degrade -> wow/flutter -> loss
  -> latency compensation -> [mid/side decode] -> filter makeup
  -> output gain -> dry/wet
```

## What was ported faithfully

* **Hysteresis**: the Jiles-Atherton model with all six Tape Modes — RK2, RK4,
  NR4, NR8, STN and the legacy V1 bias-oscillator mode — including the per-solver
  input clipping levels, the makeup gain and the DC blockers.
* **STN solver**: the 11 x 21 trained networks are parsed from the original JSON
  at load time and evaluated by a hand-written 5-4-4-1 dense/tanh forward pass.
* **Oversampling**: `juce::dsp::Oversampling` including both half-band filter
  designs (polyphase-IIR elliptic and equiripple FIR) so latency figures and
  aliasing behaviour match. 1x/2x/4x/8x/16x, minimum or linear phase.
* **All other processors**: coefficient formulas, smoothing time constants,
  block sub-division sizes (64 samples for chew, 2048 for degrade) and the
  crossfaded bypass behaviour are all preserved.
* **Parameters**: same IDs, ranges, skew factors, defaults and display strings.
* **Presets**: all 95 factory presets, unit-converted where the original files
  predate the metres-to-microns change.
* **GUI**: the gui.xml layout is reproduced — four tabbed sections, the scope
  with IN/OUT readouts, wow/flutter lights, tooltips, the speed shortcut
  buttons, the sync menus, oversampling and mix-group menus, and the preset
  browser. The knob, pointer, power switch and background were vector SVGs in
  the original and are redrawn with the same geometry in GDI+.

## Presets

The 95 factory presets are compiled in. User presets are `.chowpreset` XML --
the same format the original writes -- so libraries move between the two
plug-ins in both directions, and files written by older versions load correctly
(spacing/thickness/gap in metres, dry/wet as a percentage and the pre-2.11 `os`
parameter are all converted on the way in).

They live in `%APPDATA%\ChowdhuryDSP\ChowTape\Presets` by default; the folder
is remembered in `UserPresets.txt` beside it and can be changed from the preset
menu. Sub-folders become sub-menus.

The preset menu offers Save Preset As, Resave, Delete, Go to Preset Folder and
Choose Preset Folder; the arrows either side of the name step through the
library, and a trailing `*` means the preset has been edited.

Hosts see the 95 factory presets as VST programs. User presets deliberately are
not exposed that way: VST 2.4 fixes the program count when the plug-in is
instantiated, and user presets come and go.

## Where it deliberately differs

* **`LossFilter::calcCoefs` accumulator.** The original does `h[idx] += ...`
  into a buffer it never clears, so each recomputation folds ~1/N of the
  previous impulse response into the new one. That is unmistakably a bug (the
  filter's response ends up depending on how many times you moved a knob), so
  this port zeroes the buffer first. The audible difference is very small.
* **No SIMD.** The original processes two channels at once with xsimd in the
  hysteresis loop. Delphi has no SIMD intrinsics and neither compiler
  auto-vectorises, so matching that would mean hand-written assembly -- and in
  two versions, since 64-bit Delphi only allows whole routines to be assembly.
  This port follows the scalar reference path instead: same maths, one channel
  at a time. The transcendental work described under Performance recovered more
  than the 2x that SIMD would have offered, so it has not been worth it.
* **The transcendentals are not the RTL's.** `exp`, `log`, `cos`, `tanh` and
  `coth` in the hot paths come from `ChowTape.DSP.FastMath`, agreeing with
  `System.Math` to about 1e-10. The original leans on xsimd's equivalents, which
  are approximations of the same kind.
* **Mix groups** are simpler than the original's. Both keep the group state in
  a process-wide singleton, so the scope is the same -- instances in one host
  sync, instances in two hosts do not. What differs is:
  * The original stores a value map per group, so *joining* a group snaps you
    to that group's current settings (or seeds them, if you are the first in).
    This port only propagates changes made from now on; joining does nothing
    until somebody moves a control.
  * The original listens to every parameter change, so loading a preset syncs
    the whole group. Here only host automation and control edits propagate --
    preset loads do not.
  * The original defers propagation to the message thread with
    `MessageManager::callAsync`. This port propagates synchronously on whatever
    thread made the change, which means taking a lock on the audio thread when
    the host automates a parameter.
* **The filled part of a knob or a track is the accent colour**, not the
  original's pale cyan `FF9CBCBD` -- which is the only cool colour in an
  otherwise red, amber and slate palette. The dry/wet knob loses the brighter
  teal `FF0BBDC2` gui.xml gives it for the same reason. `clSliderTrack` in
  `ChowTape.GUI.Graphics` puts both back.
* **The value arcs, tracks, power buttons and scope trace glow.** GDI+ has
  neither a blur nor an additive blend, so the halo is the same shape stroked
  `GlowLayers` times over, each pass wider and fainter. `Glow` in the settings
  menu turns it off, remembered in
  `%USERPROFILE%\ChowdhuryDSP\ChowTape\Settings.txt`; the same menu reports
  the average repaint time so the cost can be read off rather than guessed at.
* **No auto-update check, no iOS tip jar, no CLAP/AU/LV2 wrappers**, and the
  settings menu is a short informational menu rather than the original's.
* **`dryWet` initial value.** `prepareToPlay` in the original divides an already
  0..1 parameter by 100; this port sets it directly. The only effect is that the
  original ramps the mix up over its first block.
* **The STN networks are stored as a packed float64 blob**, not the original's
  JSON. Same 11,319 weights, but 88 KB instead of 968 KB and no parsing at
  instantiation. `tools\gen_stn_models.py` rebuilds it from the JSON.
* **If the networks ever fail to load, STN falls back to RK4** instead of
  producing silence. This cannot happen with a normal build, since they are
  linked in; it can if a broken loose `STN_Models` override is present. Remove
  the fallback in `THysteresisProcessor.SetSolver` to make it fail loudly.

## Notes for host integration

* Latency is reported through `AEffect.initialDelay` and re-announced with
  `audioMasterIOChanged` whenever it changes (it depends on the oversampling
  factor and on which sections are switched on).
* State is stored as a chunk (`effFlagsProgramChunks`) in a plain
  `key=value` text format, so it is readable and forward-compatible.
* The 95 factory presets are also exposed as VST programs, so hosts that browse
  programs will list them.
* Tempo for the wow/flutter sync menus comes from `audioMasterGetTime`.
* The window is resizable from the corner grip, as `resizable="1"
  resize-corner="1"` in the original's `gui.xml` asks for. Resizing reflows the
  flex layout rather than scaling it, so the fixed-height header, tab bars and
  read-outs stay the size they were designed at. The host is told through
  `audioMasterSizeWindow`, `effEditGetRect` reports the current size, and the
  size is kept in the state chunk so a session reopens as it was left.
* Stereo in / stereo out. The mid/side and azimuth controls are disabled when
  the host is not running the plug-in in stereo.
