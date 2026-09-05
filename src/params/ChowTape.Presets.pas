unit ChowTape.Presets;

{
  Factory presets, converted from the .chowpreset files that ship with the
  original plug-in. Values are in the parameter's own units.

  This file is generated -- see tools/gen_presets.py.
}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, ChowTape.Params;

type
  TPresetParam = record
    ID: string;
    Value: Single;
  end;

  TFactoryPreset = record
    Name: string;
    Vendor: string;
    Category: string;
    Params: TArray<TPresetParam>;
  end;

function FactoryPresetCount: Integer;
function GetFactoryPreset(Index: Integer): TFactoryPreset;
function GetFactoryPresetName(Index: Integer): string;
function GetFactoryPresetCategory(Index: Integer): string;
{ Applies a preset to the parameter set, resetting every other parameter to
  its default first, exactly as the original does. }
procedure ApplyPreset(Params: TParameterSet; const Preset: TFactoryPreset);
function FindPresetIndex(const Name: string): Integer;

implementation

type
  TPresetDef = record
    Name: string;
    Vendor: string;
    Category: string;
    Data: string;   // "id=value;id=value;..."
  end;

const

  Presets: array[0..94] of TPresetDef = (
    (Name: 'Disintegrated Memories'; Vendor: 'AEIOU'; Category: 'AEIOU';
     Data: 'chew_depth=0.8;chew_freq=0.09999999;chew_var=0.6;deg_amt=0.8;deg_depth=0.4;deg_var=0.8;depth=0.8;drive=0.4;drywet=1;gap=30;h_bass=-0.2;h_treble=0.8;ingain=2;mode=2;os_factor=2;outgain=0;rate=0.5;sat=0.8;spacing=10;speed=30;thick=20;width=0.2;wow_depth=0.6;wow_rate=0.4;chew_onoff=1;deg_onoff=1;flutter_onoff=1;h_tfreq=499.9999;ifilt_high=7999.999;ifilt_low=40;ifilt_makeup=0;ifilt_onoff=1;tone_onoff=1'),
    (Name: 'Funk That 1987'; Vendor: 'AEIOU'; Category: 'AEIOU';
     Data: 'chew_depth=0.01;chew_freq=0.01;chew_var=1;deg_amt=0.09999999;deg_depth=0.09999999;deg_var=0.05;depth=0.2;drive=0.6;drywet=1;gap=10;h_bass=-0.6;h_treble=-0.4;ingain=0;mode=2;os_factor=3;outgain=0;rate=0.2;sat=0.6;spacing=0.1;speed=15;thick=0.1;width=0.3;wow_depth=0.2;wow_rate=0.2;chew_onoff=1;deg_onoff=1;flutter_onoff=1;h_tfreq=499.9999;ifilt_high=12000;ifilt_low=20;ifilt_makeup=0;ifilt_onoff=1;tone_onoff=1'),
    (Name: 'Hello Hangover'; Vendor: 'AEIOU'; Category: 'AEIOU';
     Data: 'azimuth=0;chew_depth=0.02;chew_freq=0.02;chew_onoff=0;chew_var=1;comp_amt=4;comp_attack=10;comp_onoff=0;comp_release=200;deg_amt=0.2;deg_depth=0.2;deg_env=0;deg_onoff=0;deg_point1x=0;deg_var=0.02;depth=0;drive=0.6;drywet=1;flutter_onoff=1;gap=4;h_bass=-0.6;h_tfreq=499.9999;h_treble=-0.4;hyst_onoff=0;ifilt_high=16000;ifilt_low=30;ifilt_makeup=0;ifilt_onoff=0;ingain=0;loss_onoff=0;mix_group=0;mode=4;os_factor=2;os_mode=0;outgain=0;rate=0;sat=0.6;spacing=0.1;speed=3.75;thick=0.1;tone_onoff=0;width=0.3;wow_depth=1;wow_drift=0;wow_rate=0.51;wow_var=0'),
    (Name: 'I Have A Radio'; Vendor: 'AEIOU'; Category: 'AEIOU';
     Data: 'azimuth=10;chew_depth=0.05;chew_freq=0.8;chew_onoff=1;chew_var=0.8;comp_amt=2.516404;comp_attack=0.9999998;comp_onoff=0;comp_release=99.99999;deg_amt=0;deg_depth=0.09999999;deg_env=0;deg_onoff=1;deg_point1x=0;deg_var=0.05;depth=0.2;drive=0.6;drywet=1;flutter_onoff=0;gap=10;h_bass=-0.8;h_tfreq=200.1187;h_treble=-0.8;hyst_onoff=0;ifilt_high=6000;ifilt_low=400;ifilt_makeup=0;ifilt_onoff=1;ingain=0;loss_onoff=0;mix_group=0;mode=4;os_factor=2;os_mode=0;outgain=4;rate=0.3;sat=0.6;spacing=0.1;speed=15;thick=0.1;tone_onoff=1;width=0.3;wow_depth=0.2;wow_drift=1;wow_rate=0.42;wow_var=1'),
    (Name: 'Warehouse 1997'; Vendor: 'AEIOU'; Category: 'AEIOU';
     Data: 'azimuth=10;chew_depth=0.02;chew_freq=0.02;chew_onoff=1;chew_var=1;comp_amt=4;comp_attack=10;comp_onoff=1;comp_release=200;deg_amt=0.2;deg_depth=0.2;deg_env=0;deg_onoff=1;deg_point1x=0;deg_var=0.02;depth=0.2;drive=0.6;drywet=1;flutter_onoff=1;gap=4;h_bass=-0.6;h_tfreq=499.9999;h_treble=-0.4;hyst_onoff=1;ifilt_high=16000;ifilt_low=30;ifilt_makeup=0;ifilt_onoff=1;ingain=-2;loss_onoff=1;mix_group=0;mode=2;os_factor=2;os_mode=0;outgain=-2;rate=0.3;sat=0.6;spacing=0.1;speed=3.75;thick=0.1;tone_onoff=1;width=0.3;wow_depth=0.2;wow_drift=1;wow_rate=0.42;wow_var=1'),
    (Name: 'Bad Tape Good Player'; Vendor: 'Carter'; Category: 'Carter';
     Data: 'azimuth=0;chew_depth=0.03;chew_freq=0.11;chew_onoff=1;chew_var=0;deg_amt=0.19;deg_depth=0.58;deg_env=0.05;deg_onoff=1;deg_point1x=1;deg_var=0.15;depth=0.05;drive=0.5;drywet=1;flutter_onoff=1;gap=2.953712;h_bass=0;h_tfreq=1094.92;h_treble=0.66;hyst_onoff=1;ifilt_high=22000;ifilt_low=25.7957;ifilt_makeup=0;ifilt_onoff=1;ingain=0;loss_onoff=1;mix_group=0;mode=2;os_factor=1;outgain=0;rate=0.3;sat=0.7;spacing=12.04993;speed=50;thick=3.139518;tone_onoff=1;width=0.5;wow_depth=0.05;wow_drift=0.05;wow_rate=0.3;wow_var=0.05'),
    (Name: 'Cozy Unstable'; Vendor: 'Carter'; Category: 'Carter';
     Data: 'chew_depth=0;chew_freq=0;chew_onoff=0;chew_var=0;deg_amt=0.15;deg_depth=0.09;deg_onoff=1;deg_var=0;depth=0.3;drive=0.5;drywet=1;flutter_onoff=1;gap=1.04886;h_bass=0;h_tfreq=499.9999;h_treble=0.39;hyst_onoff=1;ifilt_high=22000;ifilt_low=20;ifilt_makeup=0;ifilt_onoff=0;ingain=0;loss_onoff=1;mix_group=0;mode=2;os_factor=2;outgain=0;rate=0.36;sat=0.5;spacing=4.924258;speed=30;thick=0.7714379;tone_onoff=1;width=0.5;wow_depth=0.3;wow_rate=0.4;deg_env=0.05;deg_point1x=0;wow_drift=0;wow_var=0;os_mode=0;os_factor=1'),
    (Name: 'Fast Wobble'; Vendor: 'Carter'; Category: 'Carter';
     Data: 'azimuth=0;chew_depth=0;chew_freq=0;chew_onoff=0;chew_var=0;deg_amt=0.05;deg_depth=0.05;deg_env=0.05;deg_onoff=1;deg_point1x=1;deg_var=0.05;depth=0.49;drive=0.52;drywet=1;flutter_onoff=1;gap=1.2;h_bass=0;h_tfreq=499.9999;h_treble=0;hyst_onoff=1;ifilt_high=22000;ifilt_low=27.30974;ifilt_makeup=0;ifilt_onoff=1;ingain=0;loss_onoff=1;mix_group=0;mode=2;os_factor=1;outgain=0;rate=0.2;sat=0.5;spacing=1.2;speed=7.5;thick=1.2;tone_onoff=1;width=0.6;wow_depth=0.2;wow_drift=0.5;wow_rate=1;wow_var=0.09999999;os_mode=0'),
    (Name: 'Found Tape Player'; Vendor: 'Carter'; Category: 'Carter';
     Data: 'azimuth=0;chew_depth=0.09999999;chew_freq=0.5;chew_onoff=0;chew_var=0;comp_amt=0.9999999;comp_attack=21.00346;comp_onoff=1;comp_release=50;deg_amt=0.2;deg_depth=0.09999999;deg_env=0;deg_onoff=1;deg_point1x=1;deg_var=0.05;depth=0.2;drive=0.5;drywet=1;flutter_onoff=1;gap=1.1;h_bass=0;h_tfreq=499.9999;h_treble=0;hyst_onoff=1;ifilt_high=5027.458;ifilt_low=50.00001;ifilt_makeup=0;ifilt_onoff=1;ingain=0;loss_onoff=1;mix_group=0;mode=5;os_factor=1;os_mode=0;outgain=-2;rate=0.5;sat=0.5;spacing=4;speed=7.5;thick=1.5;tone_onoff=1;width=0.75;wow_depth=0.5;wow_drift=0.2;wow_rate=0.11;wow_var=0.09999999'),
    (Name: 'Good Tape Bad Player'; Vendor: 'Carter'; Category: 'Carter';
     Data: 'azimuth=0;chew_depth=0;chew_freq=0;chew_onoff=1;chew_var=0;deg_amt=0.02;deg_depth=0.21;deg_env=0.05;deg_onoff=1;deg_point1x=1;deg_var=0.04;depth=0.15;drive=0.5;drywet=1;flutter_onoff=1;gap=1;h_bass=0;h_tfreq=1094.92;h_treble=0.66;hyst_onoff=1;ifilt_high=22000;ifilt_low=25.7957;ifilt_makeup=0;ifilt_onoff=1;ingain=0;loss_onoff=1;mix_group=0;mode=2;os_factor=1;outgain=0;rate=0.66;sat=0.6;spacing=0.1;speed=50;thick=0.1;tone_onoff=1;width=0.5;wow_depth=0.15;wow_drift=0;wow_rate=0.3;wow_var=0.04'),
    (Name: 'INIT'; Vendor: 'Carter'; Category: 'Carter';
     Data: 'azimuth=0;chew_depth=0;chew_freq=0;chew_onoff=1;chew_var=0;deg_amt=0;deg_depth=0;deg_env=0;deg_onoff=1;deg_point1x=0;deg_var=0;depth=0;drive=0.5;drywet=1;flutter_onoff=1;gap=1;h_bass=0;h_tfreq=499.9999;h_treble=0;hyst_onoff=1;ifilt_high=22000;ifilt_low=20;ifilt_makeup=0;ifilt_onoff=1;ingain=0;loss_onoff=1;mix_group=0;mode=0;os_factor=1;outgain=0;rate=0.3;sat=0.5;spacing=0.1;speed=30;thick=0.1;tone_onoff=1;width=0.5;wow_depth=0;wow_drift=0;wow_rate=0.25;wow_var=0'),
    (Name: 'Just Warmth'; Vendor: 'Carter'; Category: 'Carter';
     Data: 'azimuth=0;chew_depth=0;chew_freq=0;chew_onoff=0;chew_var=0;deg_amt=0;deg_depth=0;deg_env=0;deg_onoff=0;deg_point1x=0;deg_var=0;depth=0;drive=0.5;drywet=0.5;flutter_onoff=1;gap=1.035636;h_bass=0;h_tfreq=499.9999;h_treble=0;hyst_onoff=1;ifilt_high=22000;ifilt_low=20;ifilt_makeup=0;ifilt_onoff=0;ingain=0;loss_onoff=1;mix_group=0;mode=0;os_factor=1;outgain=0;rate=0.3;sat=0.5;spacing=1.955416;speed=3.75;thick=0.6927272;tone_onoff=1;width=0.4;wow_depth=0;wow_drift=0;wow_rate=0.25;wow_var=0'),
    (Name: 'Low Cut High Cut'; Vendor: 'Carter'; Category: 'Carter';
     Data: 'azimuth=0;chew_depth=0;chew_freq=0;chew_onoff=1;chew_var=0;deg_amt=0;deg_depth=0;deg_env=0;deg_onoff=1;deg_point1x=0;deg_var=0;depth=0;drive=0.5;drywet=1;flutter_onoff=1;gap=1;h_bass=0;h_tfreq=499.9999;h_treble=0;hyst_onoff=1;ifilt_high=2000;ifilt_low=213.8537;ifilt_makeup=0;ifilt_onoff=1;ingain=0;loss_onoff=1;mix_group=0;mode=0;os_factor=1;outgain=3.450001;rate=0.3;sat=0.5;spacing=0.1;speed=30;thick=0.1;tone_onoff=1;width=0.5;wow_depth=0;wow_drift=0;wow_rate=0.25;wow_var=0'),
    (Name: 'Old Telephone'; Vendor: 'Carter'; Category: 'Carter';
     Data: 'azimuth=0;chew_depth=0.01;chew_freq=0.01;chew_onoff=1;chew_var=0.01;deg_amt=0.17;deg_depth=0.34;deg_env=0.15;deg_onoff=1;deg_point1x=0;deg_var=0.03;depth=0.2;drive=0.58;drywet=1;flutter_onoff=1;gap=1.10576;h_bass=0.25;h_tfreq=588.5361;h_treble=-0.11;hyst_onoff=1;ifilt_high=2000;ifilt_low=349.1327;ifilt_makeup=0;ifilt_onoff=1;ingain=0;loss_onoff=1;mix_group=0;mode=0;os_factor=1;outgain=7.07;rate=0.18;sat=0.62;spacing=1.031176;speed=30;thick=0.3239527;tone_onoff=1;width=0.88;wow_depth=0.27;wow_drift=0.19;wow_rate=0.25;wow_var=0.08'),
    (Name: 'Punchy Lofi Drums'; Vendor: 'Carter'; Category: 'Carter';
     Data: 'chew_depth=0;chew_freq=0;chew_onoff=0;chew_var=0;deg_amt=0.09999999;deg_depth=0.09;deg_onoff=1;deg_var=0;depth=0.3;drive=0.8;drywet=1;flutter_onoff=1;gap=1.04886;h_bass=0;h_tfreq=499.9999;h_treble=0.39;hyst_onoff=1;ifilt_high=2000;ifilt_low=24.49902;ifilt_makeup=0;ifilt_onoff=1;ingain=0;loss_onoff=1;mix_group=0;mode=0;os_factor=1;outgain=0;rate=0.36;sat=0.6;spacing=4.924258;speed=30;thick=0.7714379;tone_onoff=1;width=0.5;wow_depth=0.3;wow_rate=0.4;deg_env=0.03;wow_drift=0;wow_var=0;os_mode=0;os_factor=1'),
    (Name: 'That Dirty LoFi'; Vendor: 'Carter'; Category: 'Carter';
     Data: 'chew_depth=0.02;chew_freq=0.09;chew_onoff=1;chew_var=0.12;deg_amt=0.11;deg_depth=0.03;deg_onoff=1;deg_var=0.13;depth=0.29;drive=0.5;drywet=1;flutter_onoff=1;gap=1.226066;h_bass=0;h_tfreq=310.1037;h_treble=-0.03000003;hyst_onoff=1;ifilt_high=2532.061;ifilt_low=20;ifilt_makeup=0;ifilt_onoff=0;ingain=0;loss_onoff=1;mix_group=0;mode=0;os_factor=1;outgain=0;rate=0.09999999;sat=0.66;spacing=1.797835;speed=3.75;thick=1.965399;tone_onoff=1;width=0.65;wow_depth=0.42;wow_rate=0.2'),
    (Name: 'User_ThatDirtyLofi Less Noise'; Vendor: ''; Category: 'Carter';
     Data: 'chew_depth=0.02;chew_freq=0.09;chew_onoff=1;chew_var=0.12;deg_amt=0.11;deg_depth=0.03;deg_onoff=1;deg_var=0.13;depth=0.29;drive=0.5;drywet=1;flutter_onoff=1;gap=1.226066;h_bass=0;h_tfreq=310.1037;h_treble=-0.03000003;hyst_onoff=1;ifilt_high=2532.061;ifilt_low=20;ifilt_makeup=0;ifilt_onoff=0;ingain=0;loss_onoff=1;mix_group=0;mode=0;os_factor=1;outgain=0;rate=0.09999999;sat=0.66;spacing=1.797835;speed=3.75;thick=1.965399;tone_onoff=1;width=0.65;wow_depth=0.42;wow_rate=0.2;deg_env=0;deg_point1x=1;wow_drift=0;wow_var=0'),
    (Name: 'Underwater'; Vendor: 'Carter'; Category: 'Carter';
     Data: 'azimuth=0;chew_depth=0;chew_freq=0;chew_onoff=0;chew_var=0;comp_amt=0.9999999;comp_attack=40;comp_onoff=1;comp_release=12;deg_amt=0;deg_depth=0;deg_env=0;deg_onoff=0;deg_point1x=0;deg_var=0;depth=0.35;drive=0.5;drywet=1;flutter_onoff=1;gap=5;h_bass=-0.4;h_tfreq=207.5911;h_treble=0;hyst_onoff=1;ifilt_high=22000;ifilt_low=32;ifilt_makeup=0;ifilt_onoff=1;ingain=0;loss_onoff=1;mix_group=0;mode=1;os_factor=1;os_mode=0;outgain=2;rate=0.32;sat=0.5;spacing=16.5;speed=2;thick=1;tone_onoff=1;width=0.5;wow_depth=0.2;wow_drift=0.3;wow_rate=0.09999999;wow_var=0.16'),
    (Name: '808 Comp and Tone'; Vendor: 'Carter'; Category: 'Carter/Bass';
     Data: 'azimuth=0;chew_depth=0.02;chew_freq=0.03;chew_onoff=1;chew_var=0;deg_amt=0.05;deg_depth=0.05;deg_env=0.36;deg_onoff=1;deg_point1x=1;deg_var=0.05;depth=0.22;drive=0.5;drywet=1;flutter_onoff=1;gap=3.485648;h_bass=1;h_tfreq=246.0556;h_treble=0;hyst_onoff=1;ifilt_high=22000;ifilt_low=20;ifilt_makeup=0;ifilt_onoff=0;ingain=1.33;loss_onoff=1;mix_group=0;mode=3;os_factor=1;outgain=-3.220001;rate=0.5;sat=0.92;spacing=2.059294;speed=15;thick=1.128408;tone_onoff=1;width=1;wow_depth=0.12;wow_drift=0.05;wow_rate=0.09999999;wow_var=0.21;os_mode=0;comp_amt=0.3373707;comp_attack=1.199798;comp_onoff=1;comp_release=122.3165'),
    (Name: '808 Maker'; Vendor: 'Carter'; Category: 'Carter/Bass';
     Data: 'azimuth=0;chew_depth=0.05;chew_freq=0.05;chew_onoff=1;chew_var=0;deg_amt=0.05;deg_depth=0.05;deg_env=0.36;deg_onoff=1;deg_point1x=1;deg_var=0.05;depth=0.27;drive=0.5;drywet=1;flutter_onoff=1;gap=6.92156;h_bass=1;h_tfreq=246.0556;h_treble=0;hyst_onoff=1;ifilt_high=22000;ifilt_low=20;ifilt_makeup=0;ifilt_onoff=0;ingain=1.33;loss_onoff=1;mix_group=0;mode=2;os_factor=1;outgain=-3.220001;rate=0.5;sat=0.92;spacing=2.059294;speed=15;thick=1.128408;tone_onoff=1;width=1;wow_depth=0.12;wow_drift=0.05;wow_rate=0.09999999;wow_var=0.21'),
    (Name: 'Sub Beef'; Vendor: 'Carter'; Category: 'Carter/Bass';
     Data: 'azimuth=0;chew_depth=0;chew_freq=0;chew_onoff=0;chew_var=0;deg_amt=0.25;deg_depth=0.07;deg_env=0.69;deg_onoff=1;deg_point1x=1;deg_var=0;depth=0.14;drive=0.94;drywet=1;flutter_onoff=1;gap=1;h_bass=0;h_tfreq=499.9999;h_treble=0;hyst_onoff=1;ifilt_high=22000;ifilt_low=20;ifilt_makeup=0;ifilt_onoff=0;ingain=0;loss_onoff=1;mix_group=0;mode=0;os_factor=1;outgain=-3.980001;rate=0.05;sat=0.73;spacing=0.1;speed=15;thick=0.1;tone_onoff=1;width=0.4;wow_depth=0.22;wow_drift=0.06;wow_rate=0.05;wow_var=0.07'),
    (Name: 'Warm Tape'; Vendor: 'Carter'; Category: 'Carter/Bass';
     Data: 'azimuth=0;chew_depth=0;chew_freq=0;chew_onoff=1;chew_var=0;deg_amt=0.04;deg_depth=0.21;deg_env=0.09;deg_onoff=1;deg_point1x=1;deg_var=0.01;depth=0.02;drive=0.63;drywet=1;flutter_onoff=1;gap=1.009064;h_bass=0.1999999;h_tfreq=100;h_treble=0.36;hyst_onoff=1;ifilt_high=22000;ifilt_low=20;ifilt_makeup=0;ifilt_onoff=0;ingain=0;loss_onoff=1;mix_group=0;mode=2;os_factor=2;outgain=-2.120001;rate=0.01;sat=0.85;spacing=0.6013616;speed=30;thick=0.2785638;tone_onoff=1;width=0.5;wow_depth=0.05;wow_drift=0.05;wow_rate=0.01;wow_var=0.06'),
    (Name: 'Breaking Up'; Vendor: 'Carter'; Category: 'Carter/Guitar';
     Data: 'azimuth=0;chew_depth=0;chew_freq=0;chew_onoff=0;chew_var=0;deg_amt=0.71;deg_depth=1;deg_env=0.09;deg_onoff=1;deg_point1x=1;deg_var=0.22;depth=0.45;drive=0.5;drywet=1;flutter_onoff=1;gap=1.2;h_bass=0;h_tfreq=499.9999;h_treble=0;hyst_onoff=1;ifilt_high=22000;ifilt_low=32.20283;ifilt_makeup=0;ifilt_onoff=1;ingain=-1.18;loss_onoff=1;mix_group=0;mode=0;os_factor=1;outgain=1.98;rate=0.24;sat=0.6;spacing=1.2;speed=7.5;thick=1.2;tone_onoff=1;width=0.75;wow_depth=0.09999999;wow_drift=0.5;wow_rate=0.7;wow_var=0.37;comp_amt=2.130357;comp_attack=17.8624;comp_onoff=1;comp_release=23.25133'),
    (Name: 'Phaser Like'; Vendor: 'Carter'; Category: 'Carter/Guitar';
     Data: 'azimuth=0;chew_depth=0;chew_freq=0;chew_onoff=0;chew_var=0;deg_amt=0.09999999;deg_depth=0.2;deg_env=0.05;deg_onoff=1;deg_point1x=1;deg_var=0.05;depth=1;drive=0.5;drywet=0.5;flutter_onoff=1;gap=1.2;h_bass=0.2099999;h_tfreq=499.9999;h_treble=-0.02000004;hyst_onoff=1;ifilt_high=22000;ifilt_low=27.30974;ifilt_makeup=0;ifilt_onoff=1;ingain=0;loss_onoff=1;mix_group=0;mode=2;os_factor=2;outgain=1.98;rate=0.09999999;sat=0.6;spacing=1.2;speed=7.5;thick=1.2;tone_onoff=1;width=0.5;wow_depth=0.15;wow_drift=0.5;wow_rate=0.18;wow_var=0.09999999;os_mode=0;comp_amt=0;comp_attack=5;comp_onoff=0;comp_release=200'),
    (Name: 'Short Plucked'; Vendor: 'Carter'; Category: 'Carter/Guitar';
     Data: 'azimuth=0;chew_depth=0.03;chew_freq=0.02;chew_onoff=1;chew_var=0.05;deg_amt=0.11;deg_depth=0.08;deg_env=0.12;deg_onoff=1;deg_point1x=0;deg_var=0.06;depth=0.2;drive=0.5;drywet=1;flutter_onoff=1;gap=1.035101;h_bass=0;h_tfreq=585.757;h_treble=1;hyst_onoff=1;ifilt_high=22000;ifilt_low=20;ifilt_makeup=0;ifilt_onoff=0;ingain=0;loss_onoff=1;mix_group=0;mode=2;os_factor=1;outgain=1.949999;rate=0.3;sat=0.56;spacing=1.614563;speed=7.5;thick=0.6129429;tone_onoff=1;width=0.85;wow_depth=0.16;wow_drift=0.09999999;wow_rate=0.5;wow_var=0.11'),
    (Name: 'Slower Chorus'; Vendor: 'Carter'; Category: 'Carter/Guitar';
     Data: 'azimuth=0;chew_depth=0;chew_freq=0;chew_onoff=0;chew_var=0;deg_amt=0.05;deg_depth=0.05;deg_env=0.05;deg_onoff=1;deg_point1x=1;deg_var=0.05;depth=0.5;drive=0.5;drywet=0.5;flutter_onoff=1;gap=1.2;h_bass=0;h_tfreq=499.9999;h_treble=0;hyst_onoff=1;ifilt_high=22000;ifilt_low=27.30974;ifilt_makeup=0;ifilt_onoff=1;ingain=0;loss_onoff=1;mix_group=0;mode=0;os_factor=1;outgain=1.98;rate=0.3;sat=0.6;spacing=1.2;speed=7.5;thick=1.2;tone_onoff=1;width=0.75;wow_depth=0.11;wow_drift=0.5;wow_rate=0.09999999;wow_var=0.09999999'),
    (Name: 'Vintage Chorus'; Vendor: 'Carter'; Category: 'Carter/Guitar';
     Data: 'azimuth=0;chew_depth=0;chew_freq=0;chew_onoff=0;chew_var=0;deg_amt=0.05;deg_depth=0.05;deg_env=0.05;deg_onoff=1;deg_point1x=1;deg_var=0.05;depth=0.5;drive=0.5;drywet=0.5;flutter_onoff=1;gap=1.2;h_bass=0;h_tfreq=499.9999;h_treble=0;hyst_onoff=1;ifilt_high=22000;ifilt_low=27.30974;ifilt_makeup=0;ifilt_onoff=1;ingain=0;loss_onoff=1;mix_group=0;mode=0;os_factor=1;outgain=1.98;rate=0.5;sat=0.6;spacing=1.2;speed=7.5;thick=1.2;tone_onoff=1;width=0.5;wow_depth=0.11;wow_drift=0.5;wow_rate=0.09999999;wow_var=0.09999999'),
    (Name: 'Hats Shorter'; Vendor: 'Carter'; Category: 'Carter/HighHats';
     Data: 'azimuth=0;chew_depth=0.05;chew_freq=0.05;chew_onoff=0;chew_var=0.03;deg_amt=0.09999999;deg_depth=0.09999999;deg_env=0.05;deg_onoff=1;deg_point1x=1;deg_var=0.08;depth=0.2;drive=0.9;drywet=1;flutter_onoff=1;gap=1.138202;h_bass=0;h_tfreq=1215.144;h_treble=0.4;hyst_onoff=1;ifilt_high=22000;ifilt_low=38.51891;ifilt_makeup=0;ifilt_onoff=1;ingain=0;loss_onoff=1;mix_group=0;mode=0;os_factor=2;outgain=-15;rate=0.05;sat=0.7;spacing=1.226984;speed=30;thick=0.4140153;tone_onoff=1;width=0.15;wow_depth=0.25;wow_drift=0;wow_rate=0.03;wow_var=0.27;os_mode=0'),
    (Name: 'Lofi Vibe'; Vendor: 'Carter'; Category: 'Carter/HighHats';
     Data: 'azimuth=0;chew_depth=0.03;chew_freq=0.03;chew_onoff=0;chew_var=0;deg_amt=0.09999999;deg_depth=0.09999999;deg_env=0.05;deg_onoff=1;deg_point1x=1;deg_var=0.08;depth=0.2;drive=0.55;drywet=1;flutter_onoff=1;gap=1.024085;h_bass=0;h_tfreq=1140.525;h_treble=0.22;hyst_onoff=1;ifilt_high=2947.314;ifilt_low=63.28388;ifilt_makeup=0;ifilt_onoff=1;ingain=0;loss_onoff=1;mix_group=0;mode=0;os_factor=1;outgain=5.07;rate=0;sat=0.6;spacing=2.269279;speed=50;thick=0.4984612;tone_onoff=1;width=1;wow_depth=0.22;wow_drift=0.09999999;wow_rate=0.05;wow_var=0.27;os_mode=0;comp_amt=0;comp_attack=5;comp_onoff=0;comp_release=200'),
    (Name: 'Old MPC'; Vendor: 'Carter'; Category: 'Carter/HighHats';
     Data: 'azimuth=0;chew_depth=0;chew_freq=0;chew_onoff=0;chew_var=0;deg_amt=0.09999999;deg_depth=0.09999999;deg_env=0.05;deg_onoff=1;deg_point1x=1;deg_var=0.08;depth=0.2;drive=0.55;drywet=1;flutter_onoff=1;gap=1.024085;h_bass=0;h_tfreq=499.9999;h_treble=0;hyst_onoff=1;ifilt_high=12048.76;ifilt_low=20;ifilt_makeup=0;ifilt_onoff=1;ingain=0;loss_onoff=1;mix_group=0;mode=0;os_factor=1;outgain=0;rate=0;sat=0.6;spacing=2.269279;speed=15;thick=0.4984612;tone_onoff=1;width=1;wow_depth=0.25;wow_drift=0;wow_rate=0.03;wow_var=0.27'),
    (Name: 'A Little Punch'; Vendor: 'Carter'; Category: 'Carter/Kick';
     Data: 'azimuth=0;chew_depth=0;chew_freq=0;chew_onoff=0;chew_var=0;deg_amt=0.05;deg_depth=0.05;deg_env=0.04;deg_onoff=1;deg_point1x=1;deg_var=0.03;depth=0.08;drive=0.7;drywet=1;flutter_onoff=1;gap=1.042784;h_bass=0;h_tfreq=499.9999;h_treble=0;hyst_onoff=1;ifilt_high=22000;ifilt_low=20;ifilt_makeup=0;ifilt_onoff=1;ingain=0;loss_onoff=1;mix_group=0;mode=3;os_factor=1;outgain=-1.030001;rate=0.15;sat=0.65;spacing=1.599824;speed=7.5;thick=0.2335111;tone_onoff=1;width=0.4;wow_depth=0.05;wow_drift=0.07;wow_rate=0.09;wow_var=0.05'),
    (Name: 'Broken Kick'; Vendor: 'Carter'; Category: 'Carter/Kick';
     Data: 'azimuth=0;chew_depth=0.05;chew_freq=0.08;chew_onoff=1;chew_var=0.08;deg_amt=0.02;deg_depth=0.09999999;deg_env=0;deg_onoff=1;deg_point1x=1;deg_var=0.07;depth=0.05;drive=0.59;drywet=1;flutter_onoff=1;gap=2.211634;h_bass=1;h_tfreq=207.9375;h_treble=0.6999999;hyst_onoff=1;ifilt_high=2000;ifilt_low=45;ifilt_makeup=0;ifilt_onoff=1;ingain=0;loss_onoff=1;mix_group=0;mode=3;os_factor=1;outgain=0;rate=0.3;sat=1;spacing=1.951726;speed=15;thick=5.805875;tone_onoff=1;width=1;wow_depth=0.12;wow_drift=0.05;wow_rate=0.25;wow_var=0.04'),
    (Name: 'In The Cut'; Vendor: 'Carter'; Category: 'Carter/Kick';
     Data: 'azimuth=0;chew_depth=0;chew_freq=0;chew_onoff=1;chew_var=0;deg_amt=0.06;deg_depth=0.05;deg_env=0.04;deg_onoff=1;deg_point1x=1;deg_var=0.04;depth=0.16;drive=0.5;drywet=1;flutter_onoff=1;gap=1.219319;h_bass=0;h_tfreq=131.7272;h_treble=0.5799999;hyst_onoff=1;ifilt_high=3600;ifilt_low=130;ifilt_makeup=0;ifilt_onoff=1;ingain=0;loss_onoff=1;mix_group=0;mode=5;os_factor=1;outgain=-5.92;rate=0.3;sat=0;spacing=3.040739;speed=7.5;thick=0.7957121;tone_onoff=1;width=0.5;wow_depth=0.11;wow_drift=0.14;wow_rate=0.25;wow_var=0.5;os_factor=1;os_mode=0'),
    (Name: 'LoFi Kick Short'; Vendor: 'Carter'; Category: 'Carter/Kick';
     Data: 'azimuth=0;chew_depth=0.05;chew_freq=0.05;chew_onoff=1;chew_var=0;deg_amt=0.5;deg_depth=0.05;deg_env=0.08;deg_onoff=1;deg_point1x=1;deg_var=0.15;depth=0.2;drive=0.66;drywet=1;flutter_onoff=1;gap=1.042784;h_bass=0.13;h_tfreq=260.0921;h_treble=0;hyst_onoff=1;ifilt_high=2000;ifilt_low=35.99083;ifilt_makeup=0;ifilt_onoff=1;ingain=0;loss_onoff=1;mix_group=0;mode=3;os_factor=1;outgain=-4;rate=0.09999999;sat=1;spacing=1.599824;speed=7.5;thick=0.2335111;tone_onoff=1;width=0.15;wow_depth=0.13;wow_drift=0.07;wow_rate=0.06;wow_var=0.05'),
    (Name: 'LoFi Kick'; Vendor: 'Carter'; Category: 'Carter/Kick';
     Data: 'azimuth=0;chew_depth=0.05;chew_freq=0.05;chew_onoff=0;chew_var=0;deg_amt=0.5;deg_depth=0.05;deg_env=0.08;deg_onoff=1;deg_point1x=1;deg_var=0.15;depth=0.2;drive=0.66;drywet=1;flutter_onoff=1;gap=1.042784;h_bass=0.13;h_tfreq=260.0921;h_treble=0;hyst_onoff=1;ifilt_high=2000;ifilt_low=35.99083;ifilt_makeup=0;ifilt_onoff=1;ingain=0;loss_onoff=1;mix_group=0;mode=3;os_factor=1;outgain=-4;rate=0.09999999;sat=1;spacing=1.599824;speed=7.5;thick=0.2335111;tone_onoff=1;width=1;wow_depth=0.13;wow_drift=0.07;wow_rate=0.06;wow_var=0.05;os_mode=0;comp_amt=0;comp_attack=5;comp_onoff=0;comp_release=200'),
    (Name: 'Punch Hi Cut'; Vendor: 'Carter'; Category: 'Carter/Kick';
     Data: 'azimuth=0;chew_depth=0;chew_freq=0;chew_onoff=0;chew_var=0;deg_amt=0.05;deg_depth=0.05;deg_env=0.04;deg_onoff=1;deg_point1x=1;deg_var=0.03;depth=0.08;drive=0.7;drywet=1;flutter_onoff=1;gap=1.042784;h_bass=0;h_tfreq=499.9999;h_treble=0;hyst_onoff=1;ifilt_high=5032.676;ifilt_low=20;ifilt_makeup=0;ifilt_onoff=1;ingain=0;loss_onoff=1;mix_group=0;mode=3;os_factor=1;outgain=-1.030001;rate=0.15;sat=0.65;spacing=1.599824;speed=7.5;thick=0.2335111;tone_onoff=1;width=0.4;wow_depth=0.05;wow_drift=0.07;wow_rate=0.09;wow_var=0.05'),
    (Name: '30ips Glue'; Vendor: 'Carter'; Category: 'Carter/Mix';
     Data: 'azimuth=0;chew_depth=0;chew_freq=0;chew_onoff=0;chew_var=0;comp_amt=0.5000001;comp_attack=30;comp_onoff=1;comp_release=42;deg_amt=0;deg_depth=0;deg_env=0;deg_onoff=1;deg_point1x=0;deg_var=0;depth=0.05;drive=0.5;drywet=1;flutter_onoff=1;gap=1;h_bass=0;h_tfreq=499.9999;h_treble=0;hyst_onoff=1;ifilt_high=22000;ifilt_low=23;ifilt_makeup=0;ifilt_onoff=0;ingain=-2;loss_onoff=1;mix_group=0;mode=1;os_factor=1;os_mode=0;outgain=3;rate=0.2;sat=0.45;spacing=0.1;speed=30;thick=0.1;tone_onoff=1;width=0.5;wow_depth=0.05;wow_drift=0.01;wow_rate=0.2;wow_var=0'),
    (Name: 'Cassette Like'; Vendor: 'Carter'; Category: 'Carter/Mix';
     Data: 'chew_depth=0.02;chew_freq=0.02;chew_var=0.05;deg_amt=0.02;deg_depth=0.2;deg_var=0.02;depth=0.5;drive=0.5;drywet=1;gap=1;h_bass=-0.1;h_treble=0;ingain=0;mode=1;os_factor=1;outgain=1;rate=0.09999999;sat=0.6;spacing=0.2;speed=1.78;thick=0.1;width=0.4;wow_depth=0.3;wow_rate=0.25;os_mode=0;chew_onoff=0;comp_amt=0;comp_attack=5;comp_onoff=0;comp_release=200;deg_onoff=1;deg_point1x=1;h_tfreq=320;ifilt_low=25;ifilt_onoff=1;wow_drift=0.3;wow_var=0.09999999'),
    (Name: 'Super LoFi'; Vendor: 'Carter'; Category: 'Carter/Mix';
     Data: 'azimuth=0;chew_depth=0.02;chew_freq=0.05;chew_onoff=1;chew_var=1;comp_amt=4.224046;comp_attack=25.03439;comp_onoff=1;comp_release=33.29192;deg_amt=0.05;deg_depth=0.09999999;deg_env=0;deg_onoff=1;deg_point1x=0;deg_var=0.15;depth=0.4;drive=0.5;drywet=1;flutter_onoff=1;gap=1.11615;h_bass=0;h_tfreq=499.9999;h_treble=0;hyst_onoff=1;ifilt_high=22000;ifilt_low=30.82626;ifilt_makeup=0;ifilt_onoff=1;ingain=0;loss_onoff=1;mix_group=0;mode=3;os_factor=2;os_mode=0;outgain=0;rate=0.15;sat=0.5;spacing=5.901302;speed=15;thick=4.027075;tone_onoff=1;width=0.5;wow_depth=0.25;wow_drift=0.04;wow_rate=0.6;wow_var=0.05'),
    (Name: 'Just Tape Noise'; Vendor: 'Carter'; Category: 'Carter/Noise';
     Data: 'azimuth=0;chew_depth=0.03;chew_freq=0.04;chew_onoff=1;chew_var=0;deg_amt=0.05;deg_depth=0.05;deg_env=0;deg_onoff=1;deg_point1x=0;deg_var=0.02;depth=0;drive=0.5;drywet=1;flutter_onoff=1;gap=1;h_bass=0;h_tfreq=499.9999;h_treble=0;hyst_onoff=1;ifilt_high=22000;ifilt_low=20;ifilt_makeup=0;ifilt_onoff=0;ingain=0;loss_onoff=1;mix_group=0;mode=0;os_factor=1;outgain=0;rate=0.3;sat=0.5;spacing=10.66342;speed=50;thick=0.1;tone_onoff=1;width=0.5;wow_depth=0;wow_drift=0;wow_rate=0.25;wow_var=0'),
    (Name: 'Subtle Tape Noise'; Vendor: 'Carter'; Category: 'Carter/Noise';
     Data: 'azimuth=0;chew_depth=0.03;chew_freq=0.04;chew_onoff=1;chew_var=0;deg_amt=0.05;deg_depth=0.2;deg_env=0;deg_onoff=1;deg_point1x=1;deg_var=0;depth=0;drive=0.5;drywet=1;flutter_onoff=1;gap=1;h_bass=0;h_tfreq=499.9999;h_treble=0;hyst_onoff=1;ifilt_high=22000;ifilt_low=20;ifilt_makeup=0;ifilt_onoff=0;ingain=0;loss_onoff=1;mix_group=0;mode=0;os_factor=1;outgain=0;rate=0.3;sat=0.5;spacing=10.66342;speed=30;thick=0.1;tone_onoff=1;width=0.5;wow_depth=0;wow_drift=0;wow_rate=0.25;wow_var=0'),
    (Name: 'Tape Noise Hard Rain'; Vendor: 'Carter'; Category: 'Carter/Noise';
     Data: 'azimuth=0;chew_depth=0;chew_freq=0;chew_onoff=1;chew_var=0;deg_amt=0.85;deg_depth=0.59;deg_env=0;deg_onoff=1;deg_point1x=1;deg_var=0.22;depth=0;drive=0.5;drywet=1;flutter_onoff=1;gap=1;h_bass=-0.36;h_tfreq=499.9999;h_treble=-0.36;hyst_onoff=1;ifilt_high=2000;ifilt_low=20;ifilt_makeup=0;ifilt_onoff=1;ingain=0;loss_onoff=1;mix_group=0;mode=1;os_factor=1;outgain=-2.400002;rate=0;sat=0.5;spacing=0.1;speed=30;thick=0.1;tone_onoff=1;width=0.5;wow_depth=0;wow_drift=0;wow_rate=0.25;wow_var=0'),
    (Name: 'Tape Noise Rain'; Vendor: 'Carter'; Category: 'Carter/Noise';
     Data: 'azimuth=0;chew_depth=0.05;chew_freq=0.07;chew_onoff=1;chew_var=0.09;deg_amt=0.25;deg_depth=0.14;deg_env=0;deg_onoff=1;deg_point1x=0;deg_var=0.09;depth=0;drive=0.5;drywet=1;flutter_onoff=1;gap=1;h_bass=0;h_tfreq=499.9999;h_treble=0;hyst_onoff=1;ifilt_high=22000;ifilt_low=20;ifilt_makeup=0;ifilt_onoff=0;ingain=0;loss_onoff=1;mix_group=0;mode=0;os_factor=1;outgain=0;rate=0.3;sat=0.5;spacing=10.66342;speed=3.75;thick=0.1;tone_onoff=1;width=0.5;wow_depth=0;wow_drift=0;wow_rate=0.25;wow_var=0'),
    (Name: 'Noise After Hit'; Vendor: 'Carter'; Category: 'Carter/Perc';
     Data: 'azimuth=0;chew_depth=0;chew_freq=0;chew_onoff=0;chew_var=0;deg_amt=0.65;deg_depth=0.2;deg_env=0.35;deg_onoff=1;deg_point1x=0;deg_var=0.05;depth=0;drive=0.5;drywet=1;flutter_onoff=1;gap=1;h_bass=0;h_tfreq=499.9999;h_treble=0;hyst_onoff=1;ifilt_high=22000;ifilt_low=20;ifilt_makeup=0;ifilt_onoff=0;ingain=2.299999;loss_onoff=1;mix_group=0;mode=0;os_factor=1;outgain=5.130001;rate=0.3;sat=0.5;spacing=0.1;speed=30;thick=0.1;tone_onoff=1;width=0.5;wow_depth=0;wow_drift=0;wow_rate=0.25;wow_var=0'),
    (Name: 'Almost LoFi Piano'; Vendor: 'Carter'; Category: 'Carter/Piano';
     Data: 'azimuth=0;chew_depth=0.01;chew_freq=0.01;chew_onoff=1;chew_var=0.01;deg_amt=0.02;deg_depth=0.34;deg_env=0.03;deg_onoff=1;deg_point1x=1;deg_var=0.03;depth=0.2;drive=0.58;drywet=1;flutter_onoff=1;gap=1.10576;h_bass=0.25;h_tfreq=588.5361;h_treble=-0.11;hyst_onoff=1;ifilt_high=22000;ifilt_low=20;ifilt_makeup=0;ifilt_onoff=0;ingain=0;loss_onoff=1;mix_group=0;mode=0;os_factor=1;outgain=0;rate=0.18;sat=0.62;spacing=1.031177;speed=30;thick=0.3239527;tone_onoff=1;width=0.88;wow_depth=0.27;wow_drift=0.19;wow_rate=0.25;wow_var=0.08'),
    (Name: 'Clean Cassette'; Vendor: 'Carter'; Category: 'Carter/Piano';
     Data: 'azimuth=0;chew_depth=0;chew_freq=0;chew_onoff=0;chew_var=0;deg_amt=0.07;deg_depth=0.04;deg_env=0.06;deg_onoff=1;deg_point1x=1;deg_var=0.05;depth=0.13;drive=0.5;drywet=1;flutter_onoff=1;gap=1.008964;h_bass=0;h_tfreq=499.9999;h_treble=0.12;hyst_onoff=1;ifilt_high=12070.43;ifilt_low=99.95583;ifilt_makeup=0;ifilt_onoff=1;ingain=0;loss_onoff=1;mix_group=0;mode=0;os_factor=1;outgain=3.110001;rate=0.3;sat=0.5;spacing=1.271115;speed=30;thick=0.2145853;tone_onoff=1;width=0.5;wow_depth=0.12;wow_drift=0.05;wow_rate=0.44;wow_var=0.09999999'),
    (Name: 'Dirtier Cassette'; Vendor: 'Carter'; Category: 'Carter/Piano';
     Data: 'azimuth=0;chew_depth=0;chew_freq=0;chew_onoff=0;chew_var=0;deg_amt=0.35;deg_depth=0.05;deg_env=0;deg_onoff=1;deg_point1x=1;deg_var=0.05;depth=0.13;drive=0.5;drywet=1;flutter_onoff=1;gap=2.975265;h_bass=0;h_tfreq=499.9999;h_treble=0.12;hyst_onoff=1;ifilt_high=12070.43;ifilt_low=99.95583;ifilt_makeup=0;ifilt_onoff=1;ingain=0;loss_onoff=1;mix_group=0;mode=0;os_factor=1;outgain=3.110001;rate=0.3;sat=0.5;spacing=5.277358;speed=7.5;thick=1.860669;tone_onoff=1;width=0.5;wow_depth=0.12;wow_drift=0.05;wow_rate=0.44;wow_var=0.09999999'),
    (Name: 'Almost Bitcrushed'; Vendor: 'Carter'; Category: 'Carter/Snare';
     Data: 'azimuth=0;chew_depth=0.08;chew_freq=0.05;chew_onoff=1;chew_var=0;deg_amt=0.11;deg_depth=0.05;deg_env=0.18;deg_onoff=1;deg_point1x=1;deg_var=0.08;depth=0.2;drive=0.6;drywet=1;flutter_onoff=1;gap=1.116096;h_bass=-0.4;h_tfreq=499.9999;h_treble=0.4;hyst_onoff=1;ifilt_high=11837.95;ifilt_low=140.2255;ifilt_makeup=0;ifilt_onoff=1;ingain=0;loss_onoff=1;mix_group=0;mode=1;os_factor=1;outgain=2.149998;rate=0.05;sat=0.3;spacing=1.776762;speed=15;thick=0.7504541;tone_onoff=1;width=0;wow_depth=0.2;wow_drift=0.35;wow_rate=0.2;wow_var=0.15'),
    (Name: 'Cut The Lows'; Vendor: 'Carter'; Category: 'Carter/Snare';
     Data: 'azimuth=0;chew_depth=0.02;chew_freq=0.05;chew_onoff=1;chew_var=0;deg_amt=0.11;deg_depth=0.09999999;deg_env=0.05;deg_onoff=1;deg_point1x=1;deg_var=0.11;depth=0.2;drive=0.5;drywet=1;flutter_onoff=1;gap=1.144164;h_bass=-0.65;h_tfreq=499.9999;h_treble=0.3;hyst_onoff=1;ifilt_high=15807.41;ifilt_low=620.4189;ifilt_makeup=0;ifilt_onoff=1;ingain=0;loss_onoff=1;mix_group=0;mode=0;os_factor=1;outgain=0;rate=0.22;sat=0.6;spacing=1.900067;speed=3.75;thick=1.269658;tone_onoff=1;width=0.5;wow_depth=0.2;wow_drift=0.09999999;wow_rate=0.25;wow_var=0.09999999'),
    (Name: 'LoFi Vibe'; Vendor: 'Carter'; Category: 'Carter/Snare';
     Data: 'azimuth=0;chew_depth=0.02;chew_freq=0.05;chew_onoff=1;chew_var=0;deg_amt=0.11;deg_depth=0.05;deg_env=0.05;deg_onoff=1;deg_point1x=1;deg_var=0.11;depth=0.2;drive=0.5;drywet=1;flutter_onoff=1;gap=1.144164;h_bass=-0.65;h_tfreq=499.9999;h_treble=0.3;hyst_onoff=1;ifilt_high=11837.95;ifilt_low=140.2255;ifilt_makeup=0;ifilt_onoff=1;ingain=0;loss_onoff=1;mix_group=0;mode=0;os_factor=1;outgain=0;rate=0.22;sat=0.6;spacing=1.900067;speed=3.75;thick=1.269658;tone_onoff=1;width=0.5;wow_depth=0.2;wow_drift=0.09999999;wow_rate=0.25;wow_var=0.09999999'),
    (Name: 'Shorter LoFi'; Vendor: 'Carter'; Category: 'Carter/Snare';
     Data: 'azimuth=0;chew_depth=0.08;chew_freq=0.05;chew_onoff=0;chew_var=0;deg_amt=0.11;deg_depth=0.05;deg_env=0.18;deg_onoff=1;deg_point1x=1;deg_var=0.08;depth=0.2;drive=0.6;drywet=1;flutter_onoff=1;gap=1.144164;h_bass=-0.4;h_tfreq=499.9999;h_treble=0.4;hyst_onoff=1;ifilt_high=2999.351;ifilt_low=140.2255;ifilt_makeup=0;ifilt_onoff=1;ingain=0;loss_onoff=1;mix_group=0;mode=0;os_factor=1;outgain=0;rate=0.05;sat=0.6;spacing=1.900067;speed=15;thick=1.269658;tone_onoff=1;width=0.12;wow_depth=0.2;wow_drift=0.35;wow_rate=0.07;wow_var=0.15;os_mode=0'),
    (Name: 'Shorter Snare'; Vendor: 'Carter'; Category: 'Carter/Snare';
     Data: 'azimuth=0;chew_depth=0.08;chew_freq=0.05;chew_onoff=0;chew_var=0;deg_amt=0.11;deg_depth=0.05;deg_env=0.18;deg_onoff=1;deg_point1x=1;deg_var=0.08;depth=0.2;drive=0.6;drywet=1;flutter_onoff=1;gap=1.144164;h_bass=-0.4;h_tfreq=499.9999;h_treble=0.4;hyst_onoff=1;ifilt_high=11837.95;ifilt_low=140.2255;ifilt_makeup=0;ifilt_onoff=1;ingain=0;loss_onoff=1;mix_group=0;mode=0;os_factor=1;outgain=0;rate=0.05;sat=0.6;spacing=1.900067;speed=15;thick=1.269658;tone_onoff=1;width=0.05;wow_depth=0.2;wow_drift=0.35;wow_rate=0.07;wow_var=0.15'),
    (Name: 'Chew Loss'; Vendor: 'Cool WAV'; Category: 'CoolWAV';
     Data: 'chew_depth=0.11;chew_freq=0.86;chew_var=0.12;deg_amt=0.34;deg_depth=0.39;deg_var=0;depth=0;drive=0.5;drywet=1;gap=3.10285;h_bass=-1;h_treble=1;ingain=0;mode=2;os_factor=4;outgain=-0.7200012;rate=0.3;sat=0.5;spacing=3.214591;speed=7.5;thick=6.840004;width=0.5;wow_depth=0;wow_rate=0.25;os_mode=0;azimuth=-1.550003;chew_onoff=1;comp_amt=0.679978;comp_attack=31.67343;comp_onoff=1;comp_release=22.19127;deg_onoff=1;deg_point1x=1;ifilt_high=22000;ifilt_low=20;ifilt_onoff=0;wow_drift=0;wow_var=0'),
    (Name: 'Drift with Me'; Vendor: 'Cool WAV'; Category: 'CoolWAV';
     Data: 'azimuth=0;chew_depth=0;chew_freq=0;chew_onoff=0;chew_var=0;comp_amt=0;comp_attack=5;comp_onoff=0;comp_release=200;deg_amt=0;deg_depth=0;deg_env=0;deg_onoff=0;deg_point1x=0;deg_var=0;depth=0.14;drive=0.7;drywet=1;flutter_onoff=1;gap=50;h_bass=0;h_tfreq=499.9999;h_treble=0.6799999;hyst_onoff=1;ifilt_high=22000;ifilt_low=20;ifilt_makeup=0;ifilt_onoff=0;ingain=0.8599987;loss_onoff=1;mid_side=0;mix_group=0;mode=2;os_factor=1;os_mode=0;outgain=-0.960001;rate=0.6;sat=0.67;spacing=0.1;speed=15;thick=0.1;tone_onoff=1;width=0.85;wow_depth=0.16;wow_drift=1;wow_rate=0.38;wow_var=0.25'),
    (Name: 'Goodbye Highs'; Vendor: 'Cool WAV'; Category: 'CoolWAV';
     Data: 'chew_depth=0;chew_freq=0;chew_var=0;deg_amt=0;deg_depth=0;deg_var=0;depth=0.02;drive=0.5;drywet=1;gap=3.369254;h_bass=0;h_treble=0;ingain=0;mode=0;os_factor=4;outgain=0;rate=0.3;sat=0.5;spacing=5.949471;speed=15;thick=11.44244;width=0.5;wow_depth=0;wow_rate=0.25;os_mode=0;azimuth=0;chew_onoff=0;comp_amt=0;comp_attack=5;comp_onoff=0;comp_release=200;deg_onoff=0;deg_point1x=0;ifilt_high=3003.734;ifilt_low=111.8036;ifilt_onoff=1'),
    (Name: 'Heavy Drumloop'; Vendor: 'Cool WAV'; Category: 'CoolWAV';
     Data: 'azimuth=0;chew_depth=1;chew_freq=0;chew_onoff=1;chew_var=1;comp_amt=9;comp_attack=22.23759;comp_onoff=1;comp_release=57.85083;deg_amt=0.44;deg_depth=0.12;deg_env=0;deg_onoff=1;deg_point1x=0;deg_var=0;depth=0;drive=1;drywet=1;flutter_onoff=1;gap=1;h_bass=0;h_tfreq=4000;h_treble=0.12;hyst_onoff=1;ifilt_high=22000;ifilt_low=20;ifilt_makeup=0;ifilt_onoff=0;ingain=6;loss_onoff=1;mid_side=0;mix_group=0;mode=2;os_factor=1;os_mode=0;outgain=-5.52;rate=0.3;sat=1;spacing=0.1;speed=15;thick=0.1;tone_onoff=1;width=1;wow_depth=0;wow_drift=0;wow_rate=0.25;wow_var=0'),
    (Name: 'Studio Time'; Vendor: 'Cool WAV'; Category: 'CoolWAV';
     Data: 'azimuth=0;chew_depth=0;chew_freq=0;chew_onoff=0;chew_var=0;comp_amt=3.114916;comp_attack=20.80152;comp_onoff=1;comp_release=29.33311;deg_amt=0.08;deg_depth=1;deg_env=0;deg_onoff=1;deg_point1x=1;deg_var=0;depth=0;drive=0.5;drywet=0.54;flutter_onoff=1;gap=5.184079;h_bass=0;h_tfreq=499.9999;h_treble=0;hyst_onoff=1;ifilt_high=22000;ifilt_low=20;ifilt_makeup=0;ifilt_onoff=0;ingain=2.16;loss_onoff=1;mid_side=0;mix_group=0;mode=2;os_factor=1;os_mode=0;outgain=-3.6;rate=0.3;sat=1;spacing=1.175053;speed=7.5;thick=0.2932625;tone_onoff=1;width=0.5;wow_depth=0.54;wow_drift=0.54;wow_rate=0.08;wow_var=0'),
    (Name: 'Tape Wide'; Vendor: 'Cool WAV'; Category: 'CoolWAV';
     Data: 'azimuth=75;chew_depth=0.11;chew_freq=0.6;chew_onoff=1;chew_var=0.09;comp_amt=0;comp_attack=5;comp_onoff=0;comp_release=200;deg_amt=0.04;deg_depth=0;deg_env=0;deg_onoff=0;deg_point1x=0;deg_var=0;depth=0;drive=0.5;drywet=1;flutter_onoff=1;gap=1;h_bass=0;h_tfreq=499.9999;h_treble=0;hyst_onoff=1;ifilt_high=22000;ifilt_low=20;ifilt_makeup=0;ifilt_onoff=0;ingain=0;loss_onoff=1;mid_side=0;mix_group=0;mode=2;os_factor=1;os_mode=0;outgain=0;rate=0.3;sat=1;spacing=1.581622;speed=7.5;thick=1.288041;tone_onoff=1;width=0.5;wow_depth=0;wow_drift=0;wow_rate=0.25;wow_var=0'),
    (Name: 'Thats Cool'; Vendor: 'Cool WAV'; Category: 'CoolWAV';
     Data: 'azimuth=75;chew_depth=0.07;chew_freq=0.03;chew_onoff=1;chew_var=0;comp_amt=0;comp_attack=5;comp_onoff=0;comp_release=200;deg_amt=0.11;deg_depth=0.28;deg_env=0;deg_onoff=1;deg_point1x=0;deg_var=0;depth=0.42;drive=0.52;drywet=1;flutter_onoff=1;gap=1.041113;h_bass=0;h_tfreq=499.9999;h_treble=0.06999993;hyst_onoff=1;ifilt_high=22000;ifilt_low=20;ifilt_makeup=0;ifilt_onoff=0;ingain=6;loss_onoff=1;mid_side=0;mix_group=0;mode=3;os_factor=1;os_mode=0;outgain=0;rate=0.3;sat=0.88;spacing=0.5002814;speed=7.5;thick=1.16886;tone_onoff=1;width=0.5;wow_depth=0;wow_drift=0;wow_rate=0.25;wow_var=0'),
    (Name: 'Vibe Drive'; Vendor: 'Cool WAV'; Category: 'CoolWAV';
     Data: 'azimuth=17.07;chew_depth=0;chew_freq=0;chew_onoff=0;chew_var=0;comp_amt=0.4356508;comp_attack=23.12575;comp_onoff=1;comp_release=13.55984;deg_amt=0;deg_depth=0;deg_env=0;deg_onoff=0;deg_point1x=0;deg_var=0;depth=0.18;drive=0.58;drywet=1;flutter_onoff=1;gap=1.259597;h_bass=0;h_tfreq=499.9999;h_treble=0.14;hyst_onoff=1;ifilt_high=17783.1;ifilt_low=36.01041;ifilt_makeup=0;ifilt_onoff=1;ingain=1;loss_onoff=1;mid_side=0;mix_group=0;mode=0;os_factor=1;os_mode=0;outgain=-1.24;rate=0.3;sat=0.58;spacing=2.533167;speed=15;thick=0.570968;tone_onoff=1;width=1;wow_depth=0.24;wow_drift=0.34;wow_rate=0.42;wow_var=0.09999999'),
    (Name: 'Wack'; Vendor: 'Cool WAV'; Category: 'CoolWAV';
     Data: 'azimuth=-53.28;chew_depth=0;chew_freq=0;chew_onoff=0;chew_var=0;comp_amt=0;comp_attack=5;comp_onoff=0;comp_release=200;deg_amt=0;deg_depth=0;deg_env=0;deg_onoff=0;deg_point1x=0;deg_var=0;depth=1;drive=0.53;drywet=1;flutter_onoff=1;gap=9.551547;h_bass=0;h_tfreq=499.9999;h_treble=0;hyst_onoff=1;ifilt_high=11912.05;ifilt_low=2000;ifilt_makeup=1;ifilt_onoff=1;ingain=0;loss_onoff=1;mid_side=0;mix_group=0;mode=0;os_factor=1;os_mode=0;outgain=0;rate=0.31;sat=0.56;spacing=0.1;speed=30;thick=0.1;tone_onoff=1;width=1;wow_depth=0;wow_drift=0;wow_rate=0.25;wow_var=0'),
    (Name: 'Wow Dude'; Vendor: 'Cool WAV'; Category: 'CoolWAV';
     Data: 'azimuth=0;chew_depth=0;chew_freq=0;chew_onoff=0;chew_var=0;comp_amt=0.679978;comp_attack=10.0878;comp_onoff=1;comp_release=69.92815;deg_amt=0;deg_depth=0;deg_env=0;deg_onoff=0;deg_point1x=0;deg_var=0;depth=0;drive=1;drywet=1;flutter_onoff=1;gap=1;h_bass=0.01999998;h_tfreq=499.9999;h_treble=0.28;hyst_onoff=1;ifilt_high=13732.68;ifilt_low=21.97096;ifilt_makeup=0;ifilt_onoff=1;ingain=0;loss_onoff=1;mid_side=0;mix_group=0;mode=0;os_factor=4;os_mode=0;outgain=-5.76;rate=0.65;sat=0.7;spacing=0.1;speed=30;thick=0.1;tone_onoff=1;width=0.5;wow_depth=0.25;wow_drift=0.66;wow_rate=0.54;wow_var=0.25'),
    (Name: 'Default'; Vendor: 'CHOW'; Category: 'Factory';
     Data: 'chew_depth=0;chew_freq=0;chew_var=0;deg_amt=0;deg_depth=0;deg_var=0;depth=0;drive=0.5;drywet=1;gap=1;h_bass=0;h_treble=0;ingain=0;mode=2;os_factor=1;outgain=0;rate=0.3;sat=0.5;spacing=1;speed=15;thick=1;width=0.5;wow_depth=0;wow_rate=0.25'),
    (Name: 'LoFi'; Vendor: 'CHOW'; Category: 'Factory';
     Data: 'chew_depth=0;chew_freq=0;chew_var=0;deg_amt=0;deg_depth=0;deg_var=0;depth=0;drive=1;drywet=1;gap=1;h_bass=0;h_treble=0;ingain=0;mode=2;os_factor=2;outgain=-3.5;rate=0.3;sat=1;spacing=2.999998;speed=7.5;thick=4.999995;width=0.6;wow_depth=0;wow_rate=0.25'),
    (Name: 'Old Tape'; Vendor: 'CHOW'; Category: 'Factory';
     Data: 'chew_depth=0;chew_freq=0;chew_var=0;deg_amt=0.15;deg_depth=0.2;deg_onoff=1;deg_var=0.25;depth=0;drive=0.5;drywet=1;gap=1;h_bass=0;h_treble=0;ingain=0;mode=2;os_factor=1;outgain=0;rate=0.3;sat=0.5;spacing=1;speed=15;thick=1;width=0.5;wow_depth=0;wow_rate=0.25'),
    (Name: 'TC-260'; Vendor: 'CHOW'; Category: 'Factory';
     Data: 'chew_depth=0;chew_freq=0;chew_var=0;deg_amt=0;deg_depth=0;deg_var=0;depth=0.2;drive=0.66;drywet=1;gap=1.6;h_bass=0;h_treble=0;ingain=0;mode=2;os_factor=2;outgain=-2;rate=0.2;sat=0.75;spacing=0.2769172;speed=15;thick=4.748198;width=0.36;wow_depth=0.2;wow_rate=0.2'),
    (Name: 'Underbiased'; Vendor: 'CHOW'; Category: 'Factory';
     Data: 'chew_depth=0;chew_freq=0;chew_var=0;deg_amt=0;deg_depth=0;deg_var=0;depth=0;drive=0.25;drywet=1;gap=1;h_bass=0;h_treble=0;ingain=0;mode=2;os_factor=1;outgain=0;rate=0.3;sat=0.7;spacing=1;speed=15;thick=1;width=0.05;wow_depth=0;wow_rate=0.25'),
    (Name: 'Woozy Chorus'; Vendor: 'CHOW'; Category: 'Factory';
     Data: 'chew_depth=0.25;chew_freq=0.6;chew_var=0.3;deg_amt=0;deg_depth=0;deg_var=0;depth=0.8;drive=0.5;drywet=0.65;gap=1;h_bass=0;h_treble=0;ingain=0;mode=2;os_factor=1;outgain=0;rate=0.44;sat=0.5;spacing=1;speed=15;thick=1;width=0.5;wow_depth=0.8;wow_rate=0.5'),
    (Name: 'Bleak'; Vendor: 'RK'; Category: 'RK';
     Data: 'chew_depth=0.048;chew_freq=0.09599999;chew_var=0.696;deg_amt=0.5033557;deg_depth=0.04697987;deg_var=0.2013423;depth=0.249952;drive=0.396;drywet=1;gap=3;h_bass=0.1999999;h_treble=-0.2484329;ingain=0;mode=0;os_factor=1;outgain=0;rate=0.4529457;sat=0.5024001;spacing=1;speed=9.999999;thick=1.5;width=0.5;wow_depth=0.152769;wow_rate=0.2;os_factor=1;os_mode=0;azimuth=-2;chew_onoff=1;comp_amt=2;comp_attack=10;comp_onoff=1;comp_release=399.9999;deg_env=0;deg_onoff=1;deg_point1x=1;ifilt_high=18800;ifilt_low=60.00003;ifilt_makeup=0;ifilt_onoff=1;mid_side=0;stereo_balance=0;stereo_makeup=1;wow_drift=0.5;wow_var=0.3'),
    (Name: 'Solid Tape I'; Vendor: 'RK'; Category: 'RK';
     Data: 'chew_depth=0;chew_freq=0;chew_var=0;deg_amt=0;deg_depth=0;deg_var=0;depth=0.04288956;drive=0.6199999;drywet=1;gap=1;h_bass=-0.04000002;h_treble=0.1440001;ingain=0;mode=0;os_factor=1;outgain=0;rate=0.3;sat=0.416;spacing=0.1;speed=20;thick=0.15;width=0.404;wow_depth=0.1178565;wow_rate=0.2830926;os_factor=2;os_mode=0;azimuth=0;comp_amt=0.1041497;comp_attack=10;comp_onoff=1;comp_release=200;flutter_onoff=1;h_tfreq=260;hyst_onoff=1;ifilt_high=20200;ifilt_low=22;ifilt_makeup=0;ifilt_onoff=1;tone_onoff=1;wow_drift=0.1222222;wow_var=0.1777778'),
    (Name: 'Solid Tape II'; Vendor: 'RK'; Category: 'RK';
     Data: 'chew_depth=0;chew_freq=0;chew_var=0;deg_amt=0;deg_depth=0;deg_var=0;depth=0.05571829;drive=0.5799999;drywet=1;gap=1;h_bass=0.136;h_treble=0.04000008;ingain=0;mode=0;os_factor=1;outgain=0;rate=0.3;sat=0.456;spacing=0.1;speed=20;thick=0.15;width=0.584;wow_depth=0.1377886;wow_rate=0.2830926;os_factor=2;os_mode=0;azimuth=0;comp_amt=0.1432165;comp_attack=14;comp_onoff=1;comp_release=220;flutter_onoff=1;h_tfreq=260;hyst_onoff=1;ifilt_high=20400;ifilt_low=22;ifilt_makeup=0;ifilt_onoff=1;tone_onoff=1;wow_drift=0.1222222;wow_var=0.1777778'),
    (Name: 'Crane I'; Vendor: 'RK'; Category: 'RK/High';
     Data: 'chew_depth=0.01600001;chew_freq=0.2;chew_var=0.3041234;deg_amt=0.2013423;deg_depth=0.1006711;deg_var=0.1006711;depth=0;drive=0.604;drywet=1;gap=2;h_bass=-0.09600002;h_treble=0.2;ingain=0;mode=0;os_factor=1;outgain=0;rate=0.3;sat=0.5;spacing=2;speed=50;thick=4;width=0.5;wow_depth=0;wow_rate=0.25;os_factor=2;os_mode=0;azimuth=1;chew_onoff=0;comp_amt=0.9999999;comp_attack=5;comp_onoff=1;comp_release=200;deg_onoff=0;flutter_onoff=0;h_tfreq=499.9999;ifilt_low=400;ifilt_onoff=1'),
    (Name: 'Crane II'; Vendor: 'RK'; Category: 'RK/High';
     Data: 'chew_depth=0.01600001;chew_freq=0.2;chew_var=0.3041234;deg_amt=0.2013423;deg_depth=0.1006711;deg_var=0.1006711;depth=0.048;drive=0.604;drywet=1;gap=2;h_bass=-0.09600002;h_treble=0.152;ingain=0;mode=0;os_factor=1;outgain=0;rate=0.3;sat=0.5;spacing=1;speed=25;thick=4;width=0.452;wow_depth=0;wow_rate=0.25;os_factor=2;os_mode=0;azimuth=1;chew_onoff=0;comp_amt=0;comp_attack=5;comp_onoff=0;comp_release=200;deg_onoff=0;flutter_onoff=0;h_tfreq=499.9999;ifilt_high=11000;ifilt_low=300;ifilt_onoff=1'),
    (Name: 'Flavor I'; Vendor: 'RK'; Category: 'RK/High';
     Data: 'chew_depth=0.06000002;chew_freq=0.02400001;chew_var=0.016;deg_amt=0.02013423;deg_depth=0.2013423;deg_var=0.05369128;depth=0.1047622;drive=0.5;drywet=1;gap=1;h_bass=0.1;h_treble=0;ingain=0;mode=0;os_factor=1;outgain=0;rate=0.2505553;sat=0.596;spacing=0.1;speed=30;thick=2;width=0.5;wow_depth=0.09882208;wow_rate=0.2;os_factor=2;os_mode=0;azimuth=0.05000305;chew_onoff=0;comp_amt=0.1951621;comp_attack=7.999999;comp_onoff=1;comp_release=150;deg_onoff=0;deg_point1x=1;h_tfreq=400;ifilt_high=12000;ifilt_low=160.0001;ifilt_onoff=1;mid_side=0;wow_drift=0.05432197;wow_var=0.09789931'),
    (Name: 'High Sauce I'; Vendor: 'RK'; Category: 'RK/High';
     Data: 'chew_depth=0;chew_freq=0;chew_var=0;deg_amt=0;deg_depth=0;deg_var=0;depth=0;drive=0.804;drywet=1;gap=1;h_bass=0.12;h_treble=0.24;ingain=0;mode=2;os_factor=1;outgain=0;rate=0.3;sat=0.964;spacing=0.1;speed=26;thick=1;width=0.804;wow_depth=0;wow_rate=0.25;os_factor=2;os_mode=0;azimuth=0.01999664;comp_amt=4.2;comp_attack=0.4;comp_onoff=1;comp_release=120;flutter_onoff=0;h_tfreq=1600;ifilt_high=22000;ifilt_low=1000;ifilt_makeup=1;ifilt_onoff=1;mid_side=0;stereo_balance=0;wow_drift=0;wow_var=0'),
    (Name: 'High Sauce II'; Vendor: 'RK'; Category: 'RK/High';
     Data: 'chew_depth=0;chew_freq=0;chew_var=0;deg_amt=0;deg_depth=0;deg_var=0;depth=0.016;drive=0.604;drywet=1;gap=1;h_bass=0.12;h_treble=0.24;ingain=0;mode=0;os_factor=1;outgain=0;rate=0.6160001;sat=0.8;spacing=0.1;speed=26;thick=1;width=0.804;wow_depth=0.1222222;wow_rate=0.2777778;os_factor=2;os_mode=0;azimuth=0.01999664;comp_amt=4.2;comp_attack=0.4;comp_onoff=1;comp_release=120;flutter_onoff=1;h_tfreq=1600;ifilt_high=22000;ifilt_low=1000;ifilt_makeup=1;ifilt_onoff=1;mid_side=0;stereo_balance=0;wow_drift=0.4;wow_var=0.1'),
    (Name: 'Spice I'; Vendor: 'RK'; Category: 'RK/High';
     Data: 'chew_depth=0;chew_freq=0;chew_var=0;deg_amt=0;deg_depth=0;deg_var=0;depth=0.2;drive=0.4;drywet=1;gap=2;h_bass=-0.248;h_treble=0.2;ingain=0;mode=0;os_factor=1;outgain=0;rate=0.4020207;sat=0.5784001;spacing=1;speed=8;thick=0.2;width=0.5;wow_depth=0.2;wow_rate=0.2;os_factor=2;os_mode=0;azimuth=-0.4599991;comp_amt=3.004073;comp_attack=10;comp_onoff=1;comp_release=399.9999;h_tfreq=499.9999;ifilt_high=22000;ifilt_low=20;ifilt_makeup=0;ifilt_onoff=0;mid_side=0;stereo_balance=0;stereo_makeup=1;wow_drift=0.5;wow_var=0.3'),
    (Name: 'Spice II'; Vendor: 'RK'; Category: 'RK/High';
     Data: 'chew_depth=0;chew_freq=0;chew_var=0;deg_amt=0;deg_depth=0;deg_var=0;depth=0.2;drive=0.464;drywet=1;gap=1;h_bass=-0.08000004;h_treble=0.06400001;ingain=0;mode=0;os_factor=1;outgain=0;rate=0.4020207;sat=0.756;spacing=0.1;speed=28;thick=4;width=0.684;wow_depth=0.2;wow_rate=0.2;os_factor=2;os_mode=0;azimuth=0.4000015;comp_amt=0;comp_attack=10;comp_onoff=1;comp_release=399.9999;h_tfreq=499.9999;ifilt_high=22000;ifilt_low=20;ifilt_makeup=0;ifilt_onoff=0;mid_side=0;stereo_balance=0;stereo_makeup=1;wow_drift=0.5;wow_var=0.3'),
    (Name: 'Flavor II'; Vendor: 'RK'; Category: 'RK/Low';
     Data: 'chew_depth=0.06000002;chew_freq=0.02400001;chew_var=0.016;deg_amt=0.02013423;deg_depth=0.2013423;deg_var=0.05369128;depth=0.1047622;drive=0.6;drywet=1;gap=12;h_bass=0.1;h_treble=0;ingain=0;mode=0;os_factor=1;outgain=0;rate=0.2985553;sat=0.5;spacing=6.000001;speed=12;thick=12;width=0.5;wow_depth=0.1518399;wow_rate=0.2;os_factor=2;os_mode=0;azimuth=0.05000305;chew_onoff=0;comp_amt=0.1951621;comp_attack=7.999999;comp_onoff=1;comp_release=150;deg_onoff=0;deg_point1x=1;flutter_onoff=1;h_tfreq=400;ifilt_high=14000;ifilt_low=40;ifilt_makeup=0;ifilt_onoff=1;mid_side=0;wow_drift=0.05432197;wow_var=0.09789931'),
    (Name: 'Flow I'; Vendor: 'RK'; Category: 'RK/Low';
     Data: 'chew_depth=0;chew_freq=0;chew_var=0;deg_amt=0;deg_depth=0;deg_var=0;depth=0.3;drive=0.5;drywet=1;gap=10;h_bass=0;h_treble=-0.09600002;ingain=0;mode=0;os_factor=1;outgain=0;rate=0.496;sat=0.2;spacing=0.1;speed=15;thick=30;width=0.5;wow_depth=0;wow_rate=0.25;os_factor=2;os_mode=0;azimuth=3;chew_onoff=0;comp_amt=0.9999999;comp_attack=10;comp_onoff=1;comp_release=399.9999;deg_env=0;deg_onoff=0;deg_point1x=1;h_tfreq=499.9999;ifilt_high=22000;ifilt_low=20;ifilt_makeup=0;ifilt_onoff=0;mid_side=0;stereo_balance=0;stereo_makeup=1;wow_drift=0;wow_var=0'),
    (Name: 'Flow II'; Vendor: 'RK'; Category: 'RK/Low';
     Data: 'chew_depth=0;chew_freq=0;chew_var=0;deg_amt=0;deg_depth=0;deg_var=0;depth=0.4008279;drive=0.5;drywet=1;gap=10;h_bass=0;h_treble=-0.09600002;ingain=0;mode=0;os_factor=1;outgain=0;rate=0.4546023;sat=0.2;spacing=0.1;speed=15;thick=30;width=0.5;wow_depth=0.200038;wow_rate=0.5;os_factor=2;os_mode=0;azimuth=-1.239998;chew_onoff=0;comp_amt=0.9999999;comp_attack=10;comp_onoff=1;comp_release=399.9999;deg_env=0;deg_onoff=0;deg_point1x=1;ifilt_high=22000;ifilt_low=20;ifilt_makeup=0;ifilt_onoff=0;mid_side=0;stereo_balance=0;stereo_makeup=1;wow_drift=0.09857897;wow_var=0.3991108'),
    (Name: 'Low Grinder'; Vendor: 'RK'; Category: 'RK/Low';
     Data: 'chew_depth=0;chew_freq=0;chew_var=0;deg_amt=0;deg_depth=0;deg_var=0;depth=0;drive=0.704;drywet=1;gap=2;h_bass=0.12;h_treble=0.24;ingain=0;mode=0;os_factor=1;outgain=0;rate=0.3;sat=0.696;spacing=0.1;speed=6;thick=0.1;width=0.456;wow_depth=0.03677139;wow_rate=0.28;os_factor=2;os_mode=0;azimuth=0;comp_amt=4;comp_attack=0.4;comp_onoff=1;comp_release=60.00003;flutter_onoff=0;h_tfreq=200;ifilt_high=4000;ifilt_makeup=1;ifilt_onoff=1;wow_drift=0.06;wow_var=0.06'),
    (Name: 'Low Rider'; Vendor: 'RK'; Category: 'RK/Low';
     Data: 'chew_depth=0;chew_freq=0;chew_var=0;deg_amt=0;deg_depth=0;deg_var=0;depth=0;drive=0.704;drywet=1;gap=2;h_bass=0.12;h_treble=0.24;ingain=0;mode=0;os_factor=1;outgain=0;rate=0.3;sat=0.696;spacing=0.1;speed=6;thick=0.1;width=0.456;wow_depth=0.03677139;wow_rate=0.28;os_factor=2;os_mode=0;azimuth=0;comp_amt=4;comp_attack=0.4;comp_onoff=1;comp_release=60.00003;flutter_onoff=0;h_tfreq=200;ifilt_high=4000;ifilt_makeup=0;ifilt_onoff=1;wow_drift=0.06;wow_var=0.06'),
    (Name: 'Low Smasher'; Vendor: 'RK'; Category: 'RK/Low';
     Data: 'chew_depth=0;chew_freq=0;chew_var=0;deg_amt=0;deg_depth=0;deg_var=0;depth=0;drive=0.8840001;drywet=1;gap=2;h_bass=0.12;h_treble=0.24;ingain=0;mode=0;os_factor=1;outgain=0;rate=0.3;sat=0.936;spacing=1;speed=6;thick=1;width=0.536;wow_depth=0.03677139;wow_rate=0.28;os_factor=2;os_mode=0;azimuth=0;comp_amt=4.2;comp_attack=0.4;comp_onoff=1;comp_release=60.00003;flutter_onoff=0;h_tfreq=200;ifilt_high=2400;ifilt_low=20;ifilt_makeup=1;ifilt_onoff=1;wow_drift=0.06;wow_var=0.06'),
    (Name: 'String Mojo'; Vendor: 'RK'; Category: 'RK/Low';
     Data: 'chew_depth=0;chew_freq=0;chew_var=0;deg_amt=0;deg_depth=0;deg_var=0;depth=0.05350816;drive=0.5;drywet=1;gap=50;h_bass=0;h_treble=0.04999995;ingain=0;mode=0;os_factor=1;outgain=0;rate=0.304;sat=0.596;spacing=0.1;speed=6;thick=0.1;width=0.5;wow_depth=0.04659327;wow_rate=0.2;os_factor=2;os_mode=0;azimuth=0.05000305;comp_amt=0.1951621;comp_attack=7.999999;comp_onoff=1;comp_release=150;deg_point1x=0;h_tfreq=700;ifilt_high=18000;ifilt_onoff=1;mid_side=0;wow_drift=0.05432197;wow_var=0.09789931'),
    (Name: 'Bass Pusher I'; Vendor: 'Sink'; Category: 'Sink';
     Data: 'chew_depth=0;chew_freq=0;chew_var=0;deg_amt=0;deg_depth=0;deg_var=0;depth=0;drive=0.75;drywet=1;gap=1;h_bass=0.5;h_treble=-0.15;ingain=2;mix_group=0;mode=2;os_factor=1;outgain=-2;rate=0.3;sat=0.75;spacing=1;speed=3.75;thick=1;width=0.6;wow_depth=0;wow_rate=0.15'),
    (Name: 'Chorus II'; Vendor: 'Sink'; Category: 'Sink';
     Data: 'chew_depth=0.25;chew_freq=0.6;chew_var=0.3;deg_amt=0;deg_depth=0;deg_var=0;depth=0.8;drive=0.5;drywet=0.65;gap=1;h_bass=-0.21;h_treble=-0.14;ingain=0;mode=2;os_factor=1;outgain=0;rate=0.32;sat=0.5;spacing=1;speed=7.5;thick=1;width=0.5;wow_depth=0.8;wow_rate=0.26'),
    (Name: 'Chorus III'; Vendor: 'Sink'; Category: 'Sink';
     Data: 'chew_depth=0.25;chew_freq=0.6;chew_var=0.3;deg_amt=0;deg_depth=0;deg_var=0;depth=0.28;drive=0.5;drywet=0.55;gap=1;h_bass=-0.06999999;h_treble=0.22;ingain=0;mode=2;os_factor=1;outgain=2;rate=0;sat=0.5;spacing=1;speed=7.5;thick=1;width=0.5;wow_depth=0.8;wow_rate=0.18;mix_group=0'),
    (Name: 'Chorus IV'; Vendor: 'Sink'; Category: 'Sink';
     Data: 'chew_depth=0.25;chew_freq=0.6;chew_var=0.3;deg_amt=0;deg_depth=0;deg_var=0;depth=0.8;drive=0.5;drywet=0.55;gap=1;h_bass=-0.06999999;h_treble=0.22;ingain=0;mode=2;os_factor=1;outgain=0;rate=0.07;sat=0.5;spacing=1;speed=3.75;thick=1;width=1;wow_depth=1;wow_rate=0.06;mix_group=0'),
    (Name: 'Clean Fat'; Vendor: 'Sink'; Category: 'Sink';
     Data: 'chew_depth=0;chew_freq=0;chew_var=0;deg_amt=0;deg_depth=0;deg_var=0;depth=0;drive=0.65;drywet=1;gap=1;h_bass=-0.5;h_treble=-0.5;ingain=0;mix_group=0;mode=3;os_factor=1;outgain=0;rate=0.3;sat=0.65;spacing=1;speed=30;thick=1;width=0.75;wow_depth=0;wow_rate=0.25'),
    (Name: 'Fat II'; Vendor: 'Sink'; Category: 'Sink';
     Data: 'chew_depth=0;chew_freq=0;chew_var=0;deg_amt=0;deg_depth=0;deg_var=0;depth=0;drive=0.75;drywet=1;gap=1;h_bass=-0.3;h_treble=-0.3;ingain=0;mix_group=0;mode=0;os_factor=1;outgain=-3;rate=0.3;sat=0.65;spacing=1;speed=7.5;thick=1;width=0.75;wow_depth=0;wow_rate=0.25'),
    (Name: 'Gritty'; Vendor: 'Sink'; Category: 'Sink';
     Data: 'chew_depth=0;chew_freq=0;chew_var=0;deg_amt=0;deg_depth=0;deg_var=0;depth=0;drive=1;drywet=1;gap=1;h_bass=0.15;h_treble=0.3;ingain=2;mix_group=0;mode=2;os_factor=1;outgain=-2;rate=0.3;sat=0.5;spacing=1;speed=3.5;thick=1;width=0.65;wow_depth=0;wow_rate=0.15'),
    (Name: 'Gritty II'; Vendor: 'Sink'; Category: 'Sink';
     Data: 'chew_depth=0;chew_freq=0;chew_var=0;deg_amt=0;deg_depth=0;deg_var=0;depth=0;drive=1;drywet=1;gap=1;h_bass=-0.25;h_treble=0.25;ingain=2;mix_group=0;mode=2;os_factor=1;outgain=-2;rate=0.3;sat=0.6;spacing=1;speed=3.5;thick=1;width=0.35;wow_depth=0;wow_rate=0.15'),
    (Name: 'LoFi'; Vendor: 'Sink'; Category: 'Sink';
     Data: 'chew_depth=0;chew_freq=0.4;chew_var=0;deg_amt=0;deg_depth=0.15;deg_var=0;depth=0.15;drive=1;drywet=1;gap=1;h_bass=0.25;h_treble=-0.1;ingain=1;mix_group=0;mode=2;os_factor=1;outgain=-1.5;rate=0.3;sat=0.65;spacing=1;speed=1.75;thick=1;width=0.45;wow_depth=0.25;wow_rate=0.15'),
    (Name: 'Slightly Wobbly'; Vendor: 'Sink'; Category: 'Sink';
     Data: 'chew_depth=0.05;chew_freq=0.07;chew_var=0.2;deg_amt=0;deg_depth=0.21;deg_var=0;depth=0.66;drive=0.5;drywet=1;gap=1;h_bass=-0.14;h_treble=0.22;ingain=0;mix_group=0;mode=2;os_factor=1;outgain=0;rate=0.26;sat=0.5;spacing=1;speed=15;thick=1;width=0.54;wow_depth=0.61;wow_rate=0.21')
  );

function FactoryPresetCount: Integer;
begin
  Result := Length(Presets);
end;

function GetFactoryPresetName(Index: Integer): string;
begin
  Result := Presets[Index].Name;
end;

function GetFactoryPresetCategory(Index: Integer): string;
begin
  Result := Presets[Index].Category;
end;

function GetFactoryPreset(Index: Integer): TFactoryPreset;
var
  Parts: TArray<string>;
  I, EqPos: Integer;
  FS: TFormatSettings;
  V: Double;
begin
  Result.Name := Presets[Index].Name;
  Result.Vendor := Presets[Index].Vendor;
  Result.Category := Presets[Index].Category;

  FS := TFormatSettings.Invariant;
  Parts := Presets[Index].Data.Split([';']);
  SetLength(Result.Params, 0);
  for I := 0 to High(Parts) do
  begin
    EqPos := Pos('=', Parts[I]);
    if EqPos <= 0 then
      Continue;
    if not TryStrToFloat(Copy(Parts[I], EqPos + 1, MaxInt), V, FS) then
      Continue;
    SetLength(Result.Params, Length(Result.Params) + 1);
    Result.Params[High(Result.Params)].ID := Copy(Parts[I], 1, EqPos - 1);
    Result.Params[High(Result.Params)].Value := V;
  end;
end;

procedure ApplyPreset(Params: TParameterSet; const Preset: TFactoryPreset);
var
  I: Integer;
  P: TParameter;
begin
  Params.ResetAllToDefault;
  for I := 0 to High(Preset.Params) do
  begin
    P := Params.ByID(Preset.Params[I].ID);
    if P <> nil then
      P.SetValue(Preset.Params[I].Value);
  end;
end;

function FindPresetIndex(const Name: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Presets) do
    if SameText(Presets[I].Name, Name) then
      Exit(I);
  Result := -1;
end;

end.
