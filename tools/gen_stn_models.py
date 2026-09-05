#!/usr/bin/env python3
"""
Packs the STN networks into resources/stn_models.bin, which is embedded in the
DLL via ChowTapeResources.rc.

The JSON that RTNeural exports is about eleven times larger than the numbers it
carries, and parsing a megabyte of it on every plug-in instantiation is pure
waste. Each network is only 49 values, so they all fit in ~88 KB of float64.

Usage:
    python3 tools/gen_stn_models.py [path to STN_Models folder]

Layout of the output file (little-endian throughout):

    char[4]   magic 'CTSN'
    uint32    format version (1)
    uint32    width model count  (11)
    uint32    saturation count   (21)
    uint32    values per model   (49)
    float64[] width-major, then saturation, then per model:
                  W1[4][5]  B1[4]  W2[4][4]  B2[4]  W3[4]  B3
              i.e. weight matrices transposed to [output][input], which is the
              order ChowTape.DSP.HysteresisSTN reads them back in.
"""

import json
import os
import struct
import sys

WIDTH_TAGS = ['0', '10', '20', '30', '40', '50', '60', '70', '80', '90', '100']
SAT_TAGS = ['0', '5', '10', '15', '20', '25', '30', '35', '40', '45', '50',
            '55', '60', '65', '70', '75', '80', '85', '90', '95', '100']
VALUES_PER_MODEL = 49


def pack_model(model):
    """Flatten one 5-4-4-1 dense/tanh network into 49 float64."""
    layers = [L for L in model['layers'] if L.get('type') == 'dense']
    if len(layers) != 3:
        raise ValueError('expected 3 dense layers, got %d' % len(layers))

    out = []
    for index, (n_in, n_out) in enumerate(((5, 4), (4, 4), (4, 1))):
        W, b = layers[index]['weights']
        if len(W) != n_in or any(len(row) != n_out for row in W):
            raise ValueError('layer %d has unexpected shape' % index)
        if len(b) != n_out:
            raise ValueError('layer %d bias has unexpected length' % index)
        # JSON stores [input][output]; transpose to [output][input]
        for o in range(n_out):
            for i in range(n_in):
                out.append(float(W[i][o]))
        out.extend(float(x) for x in b)

    if len(out) != VALUES_PER_MODEL:
        raise ValueError('packed %d values, expected %d' % (len(out), VALUES_PER_MODEL))
    return out


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, '..', 'resources', 'STN_Models')
    dst = os.path.join(here, '..', 'resources', 'stn_models.bin')

    values = []
    for width in WIDTH_TAGS:
        path = os.path.join(src, 'hyst_width_%s.json' % width)
        if not os.path.exists(path):
            print('missing %s' % path)
            return 1
        models = json.load(open(path, encoding='utf-8'))
        for sat in SAT_TAGS:
            tag = 'drive_%s_%s' % (sat, width)
            if tag not in models:
                print('missing model %s in %s' % (tag, os.path.basename(path)))
                return 1
            values.extend(pack_model(models[tag]))

    expected = len(WIDTH_TAGS) * len(SAT_TAGS) * VALUES_PER_MODEL
    if len(values) != expected:
        print('packed %d values, expected %d' % (len(values), expected))
        return 1

    with open(dst, 'wb') as handle:
        handle.write(b'CTSN')
        handle.write(struct.pack('<IIII', 1, len(WIDTH_TAGS), len(SAT_TAGS), VALUES_PER_MODEL))
        handle.write(struct.pack('<%dd' % len(values), *values))

    print('wrote %s' % os.path.normpath(dst))
    print('  %d networks, %d values, %.0f KB'
          % (len(WIDTH_TAGS) * len(SAT_TAGS), len(values), os.path.getsize(dst) / 1024))
    return 0


if __name__ == '__main__':
    sys.exit(main())
