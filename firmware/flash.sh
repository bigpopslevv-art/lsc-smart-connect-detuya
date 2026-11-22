#!/bin/sh
# Writes a new APP partition. Only /bin/busybox (ROOTFS, which is not overwritten).
# Reboots only if the read-back md5 matches.  Usage: flash.sh IMAGE MD5 BLOCKS_OF_4K
trap '' HUP INT TERM
B=/bin/busybox
IMG=$1; WANT=$2; BLOCKS=$3
echo "== flash start: $IMG"
[ -n "$BLOCKS" ] && [ "$($B md5sum $IMG | $B cut -d' ' -f1)" = "$WANT" ] || { echo "image md5 WRONG, stop"; exit 1; }
$B killall -12 watchdog; $B sleep 1     # like the vendor's update_tmp.sh
$B killall -9 anyka_ipc; $B sleep 1
$B sync
echo "writing..."
$B dd if=$IMG of=/dev/mtdblock7 bs=4096 conv=fsync
$B sync
echo 3 > /proc/sys/vm/drop_caches
GOT=$($B dd if=/dev/mtdblock7 bs=4096 count=$BLOCKS 2>/dev/null | $B md5sum | $B cut -d' ' -f1)
echo "read back: $GOT"
if [ "$GOT" = "$WANT" ]; then
  echo "== FLASH OK, reboot"; $B sync; $B sleep 2; $B reboot -f
else
  echo "== FLASH VERIFY FAILED - not rebooting, try again"
fi
