#Requires -Version 5.1
<#
.SYNOPSIS
    Bootstrap WSL2 + Debian on a fresh Windows host and provision it.

.DESCRIPTION
    Installs WSL2 (if needed), registers Debian, makes it the default distro,
    enables systemd, creates the user, then clones this repo inside the distro
    and runs wsl2/provision.sh. The provisioner installs the zsh shell
    environment and, using the forwarded Windows ssh-agent (YubiKey FIDO key),
    clones and stows the private dotfiles.

    To test the full flow without touching your real distro, pass -InstanceName
    to register the same Debian base under a throwaway name (requires WSL 2.4.4+
    for the --name flag). A test instance is NOT made the default distro and can
    be removed afterwards with `wsl --unregister <name>`.

    Run from an ELEVATED PowerShell. Have your YubiKey ready when prompted.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\wsl2.ps1

.EXAMPLE
    # Throwaway test instance alongside your real Debian (left as non-default):
    powershell -ExecutionPolicy Bypass -File .\wsl2.ps1 -InstanceName DebianTest -WslUser keng
#>
[CmdletBinding()]
param(
    [string]$DistroName     = 'Debian',
    [string]$InstanceName   = '',
    [string]$WslUser        = 'keng',
    [string]$RepoUrl        = 'https://github.com/kengzzzz/sys-setup.git',
    [string]$Branch         = 'main',
    [string]$DotfilesRepo   = 'git@github.com:kengzzzz/dotfiles.git',
    [string]$DotfilesBranch = 'main',
    [string]$NpiperelayPath = "$env:USERPROFILE\npiperelay.exe",
    [string]$SshSkProvider  = 'internal',
    [switch]$SkipDotfiles
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:WSL_UTF8 = '1'   # make `wsl` emit clean UTF-8 instead of UTF-16LE

# $DistroName is the catalog base to install (Debian); $InstanceName is the name
# it gets registered under. They match for a normal install; differ for a
# throwaway test instance (`-InstanceName DebianTest`), which uses `wsl --install
# --name` (WSL 2.4.4+) and is deliberately left as a non-default distro.
if (-not $InstanceName) { $InstanceName = $DistroName }
$IsTestInstance = $InstanceName -ne $DistroName

# --- output helpers (mirror the bash log/warn/die style) ---------------------
function Write-Step { param([string]$m) Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Note { param([string]$m) Write-Host "    $m" }
function Write-Warn2 { param([string]$m) Write-Host "warning: $m" -ForegroundColor Yellow }
function Die { param([string]$m) Write-Host "error: $m" -ForegroundColor Red; exit 1 }

# Run a native exe WITHOUT letting its stderr abort the script. Under
# $ErrorActionPreference='Stop' PowerShell promotes any native-command stderr to
# a terminating error (even with 2>$null), which would kill an otherwise-optional
# step. Returns the process exit code; never throws on stderr.
function Invoke-Native {
    param([Parameter(Mandatory)][string]$Exe, [string[]]$Arguments = @())
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $Exe @Arguments
        return $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prev
    }
}

# --- preflight ---------------------------------------------------------------
function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-Wsl {
    Write-Step 'Checking WSL'
    $haveWsl = $null -ne (Get-Command wsl.exe -ErrorAction SilentlyContinue)
    if ($haveWsl) {
        & wsl.exe --version 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Note 'WSL is installed.'; return }
    }
    Write-Warn2 'WSL is not installed. Installing the platform (no distribution)...'
    & wsl.exe --install --no-distribution
    Die 'WSL was just installed. Reboot Windows, then re-run this script.'
}

# --- in-distro execution (base64 to dodge all the quoting layers) ------------
function Invoke-WslBash {
    param([string]$User, [string]$Script)
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Script))
    & wsl.exe -d $InstanceName -u $User -- bash -lc "echo $b64 | base64 -d | bash"
    if ($LASTEXITCODE -ne 0) { Die "in-distro command failed (exit $LASTEXITCODE)" }
}

function Test-DistroInstalled {
    $list = & wsl.exe -l -q 2>$null
    if (-not $list) { return $false }
    ($list -split "`n" | ForEach-Object { $_.Trim() }) -contains $InstanceName
}

# --- Windows ssh-agent / YubiKey ---------------------------------------------
function Initialize-WindowsSshAgent {
    Write-Step 'Preparing the Windows ssh-agent for the YubiKey'

    # Use the Windows OpenSSH ssh-add explicitly. The in-distro bridge forwards the
    # Windows ssh-agent service pipe (//./pipe/openssh-ssh-agent); a ssh-add from
    # Git/MSYS on PATH would load the key into a different (cygwin) agent the bridge
    # can't see, so the dotfiles clone would still fail.
    $sshAdd = Join-Path $env:SystemRoot 'System32\OpenSSH\ssh-add.exe'
    if (-not (Test-Path $sshAdd)) {
        $cmd = Get-Command ssh-add.exe -ErrorAction SilentlyContinue
        if ($cmd) { $sshAdd = $cmd.Source }
    }
    if (-not (Test-Path $sshAdd)) {
        Write-Warn2 'Windows OpenSSH ssh-add not found. Install "OpenSSH Client" from Windows optional features, then re-run with dotfiles.'
        return $false
    }

    try {
        Set-Service ssh-agent -StartupType Automatic
        Start-Service ssh-agent
    } catch { Write-Warn2 "could not start ssh-agent service: $_" }

    # `ssh-add -K` downloads the YubiKey's *resident* FIDO key, but that needs an SK
    # provider. Windows OpenSSH has built-in support, selected with
    # SSH_SK_PROVIDER=internal; without it ssh-add dies "Cannot download keys without
    # provider". Honor an existing value if the user already set one.
    if (-not $env:SSH_SK_PROVIDER) { $env:SSH_SK_PROVIDER = $SshSkProvider }
    Write-Note "using SSH_SK_PROVIDER=$env:SSH_SK_PROVIDER"

    Write-Note 'Insert your YubiKey and touch it when it blinks (you may be asked for its PIN)...'
    $rc = Invoke-Native -Exe $sshAdd -Arguments @('-K')   # load FIDO resident keys
    if ($rc -ne 0) {
        Write-Warn2 "ssh-add -K could not load the YubiKey key (exit $rc); dotfiles may be skipped."
    }

    if ((Invoke-Native -Exe $sshAdd -Arguments @('-l')) -ne 0) {
        Write-Warn2 'No keys are loaded in the Windows ssh-agent. Dotfiles may be skipped in the distro.'
        return $false
    }
    Write-Note 'A key is loaded in the Windows ssh-agent.'
    return $true
}

function Initialize-Npiperelay {
    Write-Step 'Ensuring npiperelay.exe is present'
    if (Test-Path $NpiperelayPath) { Write-Note "found: $NpiperelayPath"; return }
    Write-Note "downloading npiperelay to $NpiperelayPath"
    $zip = Join-Path $env:TEMP 'npiperelay.zip'
    $out = Join-Path $env:TEMP 'npiperelay'
    Invoke-WebRequest -UseBasicParsing `
        -Uri 'https://github.com/jstarks/npiperelay/releases/latest/download/npiperelay_windows_amd64.zip' `
        -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $out -Force
    $exe = Get-ChildItem -Path $out -Filter 'npiperelay.exe' -Recurse | Select-Object -First 1
    if (-not $exe) { Die 'npiperelay.exe not found in the downloaded archive.' }
    New-Item -ItemType Directory -Force -Path (Split-Path $NpiperelayPath) | Out-Null
    Copy-Item $exe.FullName $NpiperelayPath -Force
}

# --- distro setup ------------------------------------------------------------
function Install-Distro {
    if ($IsTestInstance) { Write-Step "Installing $DistroName as test instance '$InstanceName'" }
    else { Write-Step "Installing the $DistroName distribution" }
    & wsl.exe --set-default-version 2 | Out-Null
    if (Test-DistroInstalled) {
        Write-Note "$InstanceName is already installed; skipping install."
        return
    }
    if ($IsTestInstance) {
        # a custom instance name needs WSL's --name flag (WSL 2.4.4+)
        & wsl.exe --install -d $DistroName --name $InstanceName --no-launch
    } else {
        & wsl.exe --install -d $DistroName --no-launch
    }
    if ($LASTEXITCODE -ne 0) { Die "failed to install $DistroName (exit $LASTEXITCODE)" }
}

function New-WslUser {
    Write-Step "Creating user '$WslUser'"
    $pwPlain = ''
    $sec = Read-Host "Set a password for '$WslUser'" -AsSecureString
    $pwPlain = (New-Object System.Management.Automation.PSCredential 'x', $sec).GetNetworkCredential().Password
    $pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pwPlain))

    $script = @"
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends sudo ca-certificates
if ! id -u '$WslUser' >/dev/null 2>&1; then
    useradd -m -s /bin/bash -G sudo '$WslUser'
    printf '%s:%s\n' '$WslUser' "`$(printf %s '$pwB64' | base64 -d)" | chpasswd
fi
"@
    Invoke-WslBash -User 'root' -Script $script
}

function Set-WslConf {
    Write-Step 'Configuring /etc/wsl.conf (systemd + default user)'
    $script = @"
set -e
printf '[boot]\nsystemd=true\n\n[user]\ndefault=%s\n' '$WslUser' > /etc/wsl.conf
"@
    Invoke-WslBash -User 'root' -Script $script
    if ($IsTestInstance) {
        Write-Note "test instance: leaving your default distro unchanged (open it with 'wsl -d $InstanceName')"
    } else {
        & wsl.exe --set-default $InstanceName | Out-Null
    }
    & wsl.exe --terminate $InstanceName | Out-Null
}

function Invoke-Provision {
    Write-Step 'Cloning sys-setup and running the provisioner inside the distro'
    $npWsl = (& wsl.exe -d $InstanceName -- wslpath -u "$NpiperelayPath").Trim()

    $pArgs = "--user '$WslUser' --win-user '$env:USERNAME' --npiperelay-path '$npWsl' " +
             "--dotfiles-repo '$DotfilesRepo' --dotfiles-branch '$DotfilesBranch'"
    if ($SkipDotfiles) { $pArgs += ' --no-dotfiles' }

    $script = @"
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends git curl ca-certificates
rm -rf /opt/sys-setup
git clone --depth 1 --branch '$Branch' '$RepoUrl' /opt/sys-setup
bash /opt/sys-setup/wsl2/provision.sh $pArgs
"@
    Invoke-WslBash -User 'root' -Script $script
}

# --- main --------------------------------------------------------------------
if (-not (Test-Admin)) {
    Die 'Run this script from an elevated PowerShell (Run as Administrator).'
}

Write-Step "WSL2 + $DistroName bootstrap"
if ($IsTestInstance) { Write-Note "test instance: $InstanceName (your real distro is left untouched)" }
Write-Note "user=$WslUser  repo=$RepoUrl#$Branch  dotfiles=$(if ($SkipDotfiles) {'disabled'} else {$DotfilesRepo})"

Ensure-Wsl

if (-not $SkipDotfiles) {
    if (-not (Initialize-WindowsSshAgent)) {
        Write-Warn2 'Continuing; the provisioner will skip dotfiles if GitHub SSH is unreachable.'
    }
    Initialize-Npiperelay
}

Install-Distro
New-WslUser
Set-WslConf
Invoke-Provision

Write-Step 'Done'
Write-Note "Open your distro:  wsl -d $InstanceName"
Write-Note 'zsh (robbyrussell prompt) should load. If dotfiles were skipped, plug in the YubiKey,'
Write-Note "run 'ssh-add -K' in PowerShell, then re-run this script."
if ($IsTestInstance) {
    Write-Note "Test instance - remove it when done:  wsl --unregister $InstanceName"
}
