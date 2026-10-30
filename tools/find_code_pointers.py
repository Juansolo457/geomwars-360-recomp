"""Find function entries the translation missed: code addresses that the data sections point at.

Every pointer in .rdata and .data (vtables, method tables, callback tables, function-pointer
globals) that lands in a code section, 4-byte aligned, is not registered in the generated code and
starts right after a function end (blr, bctr, an unconditional b or zero padding) is printed as a
manifest line. This caught what tools/find_missed_functions.py and tools/find_vcall_thunks.py did
not in geomwars-360-recomp (run 4's 0x824B15B8, a method with no .pdata entry after a bctr) and found
374 more of the same shape in one pass (manifest round 4). A candidate that splits a registered
function shows up as an "Unresolved" codegen warning: drop it with the reason.

    python -I tools/find_code_pointers.py private/xex/default.bin port/generated/default port/geomwars_manifest.toml

The section table (code ranges, .rdata and .data) is read from private/xex/default.sections.txt
beside the image (xexdump's output); the generated function set from geomwars_register.cpp.
"""
import os
import re
import struct
import sys

BASE = 0x82000000


def main():
    image_path, generated, manifest = sys.argv[1:4]
    img = open(image_path, 'rb').read()
    code, data = [], []
    for line in open(os.path.join(os.path.dirname(image_path), 'default.sections.txt'), encoding='latin-1'):
        # "<name> 0x<start> 0x<size> [code]"; embedded section names can hold odd bytes.
        m = re.match(r'(\S+).*?(0x[0-9a-fA-F]+) (0x[0-9a-fA-F]+)( code)?\s*$', line)
        if not m:
            continue
        start, size = int(m.group(2), 16), int(m.group(3), 16)
        if m.group(4):
            code.append((start, size))
        elif m.group(1) in ('.rdata', '.data'):
            data.append((start, size))
    registered = set(int(m, 16) for m in re.findall(
        r'SetFunction\(0x([0-9A-Fa-f]+)', open(os.path.join(generated, 'geomwars_register.cpp'), encoding='utf-8').read()))
    manifest_text = open(manifest, encoding='utf-8').read()
    in_manifest = set(int(m, 16) for m in re.findall(r'^(?:# )?0x([0-9A-Fa-f]{8}) ', manifest_text, re.M))

    def word(a):
        return struct.unpack_from('>I', img, a - BASE)[0]

    def in_code(v):
        return any(s <= v < s + n for s, n in code)

    def ends_function(a):
        prev = word(a - 4)
        return prev in (0x4E800020, 0x4E800420) or ((prev >> 26) == 18 and not prev & 1) or prev == 0

    found = {}
    for start, size in data:
        for a in range(start, start + size - 3, 4):
            v = word(a)
            if v & 3 or not in_code(v) or v in registered or v in in_manifest:
                continue
            if ends_function(v) and word(v) != 0:
                found.setdefault(v, a)
    for v in sorted(found):
        print(f'0x{v:08X} = {{}}  # from 0x{found[v]:08X}, after a function end')
    print(f'# {len(found)} unregistered code pointers at function boundaries', file=sys.stderr)


if __name__ == '__main__':
    main()
