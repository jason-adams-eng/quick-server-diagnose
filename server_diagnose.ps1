# Define the server name
$ServerName = "server-name" # Change accordingly

# Create an empty report to store the results
$Report = @{}

# Check CPU Usage
$cpuUsage = Get-WmiObject -ComputerName $ServerName -Class Win32_Processor | 
    Measure-Object -Property LoadPercentage -Average | Select-Object -ExpandProperty Average
$Report.CPUUsage = "$cpuUsage% CPU Load"

# Check Memory Usage
$memory = Get-WmiObject -ComputerName $ServerName -Class Win32_OperatingSystem
$totalMemory = [math]::Round($memory.TotalVisibleMemorySize / 1MB, 2)
$freeMemory = [math]::Round($memory.FreePhysicalMemory / 1MB, 2)
$usedMemory = $totalMemory - $freeMemory
$Report.MemoryUsage = "$usedMemory GB used out of $totalMemory GB"

# Check Disk Space
$diskSpace = Get-WmiObject -ComputerName $ServerName -Class Win32_LogicalDisk -Filter "DriveType = 3"
$diskReport = @()
foreach ($disk in $diskSpace) {
    $freeSpaceGB = [math]::Round($disk.FreeSpace / 1GB, 2)
    $totalSpaceGB = [math]::Round($disk.Size / 1GB, 2)
    $diskReport += "Drive $($disk.DeviceID): $freeSpaceGB GB free out of $totalSpaceGB GB"
}
$Report.DiskSpace = $diskReport -join "`n"

# Check for recent Errors and Critical events in the Event Log, handle empty results
$events = Get-WinEvent -ComputerName $ServerName -FilterHashtable @{LogName="System"; Level=1,2; StartTime=(Get-Date).AddDays(-7)} |
    Select-Object TimeCreated, Id, Message

if ($events.Count -eq 0) {
    $Report.EventLogs = "No critical or error events found in the last 7 days"
} else {
    # Group by unique messages and count occurrences
    $groupedEvents = $events | Group-Object -Property Message | Select-Object Name, Count

    # Store the grouped results in a more readable format
    $eventReport = @()
    foreach ($event in $groupedEvents) {
        $eventReport += "$($event.Count) occurrence(s) of: $($event.Name)"
    }

    $Report.EventLogs = $eventReport -join "`n`n"
}

# Check Pagefile Usage
$pagefile = Get-WmiObject -ComputerName $ServerName -Class Win32_PageFileUsage
if ($pagefile) {
    $pagefileUsage = [math]::Round($pagefile.CurrentUsage / 1MB, 2)
    $pagefileAllocated = [math]::Round($pagefile.AllocatedBaseSize / 1MB, 2)
    $Report.PagefileUsage = "$pagefileUsage GB used out of $pagefileAllocated GB allocated"
} else {
    $Report.PagefileUsage = "Pagefile data unavailable"
}

# Check for Memory Dumps in the last 7 days
$sevenDaysAgo = (Get-Date).AddDays(-7)
$memoryDumps = Get-ChildItem "\\$ServerName\C$\Windows\minidump" -ErrorAction SilentlyContinue | 
               Where-Object { $_.LastWriteTime -ge $sevenDaysAgo }

if ($memoryDumps) {
    # Create a list of dumps found in the last 7 days
    $dumpList = $memoryDumps | ForEach-Object { $_.Name + " - Last modified: " + $_.LastWriteTime }
    $Report.MemoryDumps = "Memory dump(s) found in C:\Windows\minidump: `n$($dumpList -join "`n")"
} else {
    $Report.MemoryDumps = "No memory dumps found in the last 7 days"
}

# Output the Report with enhanced formatting
Write-Host "Diagnostics Report for $ServerName`n"

Write-Host "PagefileUsage: $($Report.PagefileUsage)`n"
Write-Host "MemoryDumps: $($Report.MemoryDumps)`n"
Write-Host "MemoryUsage: $($Report.MemoryUsage)`n"

Write-Host "CPUUsage: $($Report.CPUUsage)`n"

Write-Host "DiskSpace: `n$($Report.DiskSpace)`n"

Write-Host "EventLogs: `n$($Report.EventLogs)`n"

# Optionally export the report to a text file
#$Report | Out-File -FilePath "C:\Users\da.jason.adams\Desktop\$ServerName-Report.txt"
# Output the Report as a readable string and write it to a text file
$Report | Format-List | Out-String | Out-File -FilePath "C:\Users\da.jason.adams\Desktop\$ServerName-Report.txt"
