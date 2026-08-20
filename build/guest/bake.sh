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
for i in 1 2 3; do docker compose pull && break || { echo "pull retry $i"; sleep 10; }; done
docker compose up -d

# Wait until every service answers (Metabase's first migration is the slowest)
check() {
  local port="$1" path="$2" code
  if [ "$path" = "tcp" ]; then
    (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null && { exec 3>&- 3<&-; return 0; } || return 1
  fi
  code=$(curl -s -o /dev/null -m 3 -w '%{http_code}' "http://127.0.0.1:${port}${path}" 2>/dev/null || echo 000)
  [ "$code" != "000" ]
}
SERVICES="8888|/api 4040|/ 7860|/health 5678|/healthz 3000|/api/health 8978|/ 6333|/readyz 5432|tcp"
for attempt in $(seq 1 90); do
  all=1
  for s in $SERVICES; do
    check "${s%|*}" "${s#*|}" || { all=0; break; }
  done
  [ "$all" = 1 ] && break
  echo "waiting for services ($attempt/90) ..."
  sleep 10
done
[ "$all" = 1 ] || { echo "ERROR: services did not all come up"; docker compose ps; exit 1; }

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

docker compose down          # stop cleanly; volumes (all baked state) remain

# --- image hygiene -----------------------------------------------------------
# Stable wildcard network config: the NIC name differs between QEMU (build),
# VirtualBox (E1000) and UTM (virtio), so match any en*/eth* interface.
rm -f /etc/netplan/50-cloud-init.yaml
apt-get clean
rm -rf /var/lib/apt/lists/*
touch /etc/cloud/cloud-init.disabled   # student boots skip cloud-init entirely
fstrim -av || true

mkdir -p /var/lib/kingo
echo OK > /var/lib/kingo/bake-ok
echo "bake complete"
