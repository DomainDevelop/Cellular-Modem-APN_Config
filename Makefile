include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-ginet-cellmodem
PKG_VERSION:=1.1
PKG_RELEASE:=1

PKG_MAINTAINER:=DomainDevelop
PKG_LICENSE:=GPL-2.0-or-later

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-ginet-cellmodem
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=GiNet Cell Modem Configuration
  DEPENDS:=+luci-base +libuci-lua +libubox +uqmi +kmod-usb-net-qmi-wwan
  PKGARCH:=all
endef

define Package/luci-app-ginet-cellmodem/description
  LuCI UI for cellular status and APN profile management on GiNet XE-3000
  Puli AX and similar OpenWrt routers using QMI-capable cellular modems.

  Features:
  - Dedicated Cellular and APNs sections
  - Active SIM selection with persistent per-slot APN profiles
  - Carrier, SIM, IMEI, signal, and network mode visibility
  - Capability-aware IMEI and network-mode controls
  - TTL persistence with best-effort runtime application
endef

define Package/luci-app-ginet-cellmodem/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/ginet_modem $(1)/etc/config/ginet_modem

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/ginet-modem $(1)/etc/init.d/ginet-modem

	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/usr/bin/ginet-modem-status.sh $(1)/usr/bin/ginet-modem-status.sh
	$(INSTALL_BIN) ./files/usr/bin/apply-ginet-modem-settings.sh $(1)/usr/bin/apply-ginet-modem-settings.sh

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi
	$(INSTALL_DATA) ./files/usr/lib/lua/luci/model/cbi/ginet_modem.lua $(1)/usr/lib/lua/luci/model/cbi/ginet_modem.lua

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) ./files/usr/lib/lua/luci/controller/ginet_modem.lua $(1)/usr/lib/lua/luci/controller/ginet_modem.lua
endef

define Package/luci-app-ginet-cellmodem/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	echo "Reloading LuCI..."
	( sleep 1; /etc/init.d/uhttpd restart ) &
	/etc/init.d/ginet-modem enable
	/etc/init.d/ginet-modem restart
}
endef

$(eval $(call BuildPackage,luci-app-ginet-cellmodem))
