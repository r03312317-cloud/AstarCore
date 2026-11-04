CC ?= cc
LVGL_DIR ?= ../../software_deps/lvgl-8.3.11
BUILD ?= build
CPPFLAGS += -I. -I$(LVGL_DIR) -DLV_CONF_INCLUDE_SIMPLE
CFLAGS ?= -O2 -g
CFLAGS += -std=c11 -Wall -Wextra
LDLIBS ?= -lm
LV_SRC := $(shell find $(LVGL_DIR)/src -name '*.c')
LV_OBJ := $(patsubst $(LVGL_DIR)/%.c,$(BUILD)/lvgl/%.o,$(LV_SRC))
all: $(BUILD)/rv32-gui
$(BUILD)/rv32-gui: $(BUILD)/main.o $(BUILD)/generated_labels.o $(LV_OBJ)
	$(CC) $(CFLAGS) $(LDFLAGS) $(CRTBEGIN) $^ $(LDLIBS) $(CRTEND) -o $@
$(BUILD)/main.o: main.c lv_conf.h
	@mkdir -p $(@D)
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@
$(BUILD)/generated_labels.o: generated_labels.c lv_conf.h
	@mkdir -p $(@D)
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@
$(BUILD)/lvgl/%.o: $(LVGL_DIR)/%.c lv_conf.h
	@mkdir -p $(@D)
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@
clean:
	rm -rf $(BUILD)
.PHONY: all clean
