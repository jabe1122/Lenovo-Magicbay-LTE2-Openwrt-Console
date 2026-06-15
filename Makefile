include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-mbim-lenovo
PKG_VERSION:=1.0.1
PKG_RELEASE:=9
PKG_LICENSE:=MIT
PKG_MAINTAINER:=OpenWrt User

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-mbim-lenovo
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=Lenovo MagicBay LTE2 OpenWrt Console
  PKGARCH:=all
  DEPENDS:=+gl-sdk4-luci +gl-sdk4-lua-utils +rpcd +rpcd-mod-file +wwan +umbim +kmod-usb-net-cdc-mbim +kmod-sched-core +libmbim +mbim-utils +ip-full +tc-tiny +iptables +iptables-mod-conntrack-extra +usb-modeswitch
endef

define Package/luci-app-mbim-lenovo/description
LuCI application and bring-up service for Lenovo MagicBay LTE2 / ASR1803
USB MBIM modules. It adds a netifd protocol, registers the link as a cellular
WAN, handles the all-zero Ethernet MAC quirk, tc ingress packet type repair,
DNS, NAT/forwarding and a status/control page under the OpenWrt menu.
endef

define Build/Compile
endef

define Package/luci-app-mbim-lenovo/install
	$(CP) ./root/* $(1)/
endef

define Package/luci-app-mbim-lenovo/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/bin/sh /etc/uci-defaults/99-mbim-lenovo >/dev/null 2>&1 || true
rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null || true
exit 0
endef

define Package/luci-app-mbim-lenovo/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/etc/init.d/mbim-lenovo stop >/dev/null 2>&1 || true
/etc/init.d/mbim-lenovo disable >/dev/null 2>&1 || true
exit 0
endef

define Package/luci-app-mbim-lenovo/postrm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
sed -i '/# BEGIN mbim-lenovo/,/# END mbim-lenovo/d' /etc/firewall.user 2>/dev/null || true
rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null || true
/etc/init.d/rpcd reload >/dev/null 2>&1 || true
exit 0
endef

$(eval $(call BuildPackage,luci-app-mbim-lenovo))
