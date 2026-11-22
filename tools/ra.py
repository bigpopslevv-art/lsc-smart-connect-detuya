# Kleine reverse-engineering helper voor anyka_ipc (ARM32, stripped, non-PIE).
import sys, struct, re
from elftools.elf.elffile import ELFFile
from capstone import Cs, CS_ARCH_ARM, CS_MODE_ARM

BIN = sys.argv[1]
f = open(BIN, 'rb'); data = f.read(); elf = ELFFile(open(BIN, 'rb'))
segs = [(s['p_vaddr'], s['p_offset'], s['p_filesz']) for s in elf.iter_segments() if s['p_type'] == 'PT_LOAD']
text = elf.get_section_by_name('.text')
TS, TE = text['sh_addr'], text['sh_addr'] + text['sh_size']
md = Cs(CS_ARCH_ARM, CS_MODE_ARM); md.detail = False; md.skipdata = True  # .text bevat ook data

def off(va):
    for v, o, n in segs:
        if v <= va < v + n: return o + va - v
def va_of(o):
    for v, so, n in segs:
        if so <= o < so + n: return v + o - so
def word(va): return struct.unpack('<I', data[off(va):off(va) + 4])[0]
def cstr(va):
    o = off(va); e = data.index(b'\0', o); return data[o:e].decode('latin1')

# literal-pool index: waarde -> adressen in .text waar die waarde als woord staat
pool = {}
for a in range(TS, TE, 4):
    pool.setdefault(word(a), []).append(a)

# alle ldr rX,[pc,#imm] -> (instr-adres, geladen literal-adres)
ldrs = {}
code = data[off(TS):off(TE)]
for i in md.disasm(code, TS):
    if i.mnemonic == 'ldr' and '[pc' in i.op_str:
        m = re.search(r'#(-?0x[0-9a-f]+|-?\d+)', i.op_str)
        imm = int(m.group(1), 0) if m else 0
        ldrs.setdefault(i.address + 8 + imm, []).append(i.address)

def str_addr(s):
    b = s.encode() + b'\0'; res = []
    for m in re.finditer(re.escape(b), data):
        if m.start() == 0 or data[m.start() - 1] == 0:
            res.append(va_of(m.start()))
    return [r for r in res if r]

def xrefs_va(va):
    return [ins for lit in pool.get(va, []) for ins in ldrs.get(lit, [])]

def func_start(a):
    # zoek terug naar 'push {.., lr}' / stmdb sp!
    for b in range(a, max(TS, a - 0x4000), -4):
        w = word(b)
        if (w & 0xFFFF4000) == 0xE92D4000: return b
    return None

def dis(a, n=40):
    return [f'{i.address:08x}  {i.mnemonic} {i.op_str}' for i in md.disasm(data[off(a):off(a) + 4 * n], a)]

def calls(fs, maxlen=0x3000):
    out = []
    for i in md.disasm(data[off(fs):off(fs) + maxlen], fs):
        if i.address > fs and (word(i.address) & 0xFFFF4000) == 0xE92D4000: break
        if i.mnemonic in ('bl', 'blx') and i.op_str.startswith('#'):
            out.append((i.address, int(i.op_str[1:], 0)))
    return out

if __name__ == '__main__':
    for s in sys.argv[2:]:
        for va in str_addr(s):
            for x in xrefs_va(va):
                print(f'{s!r} str@{va:08x} ref@{x:08x} func@{func_start(x) or 0:08x}')
