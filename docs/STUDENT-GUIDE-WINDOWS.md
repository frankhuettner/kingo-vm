# Kingo VM — Windows setup (5 minutes)

You need a Windows 10 or 11 laptop with at least **8 GB of RAM** and **25 GB
of free disk space**.

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

A black VM window opens. After 1–3 minutes it shows
**ALL SERVICES ARE READY** with a list of web addresses.

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
- **Stop**: close the VM window → choose **Send the shutdown signal**.

## If something breaks

1. Close the VM window (choose *Power off the machine*) and start it again.
2. Still broken? In VirtualBox: right-click *KingoVM* → **Remove → Delete all
   files**, then double-click the `.bat` again for a fresh copy.
   (You lose your saved work inside the VM.)
3. Ask the instructor / TA.
