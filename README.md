# LSC Smart Connect — de-Tuya (art. 3215672.3 · Anyka AK3918AV130L)

Remove the **Tuya cloud** from a cheap **LSC Smart Connect** indoor camera (Action,
art. no. **3215672.3**, SoC **Anyka AK3918AV130L**) and run it as a **local** camera:
its own RTSP stream to your own server, fully cut off from the internet.

The camera keeps running the original `anyka_ipc` (that binary also produces the video), but a
**4-byte patch** makes it skip the Tuya cloud. On top of that a lockdown makes sure the device can
only reach your own LAN.

> **Status:** working. The one open issue is hardware, not software — see *Known gotchas → Brownout*.

```
sensor ─▶ anyka_ipc (Tuya skipped) ─▶ RTSP :554 ─▶ your server (go2rtc) ─▶ browser
                          └─ no DNS · no internet route · no IPv6 ─┘
```

---

## ⚠️ Warning & disclaimer

- For **your own camera** only. You are responsible for what you do.
- **Only art. no. 3215672.3** (Anyka AK3918AV130L). A different article number (e.g. `.2`) can be a
  different SoC — then this does not apply and you can damage the camera. Check your chip first.
- This writes the internal flash. A mistake can brick the camera (**brick risk**). Make a full
  **back-up of all MTD partitions** first, and test everything from the SD card before flashing.
- This repo contains **no vendor firmware** (`anyka_ipc`, flash images, kernel modules are
  copyright Anyka/Tuya and are **not** distributed). You patch your **own** dumped binary.
- **Never** put your `_ak39_factory.ini` (wifi password), `config/`, `tuya_*.db` or flash dumps
  online. See `.gitignore`.
- If you use a loose li-ion/li-po cell: mind the **safety** (charge current, protection).

---

## What you need

- The camera (Anyka AK3918AV130L — check via `cat /proc/cpuinfo` / the modules `ak_isp.ko` etc.).
- A **FAT32 micro-SD card** (the boot hook and the recovery run from it).
- **Root over telnet.** This project assumes you already have root through the known
  community SD hack for this camera (boot hook via `/mnt/hostapd` → `hack.sh`, plus an
  `_ak39_factory.ini` that enables factory-test mode → telnetd + RTSP). Login: `root` / `anyka`.
- A **Linux machine/server** with `squashfs-tools` (`mksquashfs`/`unsquashfs`) to rebuild the
  APP partition, and to run go2rtc + the clock sync.
- A **5V power supply of ≥ 2A** (see *Brownout*).

---

## How it works (steps)

### 1. Root + full back-up
Get root (community SD hack) and dump **all** MTD partitions to the SD card so you can always roll
back. On the camera:
```sh
for i in 0 1 2 3 4 5 6 7; do dd if=/dev/mtdblock$i of=/tmp/sd/mtd$i.bin bs=4096; done
sync; cat /proc/mtd > /tmp/sd/mtd.txt; md5sum /tmp/sd/mtd*.bin > /tmp/sd/md5.txt
```
The APP partition (`/usr`, squashfs) is usually `mtd7` / `/dev/mtdblock7`.

### 2. Patch out Tuya — `patch/patch_notuya.py`
`main()` in `anyka_ipc` calls, in order: `ht_media_service_init` (video/audio) →
`ht_device_ctrl_init` (incl. the factory RTSP server) → **`ht_tuya_service_start`** (the whole cloud).
The patch replaces the `bl ht_tuya_service_start` (on this firmware VA `0x10000+0xf0554`) with
`mov r0, #1` ("started, OK"). Video and RTSP keep running; Tuya is never executed.
**4 bytes changed, nothing else.**
```sh
python3 patch/patch_notuya.py anyka_ipc anyka_ipc.notuya
```
> The call address is firmware-specific. Verify with a disassembler (see `tools/`) that there is
> really a `bl ht_tuya_service_start` at that spot before patching — the script checks this.

### 3. Rebuild the APP partition — `firmware/build.sh`
Unpack the squashfs, drop in the patched binary, add the custom scripts, repack with the **exact
same** compression (xz, 128 KB block). Runs on your Linux box. Adjust the md5s and paths at the top
for your own dump. Result: `usr_new.sqsh` (must be ≤ the partition size).

### 4. Flash — `firmware/flash.sh`
Writes `usr_new.sqsh` to `/dev/mtdblock7`, **reads it back and compares the md5**, and only reboots
if it matches. Uses only `/bin/busybox` (in ROOTFS, which is not overwritten).
```sh
sh flash.sh usr_new.sqsh <md5> <number_of_4k_blocks>
```
**Alternative without flashing:** run everything from the SD card instead (see *Recovery*). Safer to
test with.

### 5. Lockdown — `firmware/lsc_lockdown.sh`
Runs at boot (via `service.sh`, before anyka_ipc). Every 2 s, forever:
- static IP (`udhcpc` is broken on this camera: symlink loop), no DHCP server, no IPv6, empty `/etc/resolv.conf`;
- **default gateway = the camera itself.** Required! anyka_ipc pings the gateway; without a reply it
  drops the wifi every ~30 s. Pointing the gateway at itself makes that ping succeed, while internet
  traffic has nowhere to go. Only active after 90 s, because earlier it disturbs the first wifi association.

### 6. Status LED — `firmware/lsc_led.sh`
Fast blink for 30 s at boot; then 1 flash per 2 min with network, 2 short blinks without network.
(The original `state/red/blue_led.sh` are disabled so anyka_ipc does not take over the LED.)

### 7. Clock — `server/camtime.py`
The camera has no internet/NTP, so your **server** sets the clock every minute over telnet. DST is
handled in the format anyka_ipc itself reads (`UTC-01:00` / `UTC-02:00`).

### 8. Live video — `server/go2rtc.yaml.example`
Run [go2rtc](https://github.com/AlexxIT/go2rtc) on your server; view it in the browser at
`http://<server>:1984/stream.html?src=camera`. Recording/motion detection can be done with go2rtc or Frigate.

---

## Recovery — `sd-recovery/`
Put `hostapd` + `hack.sh` (+ your rebuilt `usr_new.sqsh` and `_ak39_factory.ini`) on the SD card.
On every boot `hack.sh` checks the APP partition and **writes the known-good image back** if the
flash is damaged, with verification and reboot. If the camera ends up in a bad state, "card in,
power on" is your lifeline. Card out = back to normal behaviour.

---

## Known gotchas (found with blood, sweat and tears)

- **Brownout on the day/night switch.** The moment the IR-cut filter flips + the IR LEDs switch,
  there is a current spike. A weak supply (PC USB, thin cable) dips and the chip **resets**. Not on
  every switch, so it looks random. **Fix: 5V supply ≥ 2A**, a short thick cable, and optionally a
  **capacitor (~1000 µF) across the 5V** close to the camera. Not a software bug.
- **Timezone format.** `anyka_ipc` reads `/etc/config/TZ` itself and only understands `UTC±HH:MM`.
  Put a POSIX-TZ string there (`CET-1CEST,...`) and it hangs → no wifi → reboots.
- **`udhcpc` broken** (symlink loop "Too many levels of symbolic links"): use a **static IP**.
- **Self-gateway required**, otherwise the wifi re-associates every ~30 s (see step 5).
- **SD card sometimes not detected** on a cold boot, especially on a weak supply → reseat firmly,
  better supply. Without the card `hack.sh` does not run (the hook lives in the AP-mode path).
- **CRLF.** All shell scripts must have **LF** line endings; run them through `tr -d '\r'` +
  `sh -n` before they go on the camera.

---

## Config
Example IPs in the scripts: camera `192.168.1.240`, router `192.168.1.1`. Change them to your own
network in: `firmware/lsc_lockdown.sh`, `firmware/lsc_led.sh`, `sd-recovery/hack.sh`,
`server/camtime.py`, and the `tools/`. Wifi goes in `_ak39_factory.ini` (see the `.example`).

## `tools/`
Reverse-engineering and transport helpers (Python, `capstone` + `pyelftools`): `ra.py`/`names.py`
(ARM32 disassembly with symbol names from `.dynsym`), `tn.py` (mini telnet client),
`push2.py`/`pull2.py` (files to/from the camera over telnet+base64).

## Credits
- The Anyka/LSC community for the original SD boot hack and root method.
- [go2rtc](https://github.com/AlexxIT/go2rtc) for the streaming.

## License
MIT (the scripts in this repo only). Vendor firmware is not covered and is not included.
