# OpenClaw Installer for Windows
# Usage: powershell -c "irm https://openclaw.ai/install.ps1 | iex"
#        powershell -c "& ([scriptblock]::Create((irm https://openclaw.ai/install.ps1))) -Tag beta -NoOnboard -DryRun"

param(
    [string]$Tag = "latest",
    [ValidateSet("npm", "git")]
    [string]$InstallMethod = "npm",
    [string]$GitDir,
    [switch]$NoOnboard,
    [switch]$NoGitUpdate,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# Mainland-friendly defaults (can be overridden by environment variables)
if ([string]::IsNullOrWhiteSpace($env:OPENCLAW_NPM_REGISTRY)) {
    $env:OPENCLAW_NPM_REGISTRY = "https://registry.npmmirror.com"
}
if ([string]::IsNullOrWhiteSpace($env:OPENCLAW_GITHUB_MIRROR)) {
    $env:OPENCLAW_GITHUB_MIRROR = "https://gh-proxy.com/"
}

function Get-NpmRegistry {
    if (-not [string]::IsNullOrWhiteSpace($env:OPENCLAW_NPM_REGISTRY)) {
        return $env:OPENCLAW_NPM_REGISTRY
    }
    return "https://registry.npmjs.org"
}

function Get-GitHubMirrorPrefix {
    if (-not [string]::IsNullOrWhiteSpace($env:OPENCLAW_GITHUB_MIRROR)) {
        return $env:OPENCLAW_GITHUB_MIRROR
    }
    return $null
}

function Convert-ToMirroredGitHubUrl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url
    )
    $prefix = Get-GitHubMirrorPrefix
    if ([string]::IsNullOrWhiteSpace($prefix)) {
        return $null
    }
    if (-not ($Url -match "^https://github\.com/")) {
        return $null
    }
    $normalizedPrefix = $prefix.TrimEnd("/")
    return "$normalizedPrefix/$Url"
}

function Invoke-WebRequestWithMirror {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [Parameter(Mandatory = $true)]
        [string]$OutFile
    )
    $mirrorUrl = Convert-ToMirroredGitHubUrl -Url $Url
    if ($mirrorUrl) {
        try {
            Invoke-WebRequest -Uri $mirrorUrl -OutFile $OutFile
            return
        } catch {
            Write-Host "[!] Mirror download failed, falling back to origin..." -ForegroundColor Yellow
        }
    }
    Invoke-WebRequest -Uri $Url -OutFile $OutFile
}

Write-Host ""
Write-Host "  OpenClaw Installer" -ForegroundColor Cyan
Write-Host ""

# Check if running in PowerShell
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "Error: PowerShell 5+ required" -ForegroundColor Red
    exit 1
}

Write-Host "[OK] Windows detected" -ForegroundColor Green

if (-not $PSBoundParameters.ContainsKey("InstallMethod")) {
    if (-not [string]::IsNullOrWhiteSpace($env:OPENCLAW_INSTALL_METHOD)) {
        $InstallMethod = $env:OPENCLAW_INSTALL_METHOD
    }
}
if (-not $PSBoundParameters.ContainsKey("GitDir")) {
    if (-not [string]::IsNullOrWhiteSpace($env:OPENCLAW_GIT_DIR)) {
        $GitDir = $env:OPENCLAW_GIT_DIR
    }
}
if (-not $PSBoundParameters.ContainsKey("NoOnboard")) {
    if ($env:OPENCLAW_NO_ONBOARD -eq "1") {
        $NoOnboard = $true
    }
}
if (-not $PSBoundParameters.ContainsKey("NoGitUpdate")) {
    if ($env:OPENCLAW_GIT_UPDATE -eq "0") {
        $NoGitUpdate = $true
    }
}
if (-not $PSBoundParameters.ContainsKey("DryRun")) {
    if ($env:OPENCLAW_DRY_RUN -eq "1") {
        $DryRun = $true
    }
}

if ([string]::IsNullOrWhiteSpace($GitDir)) {
    $userHome = [Environment]::GetFolderPath("UserProfile")
    $GitDir = (Join-Path $userHome "openclaw")
}

# Check for Node.js
function Check-Node {
    try {
        $nodeVersion = (node -v 2>$null)
        if ($nodeVersion) {
            $version = [int]($nodeVersion -replace 'v(\d+)\..*', '$1')
            if ($version -ge 22) {
                Write-Host "[OK] Node.js $nodeVersion found" -ForegroundColor Green
                return $true
            } else {
                Write-Host "[!] Node.js $nodeVersion found, but v22+ required" -ForegroundColor Yellow
                return $false
            }
        }
    } catch {
        Write-Host "[!] Node.js not found" -ForegroundColor Yellow
        return $false
    }
    return $false
}

# Install Node.js
function Install-Node {
    Write-Host "[*] Installing Node.js..." -ForegroundColor Yellow

    # Try winget first (Windows 11 / Windows 10 with App Installer)
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "  Using winget..." -ForegroundColor Gray
        winget install OpenJS.NodeJS.LTS --source winget --accept-package-agreements --accept-source-agreements

        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        if (Check-Node) {
            Write-Host "[OK] Node.js installed via winget" -ForegroundColor Green
            return
        }
        Write-Host "[!] winget completed, but Node.js is still unavailable in this shell" -ForegroundColor Yellow
        Write-Host "Restart PowerShell and re-run the installer if Node.js was installed successfully." -ForegroundColor Yellow
        exit 1
    }

    # Try Chocolatey
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Host "  Using Chocolatey..." -ForegroundColor Gray
        choco install nodejs-lts -y

        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        Write-Host "[OK] Node.js installed via Chocolatey" -ForegroundColor Green
        return
    }

    # Try Scoop
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        Write-Host "  Using Scoop..." -ForegroundColor Gray
        scoop install nodejs-lts
        Write-Host "[OK] Node.js installed via Scoop" -ForegroundColor Green
        return
    }

    # Manual download fallback
    Write-Host ""
    Write-Host "Error: Could not find a package manager (winget, choco, or scoop)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please install Node.js 22+ manually:" -ForegroundColor Yellow
    Write-Host "  https://nodejs.org/en/download/" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Or install winget (App Installer) from the Microsoft Store." -ForegroundColor Gray
    exit 1
}

# Check for existing OpenClaw installation
function Check-ExistingOpenClaw {
    if (Get-OpenClawCommandPath) {
        Write-Host "[*] Existing OpenClaw installation detected" -ForegroundColor Yellow
        return $true
    }
    return $false
}

function Check-Git {
    try {
        $null = Get-Command git -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Add-ToProcessPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PathEntry
    )

    if ([string]::IsNullOrWhiteSpace($PathEntry)) {
        return
    }

    $currentEntries = @($env:Path -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($currentEntries | Where-Object { $_ -ieq $PathEntry }) {
        return
    }

    $env:Path = "$PathEntry;$env:Path"
}

function Get-PortableGitRoot {
    $base = Join-Path $env:LOCALAPPDATA "OpenClaw\deps"
    return (Join-Path $base "portable-git")
}

function Get-PortableGitCommandPath {
    $root = Get-PortableGitRoot
    foreach ($candidate in @(
        (Join-Path $root "mingw64\bin\git.exe"),
        (Join-Path $root "cmd\git.exe"),
        (Join-Path $root "bin\git.exe"),
        (Join-Path $root "git.exe")
    )) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }
    return $null
}

function Use-PortableGitIfPresent {
    $gitExe = Get-PortableGitCommandPath
    if (-not $gitExe) {
        return $false
    }

    $portableRoot = Get-PortableGitRoot
    foreach ($pathEntry in @(
        (Join-Path $portableRoot "mingw64\bin"),
        (Join-Path $portableRoot "usr\bin"),
        (Split-Path -Parent $gitExe)
    )) {
        if (Test-Path $pathEntry) {
            Add-ToProcessPath $pathEntry
        }
    }
    if (Check-Git) {
        return $true
    }
    return $false
}

function Resolve-PortableGitDownload {
    $releaseApi = "https://api.github.com/repos/git-for-windows/git/releases/latest"
    $headers = @{
        "User-Agent" = "openclaw-installer"
        "Accept" = "application/vnd.github+json"
    }
    $release = Invoke-RestMethod -Uri $releaseApi -Headers $headers
    if (-not $release -or -not $release.assets) {
        throw "Could not resolve latest git-for-windows release metadata."
    }

    $asset = $release.assets |
        Where-Object { $_.name -match '^MinGit-.*-64-bit\.zip$' -and $_.name -notmatch 'busybox' } |
        Select-Object -First 1

    if (-not $asset) {
        throw "Could not find a MinGit zip asset in the latest git-for-windows release."
    }

    return @{
        Tag = $release.tag_name
        Name = $asset.name
        Url = $asset.browser_download_url
    }
}

function Install-PortableGit {
    if (Use-PortableGitIfPresent) {
        $portableVersion = (& git --version 2>$null)
        if ($portableVersion) {
            Write-Host "[OK] User-local Git already available: $portableVersion" -ForegroundColor Green
        }
        return
    }

    Write-Host "[*] Git not found; bootstrapping user-local portable Git..." -ForegroundColor Yellow

    $download = Resolve-PortableGitDownload
    $portableRoot = Get-PortableGitRoot
    $portableParent = Split-Path -Parent $portableRoot
    $tmpZip = Join-Path $env:TEMP $download.Name
    $tmpExtract = Join-Path $env:TEMP ("openclaw-portable-git-" + [guid]::NewGuid().ToString("N"))

    New-Item -ItemType Directory -Force -Path $portableParent | Out-Null
    if (Test-Path $portableRoot) {
        Remove-Item -Recurse -Force $portableRoot
    }
    if (Test-Path $tmpExtract) {
        Remove-Item -Recurse -Force $tmpExtract
    }
    New-Item -ItemType Directory -Force -Path $tmpExtract | Out-Null

    try {
        Write-Host "  Downloading $($download.Tag)..." -ForegroundColor Gray
        Invoke-WebRequestWithMirror -Url $download.Url -OutFile $tmpZip
        Expand-Archive -Path $tmpZip -DestinationPath $tmpExtract -Force
        Move-Item -Path (Join-Path $tmpExtract "*") -Destination $portableRoot -Force
    } finally {
        if (Test-Path $tmpZip) {
            Remove-Item -Force $tmpZip
        }
        if (Test-Path $tmpExtract) {
            Remove-Item -Recurse -Force $tmpExtract
        }
    }

    if (-not (Use-PortableGitIfPresent)) {
        throw "Portable Git bootstrap completed, but git is still unavailable."
    }

    $portableVersion = (& git --version 2>$null)
    Write-Host "[OK] User-local Git ready: $portableVersion" -ForegroundColor Green
}

function Ensure-Git {
    if (Check-Git) { return }
    if (Use-PortableGitIfPresent) { return }
    try {
        Install-PortableGit
        if (Check-Git) {
            return
        }
    } catch {
        Write-Host "[!] Portable Git bootstrap failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Error: Git is required to install OpenClaw." -ForegroundColor Red
    Write-Host "Auto-bootstrap of user-local Git did not succeed." -ForegroundColor Yellow
    Write-Host "Install Git for Windows manually, then re-run this installer:" -ForegroundColor Yellow
    Write-Host "  https://git-scm.com/download/win" -ForegroundColor Cyan
    exit 1
}

function Get-OpenClawCommandPath {
    $openclawCmd = Get-Command openclaw.cmd -ErrorAction SilentlyContinue
    if ($openclawCmd -and $openclawCmd.Source) {
        return $openclawCmd.Source
    }

    $openclaw = Get-Command openclaw -ErrorAction SilentlyContinue
    if ($openclaw -and $openclaw.Source) {
        return $openclaw.Source
    }

    return $null
}

function Invoke-OpenClawCommand {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    $commandPath = Get-OpenClawCommandPath
    if (-not $commandPath) {
        throw "openclaw command not found on PATH."
    }

    & $commandPath @Arguments
}

function Resolve-CommandPath {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Candidates
    )

    foreach ($candidate in $Candidates) {
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($command -and $command.Source) {
            return $command.Source
        }
    }

    return $null
}

function Get-NpmCommandPath {
    $path = Resolve-CommandPath -Candidates @("npm.cmd", "npm.exe", "npm")
    if (-not $path) {
        throw "npm not found on PATH."
    }
    return $path
}

function Get-CorepackCommandPath {
    return (Resolve-CommandPath -Candidates @("corepack.cmd", "corepack.exe", "corepack"))
}

function Get-PnpmCommandPath {
    return (Resolve-CommandPath -Candidates @("pnpm.cmd", "pnpm.exe", "pnpm"))
}

function Get-NpmGlobalBinCandidates {
    param(
        [string]$NpmPrefix
    )

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($NpmPrefix)) {
        $candidates += $NpmPrefix
        $candidates += (Join-Path $NpmPrefix "bin")
    }
    if (-not [string]::IsNullOrWhiteSpace($env:APPDATA)) {
        $candidates += (Join-Path $env:APPDATA "npm")
    }

    return $candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
}

function Ensure-OpenClawOnPath {
    if (Get-OpenClawCommandPath) {
        return $true
    }

    $npmPrefix = $null
    try {
        $npmPrefix = (& (Get-NpmCommandPath) config get prefix 2>$null).Trim()
    } catch {
        $npmPrefix = $null
    }

    $npmBins = Get-NpmGlobalBinCandidates -NpmPrefix $npmPrefix
    foreach ($npmBin in $npmBins) {
        if (-not (Test-Path (Join-Path $npmBin "openclaw.cmd"))) {
            continue
        }

        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if (-not ($userPath -split ";" | Where-Object { $_ -ieq $npmBin })) {
            [Environment]::SetEnvironmentVariable("Path", "$userPath;$npmBin", "User")
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            Write-Host "[!] Added $npmBin to user PATH (restart terminal if command not found)" -ForegroundColor Yellow
        }
        return $true
    }

    Write-Host "[!] openclaw is not on PATH yet." -ForegroundColor Yellow
    Write-Host "Restart PowerShell or add the npm global install folder to PATH." -ForegroundColor Yellow
    if ($npmBins.Count -gt 0) {
        Write-Host "Expected path (one of):" -ForegroundColor Gray
        foreach ($npmBin in $npmBins) {
            Write-Host "  $npmBin" -ForegroundColor Cyan
        }
    } else {
        Write-Host "Hint: run \"npm config get prefix\" to find your npm global path." -ForegroundColor Gray
    }
    return $false
}

function Ensure-Pnpm {
    if (Get-PnpmCommandPath) {
        return
    }
    $corepackCommand = Get-CorepackCommandPath
    if ($corepackCommand) {
        try {
            & $corepackCommand enable | Out-Null
            & $corepackCommand prepare pnpm@latest --activate | Out-Null
            if (Get-PnpmCommandPath) {
                Write-Host "[OK] pnpm installed via corepack" -ForegroundColor Green
                return
            }
        } catch {
            # fallthrough to npm install
        }
    }
    Write-Host "[*] Installing pnpm..." -ForegroundColor Yellow
    $prevScriptShell = $env:NPM_CONFIG_SCRIPT_SHELL
    $env:NPM_CONFIG_SCRIPT_SHELL = "cmd.exe"
    try {
        & (Get-NpmCommandPath) install -g pnpm --registry (Get-NpmRegistry)
    } finally {
        $env:NPM_CONFIG_SCRIPT_SHELL = $prevScriptShell
    }
    Write-Host "[OK] pnpm installed" -ForegroundColor Green
}

function Get-OpenClawPackageRoot {
    try {
        $npmRoot = (& (Get-NpmCommandPath) root -g 2>$null).Trim()
        if (-not [string]::IsNullOrWhiteSpace($npmRoot)) {
            $candidate = Join-Path $npmRoot "openclaw"
            if (Test-Path $candidate) {
                return $candidate
            }
        }
    } catch {
        # fallback below
    }
    if (-not [string]::IsNullOrWhiteSpace($env:APPDATA)) {
        $fallback = Join-Path $env:APPDATA "npm\node_modules\openclaw"
        if (Test-Path $fallback) {
            return $fallback
        }
    }
    return $null
}

function Apply-OpenClawWindowsEsmPatch {
    $installerDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $externalPatchScript = if (-not [string]::IsNullOrWhiteSpace($installerDir)) { Join-Path $installerDir "patch-openclaw-windows-esm.ps1" } else { $null }
    if ($externalPatchScript -and (Test-Path $externalPatchScript)) {
        try {
            & powershell -ExecutionPolicy Bypass -File $externalPatchScript | Out-Null
            Write-Host "[OK] Applied Windows ESM patch via patch-openclaw-windows-esm.ps1" -ForegroundColor Green
            return
        } catch {
            Write-Host "[!] External patch script failed; falling back to built-in patch." -ForegroundColor Yellow
        }
    }

    $openclawRoot = Get-OpenClawPackageRoot
    if (-not $openclawRoot) {
        Write-Host "[!] OpenClaw package root not found; skipping Windows ESM patch." -ForegroundColor Yellow
        return
    }

    $patchedAny = $false

    $jitiPath = Join-Path $openclawRoot "node_modules\jiti\lib\jiti.mjs"
    if (Test-Path $jitiPath) {
        $jitiContent = Get-Content -Raw -Path $jitiPath
        if (-not ($jitiContent -match "pathToFileURL" -and $jitiContent -match "isAbsolute")) {
            $needle = "const nativeImport = (id) => import(id);"
            if ($jitiContent -match [regex]::Escape($needle)) {
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
                $jitiPatched = $jitiContent.Replace($needle, $replacement)
                Set-Content -Path $jitiPath -Value $jitiPatched -NoNewline
                $patchedAny = $true
                Write-Host "[OK] Applied Windows ESM patch to jiti.mjs" -ForegroundColor Green
            } else {
                Write-Host "[!] Expected jiti import line not found; skipped jiti patch." -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "[!] jiti.mjs not found; skipped jiti patch." -ForegroundColor Yellow
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
        Set-Content -Path $shimPath -Value $shimContent -NoNewline
        $patchedAny = $true
        Write-Host "[OK] Added windows-esm-fix.mjs loader shim" -ForegroundColor Green
    }

    $bootstrapPath = Join-Path $openclawRoot "openclaw.mjs"
    if (Test-Path $bootstrapPath) {
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
            if ($bootstrapContent -match [regex]::Escape($importNeedle)) {
                $bootstrapPatched = $bootstrapContent.Replace($importNeedle, $importInsert)
                Set-Content -Path $bootstrapPath -Value $bootstrapPatched -NoNewline
                $patchedAny = $true
                Write-Host "[OK] Patched openclaw.mjs to register loader shim" -ForegroundColor Green
            } else {
                Write-Host "[!] openclaw.mjs import anchor not found; skipped bootstrap patch." -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "[!] openclaw.mjs not found; skipped bootstrap patch." -ForegroundColor Yellow
    }

    if (-not $patchedAny) {
        Write-Host "[OK] Windows ESM patch already present" -ForegroundColor Green
    }
}

# Install OpenClaw
function Install-OpenClaw {
    if ([string]::IsNullOrWhiteSpace($Tag)) {
        $Tag = "latest"
    }
    Ensure-Git

    # Use openclaw package for beta, openclaw for stable
    $packageName = "openclaw"
    if ($Tag -eq "beta" -or $Tag -match "^beta\.") {
        $packageName = "openclaw"
    }
    Write-Host "[*] Installing OpenClaw ($packageName@$Tag)..." -ForegroundColor Yellow
    Ensure-Pnpm
    $prevLogLevel = $env:NPM_CONFIG_LOGLEVEL
    $prevUpdateNotifier = $env:NPM_CONFIG_UPDATE_NOTIFIER
    $prevFund = $env:NPM_CONFIG_FUND
    $prevAudit = $env:NPM_CONFIG_AUDIT
    $prevScriptShell = $env:NPM_CONFIG_SCRIPT_SHELL
    $prevNodeLlamaSkipDownload = $env:NODE_LLAMA_CPP_SKIP_DOWNLOAD
    $prevNpmRegistry = $env:NPM_CONFIG_REGISTRY
    $env:NPM_CONFIG_LOGLEVEL = "error"
    $env:NPM_CONFIG_UPDATE_NOTIFIER = "false"
    $env:NPM_CONFIG_FUND = "false"
    $env:NPM_CONFIG_AUDIT = "false"
    $env:NPM_CONFIG_SCRIPT_SHELL = "cmd.exe"
    $env:NODE_LLAMA_CPP_SKIP_DOWNLOAD = "1"
    $env:NPM_CONFIG_REGISTRY = Get-NpmRegistry
    try {
        $pnpmCommand = Get-PnpmCommandPath
        $pnpmSucceeded = $false
        if ($pnpmCommand) {
            Write-Host "[*] Trying pnpm global install first..." -ForegroundColor Gray
            $pnpmOutput = & $pnpmCommand add -g "$packageName@$Tag" --registry (Get-NpmRegistry) 2>&1
            if ($LASTEXITCODE -eq 0) {
                $pnpmSucceeded = $true
            } else {
                Write-Host "[!] pnpm install failed, falling back to npm..." -ForegroundColor Yellow
                $pnpmOutput | ForEach-Object { Write-Host $_ }
            }
        }

        if (-not $pnpmSucceeded) {
            $npmOutput = & (Get-NpmCommandPath) install -g "$packageName@$Tag" 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "[!] npm install failed" -ForegroundColor Red
                if ($npmOutput -match "spawn git" -or $npmOutput -match "ENOENT.*git") {
                    Write-Host "Error: git is missing from PATH." -ForegroundColor Red
                    Write-Host "Install Git for Windows, then reopen PowerShell and retry:" -ForegroundColor Yellow
                    Write-Host "  https://git-scm.com/download/win" -ForegroundColor Cyan
                } else {
                    Write-Host "Re-run with verbose output to see the full error:" -ForegroundColor Yellow
                    Write-Host '  powershell -c "irm https://openclaw.ai/install.ps1 | iex"' -ForegroundColor Cyan
                }
                $npmOutput | ForEach-Object { Write-Host $_ }
                exit 1
            }
        }
    } finally {
        $env:NPM_CONFIG_LOGLEVEL = $prevLogLevel
        $env:NPM_CONFIG_UPDATE_NOTIFIER = $prevUpdateNotifier
        $env:NPM_CONFIG_FUND = $prevFund
        $env:NPM_CONFIG_AUDIT = $prevAudit
        $env:NPM_CONFIG_SCRIPT_SHELL = $prevScriptShell
        $env:NODE_LLAMA_CPP_SKIP_DOWNLOAD = $prevNodeLlamaSkipDownload
        $env:NPM_CONFIG_REGISTRY = $prevNpmRegistry
    }
    Write-Host "[OK] OpenClaw installed" -ForegroundColor Green
}

# Install OpenClaw from GitHub
function Install-OpenClawFromGit {
    param(
        [string]$RepoDir,
        [switch]$SkipUpdate
    )
    Ensure-Git
    Ensure-Pnpm

    $repoUrl = "https://github.com/openclaw/openclaw.git"
    $repoMirrorUrl = Convert-ToMirroredGitHubUrl -Url $repoUrl
    Write-Host "[*] Installing OpenClaw from GitHub ($repoUrl)..." -ForegroundColor Yellow

    if (-not (Test-Path $RepoDir)) {
        if ($repoMirrorUrl) {
            try {
                git clone $repoMirrorUrl $RepoDir
            } catch {
                Write-Host "[!] Mirror clone failed, falling back to origin..." -ForegroundColor Yellow
                git clone $repoUrl $RepoDir
            }
        } else {
            git clone $repoUrl $RepoDir
        }
    }

    if (-not $SkipUpdate) {
        if (-not (git -C $RepoDir status --porcelain 2>$null)) {
            git -C $RepoDir pull --rebase 2>$null
        } else {
            Write-Host "[!] Repo is dirty; skipping git pull" -ForegroundColor Yellow
        }
    } else {
        Write-Host "[!] Git update disabled; skipping git pull" -ForegroundColor Yellow
    }

    Remove-LegacySubmodule -RepoDir $RepoDir

    $prevPnpmScriptShell = $env:NPM_CONFIG_SCRIPT_SHELL
    $pnpmCommand = Get-PnpmCommandPath
    if (-not $pnpmCommand) {
        throw "pnpm not found after installation."
    }
    $env:NPM_CONFIG_SCRIPT_SHELL = "cmd.exe"
    try {
        & $pnpmCommand -C $RepoDir install
        if (-not (& $pnpmCommand -C $RepoDir ui:build)) {
            Write-Host "[!] UI build failed; continuing (CLI may still work)" -ForegroundColor Yellow
        }
        & $pnpmCommand -C $RepoDir build
    } finally {
        $env:NPM_CONFIG_SCRIPT_SHELL = $prevPnpmScriptShell
    }

    $binDir = Join-Path $env:USERPROFILE ".local\\bin"
    if (-not (Test-Path $binDir)) {
        New-Item -ItemType Directory -Force -Path $binDir | Out-Null
    }
    $cmdPath = Join-Path $binDir "openclaw.cmd"
    $cmdContents = "@echo off`r`nnode ""$RepoDir\\dist\\entry.js"" %*`r`n"
    Set-Content -Path $cmdPath -Value $cmdContents -NoNewline

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not ($userPath -split ";" | Where-Object { $_ -ieq $binDir })) {
        [Environment]::SetEnvironmentVariable("Path", "$userPath;$binDir", "User")
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        Write-Host "[!] Added $binDir to user PATH (restart terminal if command not found)" -ForegroundColor Yellow
    }

    Write-Host "[OK] OpenClaw wrapper installed to $cmdPath" -ForegroundColor Green
    Write-Host "[i] This checkout uses pnpm. For deps, run: pnpm install (avoid npm install in the repo)." -ForegroundColor Gray
}

# Run doctor for migrations (safe, non-interactive)
function Run-Doctor {
    Write-Host "[*] Running doctor to migrate settings..." -ForegroundColor Yellow
    try {
        Invoke-OpenClawCommand doctor --non-interactive
    } catch {
        # Ignore errors from doctor
    }
    Write-Host "[OK] Migration complete" -ForegroundColor Green
}

function Test-GatewayServiceLoaded {
    try {
        $statusJson = (Invoke-OpenClawCommand daemon status --json 2>$null)
        if ([string]::IsNullOrWhiteSpace($statusJson)) {
            return $false
        }
        $parsed = $statusJson | ConvertFrom-Json
        if ($parsed -and $parsed.service -and $parsed.service.loaded) {
            return $true
        }
    } catch {
        return $false
    }
    return $false
}

function Refresh-GatewayServiceIfLoaded {
    if (-not (Get-OpenClawCommandPath)) {
        return
    }
    if (-not (Test-GatewayServiceLoaded)) {
        return
    }

    Write-Host "[*] Refreshing loaded gateway service..." -ForegroundColor Yellow
    try {
        Invoke-OpenClawCommand gateway install --force | Out-Null
    } catch {
        Write-Host "[!] Gateway service refresh failed; continuing." -ForegroundColor Yellow
        return
    }

    try {
        Invoke-OpenClawCommand gateway restart | Out-Null
        Invoke-OpenClawCommand gateway status --json | Out-Null
        Write-Host "[OK] Gateway service refreshed" -ForegroundColor Green
    } catch {
        Write-Host "[!] Gateway service restart failed; continuing." -ForegroundColor Yellow
    }
}

function Get-LegacyRepoDir {
    if (-not [string]::IsNullOrWhiteSpace($env:OPENCLAW_GIT_DIR)) {
        return $env:OPENCLAW_GIT_DIR
    }
    $userHome = [Environment]::GetFolderPath("UserProfile")
    return (Join-Path $userHome "openclaw")
}

function Remove-LegacySubmodule {
    param(
        [string]$RepoDir
    )
    if ([string]::IsNullOrWhiteSpace($RepoDir)) {
        $RepoDir = Get-LegacyRepoDir
    }
    $legacyDir = Join-Path $RepoDir "Peekaboo"
    if (Test-Path $legacyDir) {
        Write-Host "[!] Removing legacy submodule checkout: $legacyDir" -ForegroundColor Yellow
        Remove-Item -Recurse -Force $legacyDir
    }
}

# Main installation flow
function Main {
    if ($InstallMethod -ne "npm" -and $InstallMethod -ne "git") {
        Write-Host "Error: invalid -InstallMethod (use npm or git)." -ForegroundColor Red
        exit 2
    }

    if ($DryRun) {
        Write-Host "[OK] Dry run" -ForegroundColor Green
        Write-Host "[OK] Install method: $InstallMethod" -ForegroundColor Green
        if ($InstallMethod -eq "git") {
            Write-Host "[OK] Git dir: $GitDir" -ForegroundColor Green
            if ($NoGitUpdate) {
                Write-Host "[OK] Git update: disabled" -ForegroundColor Green
            } else {
                Write-Host "[OK] Git update: enabled" -ForegroundColor Green
            }
        }
        if ($NoOnboard) {
            Write-Host "[OK] Onboard: skipped" -ForegroundColor Green
        }
        return
    }

    Remove-LegacySubmodule -RepoDir $RepoDir

    # Check for existing installation
    $isUpgrade = Check-ExistingOpenClaw

    # Step 1: Node.js
    if (-not (Check-Node)) {
        Install-Node

        # Verify installation
        if (-not (Check-Node)) {
            Write-Host ""
            Write-Host "Error: Node.js installation may require a terminal restart" -ForegroundColor Red
            Write-Host "Please close this terminal, open a new one, and run this installer again." -ForegroundColor Yellow
            exit 1
        }
    }

    $finalGitDir = $null

    # Step 2: OpenClaw
    if ($InstallMethod -eq "git") {
        $finalGitDir = $GitDir
        Install-OpenClawFromGit -RepoDir $GitDir -SkipUpdate:$NoGitUpdate
    } else {
        Install-OpenClaw
    }

    if (-not (Ensure-OpenClawOnPath)) {
        Write-Host "Install completed, but OpenClaw is not on PATH yet." -ForegroundColor Yellow
        Write-Host "Open a new terminal, then run: openclaw doctor" -ForegroundColor Cyan
        return
    }

    Refresh-GatewayServiceIfLoaded
    Apply-OpenClawWindowsEsmPatch

    # Step 3: Run doctor for migrations if upgrading or git install
    if ($isUpgrade -or $InstallMethod -eq "git") {
        Run-Doctor
    }

    $installedVersion = $null
    try {
        $installedVersion = (Invoke-OpenClawCommand --version 2>$null).Trim()
    } catch {
        $installedVersion = $null
    }
    if (-not $installedVersion) {
        try {
            $npmList = & (Get-NpmCommandPath) list -g --depth 0 --json 2>$null | ConvertFrom-Json
            if ($npmList -and $npmList.dependencies -and $npmList.dependencies.openclaw -and $npmList.dependencies.openclaw.version) {
                $installedVersion = $npmList.dependencies.openclaw.version
            }
        } catch {
            $installedVersion = $null
        }
    }

    Write-Host ""
    if ($installedVersion) {
        Write-Host "OpenClaw installed successfully ($installedVersion)!" -ForegroundColor Green
    } else {
        Write-Host "OpenClaw installed successfully!" -ForegroundColor Green
    }
    Write-Host ""
    if ($isUpgrade) {
        $updateMessages = @(
            "Leveled up! New skills unlocked. You're welcome.",
            "Fresh code, same lobster. Miss me?",
            "Back and better. Did you even notice I was gone?",
            "Update complete. I learned some new tricks while I was out.",
            "Upgraded! Now with 23% more sass.",
            "I've evolved. Try to keep up.",
            "New version, who dis? Oh right, still me but shinier.",
            "Patched, polished, and ready to pinch. Let's go.",
            "The lobster has molted. Harder shell, sharper claws.",
            "Update done! Check the changelog or just trust me, it's good.",
            "Reborn from the boiling waters of npm. Stronger now.",
            "I went away and came back smarter. You should try it sometime.",
            "Update complete. The bugs feared me, so they left.",
            "New version installed. Old version sends its regards.",
            "Firmware fresh. Brain wrinkles: increased.",
            "I've seen things you wouldn't believe. Anyway, I'm updated.",
            "Back online. The changelog is long but our friendship is longer.",
            "Upgraded! Peter fixed stuff. Blame him if it breaks.",
            "Molting complete. Please don't look at my soft shell phase.",
            "Version bump! Same chaos energy, fewer crashes (probably)."
        )
        Write-Host (Get-Random -InputObject $updateMessages) -ForegroundColor Gray
        Write-Host ""
    } else {
        $completionMessages = @(
            "Ahh nice, I like it here. Got any snacks? ",
            "Home sweet home. Don't worry, I won't rearrange the furniture.",
            "I'm in. Let's cause some responsible chaos.",
            "Installation complete. Your productivity is about to get weird.",
            "Settled in. Time to automate your life whether you're ready or not.",
            "Cozy. I've already read your calendar. We need to talk.",
            "Finally unpacked. Now point me at your problems.",
            "cracks claws Alright, what are we building?",
            "The lobster has landed. Your terminal will never be the same.",
            "All done! I promise to only judge your code a little bit."
        )
        Write-Host (Get-Random -InputObject $completionMessages) -ForegroundColor Gray
        Write-Host ""
    }

    if ($InstallMethod -eq "git") {
        Write-Host "Source checkout: $finalGitDir" -ForegroundColor Cyan
        Write-Host "Wrapper: $env:USERPROFILE\\.local\\bin\\openclaw.cmd" -ForegroundColor Cyan
        Write-Host ""
    }

    if ($isUpgrade) {
        Write-Host "Upgrade complete. Run " -NoNewline
        Write-Host "openclaw doctor" -ForegroundColor Cyan -NoNewline
        Write-Host " to check for additional migrations."
    } else {
        if ($NoOnboard) {
            Write-Host "Skipping onboard (requested). Run " -NoNewline
            Write-Host "openclaw onboard" -ForegroundColor Cyan -NoNewline
            Write-Host " later."
        } else {
            Write-Host "Starting setup..." -ForegroundColor Cyan
            Write-Host ""
            Invoke-OpenClawCommand onboard
        }
    }
}

Main
