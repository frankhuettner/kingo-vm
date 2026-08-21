# Kingo VM — Windows setup (5 minutes)

You need a Windows 10 or 11 laptop with at least **8 GB of RAM** and **35 GB
of free disk space** (the download plus the imported VM, which grows as you
use it).

## 1. Download

Download these two files into the **same folder** (e.g. `Documents\Kingo`):

- `kingo-win-amd64.ova` (large file — wait until it finishes completely)
- `KINGO-SETUP-WINDOWS.bat`

## 2. Run the setup

Double-click **`KINGO-SETUP-WINDOWS.bat`**.

- If Windows shows *"Windows protected your PC"*: click **More info → Run anyway**.
- If VirtualBox is not installed yet, the script installs it for you
  (approve the permission popup). If that fails, install VirtualBox manually
  from <https://www.virtualbox.org/wiki/Downloads> and run the `.bat` again.

The script imports and starts the VM. **You only do this once.**

## 3. Wait for the READY screen

A black VM window opens. After a few minutes it shows
**ALL SERVICES ARE READY** with a list of web addresses.
(The **very first start** can take up to 10 minutes — later starts are much
faster. If the window stays black, click into it and press any key.)

**Minimize** that window (don't close it) and open in your normal browser:

| Service | Address | Login |
|---|---|---|
| Langflow | <http://localhost:7860> | none (logs in automatically) |
| n8n | <http://localhost:5678> | create your own account on first visit |
| JupyterLab | <http://localhost:8888> | none |
| JupyterHub | <http://localhost:8000> | any username + password `kingo2026` |
| Metabase | <http://localhost:3000> | `admin@kingo.local` / `Kingo2026!` |
| CloudBeaver | <http://localhost:8978> | `student` / `Kingo2026!` |
| Qdrant | <http://localhost:6333/dashboard> | none |
| Web Terminal (OpenCode) | <http://localhost:7681> | none |

MCP (*Model Context Protocol*) is how AI assistants such as Claude Desktop,
Claude Code, or Cursor connect to tools. Point yours at the Jupyter MCP
endpoint `http://localhost:4040/mcp` (header
`Authorization: Bearer kingo-mcp-2026`) and it can write and run code in
the class notebook for you.
In the Web Terminal, type `opencode` to start the AI coding assistant (it
asks for an API key the first time — the key is saved and can be changed
anytime with `opencode auth login`).

## How it all fits together

```
┌─ Your laptop (Windows) ────────────────────────────────────┐
│                                                            │
│   Browser, KNIME, MCP clients                              │
│       │                                                    │
│       │  always talk to  localhost:<port>                  │
│       ▼  (VirtualBox forwards each port into the VM)       │
│  ┌─ Kingo VM — Ubuntu Linux ────────────────────────────┐  │
│  │                                                      │  │
│  │   Docker runs one container per service:             │  │
│  │                                                      │  │
│  │   [Langflow] [n8n] [JupyterLab] [Metabase] ...       │  │
│  │       │        │                                     │  │
│  │       └────────┴──► [PostgreSQL]   [Qdrant]          │  │
│  │                                                      │  │
│  │   containers reach each other by service NAME:       │  │
│  │   postgres:5432, qdrant:6333                         │  │
│  └──────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────┘
```

Two address rules cover everything:

1. **From your laptop** (browser, KNIME, MCP clients): always
   `localhost:<port>` — VirtualBox forwards these ports into the VM.
2. **From one service to another** — for example an n8n workflow or a
   Langflow flow that connects to the database: use the *service name* as
   host, **not** localhost. For PostgreSQL that is host `postgres`, port
   `5432`, database `classroom`, user `student`, password `kingo2026`; for
   Qdrant it is `http://qdrant:6333`. (Inside a container, `localhost`
   means the container itself — the most common mistake.)

## Daily use

- **Start**: open VirtualBox → select *KingoVM* → **Start**
  (or double-click the `.bat` again — it just starts the VM).
- **Stop**: close the VM window → choose **Send the shutdown signal** — the
  VM turns itself off within about 10–20 seconds. (Don't pick *Power off
  the machine* for everyday use: that is like pulling the power plug and
  can damage the databases inside the VM.)
- Alternative: in the VM window's menu choose **Input → Keyboard →
  Insert Ctrl-Alt-Del** — the VM shuts down cleanly the same way.

## KNIME (optional)

KNIME runs on your laptop itself, not inside the VM: download **KNIME
Analytics Platform** from <https://www.knime.com/downloads> and install it
like any other program. To use the class database from KNIME, create a
PostgreSQL connection with host `localhost`, port `5432`, database
`classroom`, username `student`, password `kingo2026` — the VM must be
running while you use it.

## If your laptop has only 8 GB of RAM

The VM works, but your laptop will feel slow while it runs. Two tips:

1. Close everything you don't need (Teams, Zoom, extra browser tabs).
2. Optional: give the VM a little less memory. With the VM **powered off**,
   open VirtualBox → select *KingoVM* → **Settings → System → Motherboard**
   → set **Base Memory** to **5120 MB** → **OK**. (Don't go lower — the
   services need it.)

## If something breaks

1. Close the VM window (choose *Power off the machine*) and start it again.
2. An error mentions a **port** or a **forwarding rule**: another program
   on your computer is using one of the VM's network ports. Restart your
   computer and try again; if it keeps happening, ask the instructor.
3. Still broken? In VirtualBox: right-click *KingoVM* → **Remove → Delete all
   files**, then double-click the `.bat` again for a fresh copy.
   (You lose your saved work inside the VM.)
4. Ask the instructor / TA.
