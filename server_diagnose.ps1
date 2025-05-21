# ==============================
# Windows Server Spot-Check Script
# PowerShell 5.1+ | Exports to CSV
# Author: Jason Adams
# ==============================

$ServerListFile = ".\servers.txt"
$ServiceNames = @('w32time', 'WinRM', 'EventLog', 'W3SVC') # Add/edit as needed

# Get server list (from file or prompt)
if (Test-Path $ServerListFile) {
    $ServerNames = Get-Content $ServerListFile | Where-Object { $_ -and $_.Trim() -ne "" }
    if (-not $ServerNames) { Write-Host "No servers found in $ServerListFile. Exiting." -ForegroundColor Red; exit 1 }
} else {
    $ServerNames = @(Read-Host "Enter the server name to check")
}

$Results = @()

foreach ($Server in $ServerNames) {
    Write-Host "Checking $Server..." -ForegroundColor Cyan
    $Result = [ordered]@{
        ServerName     = $Server
        Ping           = ''
        UptimeDays     = ''
        CPUUsage       = ''
        MemoryUsage    = ''
        DiskSpace      = ''
        Services       = ''
        SysErrors      = ''
        AppErrors      = ''
        IISAppPools    = ''
        IISSites       = ''
        HTTPPorts      = ''
        Status         = 'OK'
        Error          = ''
    }
    try {
        # 1. Ping test
        $Result.Ping = if (Test-Connection -ComputerName $Server -Count 1 -Quiet) { "OK" } else { "Unreachable" }
        if ($Result.Ping -eq "Unreachable") { throw "Ping failed" }

        # 2. Uptime (Last Boot Time)
        $os = Get-CimInstance -ComputerName $Server -ClassName Win32_OperatingSystem -ErrorAction Stop
        $lastBootRaw = $os.LastBootUpTime
        Write-Host "DEBUG: $Server LastBootUpTime raw value: $lastBootRaw"
        
        # Check: Not null, not empty, looks like a DMTF datetime (should be 25+ chars, all digits or '.')
        if ($null -eq $lastBootRaw -or [string]::IsNullOrWhiteSpace($lastBootRaw)) {
            throw "Unable to retrieve valid LastBootUpTime (Value: '$lastBootRaw')"
        }
        try {
            # Try parsing as [datetime] directly
            $lastBoot = [datetime]::Parse($lastBootRaw)
            $uptime = (Get-Date) - $lastBoot
            $Result.UptimeDays = [math]::Round($uptime.TotalDays,1)
        } catch {
            # As a last resort, mark as unavailable
            $Result.UptimeDays = "Unavailable"
            Write-Host "Warning: Could not parse LastBootUpTime for $Server (Value: '$lastBootRaw')" -ForegroundColor Yellow
        }        
        
        # 3. CPU
        $cpu = Get-CimInstance -ComputerName $Server -ClassName Win32_Processor -ErrorAction Stop
        $cpuUsage = ($cpu | Measure-Object -Property LoadPercentage -Average).Average
        $Result.CPUUsage = "$cpuUsage%"

        # 4. Memory
        $totalMemGB = [math]::Round($os.TotalVisibleMemorySize / 1MB / 1024, 2)
        $freeMemGB  = [math]::Round($os.FreePhysicalMemory / 1MB / 1024, 2)
        $usedMemGB  = $totalMemGB - $freeMemGB
        $Result.MemoryUsage = "$usedMemGB GB used / $totalMemGB GB"

        # 5. Disk Space
        $disks = Get-CimInstance -ComputerName $Server -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop
        $diskSummary = $disks | ForEach-Object {
            $free = [math]::Round($_.FreeSpace / 1GB, 2)
            $total = [math]::Round($_.Size / 1GB, 2)
            "$($_.DeviceID): $free GB free / $total GB"
        }
        $Result.DiskSpace = $diskSummary -join "; "

        # 6. Key Services
        $Result.Services = ($ServiceNames | ForEach-Object {
            try {
                $svc = Get-Service -ComputerName $Server -Name $_ -ErrorAction Stop
                "$($_): $($svc.Status)"
            } catch {
                "$($_): Not found"
            }
        }) -join "; "

        # 7. Recent Errors (last 7 days) in System & Application
        $since = (Get-Date).AddDays(-7)
        foreach ($log in @("System","Application")) {
            $errors = Get-WinEvent -ComputerName $Server -FilterHashtable @{LogName=$log; Level=1,2; StartTime=$since} -ErrorAction SilentlyContinue |
                Select-Object -First 5 -Property TimeCreated, Id, Message
            $report = if ($errors) {
                $errors | ForEach-Object { "$($_.TimeCreated): $($_.Id) $($_.Message -replace "`r`n", " " -replace "`n", " " )" }
            } else {
                "None"
            }
            if ($log -eq "System")   { $Result.SysErrors = $report -join " || " }
            if ($log -eq "Application") { $Result.AppErrors = $report -join " || " }
        }

        # 8. IIS Checks (if IIS is present)
        $iisInfo = Invoke-Command -ComputerName $Server -ScriptBlock {
            try {
                Import-Module WebAdministration -ErrorAction Stop
                $appPools = Get-ChildItem IIS:\AppPools | Select-Object Name, State
                $sites = Get-ChildItem IIS:\Sites | Select-Object Name, State, Bindings
                return @{
                    AppPools = $appPools
                    Sites    = $sites
                }
            } catch {
                return $null
            }
        } -ErrorAction SilentlyContinue

        if ($iisInfo) {
            # App Pools
            $Result.IISAppPools = $iisInfo.AppPools | ForEach-Object { "$($_.Name): $($_.State)" } -join "; "
            # Sites
            $Result.IISSites = $iisInfo.Sites | ForEach-Object { "$($_.Name): $($_.State)" } -join "; "
        }

        # 9. HTTP/HTTPS Ports Listening
        $ports = Invoke-Command -ComputerName $Server -ScriptBlock {
            netstat -an | findstr ":80 " | findstr "LISTENING"
            netstat -an | findstr ":443" | findstr "LISTENING"
        } -ErrorAction SilentlyContinue
        if ($ports) { $Result.HTTPPorts = ($ports | Out-String).Trim() } else { $Result.HTTPPorts = "Not listening" }

    } catch {
        $Result.Status = "Error"
        $Result.Error = $_.Exception.Message
        Write-Host ('Failed to check {0}: {1}' -f $Server, $_.Exception.Message) -ForegroundColor Red
    }
    $Results += [pscustomobject]$Result
}

# Output to screen
$Results | Format-Table -AutoSize

# Export to CSV
$csvPath = ".\ServerHealthReport.csv"
$Results | Export-Csv -Path $csvPath -NoTypeInformation -Force
Write-Host "Results exported to $csvPath" -ForegroundColor Green
