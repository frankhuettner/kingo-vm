#!/usr/bin/env bash
# Runs ONCE inside the VM during image build (invoked by cloud-init).
# Installs the stack as a system service, pre-pulls all images, boots the
# stack once so every service finishes its first-run initialization
# (DB migrations, admin accounts), then shuts it down cleanly.
# Result: the distributed image starts fast and works offline.
set -euxo pipefail

KINGO=/opt/kingo
# shellcheck disable=SC1091
set -a; source "$KINGO/.env"; set +a

# --- system plumbing ---------------------------------------------------------
install -m 0644 "$KINGO/.build/kingo.service"        /etc/systemd/system/
install -m 0644 "$KINGO/.build/kingo-banner.service" /etc/systemd/system/
install -m 0755 "$KINGO/.build/kingo-banner.sh"      /usr/local/bin/kingo-banner.sh
chmod +x "$KINGO/kingo"
ln -sf "$KINGO/kingo" /usr/local/bin/kingo

# 2G swap so the stack survives memory spikes on a 6G VM
if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

usermod -aG docker student
systemctl daemon-reload
systemctl enable docker kingo kingo-banner

# --- pre-pull + first-run initialization ------------------------------------
cd "$KINGO"
# Registry pulls flake on shared-IP hosts (GitHub runners hit Docker Hub
# rate limits): retry patiently and fail LOUDLY if the images never arrive —
# continuing with a half-pulled stack just fails later with a worse message.
pull_ok=0
for i in 1 2 3 4 5; do
  docker compose pull && { pull_ok=1; break; }
  echo "pull attempt $i failed (registry flake or rate limit); retrying in 30s"
  sleep 30
done
[ "$pull_ok" = 1 ] || { echo "ERROR: docker compose pull kept failing"; exit 1; }
for i in 1 2 3; do docker compose up -d && break || { echo "up retry $i"; sleep 15; }; done

# Wait until every service answers WITH the expected status code. A lenient
# "any HTTP answer counts" check once passed while langflow was crash-looping
# (its /health responds briefly before the crash) — hence exact codes, a
# stability re-check, and an explicit no-restarting-containers assertion.
check() { # port path expected-codes ("200" or alternation like "200|302")
  local port="$1" path="$2" want="$3" code
  if [ "$path" = "tcp" ]; then
    (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null && { exec 3>&- 3<&-; return 0; } || return 1
  fi
  code=$(curl -s -o /dev/null -m 3 -w '%{http_code}' "http://127.0.0.1:${port}${path}" 2>/dev/null || echo 000)
  echo "$code" | grep -qE "^(${want})$"
}
# 4040/mcp answers 401 without the bearer token — that IS the healthy state.
SERVICES="8888|/api|200 4040|/mcp|401 7860|/health|200 5678|/healthz|200 3000|/api/health|200 8978|/|200|301|302 6333|/readyz|200 5432|tcp"
wait_all() { # $1=max attempts
  local attempt all s port path want
  for attempt in $(seq 1 "$1"); do
    all=1
    for s in $SERVICES; do
      IFS='|' read -r port path want <<<"$s"
      check "$port" "$path" "${want:-200}" || { all=0; break; }
    done
    [ "$all" = 1 ] && return 0
    echo "waiting for services ($attempt/$1) ..."
    sleep 10
  done
  return 1
}
assert_stable() {
  sleep 20   # a crash-looping container flips to "Restarting" within seconds
  if docker compose ps --format '{{.Name}} {{.Status}}' | grep -i 'restart'; then
    echo "ERROR: containers are restart-looping"; docker compose ps; exit 1
  fi
  wait_all 3 || { echo "ERROR: services flapped after coming up"; docker compose ps; exit 1; }
}
wait_all 90 || { echo "ERROR: services did not all come up"; docker compose ps; exit 1; }
assert_stable

# Starter notebook that the MCP server points at
docker exec kingo-jupyterlab bash -lc \
  'mkdir -p work && [ -f work/notebook.ipynb ] || printf "%s" "{\"cells\":[],\"metadata\":{},\"nbformat\":4,\"nbformat_minor\":5}" > work/notebook.ipynb'

# Pre-provision the Metabase admin account + classroom database connection so
# students never see the setup wizard. Non-fatal: worst case they click
# through the wizard themselves.
MB=http://127.0.0.1:3000
setup_metabase() {
  local token sid
  token=$(curl -s "$MB/api/session/properties" | python3 -c \
    'import json,sys; print(json.load(sys.stdin).get("setup-token") or "")')
  [ -n "$token" ] || { echo "Metabase already set up"; return 0; }
  sid=$(curl -s -X POST "$MB/api/setup" -H 'Content-Type: application/json' -d "{
      \"token\": \"$token\",
      \"user\": {\"email\": \"$METABASE_ADMIN_EMAIL\", \"password\": \"$KINGO_STRONG_PASSWORD\",
                 \"first_name\": \"Kingo\", \"last_name\": \"Admin\", \"site_name\": \"Kingo Classroom\"},
      \"prefs\": {\"site_name\": \"Kingo Classroom\", \"allow_tracking\": false}
    }" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id") or "")')
  [ -n "$sid" ] || { echo "WARN: Metabase setup call failed"; return 0; }
  curl -s -X POST "$MB/api/database" -H 'Content-Type: application/json' \
    -H "X-Metabase-Session: $sid" -d "{
      \"engine\": \"postgres\", \"name\": \"Classroom (PostgreSQL)\",
      \"details\": {\"host\": \"postgres\", \"port\": 5432, \"dbname\": \"classroom\",
                    \"user\": \"$KINGO_USER\", \"password\": \"$KINGO_PASSWORD\", \"ssl\": false}
    }" > /dev/null || echo "WARN: could not add classroom DB to Metabase"
}
setup_metabase || echo "WARN: Metabase pre-setup skipped"

docker compose down

# Second boot cycle: catches services that only survive their very first run
# (a first-run-only bug once shipped because the single-cycle check passed).
docker compose up -d
wait_all 45 || { echo "ERROR: services failed on second start"; docker compose ps; exit 1; }
assert_stable
docker compose down          # stop cleanly; volumes (all baked state) remain

# --- image hygiene -----------------------------------------------------------
# Stable wildcard network config: the NIC name differs between QEMU (build),
# VirtualBox (E1000) and UTM (virtio), so match any en*/eth* interface.
rm -f /etc/netplan/50-cloud-init.yaml
# Keep the text console on the firmware framebuffer: with UTM's virtio-ramfb
# display, the kernel's virtio-gpu driver takes over the visible scanout while
# fbcon keeps drawing to the now-hidden ramfb — the VM window then shows
# "Display output is not active" forever. Blacklisting virtio_gpu pins the
# console (and our READY banner) to the framebuffer hypervisors actually show.
# VirtualBox (VMSVGA) never uses virtio_gpu, so this is a no-op there.
echo 'blacklist virtio_gpu' > /etc/modprobe.d/kingo-display.conf
update-initramfs -u
apt-get clean
rm -rf /var/lib/apt/lists/*
touch /etc/cloud/cloud-init.disabled   # student boots skip cloud-init entirely
fstrim -av || true

mkdir -p /var/lib/kingo
echo OK > /var/lib/kingo/bake-ok
echo "bake complete"
