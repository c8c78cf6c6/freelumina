# FREELUMINA. The build committee has approved a build system.
CMAKE          ?= cmake
BUILD_DIR      ?= build/release
TEST_BUILD_DIR ?= build/check
CONFIG         ?= Release
FBC            ?= $(if $(wildcard build/toolchain/native/bin/fbc*),$(abspath $(firstword $(wildcard build/toolchain/native/bin/fbc*))),fbc)
JOBS           ?= 2
PYTHON         ?= python3
CMAKE_ARGS     ?=

# Standard per-user installation; override for a specific host installation.
ifeq ($(OS),Windows_NT)
# Normalize native Windows separators for CMake and the MSYS2 shell.
PLUGINS ?= $(if $(strip $(APPDATA)),$(subst \,/,$(APPDATA))/Hex-Rays/IDA Pro/plugins)
else ifeq ($(shell uname 2>/dev/null),Darwin)
PLUGINS ?= $(HOME)/Library/Application Support/IDA Pro/plugins
else
PLUGINS ?= $(HOME)/.idapro/plugins
endif

.PHONY: all configure test release install clean info

all: configure
	$(CMAKE) --build "$(BUILD_DIR)" --config "$(CONFIG)" --parallel "$(JOBS)"

configure:
	$(CMAKE) -S . -B "$(BUILD_DIR)" -DCMAKE_BUILD_TYPE="$(CONFIG)" -DBUILD_TESTING=OFF -DFBC_EXECUTABLE="$(FBC)" $(CMAKE_ARGS)

test:
	$(CMAKE) -S . -B "$(TEST_BUILD_DIR)" -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON -DFBC_EXECUTABLE="$(FBC)" $(CMAKE_ARGS)
	$(CMAKE) --build "$(TEST_BUILD_DIR)" --config Debug --parallel "$(JOBS)"
	ctest --test-dir "$(TEST_BUILD_DIR)" -C Debug --output-on-failure

release:
	$(CMAKE) -S . -B "$(BUILD_DIR)" -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON -DFBC_EXECUTABLE="$(FBC)" $(CMAKE_ARGS)
	$(CMAKE) --build "$(BUILD_DIR)" --config Release --parallel "$(JOBS)"
	$(PYTHON) tools/package_release.py "$(BUILD_DIR)"

install: all
	$(if $(strip $(PLUGINS)),,$(error PLUGINS is empty; set PLUGINS explicitly or provide APPDATA on Windows))
	$(CMAKE) -E make_directory "$(PLUGINS)"
	$(CMAKE) --install "$(BUILD_DIR)" --config "$(CONFIG)" --prefix "$(PLUGINS)"

clean:
	$(CMAKE) --build "$(BUILD_DIR)" --target clean

info:
	@echo "BUILD_DIR = $(BUILD_DIR)"
	@echo "CONFIG    = $(CONFIG)"
	@echo "PLUGINS   = $(PLUGINS)"
