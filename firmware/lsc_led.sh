#!/bin/sh
# Statuslampje:
#  - eerste 30s na opstart: heel snel knipperen
#  - daarna MET netwerk (router 192.168.1.1 antwoordt): elke 2 minuten 1 korte flits
#  - daarna ZONDER netwerk: 2x kort knipperen, ~10s wachten
# anyka_ipc kan het lampje niet meer aansturen (state/red/blue_led.sh zijn uitgeschakeld).
L=/sys/class/leds/state_led
ROUTER=192.168.1.1
[ -d $L ] || exit 0
on()  { echo 1 > $L/brightness; }
off() { echo 0 > $L/brightness; }
kort() { on; usleep 150000 2>/dev/null || sleep 1; off; }

echo timer > $L/trigger
echo 50 > $L/delay_on
echo 50 > $L/delay_off          # 10x per seconde
sleep 30
echo none > $L/trigger
off
n=0
while true; do
  if ping -c1 -W1 $ROUTER >/dev/null 2>&1; then
    [ $((n % 12)) -eq 0 ] && { on; usleep 300000 2>/dev/null || sleep 1; off; }   # elke ~2 min
    n=$((n+1))
  else
    kort; usleep 250000 2>/dev/null || sleep 1; kort
    n=0                                    # meteen flitsen zodra het netwerk terug is
  fi
  sleep 10
done
