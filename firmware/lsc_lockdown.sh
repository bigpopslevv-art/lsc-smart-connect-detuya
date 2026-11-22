#!/bin/sh
# Eigen firmware-toevoeging (vervangt hack.sh van de SD-kaart).
# Gestart door service.sh, vóór anyka_ipc. Tuya zelf is al weggepatcht in /usr/bin/anyka_ipc.
IP=192.168.1.240
MASK=255.255.255.0
L=/tmp/lsc.log
echo "== lsc_lockdown start: $(date)" > $L

# root-wachtwoord 'anyka' (service.sh wist /etc/config/shadow bij elke start)
cp /usr/local/lsc_shadow /etc/config/shadow 2>>$L

# telnet, voor beheer vanaf je eigen netwerk
( sleep 15; pidof telnetd >/dev/null || telnetd >> $L 2>&1 ) &

# geen DNS
: > /etc/resolv.conf

# Tijdzone: anyka_ipc leest /etc/config/TZ ZELF en snapt alleen "UTC-01:00" (UTC%c%02d:%02d).
# Iets anders (bv. CET-1CEST,...) laat hem vastlopen. Zomertijd zet de server (UTC-02:00).
case "$(cat /etc/config/TZ 2>/dev/null)" in UTC[-+][0-9][0-9]:[0-9][0-9]) ;; *) echo "UTC-01:00" > /etc/config/TZ ;; esac

# WACHTER, voor altijd, elke 2s: vast IP, gateway naar zichzelf, geen IPv6, geen DHCP-server
( n=0
  while true; do
    sleep 2; n=$((n+1))
    killall udhcpd 2>/dev/null
    for f in /proc/sys/net/ipv6/conf/*/disable_ipv6; do [ -f "$f" ] && echo 1 > "$f"; done
    ifconfig wlan0 2>/dev/null | grep -q "inet addr:$IP" || ifconfig wlan0 $IP netmask $MASK up 2>/dev/null
    # Gateway = de camera zelf. anyka_ipc pingt de gateway; zonder antwoord verbindt hij de
    # wifi elke ~30s opnieuw. Zo slaagt die ping, maar internetverkeer kan nergens heen.
    # Pas na 90s: vanaf de start actief verstoort het het verbinden van anyka_ipc (getest).
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
        ping -c1 -W2 8.8.8.8 >/dev/null 2>&1 && echo "   !! INTERNET BEREIKBAAR" || echo "   internet dicht (goed)"; } >> $L 2>&1
    fi
  done ) &
