CXX ?= g++
IS_CLANG = $(shell $(CXX) --version 2>/dev/null | grep -qi clang && echo true)

ifeq ($(IS_CLANG),true)
    EXTRA_FLAGS =
    NARROWING_FLAG = -Wno-c++11-narrowing
else
    EXTRA_FLAGS = -fno-gnu-unique
    NARROWING_FLAG = -Wno-narrowing
endif

CXXFLAGS ?= -O2
PLUGIN_FLAGS = -shared -fPIC -std=c++23 -Wall -Wextra -Wpedantic $(NARROWING_FLAG) -Wno-unused-parameter -Wno-missing-field-initializers
TEST_FLAGS = -std=c++23 -Wall -Wextra -Wpedantic
INCLUDES = $(shell pkg-config --cflags pixman-1 libdrm hyprland libinput libudev wayland-server xkbcommon)
BUILD_DIR ?= .
TARGET = $(BUILD_DIR)/omarchy-windows-snap.so
GEOMETRY_TEST = $(BUILD_DIR)/geometry-test

all: $(TARGET)

$(TARGET): main.cpp geometry.hpp | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) $(PLUGIN_FLAGS) $(LDFLAGS) $(EXTRA_FLAGS) $(INCLUDES) main.cpp -o "$@"

$(GEOMETRY_TEST): geometry.test.cpp geometry.hpp | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) $(TEST_FLAGS) geometry.test.cpp -o "$@"

$(BUILD_DIR):
	mkdir -p -- "$@"

test: $(GEOMETRY_TEST)
	"$(GEOMETRY_TEST)"

clean:
	rm -f -- "$(TARGET)" "$(GEOMETRY_TEST)"

.PHONY: all clean test
