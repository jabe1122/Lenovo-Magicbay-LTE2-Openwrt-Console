# Lenovo-Magicbay-LTE2-Openwrt-Console / Lenovo MagicBay LTE2 OpenWrt 控制台

OpenWrt/LuCI package for the Lenovo MagicBay LTE2 / ASR1803 USB MBIM module.

这是一个面向 Lenovo MagicBay LTE2 / ASR1803 USB MBIM 模块的 OpenWrt/LuCI 软件包。

If you happen to own a Lenovo MagicBay LTE2 that came with a ThinkPad purchase
and includes 1500 GB of free monthly traffic, and you also have an OpenWrt
router, this project helps the router recognize and use that module. It also
provides an OpenWrt-side module status page and traffic statistics. The project
was developed around the Lenovo MagicBay LTE2 and the GL.iNet MT3600BE router.

如果你正好有购买 ThinkPad 赠送的、每个月 1500 GB 免费流量的 MagicBay LTE2，
又有一台 OpenWrt 路由器，这个项目可以帮助路由器识别并使用这个模块上网。
它还附带 OpenWrt 内的模块状态显示和流量统计功能。本项目基于 Lenovo MagicBay
LTE2 及 GL.iNet MT3600BE 路由器开发。

The package exposes a `Lenovo MagicBay LTE2控制台` page in OpenWrt/GL.iNet
firmware and brings up the USB module as a cellular WAN. It handles MBIM
dialing, OpenWrt/GL cellular WAN status synchronization, traffic statistics,
annotated logs, and the ASR1803 all-zero Ethernet MAC receive-path quirk.

软件包会在 OpenWrt/GL.iNet 固件中提供 `Lenovo MagicBay LTE2控制台` 页面，
并把这个 USB 模块作为蜂窝网络 WAN 接口接入。它负责 MBIM 拨号、OpenWrt/GL
蜂窝 WAN 状态同步、流量统计、带注释日志，以及 ASR1803 入站数据包零 MAC 地址
的兼容修正。

## Compatibility / 兼容性定位

This project is Lenovo MagicBay LTE2 / ASR1803 focused. It is not a generic
manager for every USB cellular modem. Starting with `1.0.1-r10`, the package
uses standard OpenWrt LuCI dependency names and ships as a single `_all.ipk`
because it contains scripts and LuCI assets instead of compiled CPU-specific
binaries.

本项目面向 Lenovo MagicBay LTE2 / ASR1803 模块，不是所有 USB 蜂窝模块的通用管理器。
从 `1.0.1-r10` 开始，软件包使用标准 OpenWrt LuCI 依赖名称，并以单个 `_all.ipk`
发布，因为它主要由脚本和 LuCI 页面组成，不包含针对某个 CPU 架构编译的二进制。

The package was developed and tested on a GL.iNet MT3600BE running GL.iNet SDK 4
firmware, while `r10` is packaged for standard OpenWrt-style LuCI installs. The
GL.iNet OUI entry remains included as an optional enhancement; on routers
without GL.iNet OUI it is simply ignored. On stock or custom OpenWrt builds,
make sure the firmware provides the required MBIM, LuCI, traffic-control and
firewall components.

本包基于运行 GL.iNet SDK 4 固件的 GL.iNet MT3600BE 开发和测试。普通 OpenWrt
或其他定制固件需要具备 MBIM、LuCI、流量控制和防火墙相关组件。`r10` 已按标准
OpenWrt LuCI 安装方式打包；GL.iNet OUI 入口作为可选增强保留，在没有 GL.iNet
OUI 的路由器上会被自然忽略。

## Features / 功能

- MBIM dialing through `/dev/cdc-wdm0` and `wwan0`
- 通过 `/dev/cdc-wdm0` 和 `wwan0` 进行 MBIM 拨号
- automatic hotplug start and detach cleanup
- USB 热插拔自动启动，拔出时自动清理运行状态
- OpenWrt/GL cellular WAN status synchronization
- 同步 OpenWrt/GL 蜂窝网络 WAN 在线状态
- optional GL.iNet OUI application-menu entry
- 可选 GL.iNet OUI 应用菜单入口
- receive-path repair with `tc skbedit ptype host`
- 使用 `tc skbedit ptype host` 修正收包路径
- NAT and LAN forwarding setup
- 自动配置 NAT 和 LAN 转发
- operator, RSSI, registration and packet-service status display
- 显示运营商、RSSI、注册状态和数据业务状态
- hourly download/upload traffic bar chart
- 按小时展示下行/上行流量柱状图
- annotated Chinese comments for recent runtime logs
- 为最近运行日志添加中文注释
- legacy Lua LuCI page, modern LuCI JS page, and standalone fallback page
- 提供旧版 Lua LuCI 页面、现代 LuCI JS 页面，以及独立 fallback 页面

## Installation / 安装

Release artifacts are kept in `dist/`.

发布产物位于 `dist/` 目录。

For OpenWrt-style installs where the listed dependencies are available:

在依赖已满足的 OpenWrt 类固件上安装：

```sh
opkg update
opkg install /tmp/luci-app-mbim-lenovo_1.0.1-r10_all.ipk
/etc/init.d/rpcd reload
/etc/init.d/uhttpd reload
```

The same `_all.ipk` is used on the tested GL.iNet target. If your GL.iNet
firmware does not expose standard LuCI dependency names, build from source on
that firmware SDK or adjust dependencies for that firmware.

已测试的 GL.iNet 目标也使用同一个 `_all.ipk`。如果你的 GL.iNet 固件不提供标准
LuCI 依赖包名，请在对应固件 SDK 中源码编译，或按该固件的包名调整依赖。

```sh
opkg install /tmp/luci-app-mbim-lenovo_1.0.1-r10_all.ipk
/etc/init.d/rpcd reload
/etc/init.d/uhttpd reload
```

The package enables `/etc/init.d/mbim-lenovo` on install. If the module is
already plugged in, it should dial automatically.

安装后软件包会启用 `/etc/init.d/mbim-lenovo`。如果模块已经插入，服务会自动尝试拨号。

## Configuration / 配置

Default configuration file:

默认配置文件：

```sh
/etc/config/mbim-lenovo
```

Important defaults / 重要默认值：

- `device`: `/dev/cdc-wdm0`
- `iface`: `wwan0`
- `apn`: `cmnet`
- `use_netifd`: `0`
- `lan_if`: `br-lan`
- `metric`: `2`
- `usb_product`: `17ef:7005`
- `stats_interval`: `60`
- `stats_samples`: `2880`
- `native_gl_marker`: `0`
- `status_mbim_query`: `0`
- `auto_hotplug`: `1`

After changing config:

修改配置后执行：

```sh
/etc/init.d/mbim-lenovo restart
```

## Manual Control / 手动控制

```sh
/usr/bin/mbim-lenovo-up.sh status
/usr/bin/mbim-lenovo-up.sh start
/usr/bin/mbim-lenovo-up.sh stop
/usr/bin/mbim-lenovo-up.sh restart
/usr/bin/mbim-lenovo-up.sh detach
```

## Build With OpenWrt SDK / 使用 OpenWrt SDK 编译

Copy this directory to an OpenWrt source tree or SDK:

把本目录复制到 OpenWrt 源码树或 SDK：

```sh
cp -a luci-app-mbim-lenovo package/
make package/luci-app-mbim-lenovo/compile V=s
```

## Privacy / 隐私

This repository intentionally avoids storing router credentials, SIM identifiers,
runtime IP addresses, personal paths, or device-unique serial data. The USB
product ID `17ef:7005` is used only to identify the supported module model.

本仓库有意避免保存路由器登录凭据、SIM 标识、运行时 WAN 地址、个人本地路径或设备唯一序列号。
USB 产品 ID `17ef:7005` 仅用于识别受支持的模块型号。

See [PRIVACY.md](PRIVACY.md) for more detail.

更多说明见 [PRIVACY.md](PRIVACY.md)。

## Validation / 验证

The GitHub workflow checks shell syntax, release checksums, and common private
runtime-data patterns. Locally, you can run the same basic checks with:

GitHub 工作流会检查 shell 语法、发布文件校验和，以及常见运行时隐私数据模式。本地也可以运行：

```sh
sh -n root/usr/bin/mbim-lenovo-up.sh
sh -n root/etc/init.d/mbim-lenovo
sh -n root/etc/uci-defaults/99-mbim-lenovo
sh -n root/etc/hotplug.d/usb/99-mbim-lenovo
sh -n root/etc/hotplug.d/iface/99-mbim-lenovo
sh -n root/lib/netifd/proto/mbim_lenovo.sh
cd dist && sha256sum -c SHA256SUMS.txt
```

## License / 许可证

MIT. See [LICENSE](LICENSE).

本项目使用 MIT 许可证，详见 [LICENSE](LICENSE)。
