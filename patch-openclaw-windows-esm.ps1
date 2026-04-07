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

$patchedAny = $false

$jitiPath = Join-Path $openclawRoot "node_modules\jiti\lib\jiti.mjs"
if (Test-Path $jitiPath) {
    $content = Get-Content -Raw -Path $jitiPath
    if (-not ($content -match "pathToFileURL" -and $content -match "isAbsolute")) {
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
        if (-not $DryRun) {
            $patched = $content.Replace($needle, $replacement)
            Set-Content -Path $jitiPath -Value $patched -NoNewline
        }
        $patchedAny = $true
    }
} else {
    throw "jiti.mjs not found: $jitiPath"
}

$shimPath = Join-Path $openclawRoot "windows-esm-fix.mjs"
$shimContent = @'
import { pathToFileURL } from "node:url";

export async function resolve(specifier, context, nextResolve) {
  if (/^[a-zA-Z]:/.test(specifier)) {
    return nextResolve(pathToFileURL(specifier).href, context);
  }
  return nextResolve(specifier, context);
}
'@
if (-not (Test-Path $shimPath)) {
    if (-not $DryRun) {
        Set-Content -Path $shimPath -Value $shimContent -NoNewline
    }
    $patchedAny = $true
}

$bootstrapPath = Join-Path $openclawRoot "openclaw.mjs"
if (-not (Test-Path $bootstrapPath)) {
    throw "openclaw.mjs not found: $bootstrapPath"
}
$bootstrapContent = Get-Content -Raw -Path $bootstrapPath
if ($bootstrapContent -notmatch "windows-esm-fix\.mjs") {
    $importNeedle = 'import { fileURLToPath } from "node:url";'
    $importInsert = @'
import { fileURLToPath } from "node:url";

// Windows-only loader shim for drive-letter ESM imports.
if (process.platform === "win32" && typeof module.register === "function") {
  try {
    module.register("./windows-esm-fix.mjs", import.meta.url);
  } catch {
    // Non-fatal: continue without the shim if registration fails.
  }
}
'@
    if ($bootstrapContent -notmatch [regex]::Escape($importNeedle)) {
        throw "openclaw.mjs import anchor not found; patch aborted."
    }
    if (-not $DryRun) {
        $bootstrapPatched = $bootstrapContent.Replace($importNeedle, $importInsert)
        Set-Content -Path $bootstrapPath -Value $bootstrapPatched -NoNewline
    }
    $patchedAny = $true
}

if ($DryRun) {
    if ($patchedAny) {
        Write-Host "[OK] Dry run: patch can be applied in $openclawRoot" -ForegroundColor Green
    } else {
        Write-Host "[OK] Dry run: patch already present in $openclawRoot" -ForegroundColor Green
    }
    exit 0
}

if ($patchedAny) {
    Write-Host "[OK] Applied Windows ESM patch set in $openclawRoot" -ForegroundColor Green
} else {
    Write-Host "[OK] Patch already applied in $openclawRoot" -ForegroundColor Green
}
