import sys
from elftools.elf.elffile import ELFFile
sys.argv=[sys.argv[0]]+sys.argv[1:]
exec(open('ra.py').read().split('if __name__')[0])
e=ELFFile(open(BIN,'rb'))
N={}; S={}
for x in e.get_section_by_name('.dynsym').iter_symbols():
    if x['st_value']: N[x['st_value']&~1]=x.name; S[x.name]=(x['st_value'],x['st_size'])
# PLT: imports (libc) -> naam via relocaties
rel=e.get_section_by_name('.rel.plt'); plt=e.get_section_by_name('.plt'); ds=e.get_section_by_name('.dynsym')
if rel and plt:
    for k,r in enumerate(rel.iter_relocations()):
        N[plt['sh_addr']+20+12*k]=ds.get_symbol(r['r_info_sym']).name+'@plt'
def show(name, calls_only=True):
    a,z=S[name]
    for i in md.disasm(data[off(a):off(a)+z],a):
        if i.mnemonic in('bl','blx','b') and i.op_str.startswith('#'):
            t=int(i.op_str[1:],0); print(f'{i.address:08x} {i.mnemonic:4} {N.get(t,hex(t))}')
        elif not calls_only: print(f'{i.address:08x} {i.mnemonic} {i.op_str}')
