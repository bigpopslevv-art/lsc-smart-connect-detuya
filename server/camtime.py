# Keeps the LSC camera's clock in sync with this server (the camera has no internet/NTP).
# - every 60 s: read the camera clock; only set it if it is off by >3 s
#   (so right after every reboot it is correct within a minute, without needless writes)
# - write the hardware clock in LOCAL time: main.sh runs 'hwclock -s' (local) at boot;
#   with 'hwclock -w -u' the camera ran 1 hour behind after a reboot.
# - DST: /etc/config/TZ in the format anyka_ipc itself reads ("UTC-01:00"/"UTC-02:00");
#   anyka_ipc understands nothing else (e.g. "CET-1CEST,..."), so never write another format.
import socket, time, datetime
from zoneinfo import ZoneInfo

CAM = "192.168.1.240"
TZONE = ZoneInfo("Europe/Amsterdam")


def tz_string(now_utc):
    off = int(now_utc.astimezone(TZONE).utcoffset().total_seconds() // 3600)   # 1 or 2
    return f"UTC{'-' if off >= 0 else '+'}{abs(off):02d}:00"                    # POSIX: east = '-'


assert tz_string(datetime.datetime(2026, 1, 15, 12, tzinfo=datetime.timezone.utc)) == "UTC-01:00"
assert tz_string(datetime.datetime(2026, 7, 15, 12, tzinfo=datetime.timezone.utc)) == "UTC-02:00"


class Cam:
    def __init__(self):
        self.s = socket.create_connection((CAM, 23), timeout=5)
        self.rd(); self.s.send(b"root\r\n"); self.rd(); self.s.send(b"anyka\r\n"); self.rd()

    def rd(self, t=1.0):
        self.s.settimeout(t); b = b""
        try:
            while True:
                d = self.s.recv(4096)
                if not d: break
                i = 0
                while i < len(d):           # refuse telnet options
                    if d[i] == 255 and i + 2 < len(d):
                        self.s.send(bytes([255, 252 if d[i+1] == 253 else 254, d[i+2]])); i += 3
                    else:
                        b += d[i:i+1]; i += 1
        except socket.timeout:
            pass
        return b.decode("latin1")

    def run(self, cmd, marker):
        self.s.send(f"{cmd}; echo {marker[:2]}\"\"{marker[2:]}\r\n".encode())
        out = ""
        for _ in range(8):
            out += self.rd(1.0)
            if marker in out.split(cmd, 1)[-1]: break
        return out.split(cmd, 1)[-1]

    def close(self): self.s.close()


def check_once():
    c = Cam()
    try:
        out = c.run("date -u +%s; cat /etc/config/TZ", "DONE")
        nums = [l.strip() for l in out.splitlines() if l.strip().isdigit()]
        tzs = [l.strip() for l in out.splitlines() if l.strip().startswith("UTC")]
        cam_epoch = int(nums[0]) if nums else 0
        now = datetime.datetime.now(datetime.timezone.utc)
        msgs = []
        want_tz = tz_string(now)
        if tzs and tzs[0] != want_tz:                     # only on a summer/winter switch
            c.run(f"echo {want_tz} > /etc/config/TZ", "TZSET"); msgs.append(f"TZ {tzs[0]} -> {want_tz}")
        diff = cam_epoch - int(now.timestamp())
        if abs(diff) > 3:
            stamp = now.strftime("%Y-%m-%d %H:%M:%S")
            c.run(f'date -u -s "{stamp}" >/dev/null; hwclock -w 2>/dev/null', "CLKSET")
            msgs.append(f"clock set (was off by {diff:+d} s)")
        return msgs
    finally:
        c.close()


if __name__ == "__main__":
    while True:
        try:
            for m in check_once(): print(m, flush=True)
        except (OSError, IndexError, ValueError) as e:
            print("camera unreachable:", type(e).__name__, flush=True)
        time.sleep(60)
