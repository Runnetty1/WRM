param(
    [ValidateSet("Worker","Manager")]
    [string]$Mode = "Worker"
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ================= CONFIG =================
$BaseDir = $PSScriptRoot
$watchdog = "Watchdog Renderfarm Manager"
$WorkerPath  = Join-Path $BaseDir "flamenco-worker.exe"
$ManagerPath = Join-Path $BaseDir "flamenco-manager.exe"
$LogFile     = Join-Path $BaseDir "Watchdog.log"
$IconPath = "Z:\wrm.ico"
$CheckIntervalSeconds = 5
$CrashRestartThreshold = 3
$WeeklyRestartDay = "Sunday"
$WeeklyRestartHour = 12
$BroadcastPort = 25565
$BroadcastIP = "255.255.255.255"
$NodeStaleSeconds = 20
$StatusBroadcastEveryTicks = 1
# ===========================================
$Hostname = $env:COMPUTERNAME
$global:Nodes = @{}
$global:AnnouncedNodes = @{}
$global:WorkerCrashCount = 0
$global:ManagerCrashCount = 0
$global:LastNodeMenuSignature = ""
$global:TickCounter = 0

function Write-Log($message) {
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Add-Content -Path $LogFile -Value "$timestamp - ($Hostname) [$Mode] $message"
}
function Get-NodeMenuSignature {
    $parts = foreach ($name in ($global:Nodes.Keys | Sort-Object)) {
        $n = $global:Nodes[$name]
        "{0}|{1}|{2}" -f $name, $n.worker, $n.manager
    }
    return ($parts -join ";")
}
function Restart-ComputerSafe($reason) {

    Write-Log "SYSTEM RESTART TRIGGERED: $reason"
    Send-Event "RESTARTING" $reason
    $icon.ShowBalloonTip(
        5000,
        $watchdog,
        "System restarting: $reason",
        [System.Windows.Forms.ToolTipIcon]::None
    )

    Start-Sleep 5

    shutdown.exe /r /t 5 /f
}

function Start-App($Path) {

    if (!(Test-Path $Path)) {
        Write-Log "ERROR: File not found: $Path"
        return
    }

    $name = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $dir  = Split-Path $Path -Parent

    if (Get-Process -Name $name -ErrorAction SilentlyContinue) {
        return
    }

    try {
        $proc = Start-Process `
            -FilePath $Path `
            -WorkingDirectory $dir `
            -WindowStyle Hidden `
            -PassThru `
            -ErrorAction Stop

        Start-Sleep -Milliseconds 500

        if ($proc.HasExited) {
            Write-Log "ERROR: $name exited immediately (code $($proc.ExitCode))"
        } else {
            Write-Log "$name started (PID: $($proc.Id))"
        }
    }
    catch {
        Write-Log "ERROR starting $name : $_"
    }
}
function Get-GPUUsage {

    try {
        $gpu = & nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>$null

        if ($gpu) {
            $value = ($gpu | Select-Object -First 1).Trim()
            return [int]$value
        }
    }
    catch {}

    return 0
}
function Stop-App($Path) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $proc = Get-Process -Name $name -ErrorAction SilentlyContinue
    if ($proc) {
        $proc | ForEach-Object { $_.Kill() }
        Write-Log "$name stopped manually"
    }
}
function Show-Notification($title, $text)
{
    $icon.ShowBalloonTip(
        5000,
        $title,
        $text,
        [System.Windows.Forms.ToolTipIcon]::None
    )
}
function Test-Running($Path) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    return Get-Process -Name $name -ErrorAction SilentlyContinue
}

# Initial Start
Start-App $WorkerPath
if ($Mode -eq "Manager") {
    Start-App $ManagerPath
}

# ================= Tray Setup =================
$icon = New-Object System.Windows.Forms.NotifyIcon

if (Test-Path $IconPath) {
    $icon.Icon = New-Object System.Drawing.Icon($IconPath)
}
else {
    Write-Log "WARNING: Icon file not found. Using default icon."
    $icon.Icon = [System.Drawing.SystemIcons]::Application
}
$icon.Visible = $true
$icon.Text = "$watchdog - $Mode"

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$modeItem = $menu.Items.Add("$Hostname")
$modeItem = $menu.Items.Add("Mode: $Mode")
$modeItem.Enabled = $false

$workerItem = $menu.Items.Add("Worker: Checking...")
$workerItem.Enabled = $false

if ($Mode -eq "Manager") {
    $managerItem = $menu.Items.Add("Manager: Checking...")
    $managerItem.Enabled = $false
}
$menu.Items.Add("-") | Out-Null
#get the broadcasting pcs on the network and display them in the menu
$networkItem = $menu.Items.Add("Network Nodes")
$networkItem.Enabled = $true

#if nodes are broadcasting, add them to the menu
if ($global:Nodes.Count -eq 0) {
    $noNodesItem = $networkItem.DropDownItems.Add("No nodes detected")
    $noNodesItem.Enabled = $false
}



$menu.Items.Add("-") | Out-Null

$restartItem = $menu.Items.Add("Restart All")
$restartItem.Add_Click({
    Stop-App $WorkerPath
    if ($Mode -eq "Manager") { Stop-App $ManagerPath }
    Start-Sleep -Milliseconds 500
    Start-App $WorkerPath
    if ($Mode -eq "Manager") { Start-App $ManagerPath }
})

$logItem = $menu.Items.Add("Open Log")
$logItem.Add_Click({
    if (Test-Path $LogFile) {
        Start-Process notepad.exe $LogFile
    }
})

$menu.Items.Add("-") | Out-Null

$exitItem = $menu.Items.Add("Exit")
$exitItem.Add_Click({
    Stop-App $WorkerPath
    if ($Mode -eq "Manager") { Stop-App $ManagerPath }
    $icon.Visible = $false
    try { $udpListener.Close() } catch {}
    try { $udpSender.Close() } catch {}
    foreach ($img in $global:StatusIconCache.Values) {
        try { $img.Dispose() } catch {}
    }
    $global:StatusIconCache.Clear()
    Write-Log "Tray manager exited"
    [System.Windows.Forms.Application]::Exit()
})

$icon.ContextMenuStrip = $menu

# -----------------------------
# UDP NETWORK
# -----------------------------

#$udpListener = New-Object System.Net.Sockets.UdpClient($BroadcastPort)
$udpListener = [System.Net.Sockets.UdpClient]::new()
$udpListener.Client.SetSocketOption(
    [System.Net.Sockets.SocketOptionLevel]::Socket,
    [System.Net.Sockets.SocketOptionName]::ReuseAddress,
    $true
)

$udpListener.Client.Bind(
    [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, $BroadcastPort)
)
$udpSender = New-Object System.Net.Sockets.UdpClient
$udpSender.EnableBroadcast = $true

$endpoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any,0)

function Send-Status
{
    $workerState = if (Test-Running $WorkerPath) { "RUN" } else { "DOWN" }

    if ($Mode -eq "Manager") {
        $managerState = if (Test-Running $ManagerPath) { "RUN" } else { "DOWN" }
    }
    else {
        $managerState = "NONE"
    }
    $currentCPU = (Get-WmiObject -Class Win32_Processor).LoadPercentage
    $currentGPUUsage = Get-GPUUsage  
    $msg = "NODE|$Hostname|$workerState|$managerState|$Mode|$currentCPU|$currentGPUUsage"
    $bytes = [Text.Encoding]::UTF8.GetBytes($msg)
    $udpSender.Send($bytes, $bytes.Length, $BroadcastIP, $BroadcastPort) | Out-Null
}
function Send-Event($type, $message)
{
    $msg = "EVENT|$Hostname|$type|$message"
    $bytes = [Text.Encoding]::UTF8.GetBytes($msg)
    $udpSender.Send($bytes, $bytes.Length, $BroadcastIP, $BroadcastPort) | Out-Null
}
function Send-RestartAll
{
    $msg = "CMD|RESTART_ALL"
    $bytes = [Text.Encoding]::UTF8.GetBytes($msg)
    $udpSender.Send($bytes,$bytes.Length,$BroadcastIP,$BroadcastPort) | Out-Null
}

function Send-RestartNode($node)
{
    $msg = "CMD|RESTART_NODE|$node"
    $bytes = [Text.Encoding]::UTF8.GetBytes($msg)
    $udpSender.Send($bytes,$bytes.Length,$BroadcastIP,$BroadcastPort) | Out-Null
}

# -----------------------------
# RECEIVE UDP + MENU REFRESH
# -----------------------------

function Receive-UdpMessages {
    while ($udpListener.Available -gt 0) {
        try {
            $data = $udpListener.Receive([ref]$endpoint)
            $msg = [Text.Encoding]::UTF8.GetString($data)
            $parts = $msg.Split("|")

            if ($parts.Count -lt 2) { continue }

            if ($parts[0] -eq "NODE" -and $parts.Count -ge 7) {
                $node = $parts[1]
                if ([string]::IsNullOrWhiteSpace($node)) { continue }
                $isNewNode = -not $global:Nodes.ContainsKey($node)

                if ($node -ne $Hostname) {
                    $global:Nodes[$node] = @{
                        time = Get-Date
                        worker = $parts[2]
                        manager = $parts[3]
                        mode = $parts[4]
                        cpu =  $parts[5] 
                        gpu =  $parts[6] 
                    }
                    if ($isNewNode -and $node -ne $Hostname) {

                        if (-not $global:AnnouncedNodes.ContainsKey($node)) {

                            Show-Notification `
                                "Render Node Online" `
                                "$node is now online"
                                

                            $global:AnnouncedNodes[$node] = $true
                        }
                    }
                }
            }
            elseif ($parts[0] -eq "CMD" -and $parts.Count -ge 2) {
                if ($parts[1] -eq "RESTART_ALL") {
                    Restart-Computer -Force
                }
                elseif ($parts[1] -eq "RESTART_NODE" -and $parts.Count -ge 3) {
                    if ($parts[2] -eq $Hostname) {
                        Restart-Computer -Force
                    }
                }
            }elseif ($parts[0] -eq "EVENT" -and $parts.Count -ge 4) {

                $node = $parts[1]
                $etype = $parts[2]
                $msgText = $parts[3]

                if ($node -ne $Hostname) {

                    $title = "Render Node Event"
                    $text = "$node : $msgText"

                    Write-Log "EVENT from $node : $msgText"
                    Show-Notification $title $text
                }
            }
        }
        catch {
            break
        }
    }
}

function Update-NodesMenu {
    $cutoff = (Get-Date).AddSeconds(-$NodeStaleSeconds)

    foreach ($name in @($global:Nodes.Keys)) {
    if ($global:Nodes[$name].time -lt $cutoff) {

        Write-Log "Node offline: $name"

        Show-Notification `
            "Render Node Offline" `
            "$name is offline"

        $global:Nodes.Remove($name)
        $global:AnnouncedNodes.Remove($name)
    }
}

    # If menu is open, skip updates this tick to avoid visible redraw flicker.
    if ($networkItem.DropDown.Visible) {
        return
    }

    $signature = Get-NodeMenuSignature
    if ($signature -eq $global:LastNodeMenuSignature) {
        return
    }

    $networkItem.DropDown.SuspendLayout()
    try {
        $networkItem.DropDownItems.Clear()
        #Adds a restart all option at the top of the menu if there are any nodes detected
        if ($global:Nodes.Count -eq 0) {
            $noNodesItem = $networkItem.DropDownItems.Add("No nodes detected")
            $noNodesItem.Enabled = $false
        }
        else {
            $restartAllItem = $networkItem.DropDownItems.Add("Restart All Nodes")
            $restartAllItem.Add_Click({
                Send-RestartAll
                Write-Log "Restart command sent to all nodes"
            })

            foreach ($name in ($global:Nodes.Keys | Sort-Object)) {
                $info = $global:Nodes[$name]
                $label = $name + " [CPU: " + $info.cpu + "%, GPU: " + $info.gpu + "%]"
                $item = $networkItem.DropDownItems.Add($label)

                if ($info.mode -eq "Manager") {
                    $item.Image = Get-NodeStatusIcon $info.worker $info.manager
                }
                else {
                     $item.Image = Get-NodeStatusIcon $info.worker "NONE"
                }
                

                $item.Tag = $name
                $item.Add_Click({
                    param($clickSender, $clickArgs)
                    $targetNode = [string]$clickSender.Tag
                    if ([string]::IsNullOrWhiteSpace($targetNode)) { return }

                    Send-RestartNode $targetNode
                    Write-Log "Restart command sent to node: $targetNode"
                })
            }
        }

        $global:LastNodeMenuSignature = $signature
    }
    finally {
        $networkItem.DropDown.ResumeLayout()
    }
}

$global:StatusIconCache = @{}

function Get-StateColor([string]$state, [bool]$isManager) {
switch ($state) {
"RUN" { return [System.Drawing.Color]::LimeGreen }
"DOWN" { return [System.Drawing.Color]::Red }
"NONE" {
if ($isManager) { return [System.Drawing.Color]::Gray }
return [System.Drawing.Color]::DarkGray
}
default { return [System.Drawing.Color]::DarkGray }
}
}

function New-NodeStatusIcon([string]$workerState, [string]$managerState) {
    $bmp = New-Object System.Drawing.Bitmap 16,16
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    $wColor = Get-StateColor $workerState $false
    $mColor = Get-StateColor $managerState $true

    $wBrush = New-Object System.Drawing.SolidBrush($wColor)
    $mBrush = New-Object System.Drawing.SolidBrush($mColor)
    $outline = New-Object System.Drawing.Pen([System.Drawing.Color]::Black, 1)

    # left dot = worker, right dot = manager
    $g.FillEllipse($wBrush, 1, 4, 6, 6)
    $g.DrawEllipse($outline, 1, 4, 6, 6)

    $g.FillEllipse($mBrush, 9, 4, 6, 6)
    $g.DrawEllipse($outline, 9, 4, 6, 6)

    $wBrush.Dispose()
    $mBrush.Dispose()
    $outline.Dispose()
    $g.Dispose()

    return $bmp
}

function Get-NodeStatusIcon([string]$workerState, [string]$managerState) {
$key = "$workerState|$managerState"
if (-not $global:StatusIconCache.ContainsKey($key)) {
$global:StatusIconCache[$key] = New-NodeStatusIcon $workerState $managerState
}
return $global:StatusIconCache[$key]
}
# ================= Monitoring Timer =================
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = $CheckIntervalSeconds * 1000

$timer.Add_Tick({
    $global:TickCounter++

    if (($global:TickCounter % $StatusBroadcastEveryTicks) -eq 0) {
        Send-Status
    }

    Receive-UdpMessages

    Update-NodesMenu

    # ---- Worker ----
    if (Test-Running $WorkerPath) {
        $workerItem.Text = "Worker: Running"
        # check if there are more processes with the same name (multiple workers), and make sure only one is running.
        $name = [System.IO.Path]::GetFileNameWithoutExtension($WorkerPath)
        $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
        if ($procs.Count -gt 1) {
            Write-Log "WARNING: Multiple worker processes detected. Killing all and restarting."
            $procs | ForEach-Object { $_.Kill() }
            Start-Sleep -Milliseconds 500
            Start-App $WorkerPath
        }
    }
    else {
        $global:WorkerCrashCount++
        $workerItem.Text = "Worker: Crashed ($global:WorkerCrashCount)"
        Write-Log "Worker crashed. Restart #$global:WorkerCrashCount"
        Send-Event "WORKER_CRASH" "Worker crashed (#$global:WorkerCrashCount)"

        if ($global:WorkerCrashCount -ge $CrashRestartThreshold) {
            Restart-ComputerSafe "Worker crashed $CrashRestartThreshold times"
        }

        Start-App $WorkerPath
    }

    # ---- Manager ----
    if ($Mode -eq "Manager") {
        if (Test-Running $ManagerPath) {
            $managerItem.Text = "Manager: Running"
        }
        else {
           $global:ManagerCrashCount++
            $managerItem.Text = "Manager: Crashed ($global:ManagerCrashCount)"
            Write-Log "Manager crashed. Restart #$global:ManagerCrashCount"
            Send-Event "MANAGER_CRASH" "Manager crashed (#$global:ManagerCrashCount)"

            if ($global:ManagerCrashCount -ge $CrashRestartThreshold) {
                Restart-ComputerSafe "Manager crashed $CrashRestartThreshold times"
            }

            Start-App $ManagerPath
        }
    }
     # ---- Restarts ----
    $now = Get-Date

    if ($now.DayOfWeek -eq $WeeklyRestartDay -and $now.Hour -eq $WeeklyRestartHour -and $now.Minute -eq 0 -and $now.Second -lt 10) {
        Restart-ComputerSafe "Weekly scheduled restart"
    }
})

$timer.Start()

Write-Log "Tray manager started in $Mode mode"
[System.Windows.Forms.Application]::Run()
