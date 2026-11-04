include $(sort $(wildcard $(BR2_EXTERNAL_RV32_PATH)/package/*/*.mk))

define RV32_LINUX_PATCH
	python3 $(BR2_EXTERNAL_RV32_PATH)/../scripts/software_patch_linux.py $(@D)
endef
LINUX_POST_PATCH_HOOKS += RV32_LINUX_PATCH
