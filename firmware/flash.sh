#!/bin/sh
# Schrijft een nieuwe APP-partitie. Alleen /bin/busybox (ROOTFS, wordt niet overschreven).
# Herstart alleen als de teruggelezen md5 klopt.  Gebruik: flash.sh IMAGE MD5 BLOKKEN_VAN_4K
trap '' HUP INT TERM
B=/bin/busybox
IMG=$1; WANT=$2; BLOCKS=$3
echo "== flash start: $IMG"
[ -n "$BLOCKS" ] && [ "$($B md5sum $IMG | $B cut -d' ' -f1)" = "$WANT" ] || { echo "image md5 FOUT, stop"; exit 1; }
$B killall -12 watchdog; $B sleep 1     # zoals update_tmp.sh van de fabrikant
$B killall -9 anyka_ipc; $B sleep 1
$B sync
echo "schrijven..."
$B dd if=$IMG of=/dev/mtdblock7 bs=4096 conv=fsync
$B sync
echo 3 > /proc/sys/vm/drop_caches
GOT=$($B dd if=/dev/mtdblock7 bs=4096 count=$BLOCKS 2>/dev/null | $B md5sum | $B cut -d' ' -f1)
echo "teruggelezen: $GOT"
if [ "$GOT" = "$WANT" ]; then
  echo "== FLASH OK, herstart"; $B sync; $B sleep 2; $B reboot -f
else
  echo "== FLASH VERIFY FOUT - niet herstarten, opnieuw proberen"
fi
