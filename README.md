# OpenClaw 国内安装脚本（中文主说明）

这个仓库提供一个面向中国大陆网络环境优化的 OpenClaw Windows 安装脚本。

## 这个脚本做了什么

- 默认使用国内 npm 镜像：`https://registry.npmmirror.com`
- GitHub 下载与克隆支持“镜像优先、源站回退”
- 全局安装 OpenClaw 时采用 `pnpm` 优先，失败自动回退到 `npm`
- 尽量保持与官方安装脚本一致的流程，减少额外行为

## 文件说明

- `install-openclaw-cn.ps1`：主安装脚本

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

---

## English (Secondary)

This repository contains a China-network-friendly Windows installer for OpenClaw:

- Default npm mirror: `https://registry.npmmirror.com`
- GitHub mirror-first with origin fallback
- `pnpm`-first global install with `npm` fallback
- Keeps upstream installer flow as close as possible
