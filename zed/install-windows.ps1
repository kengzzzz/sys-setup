[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceDir,
    [switch]$Copy
)

$ErrorActionPreference = "Stop"

$SourceDir = (Resolve-Path -LiteralPath $SourceDir).Path
$TargetDir = Join-Path $env:APPDATA "Zed"
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$BackupDir = Join-Path $env:APPDATA "Zed.dotfiles-backup.$Timestamp"

if (-not (Test-Path -LiteralPath $SourceDir -PathType Container)) {
    throw "Zed config source not found: $SourceDir"
}

New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null

foreach ($SourceItem in Get-ChildItem -LiteralPath $SourceDir -Force) {
    $TargetPath = Join-Path $TargetDir $SourceItem.Name
    $ExistingItem = Get-Item -LiteralPath $TargetPath -Force -ErrorAction SilentlyContinue

    if ($null -ne $ExistingItem) {
        $ExistingTargets = @($ExistingItem.Target)
        if (-not $Copy -and
            $ExistingItem.LinkType -eq "SymbolicLink" -and
            $ExistingTargets -contains $SourceItem.FullName) {
            Write-Host "Already linked: $TargetPath"
            continue
        }

        if ($Copy -and -not $SourceItem.PSIsContainer -and
            -not $ExistingItem.PSIsContainer -and
            (Get-FileHash -LiteralPath $SourceItem.FullName).Hash -eq
            (Get-FileHash -LiteralPath $TargetPath).Hash) {
            Write-Host "Already copied: $TargetPath"
            continue
        }

        New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
        Move-Item -LiteralPath $TargetPath -Destination (Join-Path $BackupDir $SourceItem.Name)
        Write-Host "Backed up: $TargetPath -> $BackupDir"
    }

    try {
        if ($Copy) {
            Copy-Item -LiteralPath $SourceItem.FullName -Destination $TargetPath -Recurse
            Write-Host "Copied: $($SourceItem.FullName) -> $TargetPath"
        }
        else {
            New-Item -ItemType SymbolicLink -Path $TargetPath -Target $SourceItem.FullName | Out-Null
            Write-Host "Linked: $TargetPath -> $($SourceItem.FullName)"
        }
    }
    catch {
        $BackupPath = Join-Path $BackupDir $SourceItem.Name
        if (Test-Path -LiteralPath $BackupPath) {
            Move-Item -LiteralPath $BackupPath -Destination $TargetPath
        }
        if ($Copy) {
            throw "Could not copy the Zed config. $($_.Exception.Message)"
        }
        throw "Could not create the Zed config link. Enable Windows Developer Mode, run PowerShell as Administrator, or rerun with -Copy. $($_.Exception.Message)"
    }
}
