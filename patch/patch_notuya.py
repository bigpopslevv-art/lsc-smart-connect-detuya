# Creates anyka_ipc.notuya: main() no longer calls ht_tuya_service_start.
# Video (ht_media_service_init), drivers and the factory RTSP (ht_device_ctrl_init) still start.
import sys, struct
from capstone import Cs, CS_ARCH_ARM, CS_MODE_ARM
src, dst = sys.argv[1], sys.argv[2]
d = bytearray(open(src, 'rb').read())
VA, BASE = 0xf0554, 0x10000          # call site in main; PT_LOAD vaddr 0x10000 = file offset 0
o = VA - BASE
md = Cs(CS_ARCH_ARM, CS_MODE_ARM)
before = next(md.disasm(bytes(d[o:o+4]), VA))
assert (before.mnemonic, before.op_str) == ('bl', '#0xef4dc'), before   # ht_tuya_service_start
d[o:o+4] = struct.pack('<I', 0xE3A00001)   # mov r0, #1 -> "started", main then waits forever
after = next(md.disasm(bytes(d[o:o+4]), VA))
assert (after.mnemonic, after.op_str) == ('mov', 'r0, #1')
assert sum(a != b for a, b in zip(d, open(src, 'rb').read())) <= 4     # nothing else changed
open(dst, 'wb').write(d)
print('patch OK:', before.mnemonic, before.op_str, '->', after.mnemonic, after.op_str)
