# wsl-mount-bare.ps1
# Passes ext4 disks through to WSL2 by stable serial number, not volatile PHYSICALDRIVE index.
# Self-elevates if not already running as administrator.

# --- Self-elevation -------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)

if (-not $isAdmin) {
    $psi = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $psi
    exit
}
# --- End self-elevation ---------------------------------------------------

$allow = [ordered]@{
    'S4X6NF0N322615L'                          = 'Samsung 860 EVO 1TB  (disk was 0)'
    '205205A000E4'                             = 'WDC WDS500G2B0A      (disk was 1)'
    'S62BNJ0R113505V'                          = 'Samsung 870 EVO 500G (disk was 2)'
    '0000_0000_0000_0000_0026_B738_3940_A945.' = 'Kingston SNV3S #A945 (disk was 4)'
    # '0000_0000_0000_0000_0026_B738_3940_A865.' = 'Kingston SNV3S #A865 (disk 6 - enable after reorg)'
}

foreach ($serial in $allow.Keys) {
    $disk = Get-Disk | Where-Object { $_.SerialNumber -eq $serial }
    if (-not $disk) {
        Write-Warning "NOT FOUND: $($allow[$serial]) — serial '$serial' not present. Skipping."
        continue
    }
    if ($disk.Count -gt 1) {
        Write-Warning "AMBIGUOUS: serial '$serial' matched $($disk.Count) disks. Skipping for safety."
        continue
    }
    $path = "\\.\PHYSICALDRIVE$($disk.Number)"
    Write-Host "Mounting $($allow[$serial]) -> $path"
    wsl --mount $path --bare
}