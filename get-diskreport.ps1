<#
.SYNOPSIS
    Generates disk usage reports for remote computers.

.DESCRIPTION
    This script collects disk usage information from one or more remote computers
    and generates both console output and CSV reports. It supports querying 
    individual computers or batch processing from a file containing computer names.
    
    The script queries fixed disk drives (excludes network and removable drives)
    and provides detailed information including total space, used space, free space,
    and percentage free for each drive.

.PARAMETER ComputerName
    Array of computer names to check disk usage for. Cannot be used with ComputerListPath.

.PARAMETER ComputerListPath
    Path to a text file containing computer names (one per line). Cannot be used with ComputerName.

.PARAMETER OutCsvPath
    Output path for CSV report. If not specified, generates timestamped filename in current directory.

.EXAMPLE
    .\get-diskreport.ps1 -ComputerName "SERVER01", "SERVER02"
    
    Generates disk report for two specific servers.

.EXAMPLE
    .\get-diskreport.ps1 -ComputerListPath "servers.txt" -OutCsvPath "C:\Reports\DiskReport.csv"
    
    Reads server names from file and saves report to specified CSV path.

.EXAMPLE
    .\get-diskreport.ps1 -ComputerName "localhost"
    
    Generates disk report for the local computer.

.NOTES
    File Name      : get-diskreport.ps1
    Prerequisite   : PowerShell 3.0+, WinRM enabled on target computers
    Creation Date  : 2025-12-22
    Last Modified  : 2025-12-23
    Version        : 1.0
    
    Requires administrative privileges on target computers for WMI access.
    Target computers must be accessible via network and have WinRM enabled.

.INPUTS
    String array of computer names or path to text file containing computer names.

.OUTPUTS
    Console table display and CSV file containing disk usage information.
    CSV columns: Server, Drive, VolumeName, FileSystem, TotalGB, UsedGB, FreeGB, PercentFree, Status, Error

#>

param(
  # Array of computer names to check disk usage for

  [Parameter(Mandatory=$false)]
  [string[]]$ComputerName,

  # Path to a text file containing computer names (one per line)

  [Parameter(Mandatory=$false)]
  [string]$ComputerListPath,

  # Output path for CSV report (auto-generated if not specified)

  [Parameter(Mandatory=$false)]
  [string]$OutCsvPath
)

# Enable strict mode for better error handling and stop on errors

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Main function to collect disk information from target computers

function Get-DiskReport {
  param(
    # Array of target computer names to query
    [Parameter(Mandatory=$true)]
    [string[]]$Targets
  )

  # Initialize collection to store disk information for all computers

  $results = New-Object System.Collections.Generic.List[object]

  # Process each target computer

  foreach ($server in $Targets) {

    # Clean up server name (remove whitespace)

    $serverTrim = $server.Trim()
    if ([string]::IsNullOrWhiteSpace($serverTrim)) { continue }

    try {

      # Test network connectivity before attempting WMI queries

      if (-not (Test-Connection -ComputerName $serverTrim -Count 1 -Quiet -ErrorAction Stop)) {
        throw "Ping failed"
      }

      # Query for local disk drives (DriveType=3 = fixed disks, excludes network/removable drives)

      $disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ComputerName $serverTrim

      # Process each disk drive found

      foreach ($d in $disks) {

        # Handle null values that can occur on unusual volume configurations

        $sizeBytes = [double]($d.Size  | ForEach-Object { if ($_ -eq $null) { 0 } else { $_ } })
        $freeBytes = [double]($d.FreeSpace | ForEach-Object { if ($_ -eq $null) { 0 } else { $_ } })

        # Convert bytes to GB and calculate usage statistics

        $sizeGB = if ($sizeBytes -gt 0) { [Math]::Round($sizeBytes / 1GB, 2) } else { 0 }
        $freeGB = if ($freeBytes -gt 0) { [Math]::Round($freeBytes / 1GB, 2) } else { 0 }
        $usedGB = if ($sizeBytes -gt 0) { [Math]::Round(($sizeBytes - $freeBytes) / 1GB, 2) } else { 0 }
        $pctFree = if ($sizeBytes -gt 0) { [Math]::Round(($freeBytes / $sizeBytes) * 100, 2) } else { 0 }

        # Create result object with disk information

        $results.Add([pscustomobject]@{
          Server       = $serverTrim
          Drive        = $d.DeviceID
          VolumeName   = $d.VolumeName
          FileSystem   = $d.FileSystem
          TotalGB      = $sizeGB
          UsedGB       = $usedGB
          FreeGB       = $freeGB
          PercentFree  = $pctFree
          Status       = "OK"
          Error        = $null
        })
      }
    }
    catch {

      # Log failed connections/queries with error details

      $results.Add([pscustomobject]@{
        Server       = $serverTrim
        Drive        = $null
        VolumeName   = $null
        FileSystem   = $null
        TotalGB      = $null
        UsedGB       = $null
        FreeGB       = $null
        PercentFree  = $null
        Status       = "FAILED"
        Error        = $_.Exception.Message
      })
      continue
    }
  }

  # Return the collected disk information

  return $results
}

# Main script execution starts here
# ===================================

# Initialize array to hold target computer names

$targets = @()

# Determine source of computer names (command line parameter vs file)

if ($ComputerName -and $ComputerName.Count -gt 0) {

  # Use computer names provided via -ComputerName parameter

  $targets += $ComputerName
}
elseif ($ComputerListPath) {

  # Read computer names from specified file

  if (-not (Test-Path -Path $ComputerListPath)) {
    throw "ComputerListPath not found: $ComputerListPath"
  }

  # Load computer names from file, filtering out empty lines

  $targets += Get-Content -Path $ComputerListPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
}
else {

  # No input source specified - show usage error

  throw "Provide -ComputerName or -ComputerListPath."
}

# Generate output CSV filename if not provided

if (-not $OutCsvPath) {
  $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
  $OutCsvPath = Join-Path -Path (Get-Location) -ChildPath "DiskReport_$stamp.csv"
}

# Execute the disk report collection

$report = Get-DiskReport -Targets $targets

# Display results in console (formatted table)

$report |
  Sort-Object Server, Drive |
  Format-Table Server, Drive, VolumeName, FileSystem, TotalGB, UsedGB, FreeGB, PercentFree, Status -AutoSize

# Export results to CSV file and notify user

$report | Export-Csv -Path $OutCsvPath -NoTypeInformation -Encoding UTF8
Write-Host "Saved CSV to: $OutCsvPath"
