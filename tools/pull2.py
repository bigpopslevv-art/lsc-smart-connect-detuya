# Fetches a file/block device from the camera over telnet+base64 (fast: bytes, only checks the tail).
# argv: path_on_camera local_file
import sys, socket, base64, hashlib, time, re
src, dst = sys.argv[1], sys.argv[2]
s = socket.create_connection(('192.168.1.240', 23), timeout=10)

def drain(t):
    s.settimeout(t); out = bytearray()
    try:
        while True:
            d = s.recv(65536)
            if not d: break
            out += d
    except socket.timeout: pass
    return bytes(out)

def neg(d):  # refuse telnet options and filter them out
    out = bytearray(); i = 0
    while i < len(d):
        if d[i] == 255 and i + 2 < len(d):
            s.send(bytes([255, 252 if d[i+1] == 253 else 254, d[i+2]])); i += 3
        else: out.append(d[i]); i += 1
    return bytes(out)

neg(drain(1.5)); s.send(b'root\r\n'); neg(drain(1.5)); s.send(b'anyka\r\n'); neg(drain(1.5))
s.send(f'echo BEGIN""_B64; base64 {src}; echo END""_B64; md5sum {src}; echo DONE""_X\n'.encode())
chunks = []; tail = b''; t0 = time.time(); s.settimeout(20); n = 0
while True:
    d = s.recv(262144)
    if not d: break
    chunks.append(d); n += len(d); tail = (tail + d)[-200:]
    if b'DONE_X' in tail: break
    if time.time() - t0 > 900: sys.exit('timeout')
buf = b''.join(chunks)
body = buf.split(b'BEGIN_B64', 1)[1].split(b'END_B64')[0]
raw = base64.b64decode(re.sub(rb'[^A-Za-z0-9+/=]', b'', body))
want = re.search(rb'([0-9a-f]{32})\s+' + re.escape(src.encode()), buf).group(1).decode()
open(dst, 'wb').write(raw); got = hashlib.md5(raw).hexdigest()
print(len(raw), got, 'camera:', want, 'OK' if got == want else 'MISMATCH', f'{time.time()-t0:.0f}s')
