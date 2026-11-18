#!/usr/bin/env bash
# GitHub Actions runner for the Void Clipex bot.
set -u
export HOME="${HOME:-$PWD}"
BUNDLE="https://base44.app/api/apps/6afd5d7f94aa00438e512b21/files/mp/public/6afd5d7f94aa00438e512b21/09c906831_openclaw-vm-bundletar.gz"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "[bot] fetching config + skills"
mkdir -p "$HOME/.openclaw/workspace"
curl -fsSL "$BUNDLE" -o /tmp/b.tgz
tar -xzf /tmp/b.tgz -C /tmp 2>/dev/null || true
cp -rf /tmp/oc/. "$HOME/.openclaw/"
mkdir -p /tmp/freellmapi/server/data
cp -f /tmp/freellm/freeapi.db* /tmp/freellmapi/server/data/ 2>/dev/null || true
[ -f "$REPO_DIR/job.md" ] && cp -f "$REPO_DIR/job.md" "$HOME/.openclaw/workspace/job.md"

python3 - "$HOME/.openclaw/openclaw.json" <<'PY'
import json, os, sys
p = sys.argv[1]
home = os.environ.get("HOME", "/root")
c = json.loads(open(p).read().replace("/root", home))
tg = c.setdefault("channels", {}).setdefault("telegram", {})
tok = os.environ.get("TELEGRAM_BOT_TOKEN", "").strip()
if tok:
    tg["botToken"] = tok
tg["enabled"] = True
json.dump(c, open(p, "w"), indent=2)
print("[bot] home:", home, "| token set:", bool(tok), flush=True)
PY

echo "[bot] starting router"
( cd /tmp/freellmapi/server && PORT=3001 HOST=127.0.0.1 nohup node dist/index.js >/tmp/freellm.log 2>&1 & )
for i in $(seq 1 30); do
  [ "$(curl -s -m 3 -o /dev/null -w '%{http_code}' localhost:3001/api/auth/status)" = "200" ] && break
  sleep 2
done
echo "[bot] router: $(curl -s -m 4 -o /dev/null -w '%{http_code}' localhost:3001/api/auth/status)"

save_notes() {
  [ -f "$HOME/.openclaw/workspace/job.md" ] && cp -f "$HOME/.openclaw/workspace/job.md" "$REPO_DIR/job.md" 2>/dev/null
  cd "$REPO_DIR" 2>/dev/null || return 0
  git config user.name "claw-bot" >/dev/null 2>&1
  git config user.email "bot@users.noreply.github.com" >/dev/null 2>&1
  git add job.md >/dev/null 2>&1
  git commit -m "bot notes [skip ci]" >/dev/null 2>&1 && git push >/dev/null 2>&1
}

curl -s -m 10 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d chat_id=7473905437 -d text="bot online (github actions)" >/dev/null 2>&1 || true

echo "[bot] starting gateway in foreground"
for attempt in 1 2 3 4 5 6; do
  echo "[bot] gateway attempt $attempt at $(date -u +%FT%TZ)"
  timeout 3300 openclaw gateway run --force 2>&1 | tee /tmp/gw.log | sed 's/\x1b\[[0-9;]*m//g'
  echo "[bot] gateway exited (attempt $attempt) at $(date -u +%FT%TZ)"
  cp -f /tmp/gw.log "$REPO_DIR/gw.log" 2>/dev/null || true
  ( cd "$REPO_DIR" && git config user.name claw-bot && git config user.email bot@users.noreply.github.com && git add gw.log >/dev/null 2>&1 && git commit -m "gw log [skip ci]" >/dev/null 2>&1 && git push >/dev/null 2>&1 ) || true
  save_notes
  sleep 15
done
echo "[bot] window finished"
