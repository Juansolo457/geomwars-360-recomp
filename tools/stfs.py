"""List or extract an Xbox 360 STFS package (a LIVE, PIRS or CON container: Xbox Live Arcade
titles, title updates, DLC, saves). Reads the file table and the block hash chains; verifies
nothing (no signature or hash check). The package is only read.

    python -I tools/stfs.py <package> list
    python -I tools/stfs.py <package> extract <out_dir>

Layout (Free60's STFS notes, Velocity's StfsPackage): a fixed header (0x971A bytes for CON,
0xAD0E for LIVE and PIRS) rounded up to the next 0x1000 is the first hash table; data blocks of
0x1000 bytes follow, interleaved with hash tables (one level-0 table per 0xAA data blocks, a
level-1 table per 0xAA level-0 tables, a level-2 table above that). A "male" package (volume
descriptor flag bit 0 clear) keeps two copies of every hash table and picks one per table with a
status bit in the table above; a "female" one keeps a single copy. Each hash entry (0x18 bytes)
carries the next block number of a file's chain in its last three bytes (big-endian).
"""
import os
import struct
import sys

BLOCK = 0x1000
ENTRIES_PER_TABLE = 0xAA
HEADER_SIZE = {b'CON ': 0x971A, b'LIVE': 0xAD0E, b'PIRS': 0xAD0E}
VOLUME_DESCRIPTOR = 0x379
FILE_TABLE_BLOCK_COUNT = 0x37C
FILE_TABLE_BLOCK_NUMBER = 0x37E
ALLOCATED_BLOCKS = 0x395
DISPLAY_NAME = 0x1691
TITLE_ID = 0x360
CONTENT_TYPE = 0x344


def u24le(b, o):
    return b[o] | (b[o + 1] << 8) | (b[o + 2] << 16)


def u24be(b, o):
    return (b[o] << 16) | (b[o + 1] << 8) | b[o + 2]


class Package:
    def __init__(self, path):
        self.f = open(path, 'rb')
        self.header = self.f.read(0x4000)
        magic = self.header[:4]
        if magic not in HEADER_SIZE:
            raise SystemExit(f'{path}: not an STFS package (magic {magic!r})')
        self.magic = magic
        self.first_table = (HEADER_SIZE[magic] + 0xFFF) & ~0xFFF
        flags = self.header[VOLUME_DESCRIPTOR + 2]
        self.sex = (~flags) & 1                       # 1 = male (two copies of each table)
        self.table_shift = self.sex
        self.file_table_blocks = struct.unpack_from('<H', self.header, FILE_TABLE_BLOCK_COUNT)[0]
        self.file_table_block = u24le(self.header, FILE_TABLE_BLOCK_NUMBER)
        self.allocated = struct.unpack_from('>I', self.header, ALLOCATED_BLOCKS)[0]
        # The top table: level 0 for up to 0xAA blocks, 1 for up to 0xAA^2, 2 above that.
        if self.allocated <= ENTRIES_PER_TABLE:
            self.top_level = 0
        elif self.allocated <= ENTRIES_PER_TABLE ** 2:
            self.top_level = 1
        else:
            self.top_level = 2
        # The top table's copy (male packages): volume descriptor flag bit 1.
        self.top_copy = (flags >> 1) & 1 if self.sex else 0
        self._table_cache = {}
        self.title_id = struct.unpack_from('>I', self.header, TITLE_ID)[0]
        self.content_type = struct.unpack_from('>I', self.header, CONTENT_TYPE)[0]
        name = self.header[DISPLAY_NAME:DISPLAY_NAME + 0x100]
        self.display_name = name.decode('utf-16-be', 'replace').split('\0', 1)[0]

    # Block numbers in the data space -> file offsets.
    def backing_block(self, block):
        n = (((block + ENTRIES_PER_TABLE) // ENTRIES_PER_TABLE) << self.table_shift) + block
        if block < ENTRIES_PER_TABLE:
            return n
        n += ((block + ENTRIES_PER_TABLE ** 2) // ENTRIES_PER_TABLE ** 2) << self.table_shift
        if block < ENTRIES_PER_TABLE ** 2:
            return n
        return n + (1 << self.table_shift)

    def block_offset(self, block):
        return self.first_table + (self.backing_block(block) << 12)

    def table_backing_block(self, level, index):
        """The backing block of the FIRST copy of hash table `index` at `level`."""
        if level == 0:
            if index == 0:
                return 0
            n = index * (ENTRIES_PER_TABLE + (1 << self.table_shift))      # 0xAB male, 0xAC female
            n += ((index // ENTRIES_PER_TABLE) + 1) << self.table_shift
            if index // ENTRIES_PER_TABLE == 0:
                return n
            return n + (1 << self.table_shift)
        if level == 1:
            if index == 0:
                return ENTRIES_PER_TABLE + (1 << self.table_shift)
            n = index * ((ENTRIES_PER_TABLE ** 2) + (ENTRIES_PER_TABLE << self.table_shift) + (1 << self.table_shift))
            return n + ENTRIES_PER_TABLE + (1 << self.table_shift) + (1 << self.table_shift)
        return (ENTRIES_PER_TABLE ** 2) + (ENTRIES_PER_TABLE << self.table_shift) + (1 << self.table_shift) + (1 << self.table_shift)

    def table(self, level, index):
        """The active copy of hash table (level, index): 0xAA entries of 0x18 bytes."""
        key = (level, index)
        if key in self._table_cache:
            return self._table_cache[key]
        copy = 0
        if self.sex:
            if level == self.top_level:
                copy = self.top_copy
            else:
                above = self.table(level + 1, index // ENTRIES_PER_TABLE)
                entry = above[(index % ENTRIES_PER_TABLE) * 0x18:(index % ENTRIES_PER_TABLE + 1) * 0x18]
                copy = (entry[0x14] >> 6) & 1
        offset = self.first_table + ((self.table_backing_block(level, index) + copy) << 12)
        self.f.seek(offset)
        data = self.f.read(BLOCK)
        self._table_cache[key] = data
        return data

    def next_block(self, block):
        t = self.table(0, block // ENTRIES_PER_TABLE)
        e = (block % ENTRIES_PER_TABLE) * 0x18
        return u24be(t, e + 0x15)

    def chain(self, start, count, contiguous):
        blocks = []
        b = start
        for _ in range(count):
            if b >= 0xFFFFFF or b >= self.allocated:
                raise SystemExit(f'block chain broken at block {b:#x}')
            blocks.append(b)
            b = b + 1 if contiguous else self.next_block(b)
        return blocks

    def read_blocks(self, blocks, size):
        out = bytearray()
        for b in blocks:
            self.f.seek(self.block_offset(b))
            out += self.f.read(min(BLOCK, size - len(out)))
        return bytes(out)

    def entries(self):
        """The file table: (path, is_dir, size, start_block, block_count, contiguous)."""
        blocks = self.chain(self.file_table_block, self.file_table_blocks, False)
        table = self.read_blocks(blocks, self.file_table_blocks * BLOCK)
        entries = []
        for i in range(len(table) // 0x40):
            e = table[i * 0x40:(i + 1) * 0x40]
            flags = e[0x28]
            length = flags & 0x3F
            if length == 0:
                continue
            name = e[:length].decode('ascii', 'replace')
            is_dir = bool(flags & 0x80)
            contiguous = bool(flags & 0x40)
            block_count = u24le(e, 0x29)
            start = u24le(e, 0x2F)
            parent = struct.unpack_from('>h', e, 0x32)[0]
            size = struct.unpack_from('>I', e, 0x34)[0]
            entries.append([name, is_dir, size, start, block_count, contiguous, parent])
        paths = []
        for idx, (name, is_dir, size, start, count, contiguous, parent) in enumerate(entries):
            parts = [name]
            p = parent
            while p >= 0:
                parts.append(entries[p][0])
                p = entries[p][6]
            paths.append(('/'.join(reversed(parts)), is_dir, size, start, count, contiguous))
        return paths

    def read_file(self, entry):
        _, _, size, start, count, contiguous = entry
        blocks = self.chain(start, count, contiguous)
        data = self.read_blocks(blocks, size)
        if len(data) != size:
            raise SystemExit(f'{entry[0]}: read {len(data)} of {size} bytes')
        return data


def main(argv):
    if len(argv) < 3 or argv[2] not in ('list', 'extract'):
        raise SystemExit(__doc__)
    pkg = Package(argv[1])
    print(f'{pkg.magic.decode().strip()} package: title {pkg.title_id:08X}, content type '
          f'{pkg.content_type:08X}, "{pkg.display_name}", {pkg.allocated} blocks, '
          f'{"male" if pkg.sex else "female"}, top level {pkg.top_level}')
    entries = pkg.entries()
    if argv[2] == 'list':
        for path, is_dir, size, start, count, contiguous in entries:
            kind = 'dir ' if is_dir else 'file'
            print(f'{kind} {size:>10} {path}{"" if contiguous or is_dir else "  (chained)"}')
        return
    out = argv[3]
    for entry in entries:
        path, is_dir = entry[0], entry[1]
        if '..' in path.split('/') or os.path.isabs(path):
            raise SystemExit(f'refusing path {path!r}')
        target = os.path.join(out, *path.split('/'))
        if is_dir:
            os.makedirs(target, exist_ok=True)
            continue
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with open(target, 'wb') as f:
            f.write(pkg.read_file(entry))
        print(f'{entry[2]:>10} {path}')


if __name__ == '__main__':
    main(sys.argv)
