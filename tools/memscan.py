# Reads the guest memory snapshots that --geomwars_memscan=<dir> writes (port/src/memscan.h)
# and finds game variables in them (docs/RECLINED.md, R0). Read-only; numpy required.
#
#   python -I tools/memscan.py list   <dir>
#   python -I tools/memscan.py values <dir> <addr> [<addr>...] [--type u32]
#   python -I tools/memscan.py search <dir> 3=25 7=75 12=800 [--type u32|u64|f32] [--range lo-hi]
#   python -I tools/memscan.py trend  <dir> 4 9 --inc [--type f32] [--min 20] [--range lo-hi]
#   python -I tools/memscan.py dump   <dir> <snap> <addr> [<bytes>]
#
# <snap> is a snapshot's index in time order (`list` prints them). Values are big-endian, as the
# guest stores them. `search` keeps the addresses that hold each given value in each given
# snapshot (f32 to 0.1%). `trend` keeps the addresses whose value rises (--inc) or falls (--dec)
# at every step from one snapshot to another and changes by at least --min in all: the ship's x
# under a held stick. Both print each hit's value in every snapshot. A chunk that is missing from
# a snapshot was all zero.
import argparse
import os
import sys

import numpy as np

TYPES = {'u8': ('>u1', 1), 'u16': ('>u2', 2), 'u32': ('>u4', 4), 'u64': ('>u8', 8),
         'i32': ('>i4', 4), 'f32': ('>f4', 4)}


class Snapshot:
    def __init__(self, path):
        self.path = path
        name = os.path.basename(path)
        seq, ms = name.split('-', 1)
        self.seq, self.ms = int(seq), int(ms)
        self.chunks = {}
        data = np.fromfile(os.path.join(path, 'data.bin'), dtype=np.uint8)
        offset = 0
        with open(os.path.join(path, 'chunks.idx')) as idx:
            for line in idx:
                addr, size = line.split()
                addr, size = int(addr, 16), int(size)
                self.chunks[addr] = data[offset:offset + size]
                offset += size
        self.starts = sorted(self.chunks)

    def size(self):
        return sum(len(c) for c in self.chunks.values())

    def read(self, addr, n):
        out = bytearray(n)
        chunk = addr & ~0xFFFF
        while n and chunk < addr + len(out):
            data = self.chunks.get(chunk)
            lo = max(addr, chunk)
            hi = min(addr + len(out), chunk + 0x10000)
            if data is not None and lo < chunk + len(data):
                hi2 = min(hi, chunk + len(data))
                out[lo - addr:hi2 - addr] = data[lo - chunk:hi2 - chunk].tobytes()
            chunk += 0x10000
        return bytes(out)

    def value(self, addr, typ):
        fmt, size = TYPES[typ]
        return np.frombuffer(self.read(addr, size), dtype=fmt)[0].item()


def load(root):
    dirs = [os.path.join(root, d) for d in os.listdir(root)
            if os.path.isfile(os.path.join(root, d, 'chunks.idx'))]
    snaps = [Snapshot(d) for d in dirs]
    snaps.sort(key=lambda s: s.seq)
    if not snaps:
        sys.exit(f'no snapshots in {root}')
    return snaps


def parse_range(text):
    if not text:
        return 0, 1 << 32
    lo, hi = text.split('-')
    return int(lo, 16), int(hi, 16)


def show(snaps, addrs, typ, limit=60):
    for a in addrs[:limit]:
        vals = [snaps[i].value(a, typ) for i in range(len(snaps))]
        if typ == 'f32':
            text = ' '.join(f'{v:.1f}' for v in vals)
        else:
            text = ' '.join(str(v) for v in vals)
        print(f'{a:08X}: {text}')
    if len(addrs) > limit:
        print(f'... {len(addrs) - limit} more')


def views(snap, chunk, typ):
    data = snap.chunks.get(chunk)
    fmt, size = TYPES[typ]
    if data is None:
        return None
    usable = len(data) - len(data) % size
    return data[:usable].view(fmt)


def cmd_list(snaps, args):
    for i, s in enumerate(snaps):
        print(f'{i:3}  seq {s.seq:4}  t {s.ms / 1000:7.1f} s  {len(s.chunks):5} chunks  '
              f'{s.size() >> 20:5} MB')


def cmd_values(snaps, args):
    show(snaps, [int(a, 16) for a in args.addrs], args.type, limit=10**6)


def cmd_search(snaps, args):
    fmt, size = TYPES[args.type]
    cons = []
    for c in args.constraints:
        i, v = c.split('=')
        cons.append((int(i), float(v) if args.type == 'f32' else int(v, 0)))
    # Start from a non-zero constraint: zero matches most of memory.
    cons.sort(key=lambda c: c[1] == 0)
    lo, hi = parse_range(args.range)
    first_i, first_v = cons[0]
    hits = []
    for chunk in snaps[first_i].starts:
        if chunk + 0x10000 <= lo or chunk >= hi:
            continue
        v = views(snaps[first_i], chunk, args.type)
        if args.type == 'f32':
            ok = np.isclose(v, first_v, rtol=1e-3, atol=1e-3)
        else:
            ok = v == first_v
        for k in np.nonzero(ok)[0]:
            a = chunk + int(k) * size
            if lo <= a < hi:
                hits.append(a)
    for i, want in cons[1:]:
        kept = []
        for a in hits:
            got = snaps[i].value(a, args.type)
            if (abs(got - want) <= max(1e-3, abs(want) * 1e-3)) if args.type == 'f32' else got == want:
                kept.append(a)
        hits = kept
    print(f'{len(hits)} addresses')
    show(snaps, hits, args.type)


def cmd_trend(snaps, args):
    fmt, size = TYPES[args.type]
    a0, a1 = args.first, args.last
    picked = snaps[a0:a1 + 1]
    if len(picked) < 3:
        sys.exit('trend needs at least three snapshots')
    lo, hi = parse_range(args.range)
    hits = []
    for chunk in picked[0].starts:
        if chunk + 0x10000 <= lo or chunk >= hi:
            continue
        vs = [views(s, chunk, args.type) for s in picked]
        if any(v is None for v in vs):
            continue
        n = min(len(v) for v in vs)
        m = np.stack([v[:n].astype(np.float64) for v in vs])
        d = np.diff(m, axis=0)
        ok = np.all(np.isfinite(m), axis=0) & np.all(np.abs(m) < 1e7, axis=0)
        ok &= np.all(d > 0, axis=0) if args.inc else np.all(d < 0, axis=0)
        ok &= np.all(np.abs(d) >= args.min, axis=0)
        for k in np.nonzero(ok)[0]:
            a = chunk + int(k) * size
            if lo <= a < hi:
                hits.append(a)
    print(f'{len(hits)} addresses')
    show(snaps, hits, args.type)


def cmd_dump(snaps, args):
    s = snaps[args.snap]
    a = int(args.addr, 16)
    data = s.read(a, args.bytes)
    for off in range(0, len(data), 16):
        row = data[off:off + 16]
        words = ' '.join(row[i:i + 4].hex() for i in range(0, len(row), 4))
        floats = ' '.join(f'{x:9.2f}' for x in np.frombuffer(row[:len(row) - len(row) % 4], '>f4'))
        print(f'{a + off:08X}  {words:<36}  {floats}')


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest='cmd', required=True)
    p = sub.add_parser('list'); p.add_argument('dir')
    p = sub.add_parser('values'); p.add_argument('dir'); p.add_argument('addrs', nargs='+')
    p.add_argument('--type', default='u32', choices=TYPES)
    p = sub.add_parser('search'); p.add_argument('dir'); p.add_argument('constraints', nargs='+')
    p.add_argument('--type', default='u32', choices=TYPES); p.add_argument('--range')
    p = sub.add_parser('trend'); p.add_argument('dir'); p.add_argument('first', type=int)
    p.add_argument('last', type=int); p.add_argument('--type', default='f32', choices=TYPES)
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument('--inc', action='store_true'); g.add_argument('--dec', action='store_true')
    p.add_argument('--min', type=float, default=1.0); p.add_argument('--range')
    p = sub.add_parser('dump'); p.add_argument('dir'); p.add_argument('snap', type=int)
    p.add_argument('addr'); p.add_argument('bytes', type=int, nargs='?', default=128)
    args = ap.parse_args()
    snaps = load(args.dir)
    {'list': cmd_list, 'values': cmd_values, 'search': cmd_search, 'trend': cmd_trend,
     'dump': cmd_dump}[args.cmd](snaps, args)


if __name__ == '__main__':
    main()
