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
install -m 0644 "$KINGO/.build/kingo.service"          /etc/systemd/system/
install -m 0644 "$KINGO/.build/kingo-banner.service"   /etc/systemd/system/
install -m 0644 "$KINGO/.build/kingo-terminal.service" /etc/systemd/system/
install -m 0755 "$KINGO/.build/kingo-banner.sh"        /usr/local/bin/kingo-banner.sh
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

# Browser terminal (ttyd on :7681) + OpenCode. No API key is baked in:
# opencode stores keys per user under the student home (`opencode auth
# login`), so students add or change theirs anytime.
apt-get update -qq || true
apt-get install -y ttyd
# Ubuntu's package auto-enables its own loopback-only ttyd.service: it
# occupies the port (crash-looping kingo-terminal) yet still answers the
# localhost health checks, so the breakage is invisible from inside. The
# port forwards connect to the guest's NAT IP and need kingo-terminal's
# all-interfaces listener instead.
systemctl disable --now ttyd.service
systemctl mask ttyd.service
oc_ok=0
for i in 1 2 3; do
  su - student -c 'curl -fsSL https://opencode.ai/install | bash' && { oc_ok=1; break; }
  echo "opencode install attempt $i failed; retrying in 15s"
  sleep 15
done
[ "$oc_ok" = 1 ] || { echo "ERROR: opencode install kept failing"; exit 1; }
ocbin=$(find /home/student -maxdepth 4 -type f -name opencode 2>/dev/null | head -1)
[ -n "$ocbin" ] || { echo "ERROR: opencode binary not found after install"; exit 1; }
ln -sf "$ocbin" /usr/local/bin/opencode
su - student -c 'opencode --version'
systemctl enable --now kingo-terminal
sleep 3
systemctl is-active kingo-terminal
# Assert the BIND ADDRESS, not just that the port answers: a loopback-only
# listener passes every localhost check but is dead through the forwards.
ss -tln | grep -qE '0\.0\.0\.0:7681' || { echo "ERROR: ttyd is not listening on all interfaces"; exit 1; }

# One-key clean shutdown: Ctrl+Alt+Del on the console powers the VM off
# cleanly instead of rebooting — students never have to log in just to stop
# the VM. If someone mashes the combo, systemd's burst action must not turn
# into its default force-REBOOT either, so redirect that to a forced poweroff.
ln -sf /usr/lib/systemd/system/poweroff.target /etc/systemd/system/ctrl-alt-del.target
mkdir -p /etc/systemd/system.conf.d
printf '[Manager]\nCtrlAltDelBurstAction=poweroff-force\n' \
  > /etc/systemd/system.conf.d/10-kingo-ctrl-alt-del.conf

# --- pre-pull + first-run initialization ------------------------------------
cd "$KINGO"
# Registry pulls flake on shared-IP hosts (GitHub runners hit Docker Hub
# rate limits): retry patiently and fail LOUDLY if the images never arrive —
# continuing with a half-pulled stack just fails later with a worse message.
pull_ok=0
for i in 1 2 3 4 5; do
  # --ignore-buildable: the jupyterhub image is built locally below and its
  # tag does not exist in any registry — a plain pull would always fail.
  docker compose pull --ignore-buildable && { pull_ok=1; break; }
  echo "pull attempt $i failed (registry flake or rate limit); retrying in 30s"
  sleep 30
done
[ "$pull_ok" = 1 ] || { echo "ERROR: docker compose pull kept failing"; exit 1; }
build_ok=0
for i in 1 2 3; do
  docker compose build && { build_ok=1; break; }
  echo "compose build attempt $i failed; retrying in 20s"
  sleep 20
done
[ "$build_ok" = 1 ] || { echo "ERROR: docker compose build kept failing"; exit 1; }
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
SERVICES="8888|/api|200 8000|/hub/api|200 4040|/mcp|401 7860|/health|200 5678|/healthz|200 3000|/api/health|200 8978|/|200|301|302 6333|/readyz|200 5432|tcp 7681|/|200"
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

# A healthy hub is not enough — it must be able to LAUNCH a Lab. The classic
# failure is a hub image without the single-user server installed, which only
# surfaces when a student first logs in.
docker exec kingo-jupyterhub jupyterhub-singleuser --version
docker exec kingo-jupyterhub python3 -c 'import jupyterlab'

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
# Put the text console on the virtio-gpu framebuffer (UTM/arm64 only): UTM's
# firmware draws via virtio-gpu and shuts it off at ExitBootServices, and its
# EDK2 build cannot drive a bare ramfb either — the only scanout UTM ever
# shows is the virtio-gpu one. The firmware framebuffer leftover keeps
# simpledrm on fb0, so fbcon must be pointed at fb1 (virtio-gpu) explicitly;
# fbcon's modeset is what switches the scanout on. Verified in a live UTM VM.
# amd64/VirtualBox has exactly one framebuffer (VMSVGA), so this stays
# arm64-only — fbcon=map:1 with no fb1 would leave the console invisible.
if [ "$(uname -m)" = "aarch64" ]; then
  printf 'GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT fbcon=map:1"\n' \
    > /etc/default/grub.d/99-kingo-display.cfg
  update-grub
fi
apt-get clean
rm -rf /var/lib/apt/lists/*
touch /etc/cloud/cloud-init.disabled   # student boots skip cloud-init entirely
fstrim -av || true

mkdir -p /var/lib/kingo
echo OK > /var/lib/kingo/bake-ok
echo "bake complete"
