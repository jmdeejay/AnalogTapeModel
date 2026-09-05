library ChowTapeModel;

{
  CHOW Tape Model -- Delphi VST 2.4 port.

  A port of Jatin Chowdhury's AnalogTapeModel (github.com/jatinchowdhury18/
  AnalogTapeModel), originally written in C++ with JUCE. Licensed under the
  GPLv3, like the original.
}

{$R *.res}

// STN networks and the Roboto Condensed faces, linked in so the DLL is a
// single self-contained file. brcc32 compiles the .rc automatically.
{$R 'ChowTapeResources.res' 'ChowTapeResources.rc'}

uses
  System.SysUtils,
  System.Classes,
  ChowTape.VST2.Intf in 'src\vst\ChowTape.VST2.Intf.pas',
  ChowTape.VST2.Plugin in 'src\vst\ChowTape.VST2.Plugin.pas',
  ChowTape.DSP.Types in 'src\dsp\ChowTape.DSP.Types.pas',
  ChowTape.DSP.FastMath in 'src\dsp\ChowTape.DSP.FastMath.pas',
  ChowTape.DSP.Filters in 'src\dsp\ChowTape.DSP.Filters.pas',
  ChowTape.DSP.DelayLine in 'src\dsp\ChowTape.DSP.DelayLine.pas',
  ChowTape.DSP.Oversampling in 'src\dsp\ChowTape.DSP.Oversampling.pas',
  ChowTape.DSP.VariableOS in 'src\dsp\ChowTape.DSP.VariableOS.pas',
  ChowTape.DSP.Utils in 'src\dsp\ChowTape.DSP.Utils.pas',
  ChowTape.DSP.Basics in 'src\dsp\ChowTape.DSP.Basics.pas',
  ChowTape.DSP.HysteresisSTN in 'src\dsp\ChowTape.DSP.HysteresisSTN.pas',
  ChowTape.DSP.Hysteresis in 'src\dsp\ChowTape.DSP.Hysteresis.pas',
  ChowTape.DSP.HysteresisProcessor in 'src\dsp\ChowTape.DSP.HysteresisProcessor.pas',
  ChowTape.DSP.ToneControl in 'src\dsp\ChowTape.DSP.ToneControl.pas',
  ChowTape.DSP.Compression in 'src\dsp\ChowTape.DSP.Compression.pas',
  ChowTape.DSP.InputFilters in 'src\dsp\ChowTape.DSP.InputFilters.pas',
  ChowTape.DSP.MidSide in 'src\dsp\ChowTape.DSP.MidSide.pas',
  ChowTape.DSP.Chew in 'src\dsp\ChowTape.DSP.Chew.pas',
  ChowTape.DSP.Degrade in 'src\dsp\ChowTape.DSP.Degrade.pas',
  ChowTape.DSP.Loss in 'src\dsp\ChowTape.DSP.Loss.pas',
  ChowTape.DSP.WowFlutter in 'src\dsp\ChowTape.DSP.WowFlutter.pas',
  ChowTape.DSP.Scope in 'src\dsp\ChowTape.DSP.Scope.pas',
  ChowTape.Params in 'src\params\ChowTape.Params.pas',
  ChowTape.Presets in 'src\params\ChowTape.Presets.pas',
  ChowTape.PresetLibrary in 'src\params\ChowTape.PresetLibrary.pas',
  ChowTape.GUI.Graphics in 'src\gui\ChowTape.GUI.Graphics.pas',
  ChowTape.GUI.Menu in 'src\gui\ChowTape.GUI.Menu.pas',
  ChowTape.GUI.Controls in 'src\gui\ChowTape.GUI.Controls.pas',
  ChowTape.GUI.Editor in 'src\gui\ChowTape.GUI.Editor.pas',
  ChowTape.Processor in 'src\ChowTape.Processor.pas';

exports
  VSTPluginMain name 'VSTPluginMain',
  VSTPluginMain name 'main';

begin
  // audio, GUI and host threads all touch the memory manager
  IsMultiThread := True;
end.
