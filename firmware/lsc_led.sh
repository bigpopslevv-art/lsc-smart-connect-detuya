#!/bin/sh
# Status LED:
#  - first 30s after boot: blink very fast
#  - then WITH network (router 192.168.1.1 replies): 1 short flash every 2 minutes
#  - then WITHOUT network: 2 short blinks, wait ~10s
# anyka_ipc can no longer drive the LED (state/red/blue_led.sh are disabled).
L=/sys/class/leds/state_led
ROUTER=192.168.1.1
[ -d $L ] || exit 0
on()  { echo 1 > $L/brightness; }
off() { echo 0 > $L/brightness; }
blip() { on; usleep 150000 2>/dev/null || sleep 1; off; }

echo timer > $L/trigger
echo 50 > $L/delay_on
echo 50 > $L/delay_off          # 10x per second
sleep 30
echo none > $L/trigger
off
n=0
while true; do
  if ping -c1 -W1 $ROUTER >/dev/null 2>&1; then
    [ $((n % 12)) -eq 0 ] && { on; usleep 300000 2>/dev/null || sleep 1; off; }   # every ~2 min
    n=$((n+1))
  else
    blip; usleep 250000 2>/dev/null || sleep 1; blip
    n=0                                    # flash immediately once the network is back
  fi
  sleep 10
done
