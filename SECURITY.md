# Security Policy / 安全策略

## Supported Versions / 支持版本

The latest tagged release is the supported version.

最新 tag 对应的发布版本为当前支持版本。

## Reporting A Vulnerability / 报告漏洞

Please open a GitHub issue with reproduction details and the affected release
version. Do not include router credentials, SIM identifiers, or other private
runtime data in public reports.

请通过 GitHub issue 提交复现步骤和受影响版本。请不要在公开报告中包含路由器凭据、
SIM 标识或其他运行时隐私数据。

## Operational Notes / 运行注意事项

This package configures a cellular WAN interface, NAT/forwarding rules, and
runtime status pages. Review changes before installing on routers that expose
management interfaces to untrusted networks.

本软件包会配置蜂窝 WAN 接口、NAT/转发规则和运行状态页面。如果路由器的管理接口暴露
在不可信网络中，请在安装前审阅相关改动。
