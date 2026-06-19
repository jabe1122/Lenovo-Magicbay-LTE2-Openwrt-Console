# Changelog / 更新日志

## 1.0.1-r11

- Published two install packages: standard OpenWrt and GL.iNet SDK 4 variants.
- 发布两个安装包：标准 OpenWrt 版本和 GL.iNet SDK 4 版本。
- Kept identical runtime files in both packages, with different LuCI dependency names.
- 两个包保留相同运行文件，仅 LuCI 依赖包名不同。
- Marked the two packages as conflicting so they are not installed together.
- 将两个包标记为互斥，避免同时安装。

## 1.0.1-r10

- Switched package dependencies from GL.iNet SDK 4 LuCI package names to standard OpenWrt LuCI dependency names.
- 将软件包依赖从 GL.iNet SDK 4 LuCI 包名切换为标准 OpenWrt LuCI 依赖名称。
- Published a single architecture-independent `_all.ipk` for script/LuCI assets.
- 发布单个架构无关的 `_all.ipk`，用于脚本和 LuCI 页面资源。
- Clarified that the package targets Lenovo MagicBay LTE2 / ASR1803 modules, while GL.iNet OUI integration is optional.
- 明确本包面向 Lenovo MagicBay LTE2 / ASR1803 模块，GL.iNet OUI 集成为可选增强。

## 1.0.1-r9

- Added automatic detach cleanup for USB unplug events.
- 增加 USB 拔出事件的自动清理。
- Kept the GL Internet page synchronized with the MagicBay LTE2 cellular status.
- 让 GL 互联网页与 MagicBay LTE2 蜂窝状态保持同步。
- Displayed operator information instead of device identifiers in the Internet page.
- 在互联网页外层显示运营商信息，而不是设备标识。
- Removed unused APN credential fields from the netifd protocol helper.
- 移除 netifd 协议辅助脚本中未使用的 APN 凭据字段。
- Refreshed release artifacts and checksums after privacy cleanup.
- 隐私清理后刷新发布产物和校验文件。

## 1.0.1-r8

- Added hourly traffic statistics with download/upload bar charts.
- 增加按小时统计的下行/上行流量柱状图。
- Added annotated Chinese comments for recent logs.
- 为最近日志增加中文注释。
- Added GL.iNet OUI menu entry and fallback standalone page.
- 增加 GL.iNet OUI 菜单入口和独立 fallback 页面。
