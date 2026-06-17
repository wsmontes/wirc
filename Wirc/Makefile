# Wirc — Development Makefile
# Build, install, test, log automation.
#
# Usage:
#   make all          Kill → Build → Install → Launch
#   make build        Build for device
#   make install      Install on device
#   make launch       Launch the app
#   make deploy       Build + Install + Launch
#   make clean        Clean DerivedData + temp files

DEVICE_14PLUS := 00008110-00067D861486201E
DEVICE_15     := 00008120-000260903ED1A01E
DEVICE ?= 14plus
PROJECT ?= Wirc.xcodeproj
SCHEME  ?= Wirc
BUNDLE_ID := com.wirc.wirc

DERIVED_DATA := $(HOME)/Library/Developer/Xcode/DerivedData/Wirc-ccyaxbokjjwwpqcuoemxqdgrjtuj
APP_PATH     := $(DERIVED_DATA)/Build/Products/Debug-iphoneos/Wirc.app
GIT_DIR      := $(shell git rev-parse --show-toplevel 2>/dev/null || pwd)

ifeq ($(DEVICE),15)
  DEVICE_ID := $(DEVICE_15)
  DEVICE_NAME := "iPhone 15"
else
  DEVICE_ID := $(DEVICE_14PLUS)
  DEVICE_NAME := "iPhone 14 Plus"
endif

.PHONY: all build install launch deploy kill clean clean-tmp clean-all help

# ══════════════════════════════════════════════════════════
# Full Cycle
# ══════════════════════════════════════════════════════════

all: kill build install launch  ## Kill → Build → Install → Launch

deploy: kill build install launch  ## Kill → Build → Install → Launch

# ══════════════════════════════════════════════════════════
# Build
# ══════════════════════════════════════════════════════════

build:  ## Build for device
	@echo "🔨 Building for $(DEVICE_NAME)..."
	@cd $(dir $(realpath $(lastword $(MAKEFILE_LIST)))) && \
		xcodegen generate 2>&1 | grep -E "Created|error" && \
		xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
			-destination "platform=iOS,id=$(DEVICE_ID)" \
			-configuration Debug build 2>&1 | grep -E "error:|BUILD SUCCEEDED"

# ══════════════════════════════════════════════════════════
# Install & Launch
# ══════════════════════════════════════════════════════════

kill:  ## Kill the running app on device
	@echo "🔪 Killing Wirc on $(DEVICE_NAME)..."
	@xcrun devicectl device process terminate \
		--device $(DEVICE_ID) \
		--terminate-subprocesses \
		$(BUNDLE_ID) 2>/dev/null || echo "  (not running)"

install: kill  ## Kill + Install on device
	@echo "📱 Installing on $(DEVICE_NAME)..."
	@xcrun devicectl device install app --device $(DEVICE_ID) "$(APP_PATH)" 2>&1 \
		| grep -E "App installed|error"

launch:  ## Launch the app on device
	@echo "🚀 Launching on $(DEVICE_NAME)..."
	@xcrun devicectl device process launch --device $(DEVICE_ID) $(BUNDLE_ID) 2>&1 \
		| grep -E "Launched|error"

# ══════════════════════════════════════════════════════════
# Cleanup
# ══════════════════════════════════════════════════════════

clean: clean-tmp  ## Clean DerivedData + temp files
	@echo "🧹 Cleaning DerivedData..."
	@rm -rf $(DERIVED_DATA)
	@echo "  ✗ DerivedData"
	@echo "Done."

clean-tmp:  ## Clean temporary files created during builds
	@echo "🧹 Cleaning temp files..."
	@rm -rf $(GIT_DIR)/.git/sdd 2>/dev/null && echo "  ✗ .git/sdd" || true
	@rm -rf /private/tmp/wirc-* 2>/dev/null && echo "  ✗ /tmp/wirc-*" || true
	@find $(GIT_DIR) -name ".DS_Store" -delete 2>/dev/null || true
	@echo "Done."

clean-all: clean clean-tmp  ## Clean everything
	@echo "🧹 Full cleanup complete."
	@df -h / | grep -v Filesystem

# ══════════════════════════════════════════════════════════
# Help
# ══════════════════════════════════════════════════════════

help:  ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-16s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Variables:"
	@echo "  DEVICE=14plus|15    Target device (default: 14plus)"
