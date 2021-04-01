include $(TOPDIR)/rules.mk

PKG_NAME:=dalec
PKG_VERSION:=0.1.1
PKG_RELEASE:=1
PKG_MAINTAINER:=Stefan Venz <stefan.venz@protonmail.com>
PKG_LICENSE:=GPL-3.0+
PKG_LICENSE_FILES:=LICENSE

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
	SECTION:=utils
	CATEGORY:=Utilities
	TITLE:=Data collection and transmission tool for usage statistics
	DEPENDS:=
	MAINTAINER:=Stefan Venz <stefan.venz@protonmail.com>
	PKGARCH:=all
endef

define Package/$(PKG_NAME)/description
	Collects non personal identifiable data and transmitts them
	encrypted over the domain name system to remove sender information
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
		$(INSTALL_DIR) $(1)/usr/sbin/dalec
		$(INSTALL_BIN) ./dalec $(1)/usr/sbin/dalec/
		$(INSTALL_DATA) ./transmitt_data $(1)/usr/sbin/dalec
endef

$(eval $(call BuildPackage,dalec))
