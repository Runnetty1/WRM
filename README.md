<p align="center">
  <img src="WRM_white.png" alt="WRM LOGO" width="400">
</p>

# Watchdog Renderfarm Manager (WRM)

![PowerShell](https://img.shields.io/badge/PowerShell-5.0+-blue)
![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey)
![License](https://img.shields.io/badge/License-MIT-green)
![Status](https://img.shields.io/badge/Project-Stable-brightgreen)


A lightweight **PowerShell render node watchdog and cluster manager** designed for **Flamenco render farms**.


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

# Installation

Place the script and icon in the same folder as the Flamenco executables. 

Example:

```id="w7p3ht"
rendernode/
 ├ WatchdogRenderfarmManager.ps1
 ├ flamenco-worker.exe
 ├ flamenco-manager.exe
 └ wrm_icon.ico
```

---

# Usage

### Worker Node

Run:

```id="wnaz4u"
powershell -ExecutionPolicy Bypass -File WatchdogRenderfarmManager.ps1
```

or

```id="q5u1yp"
WatchdogRenderfarmManager.ps1 -Mode Worker
```

---

### Manager Node

Run:

```id="wsuxt1"
WatchdogRenderfarmManager.ps1 -Mode Manager
```

This starts:

* Flamenco Worker
* Flamenco Manager
* WRM monitoring tray

---

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
