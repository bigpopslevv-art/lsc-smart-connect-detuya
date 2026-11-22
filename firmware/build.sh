#!/bin/sh
# Builds the modified APP partition (usr.sqsh) from mtd7_orig.bin. Runs on the server in ~/camfw.
set -e
cd ~/camfw
[ "$(md5sum mtd7_orig.bin | cut -d' ' -f1)" = 45f7b0ea5a8a92bc2defe9c1e4769a2a ] || { echo "original does not match"; exit 1; }
rm -rf usr && unsquashfs -q -no-xattrs -d usr mtd7_orig.bin >/dev/null
U=usr

# 1) Tuya out: patched anyka_ipc (4 bytes, main skips ht_tuya_service_start)
[ "$(md5sum $U/bin/anyka_ipc | cut -d' ' -f1)" = 92b653912e9c6c8819d040bdee2f13fd ]
cp in/anyka_ipc.notuya $U/bin/anyka_ipc
[ "$(md5sum $U/bin/anyka_ipc | cut -d' ' -f1)" = cc62d95c11849174eb0ccad95633d65f ]
chmod 755 $U/bin/anyka_ipc

# 2) custom scripts + root password
cp in/lsc_lockdown.sh in/lsc_led.sh $U/sbin/ && chmod 755 $U/sbin/lsc_lockdown.sh $U/sbin/lsc_led.sh
cp in/lsc_shadow $U/local/lsc_shadow && chmod 644 $U/local/lsc_shadow

# 3) service.sh: without SD, take the factory ini (wifi + static IP -> RTSP) from flash; start lockdown
F=$U/sbin/service.sh
grep -q 'dd if="/mnt/${FACTORY_MODE_FILE}" of="/tmp/${FACTORY_MODE_FILE}" bs=1024 count=1' $F
sed -i '/dd if="\/mnt\/${FACTORY_MODE_FILE}" of="\/tmp\/${FACTORY_MODE_FILE}" bs=1024 count=1/a\
        [ -s "/tmp/${FACTORY_MODE_FILE}" ] || cp /etc/config/lsc_factory.ini "/tmp/${FACTORY_MODE_FILE}" 2>/dev/null' $F
grep -q 'echo "start service......"' $F
sed -i '/echo "start service......"/a\
        /usr/sbin/lsc_lockdown.sh' $F
[ "$(grep -c 'lsc_factory.ini\|lsc_lockdown.sh' $F)" = 2 ]

# 4) main.sh: LED from the first seconds
F=$U/sbin/main.sh
grep -q '^sh /usr/sbin/red_led.sh on' $F
sed -i '/^sh \/usr\/sbin\/red_led.sh on/a\
sh /usr/sbin/lsc_led.sh &' $F
[ "$(grep -c 'lsc_led.sh' $F)" = 1 ]

# 5) anyka_ipc must not drive the LED anymore; factory mode must not restore the config
for f in state_led red_led blue_led; do
  mv $U/sbin/$f.sh $U/sbin/$f.sh.orig
  printf '#!/bin/sh\n# disabled: the LED is handled by lsc_led.sh (original: %s.sh.orig)\nexit 0\n' $f > $U/sbin/$f.sh
  chmod 755 $U/sbin/$f.sh
done
mv $U/sbin/recover_cfg.sh $U/sbin/recover_cfg.sh.orig
printf '#!/bin/sh\n# disabled (original: recover_cfg.sh.orig)\nexit 0\n' > $U/sbin/recover_cfg.sh && chmod 755 $U/sbin/recover_cfg.sh

# 6) syntax-check all modified scripts
for f in service.sh main.sh lsc_lockdown.sh lsc_led.sh state_led.sh red_led.sh blue_led.sh recover_cfg.sh; do sh -n $U/sbin/$f; done

# 7) repack with the same settings as the original
rm -f usr_new.sqsh
mksquashfs usr usr_new.sqsh -comp xz -b 131072 -noappend -no-xattrs -all-time 1774069031 -quiet >/dev/null
SZ=$(stat -c %s usr_new.sqsh)
[ $SZ -le 5242880 ] || { echo "TOO BIG: $SZ"; exit 1; }
unsquashfs -s usr_new.sqsh | grep -E 'Compression|Block size|Filesystem size'
echo "size $SZ of 5242880 (free $((5242880-SZ)))"
md5sum usr_new.sqsh
