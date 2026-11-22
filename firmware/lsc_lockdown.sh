#!/bin/sh
# Custom firmware addition (replaces hack.sh from the SD card).
# Started by service.sh, before anyka_ipc. Tuya itself is already patched out of /usr/bin/anyka_ipc.
IP=192.168.1.240
MASK=255.255.255.0
L=/tmp/lsc.log
echo "== lsc_lockdown start: $(date)" > $L

# root password 'anyka' (service.sh wipes /etc/config/shadow on every boot)
cp /usr/local/lsc_shadow /etc/config/shadow 2>>$L

# telnet, for management from your own network
( sleep 15; pidof telnetd >/dev/null || telnetd >> $L 2>&1 ) &

# no DNS
: > /etc/resolv.conf

# Timezone: anyka_ipc reads /etc/config/TZ ITSELF and only understands "UTC-01:00" (UTC%c%02d:%02d).
# Anything else (e.g. CET-1CEST,...) makes it hang. DST is set by the server (UTC-02:00).
case "$(cat /etc/config/TZ 2>/dev/null)" in UTC[-+][0-9][0-9]:[0-9][0-9]) ;; *) echo "UTC-01:00" > /etc/config/TZ ;; esac

# WATCHER, forever, every 2s: static IP, gateway to itself, no IPv6, no DHCP server
( n=0
  while true; do
    sleep 2; n=$((n+1))
    killall udhcpd 2>/dev/null
    for f in /proc/sys/net/ipv6/conf/*/disable_ipv6; do [ -f "$f" ] && echo 1 > "$f"; done
    ifconfig wlan0 2>/dev/null | grep -q "inet addr:$IP" || ifconfig wlan0 $IP netmask $MASK up 2>/dev/null
    # Gateway = the camera itself. anyka_ipc pings the gateway; without a reply it re-associates
    # the wifi every ~30s. This way that ping succeeds, but internet traffic has nowhere to go.
    # Only after 90s: active from the start it disturbs anyka_ipc's first association (tested).
    UP=$(cut -d. -f1 /proc/uptime)
    if [ "$UP" -lt 90 ]; then
      while route del default 2>/dev/null; do :; done
    elif [ "$(route -n | grep -c '^0\.0\.0\.0')" != 1 ] || ! route -n | grep '^0\.0\.0\.0' | grep -q " $IP "; then
      while route del default 2>/dev/null; do :; done
      route add default gw $IP 2>/dev/null
    fi
    : > /etc/resolv.conf 2>/dev/null
    if [ $((n % 15)) -eq 0 ] && [ $n -le 90 ]; then
      { echo "== check $n: anyka_ipc pid $(pidof anyka_ipc)"; route -n | tail -n +3
        ping -c1 -W2 8.8.8.8 >/dev/null 2>&1 && echo "   !! INTERNET REACHABLE" || echo "   internet blocked (good)"; } >> $L 2>&1
    fi
  done ) &
