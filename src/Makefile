CC := clang
OTOOL := otool
SDK := $(shell xcrun --sdk macosx --show-sdk-path)
CFLAGS := -isysroot $(SDK) -O2 -Wall -Wno-unused

ARCHES := arm64 x86_64
OUT_DIR := ../lib/scanner
BUILD_DIR := build

TARGETS := $(foreach a,$(ARCHES),$(OUT_DIR)/bytes-$(a).ts)

.PHONY: all dump test clean \
        $(foreach a,$(ARCHES),test-$(a) dump-$(a))

all: $(TARGETS)

$(BUILD_DIR):
	mkdir -p $@

define ARCH_RULES
$$(BUILD_DIR)/scan_$(1).o: scan_$(1).S | $$(BUILD_DIR)
	$$(CC) -arch $(1) $$(CFLAGS) -c $$< -o $$@

$$(BUILD_DIR)/scan_$(1).dylib: $$(BUILD_DIR)/scan_$(1).o
	$$(CC) -arch $(1) $$(CFLAGS) -dynamiclib \
	    -install_name @rpath/scan_$(1).dylib -o $$@ $$<

$$(BUILD_DIR)/scan_$(1).bin: $$(BUILD_DIR)/scan_$(1).dylib
	./extract_text.sh $$< $$@

$$(OUT_DIR)/bytes-$(1).ts: $$(BUILD_DIR)/scan_$(1).bin \
                          $$(BUILD_DIR)/scan_$(1).dylib
	./emit_ts.sh $$< SCAN_$$(shell echo $(1) | tr a-z A-Z)_BYTES \
	    $$@ $$(BUILD_DIR)/scan_$(1).dylib

$$(BUILD_DIR)/scan_test_$(1): $$(BUILD_DIR)/scan_$(1).o test.c | $$(BUILD_DIR)
	$$(CC) -arch $(1) $$(CFLAGS) -o $$@ test.c $$(BUILD_DIR)/scan_$(1).o

test-$(1): $$(BUILD_DIR)/scan_test_$(1)
	arch -$(1) $$<

dump-$(1): $$(BUILD_DIR)/scan_$(1).dylib
	$$(OTOOL) -tvV $$<
endef

$(foreach a,$(ARCHES),$(eval $(call ARCH_RULES,$(a))))

test: $(foreach a,$(ARCHES),test-$(a))
dump: dump-arm64

clean:
	rm -rf $(BUILD_DIR)
	rm -f $(foreach a,$(ARCHES),$(OUT_DIR)/bytes-$(a).ts)
