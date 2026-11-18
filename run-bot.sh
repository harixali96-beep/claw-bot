#!/usr/bin/env bash
# Runs the bot inside GitHub Actions (free unlimited minutes on a public repo).
# 6-hour windows, auto-restart by cron. Notes survive restarts through job.md in the repo.
set -u
export HOME="${HOME:-$PWD}"
BUNDLE="https://base44.app/api/apps/6afd5d7f94aa00438e512b21/files/mp/public/6afd5d7f94aa00438e512b21/558b84d84_openclaw-vm-bundletar.gz"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "[bot] fetching config + skills"
mkdir -p "$HOME/.openclaw/workspace"
curl -fsSL "$BUNDLE" -o /tmp/b.tgz && tar -xzf /tmp/b.tgz -C /tmp
cp -rf /tmp/oc/. "$HOME/.openclaw/"
mkdir -p /tmp/freellmapi/server/data
cp -f /tmp/freellm/freeapi.db* /tmp/freellmapi/server/data/ 2>/dev/null || true

# carry over notes from the previous window
[ -f "$REPO_DIR/job.md" ] && cp -f "$REPO_DIR/job.md" "$HOME/.openclaw/workspace/job.md"

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

save_notes() {
  local src="$HOME/.openclaw/workspace/job.md"
  [ -f "$src" ] || return 0
  cp -f "$src" "$REPO_DIR/job.md" 2>/dev/null || return 0
  cd "$REPO_DIR" || return 0
  git config user.name "claw-bot" >/dev/null 2>&1
  git config user.email "bot@users.noreply.github.com" >/dev/null 2>&1
  if ! git diff --quiet -- job.md 2>/dev/null; then
    git add job.md >/dev/null 2>&1
    git commit -m "bot notes [skip ci]" >/dev/null 2>&1
    git push >/dev/null 2>&1 || echo "[bot] note push failed"
  fi
}

echo "[bot] starting router"
( cd /tmp/freellmapi/server && PORT=3001 HOST=127.0.0.1 nohup node dist/index.js >/tmp/freellm.log 2>&1 & )
sleep 10
echo "[bot] starting gateway"
nohup openclaw gateway run >/tmp/oc-gateway.log 2>&1 &
GW_PID=$!
sleep 25
if ! kill -0 "$GW_PID" 2>/dev/null; then
  echo "[bot] gateway exited, retrying once"
  nohup openclaw gateway run --verbose >/tmp/oc-gateway2.log 2>&1 &
  GW_PID=$!
  sleep 25
fi
echo "[bot] gateway pid=$GW_PID alive=$(kill -0 "$GW_PID" 2>/dev/null && echo yes || echo no)"
curl -s -m 10 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" -d chat_id=7473905437 -d text="bot online (github actions)" >/dev/null 2>&1 || true

write_status() {
  local out="$REPO_DIR/status.txt"
  {
    echo "time: $(date -u +%FT%TZ)"
    echo "node: $(node -v 2>/dev/null)"
    echo "openclaw: $(command -v openclaw) $(openclaw --version 2>/dev/null | head -1)"
    echo "router: $(curl -s -m 4 -o /dev/null -w '%{http_code}' localhost:3001/api/auth/status)"
    echo "gateway proc: $(pgrep -fc 'openclaw gateway run' 2>/dev/null || echo 0)"
    echo "gateway port: $(curl -s -m 4 -o /dev/null -w '%{http_code}' http://127.0.0.1:18789/ 2>/dev/null)"
    echo "--- channels ---"
    timeout 25 openclaw channels status 2>&1 | grep -i -A1 telegram | head -6 || echo "channels status timeout"
    echo "--- gateway log tail ---"
    tail -25 /tmp/oc-gateway.log 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g'
  } > "$out" 2>&1
  cd "$REPO_DIR" || return 0
  git config user.name "claw-bot" >/dev/null 2>&1
  git config user.email "bot@users.noreply.github.com" >/dev/null 2>&1
  git add status.txt gw.log gw2.log >/dev/null 2>&1
  git commit -m "bot status [skip ci]" >/dev/null 2>&1 && git push >/dev/null 2>&1
}
write_status

for i in $(seq 1 340); do
  pgrep -f "node dist/index.js" >/dev/null 2>&1 || ( cd /tmp/freellmapi/server && PORT=3001 HOST=127.0.0.1 nohup node dist/index.js >>/tmp/freellm.log 2>&1 & )
  pgrep -f "openclaw gateway run" >/dev/null 2>&1 || ( nohup openclaw gateway run >>/tmp/oc-gateway.log 2>&1 & )
  if [ $((i % 20)) -eq 0 ]; then
    echo "[bot] alive $((i)) min | router:$(curl -s -m 4 -o /dev/null -w '%{http_code}' localhost:3001/api/auth/status)"
    save_notes
    write_status
  fi
  sleep 60
done
save_notes
echo "[bot] window finished"
