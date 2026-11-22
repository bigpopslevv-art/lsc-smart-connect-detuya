# Houdt de klok van de LSC-camera gelijk met deze server (camera heeft geen internet/NTP).
# - elke 60 s: klok van de camera uitlezen; alleen bijzetten als die >3 s afwijkt
#   (dus vlak na elke herstart binnen een minuut goed, zonder onnodig te schrijven)
# - hardwareklok in LOKALE tijd schrijven: main.sh doet bij het opstarten 'hwclock -s' (lokaal);
#   met 'hwclock -w -u' liep de camera na een herstart 1 uur achter.
# - zomer/wintertijd: /etc/config/TZ in het formaat dat anyka_ipc zelf leest ("UTC-01:00"/"UTC-02:00");
#   anyka_ipc snapt niets anders (bv. "CET-1CEST,..."), dus nooit een ander formaat schrijven.
import socket, time, datetime
from zoneinfo import ZoneInfo

CAM = "192.168.1.240"
TZONE = ZoneInfo("Europe/Amsterdam")


def tz_string(now_utc):
    off = int(now_utc.astimezone(TZONE).utcoffset().total_seconds() // 3600)   # 1 of 2
    return f"UTC{'-' if off >= 0 else '+'}{abs(off):02d}:00"                    # POSIX: oost = '-'


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
                while i < len(d):           # telnet-opties weigeren
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
        out = c.run("date -u +%s; cat /etc/config/TZ", "EINDE")
        nums = [l.strip() for l in out.splitlines() if l.strip().isdigit()]
        tzs = [l.strip() for l in out.splitlines() if l.strip().startswith("UTC")]
        cam_epoch = int(nums[0]) if nums else 0
        now = datetime.datetime.now(datetime.timezone.utc)
        msgs = []
        want_tz = tz_string(now)
        if tzs and tzs[0] != want_tz:                     # alleen bij wissel zomer/winter
            c.run(f"echo {want_tz} > /etc/config/TZ", "KLAAR1"); msgs.append(f"TZ {tzs[0]} -> {want_tz}")
        diff = cam_epoch - int(now.timestamp())
        if abs(diff) > 3:
            stamp = now.strftime("%Y-%m-%d %H:%M:%S")
            c.run(f'date -u -s "{stamp}" >/dev/null; hwclock -w 2>/dev/null', "KLAAR2")
            msgs.append(f"klok bijgezet (week {diff:+d} s af)")
        return msgs
    finally:
        c.close()


if __name__ == "__main__":
    while True:
        try:
            for m in check_once(): print(m, flush=True)
        except (OSError, IndexError, ValueError) as e:
            print("camera niet bereikbaar:", type(e).__name__, flush=True)
        time.sleep(60)
