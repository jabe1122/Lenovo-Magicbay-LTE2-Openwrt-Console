# Privacy Notes / 隐私说明

This package is designed to run locally on an OpenWrt router.

本软件包设计为在 OpenWrt 路由器本地运行。

The repository and release artifacts should not contain:

仓库和发布产物不应包含：

- router login credentials
- 路由器登录凭据
- personal local filesystem paths
- 个人本地文件路径
- runtime WAN addresses from a live connection
- 实时连接产生的运行时 WAN 地址
- SIM-specific subscriber identifiers
- SIM 专属用户标识
- device-unique serial values
- 设备唯一序列号
- authentication tokens or API keys
- 认证 token 或 API key

The package does include the USB product identifier `17ef:7005`, which is used
to recognize the supported Lenovo MagicBay LTE2 module model. That value is not
treated as a unique device serial number.

软件包包含 USB 产品标识 `17ef:7005`，用于识别受支持的 Lenovo MagicBay LTE2
模块型号。这个值不是单台设备唯一序列号。

Runtime status such as operator name, RSSI, assigned IP address, traffic bytes,
and recent logs is read from the router at runtime and is not committed to this
repository.

运营商名称、RSSI、分配到的 IP 地址、流量字节数和最近日志等运行时状态只会在路由器
运行时读取，不会提交到本仓库。
