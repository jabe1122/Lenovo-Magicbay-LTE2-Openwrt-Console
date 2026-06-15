# luci-app-mbim-lenovo Installation Guide / 安装说明

This package is for the Lenovo MagicBay LTE2 / ASR1803 USB MBIM module. It
turns the manual bring-up process into an installable OpenWrt package: MBIM
dialing, `wwan0` configuration, all-zero MAC receive repair, default route,
DNS, NAT/forwarding, autostart, and LuCI status/control pages.

这个包用于 Lenovo MagicBay LTE2 / ASR1803 USB MBIM 模块，会把手工调通流程
做成可安装的 OpenWrt 软件包：MBIM 拨号、`wwan0` 配置、零 MAC 入站包修正、
默认路由、DNS、NAT/转发、开机自启，以及 LuCI 状态/控制页面。

The page also includes:

页面还包含：

- annotated Chinese comments for recent log lines
- 每条最近日志后的中文注释
- recent traffic bar charts, with blue for download and orange for upload
- 最近流量统计柱状图，蓝色为下行流量，橙色为上行流量

## Install / 安装

For standard OpenWrt-style installs, use the architecture-independent package:

标准 OpenWrt 使用通用包：

```sh
opkg update
opkg install /tmp/luci-app-mbim-lenovo_1.0.1-r9_all.ipk
/etc/init.d/rpcd reload
/etc/init.d/uhttpd reload
```

For the tested GL.iNet firmware, use the architecture-matched package because
its LuCI dependency name is `gl-sdk4-luci`:

当前已测试的 GL.iNet 固件使用架构匹配包，因为它的 LuCI 依赖包名是 `gl-sdk4-luci`：

```sh
opkg install /tmp/luci-app-mbim-lenovo_1.0.1-r9_aarch64_cortex-a53.ipk
/etc/init.d/rpcd reload
/etc/init.d/uhttpd reload
```

After installation, the service is enabled and tries to start automatically:

安装后服务会自动启用并尝试启动：

```sh
/etc/init.d/mbim-lenovo status
/usr/bin/mbim-lenovo-up.sh status
```

## Web UI Entry / 管理界面入口

Standard LuCI:

标准 LuCI：

```text
Applications/Services -> Lenovo MagicBay LTE2控制台
应用程序/服务 -> Lenovo MagicBay LTE2控制台
```

Fallback URL for older or custom LuCI builds:

兼容旧版或定制 LuCI 的直接地址：

```text
http://router-address/cgi-bin/luci/admin/services/mbim_lenovo
http://路由器地址/cgi-bin/luci/admin/services/mbim_lenovo
```

## Default Configuration / 默认配置

Configuration file:

配置文件：

```sh
/etc/config/mbim-lenovo
```

Defaults / 默认值：

- device / 设备：`/dev/cdc-wdm0`
- network interface / 网卡：`wwan0`
- APN：`cmnet`
- LAN：`br-lan`
- default route metric / 默认路由 metric：`2`
- USB ID：`17ef:7005`
- traffic sampling interval / 流量统计后台采样间隔：`60` 秒
- retained traffic samples / 流量统计保留采样：`2880` 条

After changing APN or interface settings:

修改 APN 或接口后执行：

```sh
/etc/init.d/mbim-lenovo restart
```

## Manual Control / 手动控制

```sh
/usr/bin/mbim-lenovo-up.sh start
/usr/bin/mbim-lenovo-up.sh stop
/usr/bin/mbim-lenovo-up.sh restart
/usr/bin/mbim-lenovo-up.sh status
/usr/bin/mbim-lenovo-up.sh detach
```

## Build From Source / 源码编译

Copy the source directory into an OpenWrt SDK or source tree:

源码包解压后放进 OpenWrt SDK 或源码树：

```sh
cp -a luci-app-mbim-lenovo package/luci-app-mbim-lenovo
make package/luci-app-mbim-lenovo/compile V=s
```
