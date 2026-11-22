# Minimal read-only FTP server (passive) for busybox ftpget. Only serves files from DIR.
# Stops by itself after 10 minutes. argv: directory [port]
import socket, os, sys, threading, time
DIR = os.path.abspath(sys.argv[1]); PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 2121
threading.Timer(600, lambda: os._exit(0)).start()

def session(c, addr):
    f = c.makefile('rwb', buffering=0); pasv = None
    def say(x): f.write((x + '\r\n').encode())
    say('220 ok')
    for line in f:
        cmd, _, arg = line.decode('latin1').strip().partition(' ')
        cmd = cmd.upper()
        if cmd == 'USER': say('331 ok')
        elif cmd == 'PASS': say('230 ok')
        elif cmd in ('TYPE', 'MODE', 'STRU'): say('200 ok')
        elif cmd == 'SYST': say('215 UNIX')
        elif cmd == 'PWD': say('257 "/"')
        elif cmd == 'CWD': say('250 ok')
        elif cmd == 'SIZE':
            p = os.path.join(DIR, os.path.basename(arg))
            say(f'213 {os.path.getsize(p)}' if os.path.isfile(p) else '550 no')
        elif cmd == 'PASV':
            pasv = socket.socket(); pasv.bind((c.getsockname()[0], 0)); pasv.listen(1)
            h = c.getsockname()[0].replace('.', ','); p = pasv.getsockname()[1]
            say(f'227 Entering Passive Mode ({h},{p >> 8},{p & 255})')
        elif cmd == 'RETR' and pasv:
            p = os.path.join(DIR, os.path.basename(arg))
            if not os.path.isfile(p): say('550 no'); continue
            say('150 ok'); d, _ = pasv.accept()
            with open(p, 'rb') as fh: d.sendall(fh.read())
            d.close(); pasv.close(); pasv = None; say('226 done')
            print('sent', p, 'to', addr[0], flush=True)
        elif cmd == 'QUIT': say('221 bye'); break
        else: say('502 no')
    c.close()

srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(('0.0.0.0', PORT)); srv.listen(2); print('ftp ready on', PORT, flush=True)
while True:
    c, a = srv.accept(); threading.Thread(target=session, args=(c, a), daemon=True).start()
