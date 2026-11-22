#!/bin/sh
# HERSTEL-hack.sh. Draait via /mnt/hostapd in de VOORGROND: het opstarten wacht hierop,
# dus watchdog en anyka_ipc draaien nog niet. Alleen /bin/busybox (ROOTFS) gebruiken.
# Als de APP-partitie niet de bewezen goede v1 is: v1 terugschrijven, controleren, herstarten.
B=/bin/busybox
SD=/tmp/sd
$B mkdir -p $SD
$B mount /dev/mmcblk0p1 $SD 2>/dev/null || $B mount /dev/mmcblk0 $SD 2>/dev/null
L=$SD/diag.txt
IMG=$SD/usr_new.sqsh
WANT=3db32626d02accaf3a90f5b1d3b593dd     # v1, bewezen goed
BLOCKS=1158
log() { echo "$*" >> $L; $B sync; }

log "== herstel-hack.sh: uptime $($B cut -d' ' -f1 /proc/uptime)"
echo "UTC-01:00" > /etc/config/TZ
CUR=$($B dd if=/dev/mtdblock7 bs=4096 count=$BLOCKS 2>/dev/null | $B md5sum | $B cut -d' ' -f1)
log "APP nu: $CUR"

if [ "$CUR" != "$WANT" ]; then
  if [ "$($B md5sum $IMG | $B cut -d' ' -f1)" != "$WANT" ]; then log "image op SD klopt niet, NIET flashen"; exit 0; fi
  $B cp $IMG /tmp/app.img
  for poging in 1 2; do
    log "flash poging $poging..."
    $B dd if=/tmp/app.img of=/dev/mtdblock7 bs=4096 conv=fsync 2>>$L
    $B sync; echo 3 > /proc/sys/vm/drop_caches
    GOT=$($B dd if=/dev/mtdblock7 bs=4096 count=$BLOCKS 2>/dev/null | $B md5sum | $B cut -d' ' -f1)
    log "teruggelezen: $GOT"
    if [ "$GOT" = "$WANT" ]; then log "== HERSTEL OK, herstart"; $B sleep 2; $B reboot -f; fi
  done
  log "== HERSTEL MISLUKT na 2 pogingen"
  exit 0
fi

# APP is goed (v1): gecorrigeerde lockdown (eigen gateway) van de kaart gebruiken
log "APP is v1 (goed)"
[ -f $SD/lsc_lockdown.sh ] && $B mount --bind $SD/lsc_lockdown.sh /usr/sbin/lsc_lockdown.sh && log "lsc_lockdown.sh van SD actief"
# nieuw lampje van de kaart: oude (al gestart door main.sh) stoppen
if [ -f $SD/lsc_led.sh ]; then
  for p in $($B pidof sh); do $B grep -q lsc_led /proc/$p/cmdline 2>/dev/null && $B kill $p; done
  $B mount --bind $SD/lsc_led.sh /usr/sbin/lsc_led.sh && ( sh /usr/sbin/lsc_led.sh </dev/null >/dev/null 2>&1 & ) && log "lsc_led.sh van SD actief"
fi
( $B sleep 25; $B pidof telnetd >/dev/null || telnetd ) &
( for t in 45 90 150 240; do
    while [ "$($B cut -d. -f1 /proc/uptime)" -lt $t ]; do $B sleep 2; done
    { echo "== na ${t}s: anyka=$($B pidof anyka_ipc) wpa=$($B pidof wpa_supplicant) telnetd=$($B pidof telnetd)"
      ifconfig wlan0 | $B grep -E 'inet addr|RUNNING'
      iwconfig wlan0 2>/dev/null | $B grep -E 'ESSID|Access Point|Signal'
      route -n | $B tail -n +3
      ping -c1 -W1 192.168.1.1 >/dev/null 2>&1 && echo "   router: bereikbaar" || echo "   router: NIET bereikbaar"
      $B tail -n 4 /var/log/messages; } >> $L 2>&1
    $B sync
  done ) &
