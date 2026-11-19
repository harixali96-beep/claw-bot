#!/usr/bin/env bash
# GitHub Actions runner for the Void Clipex bot.
set -u
export HOME="${HOME:-$PWD}"
BUNDLE="https://base44.app/api/apps/6afd5d7f94aa00438e512b21/files/mp/public/6afd5d7f94aa00438e512b21/a57c5e21a_openclaw-vm-bundletar.gz"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Render/health: tiny HTTP endpoint so free web services stay healthy ---
if [ -n "${PORT:-}" ]; then
  ( cd /tmp && nohup python3 -m http.server "$PORT" --bind 0.0.0.0 > /tmp/httpd.log 2>&1 & )
  echo "[bot] health endpoint on :$PORT"
fi

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


# --- OpenRouter free-model chain (injected when key present) ---
python3 - "$HOME/.openclaw/openclaw.json" <<'PY2'
import json, os, sys
p = sys.argv[1]
key = os.environ.get("OPENROUTER_API_KEY", "").strip()
if not key:
    sys.exit(0)
order = [("nvidia/nemotron-3-ultra-550b-a55b:free",1000000),("nvidia/nemotron-3.5-super-vl:free",1000000),
         ("baidu/ernie-5.5-flash-preview:free",1024000),("particle-ai/particle-1:free",1048576),
         ("inclusionai/ling-3.2-flash:free",1048576),("google/gemma-4-31b-it:free",262144),
         ("thinkingmachines/inkling-2-small:free",1048576),("nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free",256000),
         ("cohere/north-mini-code:free",256000),("dots-studio/dots-3-note-preview:free",512000),
         ("recursive/flint-v1.0:free",262144),("nvidia/nemotron-3.5-lightning:free",1000000),
         ("google/gemma-4-26b-a4b-it:free",262144),("liquid/lfm-3-1.7b:free",262144)]
c = json.load(open(p))
models = [{"id":m,"name":m,"contextWindow":ctx,"maxTokens":8192,"input":["text"],
           "cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0},"reasoning":False,
           "compat":{"supportsTools":True,"supportsTemperature":True,"supportsUsageInStreaming":True}} for m,ctx in order]
c.setdefault("models",{}).setdefault("providers",{})["openrouter"] = {
    "baseUrl":"https://openrouter.ai/api/v1","api":"openai-completions","apiKey":key,"models":models}
d = c.setdefault("agents",{}).setdefault("defaults",{})
d["models"] = {("openrouter/"+m):{} for m,_ in order}
d["models"]["freellm/auto"] = {}
d["model"] = {"primary":"openrouter/"+order[0][0],
              "fallbacks":["openrouter/"+m for m,_ in order[1:]]+["freellm/auto"]}
json.dump(c, open(p,"w"), indent=2)
print("[bot] openrouter models installed:", len(order))
PY2

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
  timeout 19800 openclaw gateway run --force 2>&1 | tee /tmp/gw.log | sed 's/\x1b\[[0-9;]*m//g'
  echo "[bot] gateway exited (attempt $attempt) at $(date -u +%FT%TZ)"
  cp -f /tmp/gw.log "$REPO_DIR/gw.log" 2>/dev/null || true
  ( cd "$REPO_DIR" && git config user.name claw-bot && git config user.email bot@users.noreply.github.com && git add gw.log >/dev/null 2>&1 && git commit -m "gw log [skip ci]" >/dev/null 2>&1 && git push >/dev/null 2>&1 ) || true
  save_notes
  sleep 15
done
echo "[bot] window finished"
