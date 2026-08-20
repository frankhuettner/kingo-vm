#!/usr/bin/env bash
# Kingo VM image builder — fully unattended, no clicking.
#
#   ./build/build.sh arm64        # Mac/Apple-Silicon image (UTM bundle)
#   ./build/build.sh amd64        # Windows/Intel image (VirtualBox OVA)
#   ./build/build.sh all
#
# What it does per architecture:
#   1. downloads the stock Ubuntu 24.04 cloud image (cached)
#   2. boots it once headlessly under QEMU with a cloud-init seed that
#      installs Docker, copies stack/, pre-pulls and pre-initializes the
#      whole service stack, then powers the VM off
#   3. packages the result:  arm64 -> Kingo.utm bundle (zip)
#                            amd64 -> kingo-win-amd64.ova + setup .bat
#
# Native speed on Apple Silicon (arm64 via Hypervisor.framework) and on
# Linux/x86 with KVM (amd64) — e.g. GitHub Actions, see .github/workflows.
# The "other" architecture also builds anywhere via emulation, just slowly.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE="$ROOT/build/cache"
DIST="$ROOT/dist"
UBUNTU_BASE_URL="https://cloud-images.ubuntu.com/noble/current"
VM_RAM=6144           # MiB, also the shipped VM's RAM
VM_CPUS=4
DISK_SIZE=32G
DISK_CAPACITY_BYTES=34359738368

log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
fsize(){ stat -f%z "$1" 2>/dev/null || stat -c%s "$1"; }

need() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1  (macOS: brew install qemu ; Debian/Ubuntu: apt install qemu-system qemu-utils genisoimage)"; }

make_seed_iso() { # $1=seed_dir $2=out_iso
  # Tries every available tool instead of only the first: hdiutil exists on
  # every Mac but can crash in sandboxed shells, so a failure falls through.
  rm -f "$2"
  if command -v hdiutil >/dev/null 2>&1; then
    hdiutil makehybrid -quiet -iso -joliet -default-volume-name CIDATA -o "$2" "$1" \
      && [ -s "$2" ] && return 0
  fi
  if command -v genisoimage >/dev/null 2>&1; then
    genisoimage -quiet -output "$2" -volid CIDATA -joliet -rock "$1"/* && [ -s "$2" ] && return 0
  fi
  if command -v mkisofs >/dev/null 2>&1; then
    mkisofs -quiet -output "$2" -volid CIDATA -joliet -rock "$1"/* && [ -s "$2" ] && return 0
  fi
  # Last resort: pure-Python ISO via pycdlib (e.g. python3 -m venv
  # build/cache/seedtools && build/cache/seedtools/bin/pip install pycdlib)
  local py
  for py in "$ROOT/build/cache/seedtools/bin/python3" python3; do
    command -v "$py" >/dev/null 2>&1 || continue
    "$py" -c 'import pycdlib' 2>/dev/null || continue
    "$py" - "$1" "$2" <<'PYEOF' && [ -s "$2" ] && return 0
import os, sys, pycdlib
seed, out = sys.argv[1], sys.argv[2]
iso = pycdlib.PyCdlib()
iso.new(interchange_level=3, joliet=3, rock_ridge='1.09', vol_ident='CIDATA')
for i, name in enumerate(sorted(os.listdir(seed))):
    base = ''.join(c if c.isalnum() else '_' for c in name.upper()).split('.')[0][:7]
    iso.add_file(os.path.join(seed, name), iso_path='/%s%d.;1' % (base, i),
                 rr_name=name, joliet_path='/' + name)
iso.write(out)
iso.close()
PYEOF
  done
  die "could not build the cloud-init seed ISO (need hdiutil, genisoimage, mkisofs, or python3 with pycdlib)"
}

pick_accel() { # $1=target_arch -> echoes "accel cpu"
  local host_os host_arch
  host_os=$(uname -s); host_arch=$(uname -m)
  case "$1" in
    arm64)
      if [ "$host_os" = Darwin ] && [ "$host_arch" = arm64 ]; then echo "hvf host"
      elif [ "$host_os" = Linux ] && [ "$host_arch" = aarch64 ] && [ -w /dev/kvm ]; then echo "kvm host"
      else echo "tcg max"; fi ;;
    amd64)
      if [ "$host_os" = Darwin ] && [ "$host_arch" = x86_64 ]; then echo "hvf host"
      elif [ "$host_os" = Linux ] && [ "$host_arch" = x86_64 ] && [ -w /dev/kvm ]; then echo "kvm host"
      else echo "tcg max"; fi ;;
  esac
}

find_edk2() { # aarch64 UEFI firmware shipped with qemu
  local qdir cand
  qdir="$(dirname "$(command -v qemu-system-aarch64)")"
  for cand in "$qdir/../share/qemu/edk2-aarch64-code.fd" \
              /usr/share/qemu/edk2-aarch64-code.fd \
              /usr/share/AAVMF/AAVMF_CODE.fd \
              /opt/homebrew/share/qemu/edk2-aarch64-code.fd; do
    [ -f "$cand" ] && { echo "$cand"; return 0; }
  done
  die "cannot find edk2-aarch64-code.fd (aarch64 UEFI firmware)"
}

bake() { # $1=arch(arm64|amd64)
  local arch="$1" qemu_arch img work seed payload accel cpu machine args timeout
  case "$arch" in
    arm64) qemu_arch=aarch64 ;;
    amd64) qemu_arch=x86_64 ;;
    *) die "unknown arch: $arch" ;;
  esac
  need "qemu-system-$qemu_arch"; need qemu-img; need curl; need python3

  work="$ROOT/build/work/$arch"
  rm -rf "$work"; mkdir -p "$work" "$CACHE" "$DIST"

  log "[$arch] fetching Ubuntu 24.04 cloud image"
  img="$CACHE/noble-server-cloudimg-$arch.img"
  [ -f "$img" ] || curl -fL --retry 3 -o "$img.part" \
      "$UBUNTU_BASE_URL/noble-server-cloudimg-$arch.img" && { [ -f "$img" ] || mv "$img.part" "$img"; }

  log "[$arch] preparing disk ($DISK_SIZE)"
  qemu-img convert -O qcow2 "$img" "$work/disk.qcow2"
  qemu-img resize "$work/disk.qcow2" "$DISK_SIZE"

  log "[$arch] building cloud-init seed"
  seed="$work/seed"; mkdir -p "$seed"
  payload="$work/payload"
  mkdir -p "$payload/kingo/.build"
  cp -R "$ROOT/stack/." "$payload/kingo/"
  cp "$ROOT/build/guest/"* "$payload/kingo/.build/"
  tar -czf "$seed/payload.tgz" -C "$payload" kingo

  local kingo_password
  kingo_password=$(grep '^KINGO_PASSWORD=' "$ROOT/stack/.env" | cut -d= -f2)
  sed -e "s|@KINGO_PASSWORD@|$kingo_password|g" \
      "$ROOT/build/cloud-init/user-data.tmpl" > "$seed/user-data"
  printf 'instance-id: kingo-build-%s\nlocal-hostname: kingo\n' "$arch" > "$seed/meta-data"
  make_seed_iso "$seed" "$work/seed.iso"

  read -r accel cpu <<<"$(pick_accel "$arch")"
  log "[$arch] booting bake VM (accel=$accel — this runs unattended)"
  [ "$accel" = tcg ] && log "[$arch] NOTE: emulated build; expect 1-4 hours. Native builds take ~20-40 min."

  args=( -accel "$accel" -cpu "$cpu" -smp "$VM_CPUS" -m "$VM_RAM"
         -drive "if=virtio,format=qcow2,file=$work/disk.qcow2"
         -drive "if=virtio,format=raw,readonly=on,file=$work/seed.iso"
         -nic "user,model=virtio-net-pci"
         -display none -serial "file:$work/serial.log" )
  if [ "$arch" = arm64 ]; then
    qemu-img create -q -f raw "$work/efivars.raw" 64M
    args=( -machine virt
           -drive "if=pflash,format=raw,readonly=on,file=$(find_edk2)"
           -drive "if=pflash,format=raw,file=$work/efivars.raw"
           "${args[@]}" )
  else
    args=( -machine q35 "${args[@]}" )
  fi

  timeout=$(( $([ "$accel" = tcg ] && echo 14400 || echo 5400) ))
  "qemu-system-$qemu_arch" "${args[@]}" &
  local qpid=$! start=$SECONDS
  while kill -0 "$qpid" 2>/dev/null; do
    sleep 15
    printf '[%5ss] %s\n' "$((SECONDS-start))" "$(tail -c 2000 "$work/serial.log" 2>/dev/null | tr -d '\r' | grep -v '^\s*$' | tail -1 | cut -c1-110)"
    if [ $((SECONDS-start)) -gt "$timeout" ]; then
      kill "$qpid" 2>/dev/null || true
      die "[$arch] bake timed out after ${timeout}s — see $work/serial.log"
    fi
  done
  wait "$qpid" || true

  grep -q KINGO-BAKE-SUCCESS "$work/serial.log" \
    || die "[$arch] bake did not report success — see $work/serial.log and search for 'kingo-bake'"
  log "[$arch] bake succeeded"

  if [ "$arch" = arm64 ]; then package_utm "$work"; else package_ova "$work"; fi
}

package_utm() { # $1=work
  # Stage the bundle inside the work dir, NEVER at dist/Kingo.utm: an
  # extracted Kingo.utm registered in UTM lives at that path on dev machines,
  # and UTM writing there (play/save) mid-package once emptied the bundle —
  # the zip shipped without the disk and the registered VM lost its drive.
  local work="$1" bundle="$work/Kingo.utm"
  log "[arm64] packaging UTM bundle"
  rm -rf "$bundle"; mkdir -p "$bundle/Data"
  qemu-img convert -c -O qcow2 "$work/disk.qcow2" "$bundle/Data/disk.qcow2"
  rm -f "$work/disk.qcow2"    # ~20 GB intermediate, no longer needed
  sed -e "s|@UUID@|$(uuidgen | tr 'a-z' 'A-Z')|g" \
      "$ROOT/build/templates/utm-config.plist.tmpl" > "$bundle/config.plist"
  command -v plutil >/dev/null 2>&1 && plutil -lint -s "$bundle/config.plist"
  rm -f "$DIST/kingo-mac-arm64-utm.zip"
  # Info-ZIP writes proper zip64; ditto does NOT — for members over 4 GiB it
  # silently stores the size mod 2^32 and only Archive Utility can extract.
  (cd "$work" && zip -qr "$DIST/kingo-mac-arm64-utm.zip" Kingo.utm)
  [ "$(fsize "$DIST/kingo-mac-arm64-utm.zip")" -gt 1000000000 ] \
    || die "utm zip is implausibly small — the disk was not packaged"
  rm -rf "$bundle"
  log "[arm64] wrote dist/kingo-mac-arm64-utm.zip"
}

package_ova() { # $1=work
  local work="$1" pkg="$work/ova" vmdk_size tarfmt=gnutar
  log "[amd64] packaging VirtualBox OVA"
  mkdir -p "$pkg"
  qemu-img convert -O vmdk -o subformat=streamOptimized \
      "$work/disk.qcow2" "$pkg/kingo-disk001.vmdk"
  rm -f "$work/disk.qcow2"    # ~20 GB intermediate, no longer needed
  vmdk_size=$(fsize "$pkg/kingo-disk001.vmdk")
  sed -e "s|@VMDK_SIZE@|$vmdk_size|g" \
      -e "s|@DISK_CAPACITY@|$DISK_CAPACITY_BYTES|g" \
      "$ROOT/build/templates/kingo.ovf.tmpl" > "$pkg/kingo.ovf"
  rm -f "$DIST/kingo-win-amd64.ova"
  # OVA = tar, .ovf first. GNU tar format, NOT ustar: the vmdk exceeds
  # ustar's 8 GiB per-file limit (bsdtar then DROPS it but still exits 0).
  # VirtualBox's tar reader accepts GNU base-256 sizes; it rejects pax.
  tar --version 2>/dev/null | grep -q 'GNU tar' && tarfmt=gnu
  (cd "$pkg" && COPYFILE_DISABLE=1 tar --format "$tarfmt" -cf "$DIST/kingo-win-amd64.ova" kingo.ovf kingo-disk001.vmdk)
  [ "$(fsize "$DIST/kingo-win-amd64.ova")" -gt "$vmdk_size" ] \
    || die "OVA is smaller than its vmdk — the disk was not packaged"
  rm -f "$pkg/kingo-disk001.vmdk"
  cp "$ROOT/dist-extras/KINGO-SETUP-WINDOWS.bat" "$DIST/"
  log "[amd64] wrote dist/kingo-win-amd64.ova (+ KINGO-SETUP-WINDOWS.bat)"
}

checksums() {
  log "writing SHA256SUMS.txt"
  # dotfile first so the file list never picks up the sums file itself;
  # -maxdepth 1 -type f so stray directories in dist/ don't break the run
  (cd "$DIST" && rm -f SHA256SUMS.txt \
    && find . -maxdepth 1 -type f ! -name '.*' -exec sh -c \
         'command -v sha256sum >/dev/null 2>&1 && sha256sum "$@" || shasum -a 256 "$@"' _ {} + \
       | sed 's|\./||' > .SHA256SUMS.tmp \
    && mv .SHA256SUMS.tmp SHA256SUMS.txt) || true
}

case "${1:-}" in
  arm64) bake arm64; checksums ;;
  amd64) bake amd64; checksums ;;
  all)   bake arm64; bake amd64; checksums ;;
  *)     echo "usage: $0 arm64|amd64|all"; exit 1 ;;
esac

log "done — artifacts in dist/"
ls -lh "$DIST"
cat <<'EOF'

Before distributing, test each artifact once:
  Mac    : unzip, double-click Kingo.utm, press play, wait for the READY screen
  Windows: put the .ova and .bat in one folder, double-click the .bat
EOF
