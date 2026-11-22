# LSC Smart Connect — de-Tuya (art.nr. 3215672.3 · Anyka AK3918AV130L)

Haal de **Tuya-cloud** van een goedkope **LSC Smart Connect** indoor-camera (Action,
art.nr. **3215672.3**, SoC **Anyka AK3918AV130L**) en gebruik hem als **lokale** camera:
een eigen RTSP-stream naar je eigen server, en verder volledig afgesloten van internet.

De camera blijft de originele `anyka_ipc` draaien (die levert ook het beeld), maar met een
**4-byte patch** slaat die de Tuya-cloud over. Daarbovenop komt een lockdown zodat het
apparaat alléén je eigen LAN kan bereiken.

> **Status:** werkt. Eén open punt is hardware, geen software — zie *Bekende valkuilen → Brownout*.

```
sensor ─▶ anyka_ipc (Tuya overgeslagen) ─▶ RTSP :554 ─▶ jouw server (go2rtc) ─▶ browser
                             └─ geen DNS · geen internetroute · geen IPv6 ─┘
```

---

## ⚠️ Waarschuwing & disclaimer

- Alleen voor **je eigen camera**. Je bent zelf verantwoordelijk.
- **Alleen art.nr. 3215672.3** (Anyka AK3918AV130L). Een ander artikelnummer (bv. `.2`) kan een
  andere SoC zijn — dan klopt dit niet en kun je de camera beschadigen. Controleer eerst je chip.
- Dit flasht het interne geheugen. Een fout kan de camera onbruikbaar maken (**brick-risico**).
  Maak eerst een **back-up van alle MTD-partities** en test alles eerst vanaf SD-kaart.
- Er zit **geen fabriekssoftware** in deze repo (`anyka_ipc`, firmware-images, kernelmodules zijn
  copyright van Anyka/Tuya en worden **niet** verspreid). Je patcht je **eigen** gedumpte binary.
- Zet **nooit** je `_ak39_factory.ini` (wifiwachtwoord), `config/`, `tuya_*.db` of flash-dumps online.
  Zie `.gitignore`.
- Werk je met een losse li-ion/li-po accu: let op de **veiligheid** (laadstroom, bescherming).

---

## Wat je nodig hebt

- De camera (Anyka AK3918AV130L — check met `cat /proc/cpuinfo` / de modules `ak_isp.ko` etc.).
- Een **FAT32 micro-SD-kaart** (de boot-hook en het herstel lopen hierover).
- **Root via telnet.** Dit project gaat ervan uit dat je al root hebt via de bekende
  community-SD-hack voor deze camera (boot-hook via `/mnt/hostapd` → `hack.sh`, plus
  `_ak39_factory.ini` die fabriekstest-modus aanzet → telnetd + RTSP). Login: `root` / `anyka`.
- Een **Linux-machine/server** met `squashfs-tools` (`mksquashfs`/`unsquashfs`) om de
  APP-partitie te herbouwen, en om go2rtc + de klok-sync te draaien.
- Een **5V-voeding van ≥ 2A** (zie *Brownout*).

---

## Hoe het werkt (stappen)

### 1. Root + volledige back-up
Krijg root (community-SD-hack) en dump **alle** MTD-partities naar de SD-kaart, zodat je altijd
terug kunt. Op de camera:
```sh
for i in 0 1 2 3 4 5 6 7; do dd if=/dev/mtdblock$i of=/tmp/sd/mtd$i.bin bs=4096; done
sync; cat /proc/mtd > /tmp/sd/mtd.txt; md5sum /tmp/sd/mtd*.bin > /tmp/sd/md5.txt
```
De APP-partitie (`/usr`, squashfs) heet meestal `mtd7` / `/dev/mtdblock7`.

### 2. Tuya eruit patchen — `patch/patch_notuya.py`
`main()` in `anyka_ipc` roept op volgorde aan: `ht_media_service_init` (video/audio) →
`ht_device_ctrl_init` (incl. de fabrieks-RTSP-server) → **`ht_tuya_service_start`** (de hele cloud).
De patch vervangt de `bl ht_tuya_service_start` (op deze firmware VA `0x10000+0xf0554`) door
`mov r0, #1` ("gestart, gelukt"). Video en RTSP blijven draaien; Tuya wordt nooit uitgevoerd.
**4 bytes gewijzigd, verder niets.**
```sh
python3 patch/patch_notuya.py anyka_ipc anyka_ipc.notuya
```
> Het call-adres is firmware-specifiek. Controleer met een disassembler (zie `tools/`) dat op
> die plek echt `bl ht_tuya_service_start` staat voordat je patcht — het script checkt dit.

### 3. APP-partitie herbouwen — `firmware/build.sh`
Pak de squashfs uit, leg de gepatchte binary erin, voeg de eigen scripts toe, pak weer in met
**precies dezelfde** compressie (xz, blok 128 KB). Draait op je Linux-box. Pas de md5's en
paden bovenin aan voor jouw dump. Resultaat: `usr_new.sqsh` (moet ≤ grootte van de partitie zijn).

### 4. Flashen — `firmware/flash.sh`
Schrijft `usr_new.sqsh` naar `/dev/mtdblock7`, **leest terug en vergelijkt de md5**, en herstart
alleen als die klopt. Gebruik alleen `/bin/busybox` (staat in ROOTFS, wordt niet overschreven).
```sh
sh flash.sh usr_new.sqsh <md5> <aantal_4k_blokken>
```
**Alternatief zonder flashen:** laat alles vanaf de SD-kaart draaien (zie *Herstel*). Veiliger om
mee te testen.

### 5. Lockdown — `firmware/lsc_lockdown.sh`
Draait bij het opstarten (via `service.sh`, vóór anyka_ipc). Elke 2 s, voor altijd:
- vast IP (`udhcpc` is kapot op deze camera: symlink-loop), geen DHCP-server, geen IPv6, lege `/etc/resolv.conf`;
- **default gateway = de camera zélf.** Nodig! anyka_ipc pingt de gateway; zonder antwoord
  verbreekt hij de wifi elke ~30 s. Met zichzelf als gateway slaagt die ping, maar internetverkeer
  kan nergens heen. Pas ná 90 s actief, want eerder verstoort het de eerste wifi-verbinding.

### 6. Statuslampje — `firmware/lsc_led.sh`
30 s snel knipperen bij opstarten; daarna 1 flits per 2 min mét netwerk, 2× kort zónder netwerk.
(De originele `state/red/blue_led.sh` worden uitgeschakeld zodat anyka_ipc het lampje niet overneemt.)

### 7. Klok — `server/camtime.py`
De camera heeft geen internet/NTP, dus je **server** zet de klok elke minuut gelijk via telnet.
Zomer-/wintertijd wordt geregeld in het formaat dat anyka_ipc zélf leest (`UTC-01:00` / `UTC-02:00`).

### 8. Live beeld — `server/go2rtc.yaml.example`
Draai [go2rtc](https://github.com/AlexxIT/go2rtc) op je server; kijk in de browser op
`http://<server>:1984/stream.html?src=camera`. Opnemen/bewegingsdetectie kan met go2rtc of Frigate.

---

## Herstel — `sd-recovery/`
Zet `hostapd` + `hack.sh` (+ je herbouwde `usr_new.sqsh` en `_ak39_factory.ini`) op de SD-kaart.
Bij elke boot controleert `hack.sh` de APP-partitie en **schrijft de bewezen goede image terug**
als het flash beschadigd is, met verificatie en herstart. Zit de camera in een slechte staat,
dan is "kaart erin, stroom erin" je redmiddel. Kaart eruit = terug naar normaal gedrag.

---

## Bekende valkuilen (met bloed, zweet en tranen gevonden)

- **Brownout bij dag/nacht-wissel.** Op het moment dat het IR-cut-filter omklapt + de IR-leds
  schakelen, is er een piekstroom. Een zwakke voeding (pc-USB, dunne kabel) zakt dan even in en de
  chip **reset**. Niet elke wissel, dus het lijkt willekeurig. **Fix: 5V-voeding ≥ 2A**, korte dikke
  kabel, en eventueel een **elco (~1000 µF) over de 5V** vlak bij de camera. Geen softwarefout.
- **Tijdzone-formaat.** `anyka_ipc` leest `/etc/config/TZ` zélf en snapt **alleen** `UTC±HH:MM`.
  Zet je daar een POSIX-TZ string in (`CET-1CEST,...`), dan loopt hij vast → geen wifi → reboots.
- **`udhcpc` kapot** (symlink-loop "Too many levels of symbolic links"): gebruik een **vast IP**.
- **Self-gateway nodig**, anders her-associeert de wifi elke ~30 s (zie stap 5).
- **SD-kaart soms niet gedetecteerd** bij koude start, vooral bij zwakke voeding → stevig
  herplaatsen, betere voeding. Zonder kaart draait `hack.sh` niet (hook zit in AP-modus-pad).
- **CRLF.** Alle shell-scripts moeten **LF** regeleindes hebben; draai ze door `tr -d '\r'` +
  `sh -n` voordat ze op de camera komen.

---

## Config
Voorbeeld-IP's in de scripts: camera `192.168.1.240`, router `192.168.1.1`. Pas aan naar je eigen
net in: `firmware/lsc_lockdown.sh`, `firmware/lsc_led.sh`, `sd-recovery/hack.sh`,
`server/camtime.py`, en de `tools/`. Wifi vul je in `_ak39_factory.ini` (zie `.example`).

## `tools/`
Reverse-engineering- en transporthulpjes (Python, `capstone` + `pyelftools`): `ra.py`/`names.py`
(ARM32-disassembly met symboolnamen uit `.dynsym`), `tn.py` (mini-telnetclient),
`push2.py`/`pull2.py` (bestanden via telnet+base64 van/naar de camera).

## Credits
- De Anyka/LSC community voor de oorspronkelijke SD-boot-hack en root-methode.
- [go2rtc](https://github.com/AlexxIT/go2rtc) voor de streaming.

## Licentie
MIT (alleen de scripts in deze repo). Fabriekssoftware valt hier niet onder en zit er niet in.
