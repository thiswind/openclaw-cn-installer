# OpenClaw 国内安装脚本（中文主说明）

这个仓库提供一个面向中国大陆网络环境优化的 OpenClaw Windows 安装脚本。

## 这个脚本做了什么

- 默认使用国内 npm 镜像：`https://registry.npmmirror.com`
- GitHub 下载与克隆支持“镜像优先、源站回退”
- 全局安装 OpenClaw 时采用 `pnpm` 优先，失败自动回退到 `npm`
- 安装完成后自动尝试应用 Windows ESM 热补丁（幂等）
- 尽量保持与官方安装脚本一致的流程，减少额外行为

## 文件说明

- `install-openclaw-cn.ps1`：主安装脚本
- `patch-openclaw-windows-esm.ps1`：Windows ESM 热补丁脚本（可单独执行）
- `repair-openclaw-windows.ps1`：一键修复（可选 `npm` 全局重装 + 打 ESM 补丁；默认结束后尝试 `openclaw gateway restart`）

## Windows ESM 热补丁说明

这个补丁专门用于缓解 OpenClaw 在原生 Windows 下常见的：
`ERR_UNSUPPORTED_ESM_URL_SCHEME`（`Received protocol 'c:'`）问题。

### 补丁做了什么

- 定位全局安装目录中的 `openclaw/node_modules/jiti/lib/jiti.mjs`
- 将 `nativeImport` 的 Windows 绝对路径导入逻辑改为 `file://` URL 导入
- 幂等执行：如果已打过补丁，会自动跳过，不会重复改坏

### 什么时候会被覆盖

- 当你执行 `npm/pnpm` 升级或重装 `openclaw` 后，`node_modules` 可能被重写，补丁可能失效。
- 本仓库的 `install-openclaw-cn.ps1` 已内置“安装后自动尝试打补丁”的流程。

### 手动重打补丁（一行命令）

```powershell
powershell -ExecutionPolicy Bypass -File .\patch-openclaw-windows-esm.ps1
```

### 一键修复（补丁 + 可选重装 + 重启 Gateway）

默认：只打 ESM 补丁，并尝试 `openclaw gateway restart`（可用 `-NoGatewayRestart` 跳过）。

```powershell
powershell -ExecutionPolicy Bypass -File .\repair-openclaw-windows.ps1
```

若升级/重装后希望先拉干净包再打补丁：

```powershell
powershell -ExecutionPolicy Bypass -File .\repair-openclaw-windows.ps1 -Reinstall -Tag latest
```

若国内镜像拉到的包出现 `dist` 内语法错误（例如乱码、未闭合字符串），可对 `-Reinstall` 指定官方源：

```powershell
powershell -ExecutionPolicy Bypass -File .\repair-openclaw-windows.ps1 -Reinstall -Tag 2026.4.5 -Registry https://registry.npmjs.org
```

## 快速开始（Windows PowerShell）

本地执行安装（跳过首次向导）：

```powershell
powershell -ExecutionPolicy Bypass -File .\install-openclaw-cn.ps1 -NoOnboard
```

仅检查流程（不实际安装）：

```powershell
powershell -ExecutionPolicy Bypass -File .\install-openclaw-cn.ps1 -DryRun
```

## 可选环境变量（用于覆盖默认镜像）

- `OPENCLAW_NPM_REGISTRY`：自定义 npm registry  
  默认值：`https://registry.npmmirror.com`
- `OPENCLAW_GITHUB_MIRROR`：自定义 GitHub 镜像前缀  
  默认值：`https://gh-proxy.com/`

示例：

```powershell
$env:OPENCLAW_NPM_REGISTRY="https://registry.npmmirror.com"
$env:OPENCLAW_GITHUB_MIRROR="https://gh-proxy.com/"
powershell -ExecutionPolicy Bypass -File .\install-openclaw-cn.ps1
```

## 说明与建议

- 适用于原生 Windows PowerShell 环境。
- 如果 OpenClaw 官方脚本后续有更新，建议基于最新官方版本重新同步本仓库改动。

## 常见问题（FAQ）

### 1) 配置时报错 `ERR_UNSUPPORTED_ESM_URL_SCHEME` 是什么？

这是 OpenClaw 在原生 Windows 上的已知问题之一，典型报错是：

`Only URLs with a scheme in: file, data, and node ... Received protocol 'c:'`

根因是某些动态导入路径在 Windows 下没有被正确转换为 `file://` URL。

### 2) 官方现在修好了吗？

截至目前，官方最新正式发布仍是 `v2026.4.5`：  
<https://github.com/openclaw/openclaw/releases/tag/v2026.4.5>

同时，相关问题仍有 **OPEN** 的 issue（说明在最新正式版场景下仍有人持续复现）：  
- #61899（OPEN）  
  <https://github.com/openclaw/openclaw/issues/61899>

另有同类问题已被关闭并标记修复（说明官方在 `main` 分支已经做过修复）：  
- #61795（CLOSED）  
  <https://github.com/openclaw/openclaw/issues/61795>
- #61810（CLOSED）  
  <https://github.com/openclaw/openclaw/issues/61810>
- #61911（CLOSED）  
  <https://github.com/openclaw/openclaw/issues/61911>

### 3) 有没有“看起来有效但还没合并”的修复 PR？

有，当前可追踪到：

- #62444（OPEN）：`fix(windows): resolve ERR_UNSUPPORTED_ESM_URL_SCHEME on native Windows`  
  <https://github.com/openclaw/openclaw/pull/62444>

另外，下面这些修复已进入主分支，但是否包含在你安装到的 release 里，取决于后续正式发版：

- #62286（MERGED）  
  <https://github.com/openclaw/openclaw/pull/62286>
- #61832（CLOSED，说明同类修复已由维护者以其他方式落地）  
  <https://github.com/openclaw/openclaw/pull/61832>

### 4) 这个仓库的脚本能完全解决这个 Windows 问题吗？

不能保证 100% 解决。  
本仓库脚本除了优化安装与下载链路（国内镜像、`pnpm` 优先、回退策略），也会在安装后自动对本地 `jiti.mjs` 执行热补丁；但由于上游变更、安装形态差异或未来文件结构变化，仍无法保证所有环境都一次修复。  
如果你遇到该报错，建议关注上面的 issue/PR 进展，或优先使用 WSL2 路径。

---

## English (Secondary)

This repository contains a China-network-friendly Windows installer for OpenClaw:

- Default npm mirror: `https://registry.npmmirror.com`
- GitHub mirror-first with origin fallback
- `pnpm`-first global install with `npm` fallback
- Keeps upstream installer flow as close as possible
