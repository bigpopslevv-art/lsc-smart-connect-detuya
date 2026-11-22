#!/bin/sh
# RECOVERY hack.sh. Runs via /mnt/hostapd in the FOREGROUND: boot waits for it,
# so watchdog and anyka_ipc are not running yet. Use only /bin/busybox (ROOTFS).
# If the APP partition is not the known-good v1: write v1 back, verify, reboot.
B=/bin/busybox
SD=/tmp/sd
$B mkdir -p $SD
$B mount /dev/mmcblk0p1 $SD 2>/dev/null || $B mount /dev/mmcblk0 $SD 2>/dev/null
L=$SD/diag.txt
IMG=$SD/usr_new.sqsh
WANT=3db32626d02accaf3a90f5b1d3b593dd     # v1, known good
BLOCKS=1158
log() { echo "$*" >> $L; $B sync; }

log "== recovery hack.sh: uptime $($B cut -d' ' -f1 /proc/uptime)"
echo "UTC-01:00" > /etc/config/TZ
CUR=$($B dd if=/dev/mtdblock7 bs=4096 count=$BLOCKS 2>/dev/null | $B md5sum | $B cut -d' ' -f1)
log "APP now: $CUR"

if [ "$CUR" != "$WANT" ]; then
  if [ "$($B md5sum $IMG | $B cut -d' ' -f1)" != "$WANT" ]; then log "image on SD does not match, NOT flashing"; exit 0; fi
  $B cp $IMG /tmp/app.img
  for attempt in 1 2; do
    log "flash attempt $attempt..."
    $B dd if=/tmp/app.img of=/dev/mtdblock7 bs=4096 conv=fsync 2>>$L
    $B sync; echo 3 > /proc/sys/vm/drop_caches
    GOT=$($B dd if=/dev/mtdblock7 bs=4096 count=$BLOCKS 2>/dev/null | $B md5sum | $B cut -d' ' -f1)
    log "read back: $GOT"
    if [ "$GOT" = "$WANT" ]; then log "== RECOVERY OK, reboot"; $B sleep 2; $B reboot -f; fi
  done
  log "== RECOVERY FAILED after 2 attempts"
  exit 0
fi

# APP is good (v1): use the corrected lockdown (own gateway) from the card
log "APP is v1 (good)"
[ -f $SD/lsc_lockdown.sh ] && $B mount --bind $SD/lsc_lockdown.sh /usr/sbin/lsc_lockdown.sh && log "lsc_lockdown.sh from SD active"
# new LED script from the card: stop the old one (already started by main.sh)
if [ -f $SD/lsc_led.sh ]; then
  for p in $($B pidof sh); do $B grep -q lsc_led /proc/$p/cmdline 2>/dev/null && $B kill $p; done
  $B mount --bind $SD/lsc_led.sh /usr/sbin/lsc_led.sh && ( sh /usr/sbin/lsc_led.sh </dev/null >/dev/null 2>&1 & ) && log "lsc_led.sh from SD active"
fi
( $B sleep 25; $B pidof telnetd >/dev/null || telnetd ) &
( for t in 45 90 150 240; do
    while [ "$($B cut -d. -f1 /proc/uptime)" -lt $t ]; do $B sleep 2; done
    { echo "== after ${t}s: anyka=$($B pidof anyka_ipc) wpa=$($B pidof wpa_supplicant) telnetd=$($B pidof telnetd)"
      ifconfig wlan0 | $B grep -E 'inet addr|RUNNING'
      iwconfig wlan0 2>/dev/null | $B grep -E 'ESSID|Access Point|Signal'
      route -n | $B tail -n +3
      ping -c1 -W1 192.168.1.1 >/dev/null 2>&1 && echo "   router: reachable" || echo "   router: NOT reachable"
      $B tail -n 4 /var/log/messages; } >> $L 2>&1
    $B sync
  done ) &
