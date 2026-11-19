#!/usr/bin/env bash
# Render entrypoint: keep the gateway alive and supervised.
set -u
export HOME=/root
cd /root || exit 1
setsid bash /root/run-all.sh > /root/supervisor.log 2>&1 < /dev/null &
sleep 25
while true; do
  openclaw gateway run --force > /root/gwR.log 2>&1
  echo "[render] gateway exited, restarting in 10s"
  sleep 10
done
