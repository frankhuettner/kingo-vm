#!/usr/bin/env bash
# Full-screen status display on the VM console (tty1). This is the only thing
# zero-IT students ever see inside the VM window: it tells them when the stack
# is ready and which URLs to open in their normal browser.
set -u
# shellcheck disable=SC1091
set -a; source /opt/kingo/.env 2>/dev/null || true; set +a

SERVICES=(
  "JupyterLab|8888|/api"
  "Jupyter MCP|4040|/"
  "Langflow|7860|/health"
  "n8n|5678|/healthz"
  "Metabase|3000|/api/health"
  "CloudBeaver|8978|/"
  "Qdrant|6333|/readyz"
  "PostgreSQL|5432|tcp"
)

check() {
  local port="$1" path="$2"
  if [ "$path" = "tcp" ]; then
    (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null && { exec 3>&- 3<&-; return 0; } || return 1
  fi
  local code
  code=$(curl -s -o /dev/null -m 2 -w '%{http_code}' "http://127.0.0.1:${port}${path}" 2>/dev/null || echo 000)
  [ "$code" != "000" ]
}

while true; do
  up=0; total=${#SERVICES[@]}; lines=""
  for s in "${SERVICES[@]}"; do
    IFS='|' read -r name port path <<<"$s"
    if check "$port" "$path"; then
      up=$((up+1)); lines+=$(printf '   [ OK ]  %-13s http://localhost:%s' "$name" "$port")$'\n'
    else
      lines+=$(printf '   [ .. ]  %-13s starting ...' "$name")$'\n'
    fi
  done

  clear
  echo
  echo "  ==============================================================="
  echo "                     KINGO  CLASSROOM  VM"
  echo "  ==============================================================="
  echo
  if [ "$up" -eq "$total" ]; then
    echo "   ALL SERVICES ARE READY."
    echo
    echo "   Minimize this window (do NOT close it) and open these in the"
    echo "   browser on YOUR OWN computer:"
    echo
    echo "     Langflow      http://localhost:7860"
    echo "     n8n           http://localhost:5678"
    echo "     JupyterLab    http://localhost:8888"
    echo "     Metabase      http://localhost:3000"
    echo "     CloudBeaver   http://localhost:8978"
    echo "     Qdrant        http://localhost:6333/dashboard"
    echo
    echo "   Logins -> ask your instructor, or press Ctrl+Alt+F2 (Mac: use"
    echo "   the UTM menu), log in as ${KINGO_USER:-student} / ${KINGO_PASSWORD:-kingo2026},"
    echo "   and run:  kingo credentials"
  else
    echo "   Starting services  ($up/$total ready)  -- this takes 1-3 minutes"
    echo
    printf '%s' "$lines"
  fi
  echo
  echo "  ==============================================================="
  sleep 5
done
