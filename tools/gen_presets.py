#!/usr/bin/env python3
"""
Regenerates src/params/ChowTape.Presets.pas from the original plug-in's
.chowpreset files.

The .chowpreset files are not part of this repository -- point this at a
checkout of the upstream C++ project.

Usage:
    python3 tools/gen_presets.py <path to AnalogTapeModel/Plugin/Source/Presets/PresetConfigs>

The .chowpreset files are XML and store *real* parameter values (dB, Hz, ips,
...), not normalised ones. Two things need fixing up on the way in:

  * older presets store spacing/thickness/gap in metres rather than microns --
    the two ranges do not overlap, so a value below 1e-3 is taken as metres;
  * older presets store dry/wet as a percentage rather than 0..1.

Parameters that no longer exist ("preset", the offline-render oversampling
options) are dropped, and the pre-2.11 "os" parameter maps onto "os_factor".
"""

import os
import sys
import xml.etree.ElementTree as ET

SKIP = {'preset', 'os_render_factor', 'os_render_mode', 'os_render_like_realtime'}
MICRON = {'gap', 'spacing', 'thick'}

HEADER = '''unit ChowTape.Presets;

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
'''

FOOTER = '''
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
'''


def category_of(path, root_dir):
    rel = os.path.relpath(path, root_dir)
    parts = rel.split(os.sep)
    return '/'.join(parts[:-1]) if len(parts) > 1 else ''


def collect(root_dir):
    files = []
    for root, _dirs, names in os.walk(root_dir):
        for name in sorted(names):
            if name.endswith('.chowpreset'):
                files.append(os.path.join(root, name))

    presets = []
    for path in sorted(files, key=lambda p: (category_of(p, root_dir).lower(),
                                             os.path.basename(p).lower())):
        tree = ET.fromstring(open(path, encoding='utf-8-sig').read())
        name = tree.get('name') or os.path.splitext(os.path.basename(path))[0]
        vendor = tree.get('vendor') or ''
        node = tree.find('Parameters')
        if node is None:
            continue

        params = []
        for element in node.findall('PARAM'):
            pid, raw = element.get('id'), element.get('value')
            if not pid or not raw or pid in SKIP:
                continue
            try:
                value = float(raw)
            except ValueError:
                continue

            if pid == 'os':
                pid, value = 'os_factor', max(0.0, min(4.0, round(value)))
            if pid == 'drywet' and value > 1.5:
                value /= 100.0
            if pid in MICRON and abs(value) < 1e-3:
                value *= 1e6

            params.append((pid, value))

        presets.append((name, vendor, category_of(path, root_dir), params))
    return presets


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1

    root_dir = sys.argv[1]
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       '..', 'src', 'params', 'ChowTape.Presets.pas')

    presets = collect(root_dir)
    if not presets:
        print('no presets found under', root_dir)
        return 1

    def esc(text):
        return text.replace("'", "''")

    lines = [HEADER, '  Presets: array[0..%d] of TPresetDef = (' % (len(presets) - 1)]
    for index, (name, vendor, category, params) in enumerate(presets):
        data = ';'.join('%s=%.7g' % (pid, value) for pid, value in params)
        comma = '' if index == len(presets) - 1 else ','
        lines.append("    (Name: '%s'; Vendor: '%s'; Category: '%s';"
                     % (esc(name), esc(vendor), esc(category)))
        lines.append("     Data: '%s')%s" % (esc(data), comma))
    lines.append('  );')
    lines.append(FOOTER)

    with open(out, 'w', encoding='utf-8', newline='') as handle:
        handle.write('\n'.join(lines))

    print('wrote %d presets to %s' % (len(presets), os.path.normpath(out)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
