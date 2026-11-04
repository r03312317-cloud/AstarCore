RV32_GUI_VERSION = 8.3.11
RV32_GUI_SITE = https://codeload.github.com/lvgl/lvgl/tar.gz/refs/tags
RV32_GUI_SOURCE = v$(RV32_GUI_VERSION)
RV32_GUI_LICENSE = MIT
RV32_GUI_LICENSE_FILES = LICENCE.txt

define RV32_GUI_EXTRACT_CMDS
	gzip -dc $(RV32_GUI_DL_DIR)/$(RV32_GUI_SOURCE) | $(TAR) --strip-components=1 -C $(@D) -xf -
endef

define RV32_GUI_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(BR2_EXTERNAL_RV32_PATH)/../gui CC="$(TARGET_CC)" LVGL_DIR=$(@D) BUILD=$(@D)/rv32-build CFLAGS="$(TARGET_CFLAGS) -std=c11 -Wall -Wextra"
endef

define RV32_GUI_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/rv32-build/rv32-gui $(TARGET_DIR)/usr/bin/rv32-gui
endef

$(eval $(generic-package))
