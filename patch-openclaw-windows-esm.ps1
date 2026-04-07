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

function Apply-TextReplacements {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [array]$Replacements
    )
    if (-not (Test-Path $Path)) {
        return $false
    }
    $content = Get-Content -Raw -Path $Path
    $updated = $content
    $changed = $false
    foreach ($pair in $Replacements) {
        $old = $pair[0]
        $new = $pair[1]
        if ($updated.Contains($old)) {
            $updated = $updated.Replace($old, $new)
            $changed = $true
        }
    }
    if ($changed -and -not $DryRun) {
        Set-Content -Path $Path -Value $updated -NoNewline
    }
    return $changed
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

$jitiCjsPath = Join-Path $openclawRoot "node_modules\jiti\lib\jiti.cjs"
if (Test-Path $jitiCjsPath) {
    $patchedAny = (Apply-TextReplacements -Path $jitiCjsPath -Replacements @(
        @('const { createRequire } = require("node:module");', 'const { createRequire } = require("node:module");' + "`n" + 'const { pathToFileURL } = require("node:url");' + "`n" + 'const { isAbsolute } = require("node:path");'),
        @('const nativeImport = (id) => import(id);', 'const nativeImport = (id) =>' + "`n" + '  import(' + "`n" + '    process.platform === "win32" && typeof id === "string" && isAbsolute(id)' + "`n" + '      ? pathToFileURL(id).href' + "`n" + '      : id,' + "`n" + '  );')
    )) -or $patchedAny
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

$distDir = Join-Path $openclawRoot "dist"
$patchedAny = (Apply-TextReplacements -Path (Join-Path $distDir "loader-BkajlJCF.js") -Replacements @(
    @('import path from "node:path";', 'import path from "node:path";' + "`n" + 'import { pathToFileURL } from "node:url";'),
    @('const defaultLogger = () => createSubsystemLogger("plugins");', 'const defaultLogger = () => createSubsystemLogger("plugins");' + "`n" + 'function toSafeImportPath(specifier) {' + "`n" + "`t" + 'if (process.platform !== "win32") return specifier;' + "`n" + "`t" + 'if (specifier.startsWith("file://")) return specifier;' + "`n" + "`t" + 'if (path.win32.isAbsolute(specifier)) return pathToFileURL(specifier).href;' + "`n" + "`t" + 'return specifier;' + "`n" + '}'),
    @('getJiti(runtimeModulePath)(runtimeModulePath)', 'getJiti(runtimeModulePath)(toSafeImportPath(runtimeModulePath))'),
    @('getJiti(safeSource)(safeSource)', 'getJiti(safeSource)(toSafeImportPath(safeSource))')
)) -or $patchedAny

$patchedAny = (Apply-TextReplacements -Path (Join-Path $distDir "channel-entry-contract-DyY5TZkc.js") -Replacements @(
    @('import { fileURLToPath } from "node:url";', 'import { fileURLToPath, pathToFileURL } from "node:url";'),
    @('return opened.path;' + "`n" + '}', 'return opened.path;' + "`n" + '}' + "`n" + 'function toSafeImportPath(specifier) {' + "`n" + "`t" + 'if (process.platform !== "win32") return specifier;' + "`n" + "`t" + 'if (specifier.startsWith("file://")) return specifier;' + "`n" + "`t" + 'if (path.win32.isAbsolute(specifier)) return pathToFileURL(specifier).href;' + "`n" + "`t" + 'return specifier;' + "`n" + '}'),
    @('shouldPreferNativeJiti(modulePath) || modulePath.includes(`${path.sep}dist${path.sep}`)', 'shouldPreferNativeJiti(modulePath) || process.platform !== "win32" && modulePath.includes(`${path.sep}dist${path.sep}`)'),
    @('getJiti(modulePath)(modulePath)', 'getJiti(modulePath)(toSafeImportPath(modulePath))')
)) -or $patchedAny

$patchedAny = (Apply-TextReplacements -Path (Join-Path $distDir "facade-runtime-Bv3MxT2V.js") -Replacements @(
    @('import { fileURLToPath } from "node:url";', 'import { fileURLToPath, pathToFileURL } from "node:url";'),
    @('const loadedFacadePluginIds = /* @__PURE__ */ new Set();', 'const loadedFacadePluginIds = /* @__PURE__ */ new Set();' + "`n" + 'function toSafeImportPath(specifier) {' + "`n" + "`t" + 'if (process.platform !== "win32") return specifier;' + "`n" + "`t" + 'if (specifier.startsWith("file://")) return specifier;' + "`n" + "`t" + 'if (path.win32.isAbsolute(specifier)) return pathToFileURL(specifier).href;' + "`n" + "`t" + 'return specifier;' + "`n" + '}'),
    @('shouldPreferNativeJiti(modulePath) || modulePath.includes(`${path.sep}dist${path.sep}`)', 'shouldPreferNativeJiti(modulePath) || process.platform !== "win32" && modulePath.includes(`${path.sep}dist${path.sep}`)'),
    @('getJiti(location.modulePath)(location.modulePath)', 'getJiti(location.modulePath)(toSafeImportPath(location.modulePath))')
)) -or $patchedAny

$patchedAny = (Apply-TextReplacements -Path (Join-Path $distDir "zod-schema-C3jh3SvI.js") -Replacements @(
    @('import { fileURLToPath } from "node:url";', 'import { fileURLToPath, pathToFileURL } from "node:url";'),
    @('const jitiLoaders = /* @__PURE__ */ new Map();', 'const jitiLoaders = /* @__PURE__ */ new Map();' + "`n" + 'function toSafeImportPath(specifier) {' + "`n" + "`t" + 'if (process.platform !== "win32") return specifier;' + "`n" + "`t" + 'if (specifier.startsWith("file://")) return specifier;' + "`n" + "`t" + 'if (path.win32.isAbsolute(specifier)) return pathToFileURL(specifier).href;' + "`n" + "`t" + 'return specifier;' + "`n" + '}'),
    @('shouldPreferNativeJiti(modulePath) || modulePath.includes(`${path.sep}dist${path.sep}`)', 'shouldPreferNativeJiti(modulePath) || process.platform !== "win32" && modulePath.includes(`${path.sep}dist${path.sep}`)'),
    @('getJiti(modulePath)(modulePath)', 'getJiti(modulePath)(toSafeImportPath(modulePath))')
)) -or $patchedAny

$patchedAny = (Apply-TextReplacements -Path (Join-Path $distDir "bootstrap-registry-DSG7nIY1.js") -Replacements @(
    @('import path from "node:path";', 'import path from "node:path";' + "`n" + 'import { pathToFileURL } from "node:url";'),
    @('const nodeRequire = createRequire(import.meta.url);', 'const nodeRequire = createRequire(import.meta.url);' + "`n" + 'function toSafeImportPath(specifier) {' + "`n" + "`t" + 'if (process.platform !== "win32") return specifier;' + "`n" + "`t" + 'if (specifier.startsWith("file://")) return specifier;' + "`n" + "`t" + 'if (path.win32.isAbsolute(specifier)) return pathToFileURL(specifier).href;' + "`n" + "`t" + 'return specifier;' + "`n" + '}'),
    @('shouldPreferNativeJiti(modulePath) || modulePath.includes(`${path.sep}dist${path.sep}`)', 'shouldPreferNativeJiti(modulePath) || process.platform !== "win32" && modulePath.includes(`${path.sep}dist${path.sep}`)'),
    @('loadModule(safePath)(safePath)', 'loadModule(safePath)(toSafeImportPath(safePath))')
)) -or $patchedAny

$patchedAny = (Apply-TextReplacements -Path (Join-Path $distDir "config-presence-Bwyumb-a.js") -Replacements @(
    @('import path from "node:path";', 'import path from "node:path";' + "`n" + 'import { pathToFileURL } from "node:url";'),
    @('const registryCache = /* @__PURE__ */ new Map();', 'const registryCache = /* @__PURE__ */ new Map();' + "`n" + 'function toSafeImportPath(specifier) {' + "`n" + "`t" + 'if (process.platform !== "win32") return specifier;' + "`n" + "`t" + 'if (specifier.startsWith("file://")) return specifier;' + "`n" + "`t" + 'if (path.win32.isAbsolute(specifier)) return pathToFileURL(specifier).href;' + "`n" + "`t" + 'return specifier;' + "`n" + '}'),
    @('shouldPreferNativeJiti(modulePath) || modulePath.includes(`${path.sep}dist${path.sep}`)', 'shouldPreferNativeJiti(modulePath) || process.platform !== "win32" && modulePath.includes(`${path.sep}dist${path.sep}`)'),
    @('loadModule(safePath)(safePath)', 'loadModule(safePath)(toSafeImportPath(safePath))')
)) -or $patchedAny

$patchedAny = (Apply-TextReplacements -Path (Join-Path $distDir "setup-registry-CLKO_jQP.js") -Replacements @(
    @('import { fileURLToPath } from "node:url";', 'import { fileURLToPath, pathToFileURL } from "node:url";'),
    @('const setupProviderCache = /* @__PURE__ */ new Map();', 'const setupProviderCache = /* @__PURE__ */ new Map();' + "`n" + 'function toSafeImportPath(specifier) {' + "`n" + "`t" + 'if (process.platform !== "win32") return specifier;' + "`n" + "`t" + 'if (specifier.startsWith("file://")) return specifier;' + "`n" + "`t" + 'if (path.win32.isAbsolute(specifier)) return pathToFileURL(specifier).href;' + "`n" + "`t" + 'return specifier;' + "`n" + '}'),
    @('getJiti(setupSource)(setupSource)', 'getJiti(setupSource)(toSafeImportPath(setupSource))')
)) -or $patchedAny

$patchedAny = (Apply-TextReplacements -Path (Join-Path $distDir "io-CS2J_l4V.js") -Replacements @(
    @('import { fileURLToPath } from "node:url";', 'import { fileURLToPath, pathToFileURL } from "node:url";'),
    @('const doctorContractCache = /* @__PURE__ */ new Map();', 'const doctorContractCache = /* @__PURE__ */ new Map();' + "`n" + 'function toSafeImportPath(specifier) {' + "`n" + "`t" + 'if (process.platform !== "win32") return specifier;' + "`n" + "`t" + 'if (specifier.startsWith("file://")) return specifier;' + "`n" + "`t" + 'if (path.win32.isAbsolute(specifier)) return pathToFileURL(specifier).href;' + "`n" + "`t" + 'return specifier;' + "`n" + '}'),
    @('getJiti(contractSource)(contractSource)', 'getJiti(contractSource)(toSafeImportPath(contractSource))')
)) -or $patchedAny

$patchedAny = (Apply-TextReplacements -Path (Join-Path $distDir "pi-embedded-DWASRjxE.js") -Replacements @(
    @('import { fileURLToPath } from "node:url";', 'import { fileURLToPath, pathToFileURL } from "node:url";'),
    @('getJiti(safeSource)(safeSource)', 'getJiti(safeSource)(process.platform === "win32" && path.win32.isAbsolute(safeSource) ? pathToFileURL(safeSource).href : safeSource)')
)) -or $patchedAny

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
