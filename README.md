<p align="center">
  <img src="WRM_white.png" alt="WRM LOGO" width="400">
</p>

# Watchdog Renderfarm Manager (WRM)

![PowerShell](https://img.shields.io/badge/PowerShell-5.0+-blue)
![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey)
![License](https://img.shields.io/badge/License-MIT-green)
![Status](https://img.shields.io/badge/Project-Stable-brightgreen)


A lightweight **PowerShell render node watchdog and cluster manager** designed for [**Flamenco render farms**](https://flamenco.blender.org)


WRM runs quietly in the **Windows system tray**, monitors render nodes, automatically restarts crashed services, and provides a simple cluster overview without requiring a dedicated management server.

---

# Features

### Node Monitoring

* Automatically starts **Flamenco Worker**
* Optionally runs **Flamenco Manager**
* Detects crashes and **restarts processes automatically**
* Detects multiple worker instances and fixes them

---

### Automatic Recovery

WRM keeps render nodes stable by automatically handling failures.

* Worker crash detection
* Manager crash detection
* Automatic worker restart
* Automatic system reboot after repeated crashes
* Scheduled weekly restart

---

### Cluster Discovery

Nodes automatically discover each other using **UDP broadcast**.

No configuration required.

Each node broadcasts:

* hostname
* worker status
* manager status
* CPU usage
* GPU usage

Nodes automatically appear in the tray menu.

---

### Tray UI

Each node runs a **Windows tray manager** showing:

* Worker status
* Manager status
* Network nodes
* Live CPU usage
* Live GPU usage

Example:

```id="i3vflp"
Network Nodes
  Restart All Nodes

  Render01   ●●   CPU 93%  GPU 99%
  Render02   ●●   CPU 81%  GPU 96%
  Render03   ●○   CPU 12%  GPU 0%
```

Icons:

| Icon | Meaning                  |
| ---- | ------------------------ |
| ●●   | Worker + Manager running |
| ●○   | Worker running           |
| ○○   | Offline                  |

---

### Remote Control

Nodes can send commands across the network:

* Restart all nodes
* Restart a specific node

Uses **UDP broadcast**, no central server required.

---

### Notifications

Nodes notify the farm when events happen.

Notifications include:

* Worker crash
* Manager crash
* Node restarting
* Node online
* Node offline

Example Windows notification:

```id="07pc6n"
Render Node Event
Render02 : Worker crashed (#1)
```

---

### Hardware Monitoring

Nodes broadcast live performance data:

* CPU usage
* GPU usage (via NVIDIA SMI)

This helps identify:

* stuck render nodes
* idle machines
* overloaded machines

Example:

```id="t3afys"
Render01   CPU 96%  GPU 99%
Render02   CPU 72%  GPU 95%
Render03   CPU 10%  GPU 0%
```

---

# Architecture

Each render node runs the same script.

```id="nmq7x2"
Render Node
 ├ Flamenco Worker
 ├ WRM Watchdog Script
 └ UDP Broadcast
```

Manager node runs:

```id="s8pqqn"
Manager Node
 ├ Flamenco Manager
 ├ Flamenco Worker
 ├ WRM Watchdog Script
 └ Tray UI
```

Nodes communicate using **UDP broadcast** across the LAN.

No central control server is required.

---

# Requirements

* Windows
* PowerShell 5+

Flamenco worker and manager:

https://flamenco.blender.org

GPU monitoring requires:

* NVIDIA GPU
* NVIDIA drivers with `nvidia-smi`

---

# Installation Guide

### 1. Prerequisites
Before setting up the manager/worker scripts:
*   Follow the official [Flamenco Quickstart Guide](https://flamenco.blender.org).
*   **Firewall**: Ensure inbound and outbound rules are open for the required ports on all machines. (Default: **Port 25565**).
*   **Auto-Login**: Configure Windows to bypass the login screen so nodes resume automatically after a restart.

### 2. File Placement
Place the script and its icon in the same directory as your Flamenco executables.

**Example Structure:**
```text
rendernode/
 ├─ WatchdogRenderfarmManager.ps1
 ├─ flamenco-worker.exe
 ├─ flamenco-manager.exe
 └─ wrm_icon.ico
```

### 3. Configure Windows Auto-Start
To ensure the manager and workers start automatically on boot:

1. Press `Win + R`, type **`shell:startup`**, and hit Enter to open your Startup folder.
2. Right-click inside the folder and select **New > Shortcut**.
3. In the location box, paste the appropriate command (replace `Z:\path\to\` with your actual file path):

**For Workers:**
```powershell
powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "Z:\path\to\WatchdogRenderfarmManager.ps1"
```

**For the Manager:**
```powershell
powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "Z:\path\to\WatchdogRenderfarmManager.ps1" -Manager
```

---

## 🛠️ Troubleshooting

### Script Fails to Run (Execution Policy)
If you see an error stating "scripts are disabled on this system," the shortcut's `-ExecutionPolicy Bypass` flag should handle it. However, if it still fails:
*   **Manual Fix**: Open PowerShell as Administrator and run: `Set-ExecutionPolicy RemoteSigned -Scope LocalMachine`.
*   **Unblock File**: Right-click your `.ps1` file, select **Properties**, and check the **Unblock** box at the bottom.

### Icon Not Visible in System Tray
*   **Hidden Icons**: Windows often hides new tray icons. Click the **^** arrow in your taskbar and drag the icon onto the main taskbar area to keep it visible.
*   **Missing Icon File**: Ensure `wrm_icon.ico` is in the exact folder specified in your script. If the file is missing, the script may fail to initialize the tray icon.

### Connection Issues (Worker cannot find Manager)
*   **Port Blocked**: Verify that **Port 25565** is allowed through both Windows Firewall and any third-party antivirus software.
*   **IP Address**: If auto-discovery fails, you may need to manually point the worker to the manager's IP in the `flamenco-worker.cfg` file.

### Script Starts but Window Stays Visible
*   Ensure the shortcut command includes the `-WindowStyle Hidden` flag. If it still pops up, ensure there are no `Read-Host` or interactive prompts in your script that force the window to stay open for user input.

# Configuration

Important settings in the script:

```id="71i40j"
$BroadcastPort = 25565
$CheckIntervalSeconds = 5
$CrashRestartThreshold = 3
$WeeklyRestartDay = Sunday
$WeeklyRestartHour = 12
```

---

# Network

WRM uses **UDP broadcast**.

```id="t2nbc3"
Port: 25565
Protocol: UDP
```

All nodes must be on the **same LAN**.

---

# Log File

Each node writes a log file:

```id="69k6w3"
FlamencoWatchdog.log
```

Example:

```id="0wh9kr"
2026-03-10 12:21:04 - (Render03) Worker crashed. Restart #1
2026-03-10 12:21:05 - (Render03) Worker started
```

---

# Safety Features

* Prevents duplicate worker processes
* Detects crashed processes
* Automatic restart handling
* Prevents runaway restart loops
* Scheduled node reboots

---

# Why This Exists

Flamenco runs in a **console window** on all render machines.

For small-scale teams where each user's computer is also used as a render node, it becomes annoying to have a console window **open or minimized all the time**, creating clutter on the taskbar.

Flamenco also does not handle situations where:

* a worker crashes
* the manager crashes
* a render node silently fails

If a node crashes, nobody except the render farm manager knows about it. Users would have to manually open the **Flamenco web interface** to check the node status.

Long renders can also take longer if machines have been running for extended periods without restarting.

WRM solves these problems by:

* running Flamenco in the background
* monitoring worker and manager processes
* automatically restarting crashed services
* notifying other nodes when failures occur
* restarting systems on a weekly schedule

WRM does all of this **without requiring specific Flamenco versions**.

Technically, WRM can monitor **any program that needs to stay running**. Only the worker and manager executable paths need to be changed.
