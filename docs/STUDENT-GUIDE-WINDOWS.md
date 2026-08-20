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

| Service | Address |
|---|---|
| Langflow | <http://localhost:7860> |
| n8n | <http://localhost:5678> |
| JupyterLab | <http://localhost:8888> |
| Metabase | <http://localhost:3000> |
| CloudBeaver | <http://localhost:8978> |
| Qdrant | <http://localhost:6333/dashboard> |

Logins are on the instructor's slide (or the READY screen tells you how to
print them).

## Daily use

- **Start**: open VirtualBox → select *KingoVM* → **Start**
  (or double-click the `.bat` again — it just starts the VM).
- **Stop**: close the VM window → choose **Send the shutdown signal** — the
  VM turns itself off within about 10–20 seconds. (Don't pick *Power off
  the machine* for everyday use: that is like pulling the power plug and
  can damage the databases inside the VM.)

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
