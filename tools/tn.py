# Minimal telnet client: logs in to the camera and runs commands (argv[1:]).
import socket, sys, time
HOST = '192.168.1.240'
s = socket.create_connection((HOST, 23), timeout=10)

def read(t=1.5):
    s.settimeout(t); buf = b''
    try:
        while True:
            d = s.recv(4096)
            if not d: break
            out = bytearray(); i = 0
            while i < len(d):  # refuse telnet options
                if d[i] == 255 and i + 2 < len(d):
                    s.send(bytes([255, 252 if d[i+1] == 253 else 254, d[i+2]])); i += 3
                else:
                    out.append(d[i]); i += 1
            buf += out
    except socket.timeout:
        pass
    return buf.decode('latin1')

read(); s.send(b'root\r\n'); read(); s.send(b'anyka\r\n'); read()
for c in sys.argv[1:]:
    s.send(c.encode() + b'\r\n'); time.sleep(0.3)
    print(read(3))
s.close()
