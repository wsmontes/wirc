# Wirc — Development Makefile
# Build, install, test, log automation.
#
# Usage:
#   make all          Build → Install
#   make build        Build for device
#   make install      Install on device
#   make logs         Stream logs from iPhone 14 Plus
#   make clean        Clean DerivedData

SCRIPTS := $(shell cd "$(dir $(lastword $(MAKEFILE_LIST)))" && pwd)/scripts

DEVICE_14PLUS := 00008110-00067D861486201E
DEVICE_15     := 00008120-000260903ED1A01E
DEVICE ?= 14plus
SIM_DEVICE ?= iPhone 14 Plus
PROJECT ?= Wirc.xcodeproj
SCHEME  ?= Wirc

DERIVED_DATA := $(HOME)/Library/Developer/Xcode/DerivedData/Wirc-ccyaxbokjjwwpqcuoemxqdgrjtuj
APP_PATH     := $(DERIVED_DATA)/Build/Products/Debug-iphoneos/Wirc.app

.PHONY: all build install deploy clean help

# ══════════════════════════════════════════════════════════
# Full Cycle
# ══════════════════════════════════════════════════════════

all: build install  ## Build → Install

# ══════════════════════════════════════════════════════════
# Build & Install
# ══════════════════════════════════════════════════════════

build:  ## Build for device (set DEVICE=15 for iPhone 15)
ifeq ($(DEVICE),15)
	@echo "🔨 Building for iPhone 15..."
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination "platform=iOS,id=$(DEVICE_15)" \
		-configuration Debug build 2>&1 | tail -5
else
	@echo "🔨 Building for iPhone 14 Plus..."
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination "platform=iOS,id=$(DEVICE_14PLUS)" \
		-configuration Debug build 2>&1 | tail -5
endif

install:  ## Install on device (set DEVICE=15 for iPhone 15)
ifeq ($(DEVICE),15)
	@echo "📱 Installing on iPhone 15..."
	@xcrun devicectl device install app --device $(DEVICE_15) "$(APP_PATH)" 2>&1 \
		| grep -E "App installed|error" || echo "⚠️  Install may have failed"
else
	@echo "📱 Installing on iPhone 14 Plus..."
	@xcrun devicectl device install app --device $(DEVICE_14PLUS) "$(APP_PATH)" 2>&1 \
		| grep -E "App installed|error" || echo "⚠️  Install may have failed"
endif

deploy: build install  ## Build + Install

# ══════════════════════════════════════════════════════════
# Logs
# ══════════════════════════════════════════════════════════

logs:  ## Stream device logs
ifeq ($(DEVICE),15)
	@xcrun devicectl device info processes --device $(DEVICE_15) 2>/dev/null || true
	@echo "Use Console.app or: log stream --predicate 'process == \"Wirc\"' --device"
else
	@xcrun devicectl device info processes --device $(DEVICE_14PLUS) 2>/dev/null || true
	@echo "Use Console.app or: log stream --predicate 'process == \"Wirc\"' --device"
endif

# ══════════════════════════════════════════════════════════
# Cleanup
# ══════════════════════════════════════════════════════════

clean:  ## Clean DerivedData
	@echo "🧹 Cleaning DerivedData..."
	@rm -rf $(DERIVED_DATA)
	@echo "Done."

# ══════════════════════════════════════════════════════════
# Help
# ══════════════════════════════════════════════════════════

help:  ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-16s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Variables:"
	@echo "  DEVICE=14plus|15    Target device (default: 14plus)"
