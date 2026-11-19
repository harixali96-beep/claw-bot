#!/usr/bin/env bash
# Render entrypoint for the Void Clipex bot.
set -u
export HOME="${HOME:-/opt/claw}"
mkdir -p "$HOME"
BUNDLE="https://base44.app/api/apps/6afd5d7f94aa00438e512b21/files/mp/public/6afd5d7f94aa00438e512b21/a57c5e21a_openclaw-vm-bundletar.gz"

echo "[render] fetching bundle"
curl -fsSL "$BUNDLE" -o /tmp/b.tgz || echo "[render] bundle download failed"
tar -xzf /tmp/b.tgz -C /tmp 2>/dev/null || true
cp -rf /tmp/oc/. "$HOME/.openclaw/" 2>/dev/null || true

ROUTER_DIR=""
for d in /opt/claw/freellmapi/server /root/freellmapi/server "$HOME/freellmapi/server"; do
  if [ -d "$d" ]; then ROUTER_DIR="$d"; break; fi
done
if [ -n "$ROUTER_DIR" ] && [ -d /tmp/freellm ]; then
  mkdir -p "$ROUTER_DIR/data"
  cp -f /tmp/freellm/freeapi.db* "$ROUTER_DIR/data/" 2>/dev/null || true
fi

python3 - "$HOME/.openclaw/openclaw.json" <<'PY'
import json, os, sys
p = sys.argv[1]
try:
    c = json.load(open(p))
except Exception:
    sys.exit(0)
tok = os.environ.get("TELEGRAM_BOT_TOKEN", "")
if tok:
    c.setdefault("channels", {}).setdefault("telegram", {})["botToken"] = tok
json.dump(c, open(p, "w"), indent=2)
print("[render] token set:", bool(tok))
PY

( cd /tmp && nohup python3 -m http.server "${PORT:-8080}" --bind 0.0.0.0 > /tmp/httpd.log 2>&1 & )
echo "[render] health on :${PORT:-8080}"

if [ -n "$ROUTER_DIR" ]; then
  ( cd "$ROUTER_DIR" && nohup node dist/index.js > /tmp/router.log 2>&1 & )
  echo "[render] router starting in $ROUTER_DIR"
fi

sleep 15
while true; do
  echo "[render] gateway start $(date -u +%H:%M:%S)"
  openclaw gateway run --force >> /tmp/gw.log 2>&1
  echo "[render] gateway exited, restart in 8s"
  sleep 8
done
