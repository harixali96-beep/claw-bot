#!/usr/bin/env bash
# Runs the bot inside GitHub Actions (no card, no phone verification needed).
set -u
export HOME="${HOME:-$PWD}"
BUNDLE="https://base44.app/api/apps/6afd5d7f94aa00438e512b21/files/mp/public/6afd5d7f94aa00438e512b21/558b84d84_openclaw-vm-bundletar.gz"

echo "[bot] fetching config + skills"
mkdir -p "$HOME/.openclaw"
curl -fsSL "$BUNDLE" -o /tmp/b.tgz && tar -xzf /tmp/b.tgz -C /tmp
cp -rf /tmp/oc/. "$HOME/.openclaw/"
mkdir -p /tmp/freellmapi/server/data
cp -f /tmp/freellm/freeapi.db* /tmp/freellmapi/server/data/ 2>/dev/null || true

python3 - "$HOME/.openclaw/openclaw.json" <<'PY'
import json, os, sys
p = sys.argv[1]
tok = os.environ.get("TELEGRAM_BOT_TOKEN", "").strip()
c = json.load(open(p))
tg = c.setdefault("channels", {}).setdefault("telegram", {})
if tok:
    tg["botToken"] = tok
tg["enabled"] = True
json.dump(c, open(p, "w"), indent=2)
print("[bot] token set:", bool(tok))
PY

echo "[bot] starting router"
( cd /tmp/freellmapi/server && PORT=3001 HOST=127.0.0.1 nohup node dist/index.js >/tmp/freellm.log 2>&1 & )
sleep 10
echo "[bot] starting gateway"
( nohup openclaw gateway run >/tmp/oc-gateway.log 2>&1 & )

# keep alive until the job's own timeout kills the runner
for i in $(seq 1 340); do
  pgrep -f "node dist/index.js" >/dev/null 2>&1 || ( cd /tmp/freellmapi/server && PORT=3001 HOST=127.0.0.1 nohup node dist/index.js >>/tmp/freellm.log 2>&1 & )
  pgrep -f "openclaw gateway run" >/dev/null 2>&1 || ( nohup openclaw gateway run >>/tmp/oc-gateway.log 2>&1 & )
  if [ $((i % 10)) -eq 0 ]; then
    echo "[bot] alive $((i/2)) min | router:$(curl -s -m 4 -o /dev/null -w '%{http_code}' localhost:3001/api/auth/status) telegram:$(grep -c . /tmp/oc-gateway.log 2>/dev/null)"
  fi
  sleep 60
done
echo "[bot] run window finished"
