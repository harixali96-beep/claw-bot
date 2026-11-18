#!/usr/bin/env bash
# Entrypoint for OpenShift / Render / any container host (works with random UID).
# Needs env TELEGRAM_BOT_TOKEN.
set -u
export HOME="${HOME:-/opt/claw}"
BUNDLE="https://base44.app/api/apps/6afd5d7f94aa00438e512b21/files/mp/public/6afd5d7f94aa00438e512b21/09c906831_openclaw-vm-bundletar.gz"
DATA="/opt/claw/freellmapi/server/data"

mkdir -p "$HOME/.openclaw" "$DATA" 2>/dev/null || true

echo "[boot] fetching bot bundle"
curl -fsSL "$BUNDLE" -o /tmp/b.tgz && tar -xzf /tmp/b.tgz -C /tmp || echo "[boot] bundle failed"
cp -rf /tmp/oc/. "$HOME/.openclaw/" 2>/dev/null || true
cp -f /tmp/freellm/freeapi.db* "$DATA"/ 2>/dev/null || true

python3 - "$HOME/.openclaw/openclaw.json" <<'PY'
import json, os, sys
p = sys.argv[1]
tok = os.environ.get('TELEGRAM_BOT_TOKEN', '').strip()
if not os.path.exists(p):
    print('[boot] no config yet'); raise SystemExit
c = json.load(open(p))
tg = c.setdefault('channels', {}).setdefault('telegram', {})
if tok:
    tg['botToken'] = tok
tg['enabled'] = True
json.dump(c, open(p, 'w'), indent=2)
print('[boot] token set:', bool(tok))
PY

echo "[boot] starting model router"
( cd /opt/claw/freellmapi/server && PORT=3001 HOST=127.0.0.1 nohup node dist/index.js >/tmp/freellm.log 2>&1 & )
sleep 10
echo "[boot] starting gateway"
( nohup openclaw gateway run >/tmp/oc-gateway.log 2>&1 & )
sleep 25

while true; do
  pgrep -f "node dist/index.js" >/dev/null 2>&1 || ( cd /opt/claw/freellmapi/server && PORT=3001 HOST=127.0.0.1 nohup node dist/index.js >>/tmp/freellm.log 2>&1 & )
  pgrep -f "openclaw gateway run" >/dev/null 2>&1 || ( nohup openclaw gateway run >>/tmp/oc-gateway.log 2>&1 & )
  sleep 60
done
