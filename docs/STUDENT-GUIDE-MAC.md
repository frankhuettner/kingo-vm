# Kingo VM — Mac setup (5 minutes)

Works on any Apple-Silicon Mac (M1 or newer, i.e. Macs from 2021 on) with at
least **8 GB of RAM** and **35 GB of free disk space** (the download plus
the extracted VM, which grows as you use it).
(Older Intel Macs: follow the Windows guide instead — VirtualBox for Intel
Macs — or ask the instructor.)

## 1. Install UTM (free)

Download UTM from <https://mac.getutm.app>, open the `.dmg`, and drag **UTM**
into **Applications**. (The App Store version works too but costs a few
dollars — the website download is identical and free.)

## 2. Download and open the VM

1. Download `kingo-mac-arm64-utm.zip` and wait until it finishes completely.
2. Double-click the zip — you get **Kingo.utm**.
3. Double-click **Kingo.utm** → UTM opens and shows *Kingo Classroom*.
4. Press the **▶ play** button.

## 3. Wait for the READY screen

The window shows Linux boot text and, after a few minutes, **ALL SERVICES
ARE READY**. (The **very first start** can take up to 10 minutes — later
starts are much faster.)

**Minimize** the VM window (don't close it) and open in Safari/Chrome:

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

For AI tools that speak MCP: the Jupyter MCP endpoint is
`http://localhost:4040/mcp` with header `Authorization: Bearer kingo-mcp-2026`.
In the Web Terminal, type `opencode` to start the AI coding assistant (it
asks for an API key the first time — the key is saved and can be changed
anytime with `opencode auth login`).

## Daily use

- **Start**: open UTM → select *Kingo Classroom* → **▶**
- **Stop**: click into the VM window and press
  **⌃ Ctrl + ⌥ Option + fn + ⌫ Delete** (all four at once — that is
  "Ctrl+Alt+Del": "Alt" is the Option key, and **fn + ⌫** makes the
  backspace key act as a real Delete key). The VM turns itself off cleanly
  in about 20 seconds.
- If that combo does nothing: press **⌃ Ctrl + ⌥ Option + fn + F2**, log in
  as `student` / `kingo2026` (the password stays **invisible** while you
  type — that's normal), then type `sudo poweroff` and press Enter.
- UTM's **⏻ button** is a *hard* power-off — UTM warns that it "may corrupt
  the VM". Only click OK there if the VM is frozen: it is like pulling the
  power plug and you may lose your work inside the VM.

## KNIME (optional)

KNIME runs on your Mac itself, not inside the VM: download **KNIME
Analytics Platform** from <https://www.knime.com/downloads> and install it
like any other app. To use the class database from KNIME, create a
PostgreSQL connection with host `localhost`, port `5432`, database
`classroom`, username `student`, password `kingo2026` — the VM must be
running while you use it.

## If your Mac has only 8 GB of RAM

The VM works, but your Mac will feel slow while it runs. Two tips:

1. Close everything you don't need (extra apps and browser tabs).
2. Optional: give the VM a little less memory. With the VM **stopped**,
   right-click *Kingo Classroom* in UTM → **Edit** → **System** → set
   **Memory** to **5120 MB** → **Save**. (Don't go lower — the services
   need it.)

## If something breaks

1. In UTM press ■ (stop), then ▶ (start) again.
2. UTM shows an error mentioning **"Could not set up host forwarding
   rule"**: another program on your Mac is using one of the VM's network
   ports (for example a database app such as Postgres.app on port 5432).
   Quit that program — or simply restart your Mac — and press ▶ again.
3. The window says *"Display output is not active"* or *"Guest has not
   initialized the display"* for more than two minutes: with the VM
   **stopped**, right-click *Kingo Classroom* → **Edit** → **Display** →
   make sure **Emulated Display Card** is **virtio-ramfb** → **Save**,
   then ▶ again.
4. Still broken? Delete *Kingo Classroom* in UTM, re-extract the zip, and
   double-click `Kingo.utm` again for a fresh copy.
   (You lose your saved work inside the VM.)
5. Ask the instructor / TA.
