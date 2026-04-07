param(
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Get-GlobalOpenClawRoot {
    $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if (-not $npm) {
        $npm = Get-Command npm -ErrorAction SilentlyContinue
    }
    if (-not $npm) {
        throw "npm not found on PATH."
    }
    $npmRoot = (& $npm.Source root -g 2>$null).Trim()
    if (-not [string]::IsNullOrWhiteSpace($npmRoot)) {
        $candidate = Join-Path $npmRoot "openclaw"
        if (Test-Path $candidate) {
            return $candidate
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($env:APPDATA)) {
        $fallback = Join-Path $env:APPDATA "npm\node_modules\openclaw"
        if (Test-Path $fallback) {
            return $fallback
        }
    }
    return $null
}

$openclawRoot = Get-GlobalOpenClawRoot
if (-not $openclawRoot) {
    throw "openclaw package root not found in global npm paths."
}

$jitiPath = Join-Path $openclawRoot "node_modules\jiti\lib\jiti.mjs"
if (-not (Test-Path $jitiPath)) {
    throw "jiti.mjs not found: $jitiPath"
}

$content = Get-Content -Raw -Path $jitiPath
if ($content -match "pathToFileURL" -and $content -match "isAbsolute") {
    Write-Host "[OK] Patch already applied at $jitiPath" -ForegroundColor Green
    exit 0
}

$needle = "const nativeImport = (id) => import(id);"
if ($content -notmatch [regex]::Escape($needle)) {
    throw "Expected target line not found in jiti.mjs; patch aborted."
}

$replacement = @'
import { pathToFileURL } from "node:url";
import { isAbsolute } from "node:path";
const nativeImport = (id) =>
	import(
		process.platform === "win32" && typeof id === "string" && isAbsolute(id)
			? pathToFileURL(id).href
			: id,
	);
'@

if ($DryRun) {
    Write-Host "[OK] Dry run: patch can be applied to $jitiPath" -ForegroundColor Green
    exit 0
}

$patched = $content.Replace($needle, $replacement)
Set-Content -Path $jitiPath -Value $patched -NoNewline
Write-Host "[OK] Patched Windows ESM import handling in $jitiPath" -ForegroundColor Green
