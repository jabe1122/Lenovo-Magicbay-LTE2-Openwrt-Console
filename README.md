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
manager for every USB cellular modem. Starting with `1.0.1-r11`, releases ship
two architecture-independent packages because the runtime is made of scripts
and LuCI assets instead of compiled CPU-specific binaries.

本项目面向 Lenovo MagicBay LTE2 / ASR1803 模块，不是所有 USB 蜂窝模块的通用管理器。
从 `1.0.1-r11` 开始，发布物提供两个架构无关软件包，因为运行时代码主要由脚本和
LuCI 页面组成，不包含针对某个 CPU 架构编译的二进制。

The package was developed and tested on a GL.iNet MT3600BE running GL.iNet SDK 4
firmware. The standard OpenWrt package depends on `luci-base`; the GL.iNet
package depends on `gl-sdk4-luci` and `gl-sdk4-lua-utils`. Both packages install
the same runtime files, so choose one package for your firmware and do not
install both at the same time.

本包基于运行 GL.iNet SDK 4 固件的 GL.iNet MT3600BE 开发和测试。普通 OpenWrt
软件包依赖 `luci-base`；GL.iNet 软件包依赖 `gl-sdk4-luci` 和 `gl-sdk4-lua-utils`。
两个包安装的是同一套运行文件，请按固件选择其中一个，不要同时安装。

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

For standard OpenWrt or custom firmware with standard LuCI package names:

标准 OpenWrt 或使用标准 LuCI 包名的定制固件：

```sh
opkg update
opkg install /tmp/luci-app-mbim-lenovo_1.0.1-r11_all.ipk
/etc/init.d/rpcd reload
/etc/init.d/uhttpd reload
```

For GL.iNet SDK 4 firmware using GL.iNet LuCI dependency names:

使用 GL.iNet LuCI 依赖包名的 GL.iNet SDK 4 固件：

```sh
opkg install /tmp/luci-app-mbim-lenovo-glinet_1.0.1-r11_all.ipk
/etc/init.d/rpcd reload
/etc/init.d/uhttpd reload
```

The package enables `/etc/init.d/mbim-lenovo` on install. If the module is
already plugged in, it should dial automatically.

安装后软件包会启用 `/etc/init.d/mbim-lenovo`。如果模块已经插入，服务会自动尝试拨号。

If you switch between the standard and GL.iNet packages, remove the previously
installed variant first because the two packages install the same runtime files.

如果要在标准包和 GL.iNet 包之间切换，请先卸载已经安装的另一种包，因为两个包安装的是
同一套运行文件。

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
