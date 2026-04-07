# OpenClaw CN Installer

Windows-friendly OpenClaw installer script with:

- Mainland China npm mirror by default (`registry.npmmirror.com`)
- GitHub download/clone mirror fallback support
- `pnpm`-first global install strategy with automatic fallback to `npm`
- Original OpenClaw installer flow preserved as much as possible

## Files

- `install-openclaw-cn.ps1`: the installer script

## Quick Start

Run from local file:

```powershell
powershell -ExecutionPolicy Bypass -File .\install-openclaw-cn.ps1 -NoOnboard
```

Dry run:

```powershell
powershell -ExecutionPolicy Bypass -File .\install-openclaw-cn.ps1 -DryRun
```

## Optional Environment Variables

- `OPENCLAW_NPM_REGISTRY`: override npm registry (default: `https://registry.npmmirror.com`)
- `OPENCLAW_GITHUB_MIRROR`: override GitHub mirror prefix (default: `https://gh-proxy.com/`)

Example:

```powershell
$env:OPENCLAW_NPM_REGISTRY="https://registry.npmmirror.com"
$env:OPENCLAW_GITHUB_MIRROR="https://gh-proxy.com/"
powershell -ExecutionPolicy Bypass -File .\install-openclaw-cn.ps1
```

## Notes

- This script is intended for native Windows PowerShell usage.
- If OpenClaw upstream releases newer installers, consider rebasing changes onto the latest script.
