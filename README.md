# Kingo classroom VM

Reproducible, fully scripted build of a classroom VM for the Langflow / n8n
automation course. One repo produces two images from the same recipe:

| Students on | Artifact | They install | They do |
|---|---|---|---|
| Windows (Intel/AMD) | `dist/kingo-win-amd64.ova` + `KINGO-SETUP-WINDOWS.bat` | VirtualBox (the .bat installs it) | double-click the `.bat` |
| Mac (Apple Silicon) | `dist/kingo-mac-arm64-utm.zip` | [UTM](https://mac.getutm.app) (free) | double-click `Kingo.utm`, press ▶ |

Both images bake in localhost port forwards, so every service is reachable at
the URLs below **on the student's own machine**, exactly as documented.
The VM console shows a big **ALL SERVICES READY** screen — students never
touch a Linux shell.

## Services

| Service | URL | First login |
|---|---|---|
| JupyterLab | http://localhost:8888 | no login required |
| Jupyter MCP | http://localhost:4040/mcp | bearer token from `kingo mcp` |
| Langflow | http://localhost:7860 | auto-login classroom instance |
| n8n | http://localhost:5678 | create an account on first visit |
| Metabase | http://localhost:3000 | from `kingo credentials` |
| CloudBeaver | http://localhost:8978 | from `kingo credentials` |
| Qdrant dashboard | http://localhost:6333/dashboard | no login |
| PostgreSQL | localhost:5432 | from `kingo credentials` |

All credentials live in `stack/.env` (fixed and deliberately simple — the VM
is only reachable via localhost). SSH into a running VM: `ssh -p 2222
student@localhost`, password in `stack/.env`.

## Building the images (instructor)

Prereq on your Mac: `brew install qemu`. Then:

```bash
./build/build.sh arm64     # Mac image — native speed on Apple Silicon, ~20-40 min
./build/build.sh amd64     # Windows image — EMULATED on a Mac (1-4 h, unattended)
```

Recommended split: build `arm64` locally, and let GitHub Actions build
`amd64` natively with KVM (~30–45 min): push this repo to GitHub, then run
the **build-amd64-image** workflow (Actions tab → Run workflow). It publishes
a GitHub **release** with the OVA split into <2 GiB parts (private-repo
artifact storage is too small); download the parts and reassemble:
`cat kingo-win-amd64.ova.part* > kingo-win-amd64.ova`.

The build is fully unattended: it boots a stock Ubuntu 24.04 cloud image
headlessly under QEMU; cloud-init installs Docker, copies `stack/` to
`/opt/kingo`, pre-pulls every container image, boots the stack once so all
first-run migrations/admin accounts are baked in (Metabase admin, CloudBeaver
admin, sample PostgreSQL data), then powers off and packages the disk.
First boot in class is therefore fast and needs **no internet**.

**Before distributing, test each artifact once** (Windows laptop for the OVA,
your Mac for the UTM bundle). Upload `dist/*` + `SHA256SUMS.txt` to
university storage and hand students the matching guide from `docs/`.

## Repo layout

```
stack/                  the single source of truth for the service stack
  docker-compose.yml    all 8 services, versions pinned, multi-arch
  .env                  fixed classroom credentials
  kingo                 CLI: status / credentials / mcp / logs / update / reset
  postgres-init/        creates per-service DBs + sample classroom data
build/
  build.sh              one-command image builder (arm64 | amd64 | all)
  cloud-init/           unattended bake configuration
  guest/                what gets installed inside the VM (systemd units,
                        console READY banner, bake script)
  templates/            OVF (VirtualBox) and config.plist (UTM) templates
dist-extras/            KINGO-SETUP-WINDOWS.bat shipped next to the OVA
docs/                   student guides (Windows / Mac)
```

## Mid-semester updates

Everything runs from `docker compose`, so you rarely need to reship images:
change `stack/`, push, and have students run `kingo update` inside the VM
(Ctrl+Alt+F2 console or `ssh -p 2222 student@localhost`) — or just reship the
image and have them delete + re-import (their data lives in the VM, warn
them). To bump a service version: edit the tag in `stack/docker-compose.yml`
and rebuild.

## Notes & alternatives

- **VM sizing**: 4 vCPU / 6 GB RAM / 32 GB thin disk (+2 GB swap inside).
  Hosts with 8 GB RAM work but are the floor; 16 GB is comfortable. Students
  on 8 GB machines can lower the VM to 5120 MB in VirtualBox/UTM (a setting,
  no rebuild — both student guides show how); the 2 GB swap inside the VM
  absorbs the difference. Don't go below that: the 8 services genuinely use
  ~5 GB (Metabase and CloudBeaver are JVMs, Langflow is Python-heavy).
- **Why headless (no desktop GUI)**: a deliberate choice, not a shortcut.
  Every service in the stack is a web UI that is port-forwarded to
  `localhost` on the student's own machine, so students work in their own
  browser — with their own keyboard layout (relevant for Korean input),
  their own clipboard, passwords, bookmarks and downloads folder. A Ubuntu
  desktop inside the VM would only add a second browser nobody needs, while
  costing: ~3–4 GB larger image (≈15 GB download instead of 11), ~2 GB more
  RAM for GNOME (an 8 GB VM would exclude the 8 GB laptops we promise to
  support), a longer bake, and a pile of GUI failure modes to support in
  class (login/lock screens, update pop-ups, display scaling, guest tools
  that differ between VirtualBox and UTM, host↔guest clipboard quirks).
  The "is it running?" reassurance a GUI would give is covered by the big
  **ALL SERVICES READY** console banner instead. If a GUI is ever genuinely
  needed, it is a small change — install `ubuntu-desktop-minimal` +
  autologin in `build/cloud-init/user-data.tmpl` and raise the RAM/disk
  sizing — not a redesign.
- **Docker Desktop route**: students with Docker Desktop can skip the VM
  entirely: clone the repo, `cd stack && docker compose up -d`. Same stack,
  same URLs, same `./kingo` CLI. Also the escape hatch for Windows-on-ARM
  laptops (Snapdragon), which none of the x86 hypervisors cover.
- **VMware**: the OVA also imports into VMware Workstation (free from
  Broadcom), but VMware ignores the port-forward setup the `.bat` does, so
  treat VirtualBox as the supported Windows path.
- **Snapshots**: encourage students to take a VirtualBox/UTM snapshot after
  first successful boot — "restore snapshot" fixes almost anything.
- **Jupyter MCP**: the container follows the
  [datalayer/jupyter-mcp-server](https://github.com/datalayer/jupyter-mcp-server)
  conventions; if your existing kingo MCP setup differs, adjust the
  `jupyter-mcp` service in `stack/docker-compose.yml` — the build consumes
  whatever `stack/` contains.
