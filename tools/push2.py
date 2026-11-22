# Zet bestand in één keer via telnet (heredoc + base64) op de camera. argv: lokaal doelpad
import sys, base64, hashlib, socket, time
src, dst = sys.argv[1], sys.argv[2]
raw = open(src, 'rb').read(); want = hashlib.md5(raw).hexdigest()
b = base64.b64encode(raw).decode(); lines = '\n'.join(b[i:i+76] for i in range(0, len(b), 76))
exec(open('tn.py').read().split("read(); s.send(b'root")[0])   # socket + read()
read(); s.send(b'root\r\n'); read(); s.send(b'anyka\r\n'); read()
s.send(f"base64 -d > {dst}.new <<'B64EOF'\n{lines}\nB64EOF\nmd5sum {dst}.new\n".encode()); time.sleep(2)
out = read(4)
if want in out:
    s.send(f'mv {dst}.new {dst} && sync && md5sum {dst}\n'.encode()); time.sleep(1); print(read(3)); print('PUSH OK', want)
else:
    print('PUSH MISLUKT, verwacht', want, out[-500:])
