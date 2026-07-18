include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-ginet-cellmodem
PKG_VERSION:=0.2.0
PKG_RELEASE:=1

PKG_MAINTAINER:=DomainDevelop
PKG_LICENSE:=GPL-2.0-or-later

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-ginet-cellmodem
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=GiNet Cellular Modem & VPN Control
  DEPENDS:=+luci-base +libuci-lua +libubox +uqmi +kmod-usb-net-qmi-wwan +wireguard-tools +kmod-wireguard +kmod-crypto-lib-chacha20poly1305 +kmod-crypto-lib-curve25519
  PKGARCH:=all
endef

define Package/luci-app-ginet-cellmodem/description
  LuCI application for cellular modem APN management, per-SIM WireGuard policy,
  and an admin-only controlled terminal for OpenWrt 24/25 and XE-3000 class targets.
endef

define Package/luci-app-ginet-cellmodem/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/ginet_modem $(1)/etc/config/ginet_modem

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/ginet-modem $(1)/etc/init.d/ginet-modem
	$(INSTALL_BIN) ./files/etc/init.d/ginet-vpn $(1)/etc/init.d/ginet-vpn

	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/usr/bin/ginet-modem-status.sh $(1)/usr/bin/ginet-modem-status.sh
	$(INSTALL_BIN) ./files/usr/bin/apply-ginet-modem-settings.sh $(1)/usr/bin/apply-ginet-modem-settings.sh
	$(INSTALL_BIN) ./files/usr/bin/ginet-vpn-policy.sh $(1)/usr/bin/ginet-vpn-policy.sh
	$(INSTALL_BIN) ./files/usr/bin/ginet-wg-update-check.sh $(1)/usr/bin/ginet-wg-update-check.sh

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi
	$(INSTALL_DATA) ./files/usr/lib/lua/luci/model/cbi/ginet_modem.lua $(1)/usr/lib/lua/luci/model/cbi/ginet_modem.lua
	$(INSTALL_DATA) ./files/usr/lib/lua/luci/model/cbi/ginet_vpn.lua $(1)/usr/lib/lua/luci/model/cbi/ginet_vpn.lua
	$(INSTALL_DATA) ./files/usr/lib/lua/luci/model/cbi/ginet_terminal.lua $(1)/usr/lib/lua/luci/model/cbi/ginet_terminal.lua

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) ./files/usr/lib/lua/luci/controller/ginet_modem.lua $(1)/usr/lib/lua/luci/controller/ginet_modem.lua
endef

define Build/Compile
endef

define Package/luci-app-ginet-cellmodem/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	/etc/init.d/ginet-modem enable
	/etc/init.d/ginet-modem restart
	/etc/init.d/ginet-vpn enable
	/etc/init.d/ginet-vpn restart
	( sleep 1; /etc/init.d/uhttpd restart ) &
}
endef

$(eval $(call BuildPackage,luci-app-ginet-cellmodem))
