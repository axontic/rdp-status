param(
    [switch]$Once,
    [switch]$InventoryOnly,
    [switch]$DebugMode
)

$script:debugStartedAt = Get-Date
function Write-DebugLog {
    param([Parameter(Mandatory)][string]$Message)
    if (-not $DebugMode) { return }
    $elapsed = ((Get-Date) - $script:debugStartedAt).TotalSeconds
    Write-Host ("[DEBUG +{0:N3}s] {1}" -f $elapsed, $Message) -ForegroundColor DarkGray
}

Write-DebugLog "Script started (PowerShell $($PSVersionTable.PSVersion), PID=$PID)"

# Server URL - optionally override the production URL with an environment variable
$serverUrl  = if ($env:RDP_STATUS_SERVER_URL) { $env:RDP_STATUS_SERVER_URL } else { "https://rdp-status.we4it.com/api/status" }
$vm         = $env:COMPUTERNAME
$timeoutS   = 2
$heartbeatS = 60
$quiet      = -not ($Once -or $InventoryOnly)

# Collect IP and FQDN once at startup
Write-DebugLog 'Starting default-route and IPv4 lookup'
$clientIp   = try {
    (Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex (
        Get-NetRoute -DestinationPrefix '0.0.0.0/0' |
        Sort-Object RouteMetric |
        Select-Object -First 1 -ExpandProperty ifIndex
    ) | Select-Object -First 1 -ExpandProperty IPAddress)
} catch {
    Write-DebugLog "IPv4 lookup failed: $($_.Exception.Message)"
    $null
}
Write-DebugLog "IPv4 lookup completed: $clientIp"
Write-DebugLog 'Starting computer-name DNS lookup'
$clientFqdn = try { [System.Net.Dns]::GetHostEntry($env:COMPUTERNAME).HostName } catch {
    Write-DebugLog "Computer-name DNS lookup failed: $($_.Exception.Message)"
    $null
}
Write-DebugLog "Computer-name DNS lookup completed: $clientFqdn"
Write-DebugLog 'Starting reverse DNS lookup'
$clientRdns = try { [System.Net.Dns]::GetHostEntry($clientIp).HostName } catch {
    Write-DebugLog "Reverse DNS lookup failed: $($_.Exception.Message)"
    $null
}
Write-DebugLog "Reverse DNS lookup completed: $clientRdns"
Write-DebugLog 'Starting DNS A-record lookup'
$clientDnsA = try {
    (Resolve-DnsName -Name $env:COMPUTERNAME -Type A -ErrorAction Stop |
        Where-Object { $_.Type -eq 'A' } |
        Select-Object -First 1).IPAddress
} catch {
    Write-DebugLog "DNS A-record lookup failed: $($_.Exception.Message)"
    $null
}
Write-DebugLog "DNS A-record lookup completed: $clientDnsA"

if (-not $quiet) {
    Write-Host ("[INIT] VM=$vm  IP=$clientIp  FQDN=$clientFqdn  rDNS=$clientRdns  DNS-A=$clientDnsA") -ForegroundColor Cyan
}

$considerDisconnectedAsBusy = $false  # $true => "Disconnected" counts as occupied
$consoleCountsAsBusy        = $false  # << Do NOT count console as occupied

$script:considerDisconnectedAsBusy = $considerDisconnectedAsBusy
$script:consoleCountsAsBusy        = $consoleCountsAsBusy

$ProgressPreference = 'SilentlyContinue'
$script:warnedInvalidUrl = $false
$script:machineInventory = $null
$script:lastSendSucceeded = $false

function Get-MachineInventory {
    Write-DebugLog 'Machine inventory collection started'
    $ramGb = $null
    $os = $null
    try {
        Write-DebugLog 'Querying Win32_ComputerSystem for RAM'
        $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        if ($computer.TotalPhysicalMemory) {
            $ramGb = [math]::Round([double]$computer.TotalPhysicalMemory / 1GB, 1)
        }
        Write-DebugLog "RAM query completed: $ramGb GB"
    } catch {
        Write-DebugLog "RAM query failed: $($_.Exception.Message)"
    }

    try {
        Write-DebugLog 'Reading Windows version registry values'
        $windows = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        Write-DebugLog 'Querying Win32_OperatingSystem'
        $operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
        $build = [string]$windows.CurrentBuildNumber
        if ($null -ne $windows.UBR) { $build = "$build.$($windows.UBR)" }

        Write-DebugLog 'Starting Get-HotFix (this can be slow on some systems)'
        $lastUpdate = Get-HotFix -ErrorAction SilentlyContinue |
            Where-Object { $_.InstalledOn } |
            Sort-Object InstalledOn -Descending |
            Select-Object -First 1
        Write-DebugLog "Get-HotFix completed: $($lastUpdate.HotFixID)"
        $lastUpdateDate = $null
        if ($lastUpdate -and $lastUpdate.InstalledOn) {
            try {
                $lastUpdateDate = ([datetime]$lastUpdate.InstalledOn).ToString('yyyy-MM-dd')
            } catch {
                $lastUpdateDate = [string]$lastUpdate.InstalledOn
            }
        }

        $os = [ordered]@{
            productName       = if ($operatingSystem.Caption) { $operatingSystem.Caption } else { $windows.ProductName }
            displayVersion    = $windows.DisplayVersion
            build             = $build
            lastUpdateId      = if ($lastUpdate) { $lastUpdate.HotFixID } else { $null }
            lastUpdateDate    = $lastUpdateDate
            lastUpdateDetails = if ($lastUpdate) { $lastUpdate.Description } else { $null }
        }
        Write-DebugLog "Windows inventory completed: $($os.productName), $($os.displayVersion), build $($os.build)"
    } catch {
        Write-DebugLog "Windows inventory failed: $($_.Exception.Message)"
    }

    $outlook = $null
    Write-DebugLog 'Searching standard Outlook executable paths'
    $outlookPaths = @(
        "$env:ProgramFiles\Microsoft Office\root\Office16\OUTLOOK.EXE",
        "${env:ProgramFiles(x86)}\Microsoft Office\root\Office16\OUTLOOK.EXE",
        "$env:ProgramFiles\Microsoft Office\Office16\OUTLOOK.EXE",
        "${env:ProgramFiles(x86)}\Microsoft Office\Office16\OUTLOOK.EXE"
    )
    $outlookPath = $outlookPaths |
        Where-Object { $_ -and (Test-Path -LiteralPath $_) } |
        Select-Object -First 1
    Write-DebugLog "Outlook path search completed: $outlookPath"

    if ($outlookPath) {
        try {
            Write-DebugLog 'Reading Outlook executable version'
            $versionInfo = (Get-Item -LiteralPath $outlookPath -ErrorAction Stop).VersionInfo
            $fullVersion = $versionInfo.ProductVersion
            if (-not $fullVersion) { $fullVersion = $versionInfo.FileVersion }
            $build = $fullVersion -replace '^16\.0\.', ''
            $buildFamily = ($build -split '\.')[0]

            # Office does not expose labels such as "2408" as an executable
            # version. Known labels can be mapped by build family or supplied
            # with RDP_STATUS_OUTLOOK_RELEASE (for example, 2408).
            $releaseByBuild = @{
                '17932' = '2408'
                '14334' = '2108'
            }
            $release = if ($env:RDP_STATUS_OUTLOOK_RELEASE) {
                $env:RDP_STATUS_OUTLOOK_RELEASE.Trim()
            } else {
                $releaseByBuild[$buildFamily]
            }
            $displayName = if ($release -and $release.Length -ge 2) {
                "Outlook $($release.Substring(0, 2))"
            } else {
                'Outlook'
            }

            $outlook = [ordered]@{
                displayName      = $displayName
                release          = $release
                build            = $build
                fullVersion      = $fullVersion
            }
            Write-DebugLog "Outlook inventory completed: $displayName, build $build"
        } catch {
            Write-DebugLog "Outlook inventory failed: $($_.Exception.Message)"
        }
    }

    Write-DebugLog 'Machine inventory collection completed'
    return [ordered]@{
        ramGb   = $ramGb
        os      = $os
        outlook = $outlook
    }
}

$wcTypeName = 'Mbb.Net.WebClientWithTimeout'
if (-not ($wcTypeName -as [type])) {
    Write-DebugLog 'Compiling HTTP timeout helper'
    Add-Type -TypeDefinition @"
using System;
using System.Net;
using System.Text;

namespace Mbb.Net {
    public class WebClientWithTimeout : WebClient {
        public int Timeout { get; set; }
        public WebClientWithTimeout() { this.Timeout = 2000; } // ms
        protected override WebRequest GetWebRequest(Uri address) {
            var req = base.GetWebRequest(address);
            if (req != null) {
                req.Timeout = this.Timeout;
                var http = req as HttpWebRequest;
                if (http != null) {
                    http.ReadWriteTimeout = this.Timeout;
                    http.KeepAlive = false;
                }
            }
            return req;
        }
    }
}
"@ -Language CSharp
    Write-DebugLog 'HTTP timeout helper compiled'
}

function New-RestClient {
    param([int]$TimeoutMs)
    $wc = New-Object $wcTypeName
    $wc.Timeout = $TimeoutMs
    $wc.Headers['Content-Type'] = 'application/json'
    $wc.Encoding = [System.Text.Encoding]::UTF8
    try { $wc.Proxy = $null } catch {}
    return $wc
}

function Test-ServerUrlValid {
    param([string]$Url)
    try {
        $outUri = $null
        if ([Uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$outUri)) { return $true }
        return $false
    } catch { return $false }
}

$wtsTypeName = 'Mbb.Net.Wts'
if (-not ($wtsTypeName -as [type])) {
    Write-DebugLog 'Compiling Windows Terminal Services helper'
    Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace Mbb.Net {
    public class Wts {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
        private struct WTS_SESSION_INFO {
            public int SessionId;
            [MarshalAs(UnmanagedType.LPTStr)]
            public string pWinStationName;
            public WTS_CONNECTSTATE_CLASS State;
        }

        private enum WTS_CONNECTSTATE_CLASS {
            WTSActive, WTSConnected, WTSConnectQuery, WTSShadow, WTSDisconnected, WTSIdle, WTSListen, WTSReset, WTSDown, WTSInit
        }

        private enum WTS_INFO_CLASS {
            WTSInitialProgram, WTSApplicationName, WTSWorkingDirectory, WTSOEMId, WTSSessionId, WTSUserName,
            WTSWinStationName, WTSDomainName, WTSConnectState, WTSClientBuildNumber, WTSClientName, WTSClientDirectory,
            WTSClientProductId, WTSClientHardwareId, WTSClientAddress, WTSClientDisplay, WTSClientProtocolType
        }

        [DllImport("Wtsapi32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        private static extern bool WTSEnumerateSessions(IntPtr hServer, int Reserved, int Version, out IntPtr ppSessionInfo, out int pCount);

        [DllImport("Wtsapi32.dll")]
        private static extern void WTSFreeMemory(IntPtr pMemory);

        [DllImport("Wtsapi32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern bool WTSQuerySessionInformation(IntPtr hServer, int sessionId, WTS_INFO_CLASS wtsInfoClass, out IntPtr ppBuffer, out int pBytesReturned);

        public class SessionInfo {
            public int SessionId;
            public string StationName;
            public string State;          // "Active" | "Connected" | "Disconnected" | "Unknown"
            public string User;           // DOMAIN\user (if available)
            public string Domain;
            public int ProtocolType;      // 0 = Console, 2 = RDP (typical)
        }

        public static SessionInfo[] EnumSessions() {
            IntPtr p = IntPtr.Zero;
            int count = 0;
            var list = new List<SessionInfo>();
            try {
                if (!WTSEnumerateSessions(IntPtr.Zero, 0, 1, out p, out count) || p == IntPtr.Zero || count <= 0) {
                    return list.ToArray();
                }
                int dataSize = Marshal.SizeOf(typeof(WTS_SESSION_INFO));
                for (int i = 0; i < count; i++) {
                    IntPtr itemPtr = new IntPtr(p.ToInt64() + i * dataSize);
                    var si = (WTS_SESSION_INFO)Marshal.PtrToStructure(itemPtr, typeof(WTS_SESSION_INFO));
                    var info = new SessionInfo();
                    info.SessionId = si.SessionId;
                    info.StationName = si.pWinStationName ?? "";

                    // Map state precisely
                    info.State = MapState(si.State);

                    string user = QueryString(si.SessionId, WTS_INFO_CLASS.WTSUserName);
                    string domain = QueryString(si.SessionId, WTS_INFO_CLASS.WTSDomainName);
                    info.Domain = domain ?? "";
                    if (!string.IsNullOrEmpty(domain) && !string.IsNullOrEmpty(user)) info.User = domain + "\\" + user;
                    else if (!string.IsNullOrEmpty(user)) info.User = user;
                    else info.User = "";

                    info.ProtocolType = QueryUShort(si.SessionId, WTS_INFO_CLASS.WTSClientProtocolType);
                    list.Add(info);
                }
            } finally {
                if (p != IntPtr.Zero) WTSFreeMemory(p);
            }
            return list.ToArray();
        }

        private static string MapState(WTS_CONNECTSTATE_CLASS st) {
            switch (st) {
                case WTS_CONNECTSTATE_CLASS.WTSActive:
                    return "Active";
                case WTS_CONNECTSTATE_CLASS.WTSConnected:
                    return "Connected";
                case WTS_CONNECTSTATE_CLASS.WTSDisconnected:
                    return "Disconnected";
                default:
                    return "Unknown";
            }
        }

        private static string QueryString(int sessionId, WTS_INFO_CLASS cls) {
            IntPtr buf;
            int bytes;
            if (!WTSQuerySessionInformation(IntPtr.Zero, sessionId, cls, out buf, out bytes) || buf == IntPtr.Zero || bytes <= 2)
                return null;
            try {
                return Marshal.PtrToStringUni(buf);
            } finally {
                WTSFreeMemory(buf);
            }
        }

        private static int QueryUShort(int sessionId, WTS_INFO_CLASS cls) {
            IntPtr buf;
            int bytes;
            if (!WTSQuerySessionInformation(IntPtr.Zero, sessionId, cls, out buf, out bytes) || buf == IntPtr.Zero || bytes < 2) {
                return -1;
            }
            try {
                return (int)(ushort)Marshal.ReadInt16(buf);
            } finally {
                WTSFreeMemory(buf);
            }
        }
    }
}
"@ -Language CSharp
    Write-DebugLog 'Windows Terminal Services helper compiled'
}

function Get-SessionSnapshot {
    Write-DebugLog 'Session snapshot started'
    $sessions = @()

    try {
        Write-DebugLog 'Calling WTSEnumerateSessions'
        $wtsSessions = [Mbb.Net.Wts]::EnumSessions()
        Write-DebugLog "WTSEnumerateSessions completed: $($wtsSessions.Count) session(s)"
    } catch {
        Write-DebugLog "WTSEnumerateSessions failed: $($_.Exception.Message)"
        $wtsSessions = @()
    }

    foreach ($s in $wtsSessions) {
        $type =
            if ($s.ProtocolType -eq 2) { 'rdp' }
            elseif ($s.ProtocolType -eq 0) { 'console' }
            elseif (($s.StationName -as [string]).ToLower().Contains('rdp')) { 'rdp' }
            elseif (($s.StationName -as [string]).ToLower().Contains('console')) { 'console' }
            else { 'other' }

        $state = $s.State

        $sessions += [PSCustomObject]@{
            user       = $s.User
            sessionId  = $s.SessionId
            session    = $s.StationName
            type       = $type
            state      = $state
        }
    }

    $rdpBusy     = $sessions | Where-Object { $_.type -eq 'rdp'     -and $_.state -eq 'Active' }
    $consoleBusy = $sessions | Where-Object { $_.type -eq 'console' -and $_.state -ne 'Disconnected' }
    $rdpDisc     = $sessions | Where-Object { $_.type -eq 'rdp'     -and $_.state -eq 'Disconnected' }

    $inUseByRdp     = ($rdpBusy.Count -gt 0)
    $inUseByConsole = ($script:consoleCountsAsBusy -and ($consoleBusy.Count -gt 0))
    $inUse          = $inUseByRdp -or $inUseByConsole
    $hasDiscOnly    = (-not $inUse) -and ($rdpDisc.Count -gt 0)

    if ($inUse) {
        $status = 'in_use'
    } elseif ($hasDiscOnly -and -not $script:considerDisconnectedAsBusy) {
        $status = 'idle_with_disconnected'
    } elseif ($hasDiscOnly -and  $script:considerDisconnectedAsBusy) {
        $status = 'in_use'
    } else {
        $status = 'free'
    }

    Write-DebugLog "Session snapshot completed: status=$status, sessions=$($sessions.Count)"
    return [PSCustomObject]@{
        Sessions  = $sessions
        Occupancy = [PSCustomObject]@{
            status                     = $status
            rdp_active_count           = $rdpBusy.Count
            rdp_disconnected_count     = $rdpDisc.Count
            console_active_count       = $consoleBusy.Count
            considerDisconnectedAsBusy = $script:considerDisconnectedAsBusy
            consoleCountsAsBusy        = $script:consoleCountsAsBusy
        }
    }
}

function Get-SnapshotSignature {
    param($snapshot)
    if ($null -eq $snapshot -or $null -eq $snapshot.Sessions) { return '' }
    $rows = $snapshot.Sessions | Sort-Object type, state, user, sessionId | ForEach-Object {
        "$($_.type)|$($_.state)|$($_.user)|$($_.sessionId)"
    }
    return ($rows -join ';')
}

function Send-Event {
    param(
        [Parameter(Mandatory)][ValidateSet(
            'vm_online','heartbeat',
            'rdp_connect','rdp_disconnect','rdp_logon','rdp_logoff',
            'local_connect','local_disconnect','local_logon','local_logoff',
            'session_lock','session_unlock',
            'state_snapshot'
        )][string]$Event,
        [string]$User,
        [int]$SessionId = -1
    )

    Write-DebugLog "Send-Event started: event=$Event, url=$serverUrl"
    if (-not (Test-ServerUrlValid $serverUrl)) {
        $script:lastSendSucceeded = $false
        if (-not $script:warnedInvalidUrl -and -not $quiet) {
            Write-Warning "Ungültige Server-URL: $serverUrl (Ereignisse werden nicht gesendet, Skript läuft weiter)"
        }
        $script:warnedInvalidUrl = $true
        return
    }

    Write-DebugLog 'Collecting session snapshot for payload'
    $snap = Get-SessionSnapshot
    $userText = if ($null -ne $User) { $User } else { '' }

    $payload = [ordered]@{
        vm        = $vm
        ip        = $clientIp
        fqdn      = $clientFqdn
        rdns      = $clientRdns
        dnsA      = $clientDnsA
        ts        = (Get-Date).ToString('o')
        event     = $Event
        user      = $userText
        sessionId = $SessionId
        inventory = $script:machineInventory
        occupancy = $snap.Occupancy
        sessions  = @(
            $snap.Sessions | ForEach-Object {
                [ordered]@{
                    user      = $_.user
                    sessionId = $_.sessionId
                    type      = $_.type
                    state     = $_.state
                }
            }
        )
    }

    try {
        $script:lastSendSucceeded = $false
        Write-DebugLog 'Serializing payload to JSON'
        $json    = $payload | ConvertTo-Json -Depth 6
        Write-DebugLog "Payload serialized: $($json.Length) character(s)"
        Write-Host ("[SEND] $Event  ip=$clientIp  fqdn=$clientFqdn") -ForegroundColor Yellow
        Write-DebugLog "Starting HTTP POST (timeout=$($timeoutS * 1000)ms)"
        $wc      = New-RestClient -TimeoutMs ($timeoutS * 1000)
        [void]$wc.UploadString($serverUrl, 'POST', $json)
        $script:lastSendSucceeded = $true
        Write-DebugLog 'HTTP POST completed successfully'

        if (-not $quiet) {
            Write-Output ("[{0}] Gesendet: {1} {2}" -f (Get-Date -Format "HH:mm:ss"), $Event, $userText)
        }
    } catch {
        Write-DebugLog "HTTP POST failed: $($_.Exception.Message)"
        if (-not $quiet) {
            Write-Warning ("[{0}] Sendefehler: {1} ({2})" -f (Get-Date -Format "HH:mm:ss"), $Event, $_.Exception.Message)
        }
        # never exit
    }
}

function Map-And-Send {
    param([int]$SessionEventType, [int]$SessionId)

    $snap = Get-SessionSnapshot
    $sess = $null
    if ($snap -and $snap.Sessions) {
        $sess = $snap.Sessions | Where-Object { $_.sessionId -eq $SessionId } | Select-Object -First 1
    }
    $user = ''
    if ($sess) { $user = $sess.user }

    switch ($SessionEventType) {
        1 { Send-Event -Event 'local_connect'    -User $user -SessionId $SessionId }   # ConsoleConnect
        2 { Send-Event -Event 'local_disconnect' -User $user -SessionId $SessionId }   # ConsoleDisconnect
        3 { Send-Event -Event 'rdp_connect'      -User $user -SessionId $SessionId }   # RemoteConnect
        4 { Send-Event -Event 'rdp_disconnect'   -User $user -SessionId $SessionId }   # RemoteDisconnect
        5 { # Logon
            if     ($sess -and $sess.type -eq 'rdp')     { Send-Event -Event 'rdp_logon'    -User $user -SessionId $SessionId }
            elseif ($sess -and $sess.type -eq 'console') { Send-Event -Event 'local_logon'  -User $user -SessionId $SessionId }
            else { Send-Event -Event 'state_snapshot' -User $user -SessionId $SessionId }
        }
        6 { # Logoff
            if     ($sess -and $sess.type -eq 'rdp')     { Send-Event -Event 'rdp_logoff'   -User $user -SessionId $SessionId }
            elseif ($sess -and $sess.type -eq 'console') { Send-Event -Event 'local_logoff' -User $user -SessionId $SessionId }
            else { Send-Event -Event 'state_snapshot' -User $user -SessionId $SessionId }
        }
        7 { Send-Event -Event 'session_lock'     -User $user -SessionId $SessionId }   # Lock
        8 { Send-Event -Event 'session_unlock'   -User $user -SessionId $SessionId }   # Unlock
        default { Send-Event -Event 'state_snapshot' -User $user -SessionId $SessionId }
    }
}

Write-DebugLog 'Starting initial machine inventory collection'
$script:machineInventory = Get-MachineInventory
Write-DebugLog 'Initial machine inventory is ready'
if ($Once -or $InventoryOnly) {
    Write-Output 'Collected machine inventory:'
    Write-Output ($script:machineInventory | ConvertTo-Json -Depth 5)
}

if ($InventoryOnly) {
    Write-DebugLog 'InventoryOnly requested; exiting'
    exit 0
}

Write-DebugLog 'Sending initial vm_online event'
Send-Event -Event 'vm_online' -User '' -SessionId -1

if ($Once) {
    if ($script:lastSendSucceeded) {
        Write-Output "One-shot status report successfully sent to $serverUrl"
        exit 0
    }
    Write-Error "One-shot status report could not be sent to $serverUrl"
    exit 1
}

$sessionEventRegistered = $false
try {
    Write-DebugLog 'Registering Win32_SessionChangeEvent subscription'
    Unregister-Event -SourceIdentifier 'SessionEvents' -ErrorAction SilentlyContinue | Out-Null
    $null = Register-WmiEvent -Class Win32_SessionChangeEvent -SourceIdentifier 'SessionEvents'
    $sessionEventRegistered = $true
    Write-DebugLog 'Session event subscription registered; entering event loop'
    if (-not $quiet) { Write-Output "SessionChange-Events abonniert." }
} catch {
    Write-DebugLog "Session event registration failed: $($_.Exception.Message); using polling"
    if (-not $quiet) { Write-Warning "SessionChange-Events nicht verfügbar, nutze Polling-Fallback." }
    $sessionEventRegistered = $false
}

$nextHeartbeat = (Get-Date).AddSeconds($heartbeatS)
$reSubAt = (Get-Date).AddMinutes(30)   # optional auto re-subscribe

if ($sessionEventRegistered) {
    while ($true) {
        $evtProcessed = $false
        try {
            $evt = Wait-Event -SourceIdentifier 'SessionEvents' -Timeout 5
            if ($null -ne $evt) {
                $t   = [int]$evt.SourceEventArgs.NewEvent.SessionEventType
                $sid = [int]$evt.SourceEventArgs.NewEvent.SessionId
                Map-And-Send -SessionEventType $t -SessionId $sid
                Remove-Event -EventIdentifier $evt.EventIdentifier | Out-Null
                $evtProcessed = $true
            }

            # Optional: re-subscribe every 30 min (robust against WMI hangs)
            if ((Get-Date) -ge $reSubAt) {
                try {
                    Unregister-Event -SourceIdentifier 'SessionEvents' -ErrorAction SilentlyContinue | Out-Null
                    $null = Register-WmiEvent -Class Win32_SessionChangeEvent -SourceIdentifier 'SessionEvents'
                } catch { }
                $reSubAt = (Get-Date).AddMinutes(30)
            }
        } catch {
            Start-Sleep -Milliseconds 300
        }

        if ((Get-Date) -ge $nextHeartbeat) {
            Send-Event -Event 'heartbeat' -User '' -SessionId -1
            $nextHeartbeat = (Get-Date).AddSeconds($heartbeatS)
        }
    }
}

else {
    Write-DebugLog 'Entering polling fallback loop'
    $prevSnap = Get-SessionSnapshot
    $prevSig  = Get-SnapshotSignature -snapshot $prevSnap
    while ($true) {
        Start-Sleep -Seconds 2
        try {
            $currSnap = Get-SessionSnapshot
            $currSig  = Get-SnapshotSignature -snapshot $currSnap
            if ($prevSig -ne $currSig) {
                Send-Event -Event 'state_snapshot' -User '' -SessionId -1
                $prevSig = $currSig
            }
        } catch {
            if (-not $quiet) {
                Write-Output ("[{0}] Polling-Fallback: Ausnahmesituation, weiter..." -f (Get-Date -Format "HH:mm:ss"))
            }
        } finally {
            # <<< Heartbeat ALWAYS >>>
            if ((Get-Date) -ge $nextHeartbeat) {
                Send-Event -Event 'heartbeat' -User '' -SessionId -1
                $nextHeartbeat = (Get-Date).AddSeconds($heartbeatS)
            }
        }
    }
}

