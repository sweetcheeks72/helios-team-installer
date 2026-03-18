#Requires -Version 5.1
<#
.SYNOPSIS
    Helios Team Installer for Windows
.DESCRIPTION
    Bootstraps Helios + Pi inside WSL 2 / Ubuntu, then creates
    helios.cmd, helios.ps1, pi.cmd, and pi.ps1 shims so the
    commands work from any PowerShell or CMD window.
.EXAMPLE
    irm https://raw.githubusercontent.com/sweetcheeks72/helios-team-installer/main/install.ps1 | iex
#>

$ErrorActionPreference = 'Stop'

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

function Write-Banner {
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║           helios. — AI Orchestrator for Windows         ║" -ForegroundColor Cyan
    Write-Host "  ║          Powered by Pi CLI + WSL 2 + Ubuntu             ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step {
    param([string]$Message)
    Write-Host "  ▶  $Message" -ForegroundColor Cyan
}

function Write-OK {
    param([string]$Message)
    Write-Host "  ✓  $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  ⚠  $Message" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Message)
    Write-Host "  ✗  $Message" -ForegroundColor Red
}

function Add-ToUserPath {
    param([string]$Dir)
    $currentPath = [System.Environment]::GetEnvironmentVariable('PATH', 'User')
    if ($currentPath -split ';' -notcontains $Dir) {
        $newPath = "$currentPath;$Dir".TrimStart(';')
        [System.Environment]::SetEnvironmentVariable('PATH', $newPath, 'User')
        # Also update the current session
        $env:PATH = "$env:PATH;$Dir"
        return $true
    }
    return $false
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 1 — Banner
# ─────────────────────────────────────────────────────────────────────────────

Write-Banner
Write-Host "  Starting Helios installation..." -ForegroundColor White
Write-Host "  This will set up WSL, Ubuntu, and the full Helios stack." -ForegroundColor DarkGray
Write-Host "  Estimated time: 5-10 minutes (first install)." -ForegroundColor DarkGray
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────────
# Step 2 — Windows version check
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Checking Windows version..."

$osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
if (-not $osInfo) {
    Write-Err "Could not determine Windows version."
    exit 1
}

$caption    = $osInfo.Caption          # e.g. "Microsoft Windows 11 Pro"
$buildStr   = $osInfo.BuildNumber      # e.g. "22000"
$build      = [int]$buildStr

# Windows 10 21H2 = build 19044
# Windows 11 (first release) = build 22000
$minBuild = 19044

if ($build -lt $minBuild) {
    Write-Err "Windows version not supported."
    Write-Err "  Detected : $caption (build $build)"
    Write-Err "  Required : Windows 10 21H2 (build 19044) or Windows 11"
    Write-Err ""
    Write-Err "  Please update Windows via Settings → Windows Update."
    exit 1
}

Write-OK "$caption (build $build) — OK"

# ─────────────────────────────────────────────────────────────────────────────
# Step 3 — Check for WSL command
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Checking WSL availability..."

$wslExe = Get-Command wsl -ErrorAction SilentlyContinue
if (-not $wslExe) {
    Write-Err "The 'wsl' command was not found."
    Write-Err ""
    Write-Err "  WSL is not installed on this machine."
    Write-Err "  Run the following in an ADMIN PowerShell, then restart:"
    Write-Host ""
    Write-Host "      wsl --install" -ForegroundColor Yellow
    Write-Host ""
    Write-Err "  Or re-run this script in an elevated (Admin) PowerShell and"
    Write-Err "  it will attempt the install automatically."
    exit 1
}

Write-OK "wsl command found at $($wslExe.Source)"

# ─────────────────────────────────────────────────────────────────────────────
# Step 4 — Check if Ubuntu distro is installed in WSL
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Checking for Ubuntu in WSL..."

# wsl --list --verbose exits 0 even when empty; parse output for Ubuntu
$wslListRaw = & wsl --list --verbose 2>&1
$wslList    = $wslListRaw | Out-String

$ubuntuReady = $false
$ubuntuDistro = "Ubuntu"  # Default; updated if versioned variant found
foreach ($line in $wslListRaw) {
    # Line format: "  Ubuntu   Running   2" (spaces, optional *, name, state, version)
    $trimmed = $line -replace '[^\x20-\x7E]', '' # strip non-ASCII (BOM, utf-16 nulls)
    $trimmed = $trimmed.Trim().TrimStart('*').Trim()
    if ($trimmed -match '^(Ubuntu[^\s]*)') {
        $ubuntuDistro = $Matches[1]  # Capture actual name (Ubuntu, Ubuntu-22.04, etc.)
        # Check WSL version column — we want version 2
        if ($trimmed -match '\s+2\s*$') {
            $ubuntuReady = $true
        } elseif ($trimmed -match '\s+1\s*$') {
            Write-Warn "Ubuntu found in WSL 1. Attempting upgrade to WSL 2..."
            try {
                & wsl --set-version Ubuntu 2 2>&1 | ForEach-Object { Write-Host "    $_" }
                $ubuntuReady = $true
            } catch {
                Write-Warn "Could not auto-upgrade Ubuntu to WSL 2. You can do it manually:"
                Write-Host "      wsl --set-version Ubuntu 2" -ForegroundColor Yellow
                $ubuntuReady = $true  # proceed anyway; bootstrap.sh will surface any issues
            }
        } else {
            # Line matched Ubuntu but version unclear — treat as ready
            $ubuntuReady = $true
        }
        break
    }
}

if (-not $ubuntuReady) {
    Write-Warn "Ubuntu not found in WSL."
    Write-Step "Installing Ubuntu via WSL (this may take a few minutes)..."

    # Check for admin rights — WSL install requires elevation
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )

    if (-not $isAdmin) {
        Write-Err "Installing WSL requires administrator privileges."
        Write-Err ""
        Write-Err "  Please re-run this script in an Admin PowerShell:"
        Write-Host ""
        Write-Host "      Start-Process pwsh -Verb RunAs" -ForegroundColor Yellow
        Write-Host "      # Then re-run:" -ForegroundColor DarkGray
        Write-Host "      irm https://raw.githubusercontent.com/sweetcheeks72/helios-team-installer/main/install.ps1 | iex" -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }

    # Prevent RSA cryptographic deadlock (Windows security updates Oct 2025+)
    try {
        $regPath = "HKLM:\SOFTWARE\Microsoft\Cryptography\Calais"
        if (Test-Path $regPath) {
            $currentVal = Get-ItemProperty -Path $regPath -Name "DisableCapiOverrideForRSA" -ErrorAction SilentlyContinue
            if ($null -eq $currentVal -or $currentVal.DisableCapiOverrideForRSA -ne 0) {
                Set-ItemProperty -Path $regPath -Name "DisableCapiOverrideForRSA" -Value 0 -Type DWord -Force
                Write-OK "Applied RSA compatibility fix"
            }
        }
    } catch {
        Write-Warn "Could not apply RSA fix (may require admin) — WSL install may hang on some machines"
    }

    try {
        & wsl --install -d Ubuntu 2>&1 | ForEach-Object { Write-Host "    $_" }
    } catch {
        Write-Err "WSL install failed: $_"
        Write-Err "Try running 'wsl --install -d Ubuntu' manually in Admin PowerShell."
        exit 1
    }

    # Verify features are actually enabled (wsl --install returns 0 even when pending reboot)
    $wslFeature = Get-WindowsOptionalFeature -Online -FeatureName "Microsoft-Windows-Subsystem-Linux" -ErrorAction SilentlyContinue
    $vmFeature = Get-WindowsOptionalFeature -Online -FeatureName "VirtualMachinePlatform" -ErrorAction SilentlyContinue
    
    $needsReboot = ($null -eq $wslFeature -or $wslFeature.State -ne "Enabled" -or 
                    $null -eq $vmFeature -or $vmFeature.State -ne "Enabled")
    
    if (-not $needsReboot) {
        # Features enabled without reboot — try to continue
        Write-OK "WSL features enabled (no reboot needed)"
        # Re-check if Ubuntu is now available
        Start-Sleep -Seconds 3
        $testUbuntu = & wsl --list --verbose 2>&1 | Out-String
        if ($testUbuntu -match 'Ubuntu') {
            Write-OK "Ubuntu installed and ready"
            $ubuntuReady = $true
        }
    }
    
    if (-not $ubuntuReady) {
    Write-Host ""
    Write-Warn "╔══════════════════════════════════════════════════════════╗"
    Write-Warn "║  WSL + Ubuntu installed — RESTART REQUIRED               ║"
    Write-Warn "╠══════════════════════════════════════════════════════════╣"
    Write-Warn "║  1. Restart your computer                                ║"
    Write-Warn "║  2. Ubuntu will open and finish setting up               ║"
    Write-Warn "║  3. Create your Linux username/password                  ║"
    Write-Warn "║  4. Re-run this command in PowerShell:                   ║"
    Write-Warn "║                                                           ║"
    Write-Warn "║    irm https://raw.githubusercontent.com/                ║"
    Write-Warn "║      sweetcheeks72/helios-team-installer/                ║"
    Write-Warn "║      main/install.ps1 | iex                              ║"
    Write-Warn "╚══════════════════════════════════════════════════════════╝"
    Write-Host ""
    exit 0
    }
}

Write-OK "Ubuntu (WSL 2) is ready"

# ─────────────────────────────────────────────────────────────────────────────
# Step 5 — Run the Helios bash installer inside WSL
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Launching Helios installer inside WSL / Ubuntu..."
Write-Host ""

# ── Step 5a — Verify Ubuntu has completed first-run initialization ────────────
# Ubuntu's first-run wizard (username/password setup) intercepts the WSL
# session and swallows any command we pass. We detect this by running
# `echo ready` and checking if the output actually contains "ready".
# If first-run intercepted, the output won't match and we guide the user.

$maxInitRetries = 3
$initAttempt    = 0
$ubuntuReady    = $false

while (-not $ubuntuReady -and $initAttempt -le $maxInitRetries) {
    $initAttempt++
    Write-Host "  [»] Testing Ubuntu initialization (attempt $initAttempt of $maxInitRetries)..." -ForegroundColor DarkGray
    $testOutput = (& wsl -d $ubuntuDistro -- echo ready 2>&1) -join " "

    if ($testOutput.Trim() -eq 'ready') {
        $ubuntuReady = $true
    } else {
        Write-Host ""
        Write-Warn "Ubuntu needs first-time setup — a setup window may have appeared."
        Write-Host ""
        Write-Host "  Complete these steps in the Ubuntu window:" -ForegroundColor Yellow
        Write-Host "    1) Enter a username when prompted" -ForegroundColor Cyan
        Write-Host "    2) Enter and confirm a password when prompted" -ForegroundColor Cyan
        Write-Host "    3) Type  exit  and press Enter to close the Ubuntu window" -ForegroundColor Cyan
        Write-Host ""
        if ($initAttempt -le $maxInitRetries) {
            Read-Host "  Press Enter here once you have completed setup and typed 'exit' in Ubuntu"
            Write-Host ""
        }
    }
}

if (-not $ubuntuReady) {
    Write-Err "Ubuntu did not finish initialization after $maxInitRetries attempts."
    Write-Err "Please open Ubuntu from the Start Menu, complete the setup, then re-run this installer."
    exit 1
}

Write-OK "Ubuntu is initialized and ready"
Write-Host ""

# ── Step 5b — Run the bootstrap (with one automatic retry on failure) ─────────
Write-Host "  ┄┄┄┄┄┄┄┄┄┄ WSL session begin ┄┄┄┄┄┄┄┄┄┄" -ForegroundColor DarkGray

& wsl -d $ubuntuDistro -- bash -c "curl --max-time 600 -fsSL https://raw.githubusercontent.com/sweetcheeks72/helios-team-installer/main/bootstrap.sh | bash"

$wslExit = $LASTEXITCODE
Write-Host "  ┄┄┄┄┄┄┄┄┄┄ WSL session end ┄┄┄┄┄┄┄┄┄┄┄" -ForegroundColor DarkGray
Write-Host ""

if ($wslExit -ne 0) {
    Write-Warn "Bootstrap exited with code $wslExit — retrying once..."
    Write-Host ""
    Write-Host "  If you see errors above, common fixes:" -ForegroundColor Yellow
    Write-Host "    - Check internet:   wsl -d $ubuntuDistro -- ping -c1 github.com" -ForegroundColor Cyan
    Write-Host "    - Check disk space: wsl -d $ubuntuDistro -- df -h" -ForegroundColor Cyan
    Write-Host ""
    Read-Host "  Press Enter to retry"
    Write-Host ""
    Write-Host "  ┄┄┄┄┄┄┄┄┄┄ WSL session begin (retry) ┄┄┄┄┄┄┄┄┄┄" -ForegroundColor DarkGray

    & wsl -d $ubuntuDistro -- bash -c "curl --max-time 600 -fsSL https://raw.githubusercontent.com/sweetcheeks72/helios-team-installer/main/bootstrap.sh | bash"

    $wslExit = $LASTEXITCODE
    Write-Host "  ┄┄┄┄┄┄┄┄┄┄ WSL session end ┄┄┄┄┄┄┄┄┄┄┄" -ForegroundColor DarkGray
    Write-Host ""

    if ($wslExit -ne 0) {
        Write-Err "Bootstrap failed after retry (exit code $wslExit)."
        Write-Err "Run this command directly inside Ubuntu to install manually:"
        Write-Err ""
        Write-Err "  curl -fsSL https://raw.githubusercontent.com/sweetcheeks72/helios-team-installer/main/bootstrap.sh | bash"
        Write-Err ""
        Write-Err "Open Ubuntu from the Start Menu, paste the command above, and press Enter."
        exit $wslExit
    }
}

Write-OK "Helios installed inside WSL"

# ─────────────────────────────────────────────────────────────────────────────
# Step 6 — Create Windows shims
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Creating Windows command shims..."

$shimDir = Join-Path $env:LOCALAPPDATA 'Programs\Helios'
if (-not (Test-Path $shimDir)) {
    New-Item -ItemType Directory -Path $shimDir -Force | Out-Null
    Write-OK "Created shim directory: $shimDir"
} else {
    Write-OK "Shim directory already exists: $shimDir"
}

# ── helios.cmd ────────────────────────────────────────────────────────────────
$heliosCmdPath = Join-Path $shimDir 'helios.cmd'
$heliosCmdContent = "@echo off`r`nwsl -d $ubuntuDistro -- helios %*"
Set-Content -Path $heliosCmdPath -Value $heliosCmdContent -Encoding ASCII -Force
Write-OK "Written: helios.cmd"

# ── helios.ps1 ───────────────────────────────────────────────────────────────
$heliosPs1Path = Join-Path $shimDir 'helios.ps1'
$heliosPs1Content = "`$wslArgs = @('-d', '$ubuntuDistro', '--', 'helios') + `$args`n& wsl @wslArgs"
Set-Content -Path $heliosPs1Path -Value $heliosPs1Content -Encoding UTF8 -Force
Write-OK "Written: helios.ps1"

# ── pi.cmd ────────────────────────────────────────────────────────────────────
$piCmdPath = Join-Path $shimDir 'pi.cmd'
$piCmdContent = "@echo off`r`nwsl -d $ubuntuDistro -- pi %*"
Set-Content -Path $piCmdPath -Value $piCmdContent -Encoding ASCII -Force
Write-OK "Written: pi.cmd"

# ── pi.ps1 ────────────────────────────────────────────────────────────────────
$piPs1Path = Join-Path $shimDir 'pi.ps1'
$piPs1Content = "`$wslArgs = @('-d', '$ubuntuDistro', '--', 'pi') + `$args`n& wsl @wslArgs"
Set-Content -Path $piPs1Path -Value $piPs1Content -Encoding UTF8 -Force
Write-OK "Written: pi.ps1"

# ─────────────────────────────────────────────────────────────────────────────
# Step 6b — Sync API key environment variables to WSL
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Setting up environment variable sharing with WSL..."

$keysToShare = @(
    "ANTHROPIC_API_KEY",
    "OPENAI_API_KEY",
    "AWS_ACCESS_KEY_ID",
    "AWS_SECRET_ACCESS_KEY",
    "AWS_DEFAULT_REGION",
    "GITHUB_TOKEN",
    "GROQ_API_KEY"
)

$currentWslEnv = [System.Environment]::GetEnvironmentVariable('WSLENV', 'User')
$wslEnvParts = @()
if ($currentWslEnv) {
    $wslEnvParts = @($currentWslEnv -split ':' | Where-Object { $_ })
}

$added = 0
foreach ($key in $keysToShare) {
    $entry = "$key"  # No flag — API keys are plain strings, not paths
    if ($wslEnvParts -notcontains $entry) {
        $wslEnvParts += $entry
        $added++
    }
}

if ($added -gt 0) {
    $newWslEnv = ($wslEnvParts | Where-Object { $_ }) -join ':'
    [System.Environment]::SetEnvironmentVariable('WSLENV', $newWslEnv, 'User')
    $env:WSLENV = $newWslEnv
    Write-OK "WSLENV configured — API keys will automatically sync to WSL"
} else {
    Write-OK "WSLENV already configured for API key sharing"
}

Write-Host ""

# ─────────────────────────────────────────────────────────────────────────────
# Step 7 — Add shim directory to user PATH
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Updating user PATH..."

$added = Add-ToUserPath -Dir $shimDir
if ($added) {
    Write-OK "Added $shimDir to user PATH"
    Write-Warn "PATH updated — restart your terminal for 'helios' and 'pi' to work."
} else {
    Write-OK "$shimDir already in user PATH"
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 8 — Success
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║                 ✓  Install complete!                     ║" -ForegroundColor Green
Write-Host "  ╚══════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Cyan
Write-Host ""
Write-Host "    1. Close and reopen PowerShell (to pick up PATH change)" -ForegroundColor White
Write-Host "    2. Run your first task:" -ForegroundColor White
Write-Host ""
Write-Host "         helios ""explain the codebase in /mnt/c/Users/$env:USERNAME/myproject""" -ForegroundColor Yellow
Write-Host ""
Write-Host "    3. Or drop into the Pi REPL:" -ForegroundColor White
Write-Host ""
Write-Host "         pi" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Tip: 'helios' and 'pi' run in WSL / Ubuntu under the hood." -ForegroundColor DarkGray
Write-Host "  Your Windows files are at /mnt/c/Users/$env:USERNAME/ inside WSL." -ForegroundColor DarkGray
Write-Host ""
