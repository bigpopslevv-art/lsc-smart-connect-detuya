#!/bin/sh
# Bouwt de aangepaste APP-partitie (usr.sqsh) uit mtd7_orig.bin. Draait op de server in ~/camfw.
set -e
cd ~/camfw
[ "$(md5sum mtd7_orig.bin | cut -d' ' -f1)" = 45f7b0ea5a8a92bc2defe9c1e4769a2a ] || { echo "origineel klopt niet"; exit 1; }
rm -rf usr && unsquashfs -q -no-xattrs -d usr mtd7_orig.bin >/dev/null
U=usr

# 1) Tuya eruit: gepatchte anyka_ipc (4 bytes, main slaat ht_tuya_service_start over)
[ "$(md5sum $U/bin/anyka_ipc | cut -d' ' -f1)" = 92b653912e9c6c8819d040bdee2f13fd ]
cp in/anyka_ipc.notuya $U/bin/anyka_ipc
[ "$(md5sum $U/bin/anyka_ipc | cut -d' ' -f1)" = cc62d95c11849174eb0ccad95633d65f ]
chmod 755 $U/bin/anyka_ipc

# 2) eigen scripts + root-wachtwoord
cp in/lsc_lockdown.sh in/lsc_led.sh $U/sbin/ && chmod 755 $U/sbin/lsc_lockdown.sh $U/sbin/lsc_led.sh
cp in/lsc_shadow $U/local/lsc_shadow && chmod 644 $U/local/lsc_shadow

# 3) service.sh: zonder SD de fabrieks-ini (wifi + vast IP -> RTSP) uit flash halen; lockdown starten
F=$U/sbin/service.sh
grep -q 'dd if="/mnt/${FACTORY_MODE_FILE}" of="/tmp/${FACTORY_MODE_FILE}" bs=1024 count=1' $F
sed -i '/dd if="\/mnt\/${FACTORY_MODE_FILE}" of="\/tmp\/${FACTORY_MODE_FILE}" bs=1024 count=1/a\
        [ -s "/tmp/${FACTORY_MODE_FILE}" ] || cp /etc/config/lsc_factory.ini "/tmp/${FACTORY_MODE_FILE}" 2>/dev/null' $F
grep -q 'echo "start service......"' $F
sed -i '/echo "start service......"/a\
        /usr/sbin/lsc_lockdown.sh' $F
[ "$(grep -c 'lsc_factory.ini\|lsc_lockdown.sh' $F)" = 2 ]

# 4) main.sh: lampje vanaf de eerste seconden
F=$U/sbin/main.sh
grep -q '^sh /usr/sbin/red_led.sh on' $F
sed -i '/^sh \/usr\/sbin\/red_led.sh on/a\
sh /usr/sbin/lsc_led.sh &' $F
[ "$(grep -c 'lsc_led.sh' $F)" = 1 ]

# 5) anyka_ipc mag het lampje niet meer aansturen; fabrieksmodus mag config niet terugzetten
for f in state_led red_led blue_led; do
  mv $U/sbin/$f.sh $U/sbin/$f.sh.orig
  printf '#!/bin/sh\n# uitgeschakeld: lampje wordt geregeld door lsc_led.sh (origineel: %s.sh.orig)\nexit 0\n' $f > $U/sbin/$f.sh
  chmod 755 $U/sbin/$f.sh
done
mv $U/sbin/recover_cfg.sh $U/sbin/recover_cfg.sh.orig
printf '#!/bin/sh\n# uitgeschakeld (origineel: recover_cfg.sh.orig)\nexit 0\n' > $U/sbin/recover_cfg.sh && chmod 755 $U/sbin/recover_cfg.sh

# 6) syntaxcheck van alle gewijzigde scripts
for f in service.sh main.sh lsc_lockdown.sh lsc_led.sh state_led.sh red_led.sh blue_led.sh recover_cfg.sh; do sh -n $U/sbin/$f; done

# 7) inpakken met dezelfde instellingen als het origineel
rm -f usr_new.sqsh
mksquashfs usr usr_new.sqsh -comp xz -b 131072 -noappend -no-xattrs -all-time 1774069031 -quiet >/dev/null
SZ=$(stat -c %s usr_new.sqsh)
[ $SZ -le 5242880 ] || { echo "TE GROOT: $SZ"; exit 1; }
unsquashfs -s usr_new.sqsh | grep -E 'Compression|Block size|Filesystem size'
echo "grootte $SZ van 5242880 (vrij $((5242880-SZ)))"
md5sum usr_new.sqsh
