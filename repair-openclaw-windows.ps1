# Repair OpenClaw on Windows: optional global reinstall + Windows ESM hotfix.
# Run from repo root or any path:
#   powershell -ExecutionPolicy Bypass -File .\repair-openclaw-windows.ps1
#   powershell -ExecutionPolicy Bypass -File .\repair-openclaw-windows.ps1 -Reinstall

param(
    [switch]$Reinstall,
    [string]$Tag = "latest",
    [string]$Registry,
    [switch]$NoGatewayRestart
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$patchScript = Join-Path $scriptDir "patch-openclaw-windows-esm.ps1"

if (-not (Test-Path $patchScript)) {
    throw "patch-openclaw-windows-esm.ps1 not found next to this script: $patchScript"
}

# Align with install-openclaw-cn.ps1 defaults when not set
if ([string]::IsNullOrWhiteSpace($env:OPENCLAW_NPM_REGISTRY)) {
    $env:OPENCLAW_NPM_REGISTRY = "https://registry.npmmirror.com"
}

function Get-NpmCommandPath {
    $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if (-not $npm) { $npm = Get-Command npm -ErrorAction SilentlyContinue }
    if (-not $npm) { throw "npm not found on PATH." }
    return $npm.Source
}

Write-Host ""
Write-Host "  OpenClaw Windows repair" -ForegroundColor Cyan
Write-Host ""

$npmRegistry = if (-not [string]::IsNullOrWhiteSpace($Registry)) { $Registry } else { $env:OPENCLAW_NPM_REGISTRY }

if ($Reinstall) {
    Write-Host "[*] Reinstalling openclaw@$Tag globally (npm --force)..." -ForegroundColor Yellow
    $npmExe = Get-NpmCommandPath
    & $npmExe install -g "openclaw@$Tag" --force --registry $npmRegistry
    if ($LASTEXITCODE -ne 0) {
        throw "npm global install failed (exit $LASTEXITCODE)."
    }
    Write-Host "[OK] npm global install finished" -ForegroundColor Green
}

Write-Host "[*] Applying Windows ESM patch..." -ForegroundColor Yellow
& powershell -ExecutionPolicy Bypass -File $patchScript
if ($LASTEXITCODE -ne 0) {
    throw "patch-openclaw-windows-esm.ps1 failed (exit $LASTEXITCODE)."
}

Write-Host "[OK] Repair complete." -ForegroundColor Green

if (-not $NoGatewayRestart) {
    Write-Host "[*] Restarting gateway service..." -ForegroundColor Yellow
    try {
        & openclaw gateway restart
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[!] gateway restart returned exit $LASTEXITCODE (service may not be installed)." -ForegroundColor Yellow
        } else {
            Write-Host "[OK] Gateway restart issued." -ForegroundColor Green
        }
    } catch {
        Write-Host "[!] gateway restart failed: $_" -ForegroundColor Yellow
    }
}
