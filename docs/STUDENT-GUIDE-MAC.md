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

After 1–3 minutes the VM window shows **ALL SERVICES ARE READY**.

**Minimize** the VM window (don't close it) and open in Safari/Chrome:

| Service | Address |
|---|---|
| Langflow | <http://localhost:7860> |
| n8n | <http://localhost:5678> |
| JupyterLab | <http://localhost:8888> |
| Metabase | <http://localhost:3000> |
| CloudBeaver | <http://localhost:8978> |
| Qdrant | <http://localhost:6333/dashboard> |

Logins are on the instructor's slide.

## Daily use

- **Start**: open UTM → select *Kingo Classroom* → **▶**
- **Stop**: VM window → choose shut down (or UTM's ■ button)

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
3. Still broken? Delete *Kingo Classroom* in UTM, re-extract the zip, and
   double-click `Kingo.utm` again for a fresh copy.
   (You lose your saved work inside the VM.)
4. Ask the instructor / TA.
