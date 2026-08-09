# FlowDown build automation

SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

ROOT_DIR := $(abspath $(CURDIR))
WORKSPACE := $(ROOT_DIR)/FlowDown.xcworkspace
IOS_SCHEME := FlowDown
EXTENSION_SCHEME := FlowDownTranslationProvider
CONFIGURATION ?= Debug
DERIVED_DATA ?= /private/tmp/flowdown-deriveddata
BUILD_HOME := $(DERIVED_DATA)/home
XDG_CACHE_HOME := $(DERIVED_DATA)/xdg-cache
MODULE_CACHE := $(DERIVED_DATA)/ModuleCache.noindex

IOS_DESTINATION := generic/platform=iOS
CATALYST_DESTINATION := generic/platform=macOS,variant=Mac Catalyst

XCODEBUILD_WRAPPER := ./Resources/DevKit/scripts/run_xcodebuild.sh
TRANSLATION_CHECK_SCRIPT := Resources/DevKit/scripts/check_untranslated.py
TRANSLATION_STALE_SCRIPT := Resources/DevKit/scripts/check_translations.py

XCODEBUILD := $(XCODEBUILD_WRAPPER) \
	-workspace "$(WORKSPACE)" \
	-configuration $(CONFIGURATION) \
	-derivedDataPath "$(DERIVED_DATA)" \
	-skipMacroValidation \
	-skipPackagePluginValidation \
	CODE_SIGNING_ALLOWED=NO \
	CODE_SIGNING_REQUIRED=NO \
	CODE_SIGN_IDENTITY=""

LOCALIZATION_FILES := \
	FlowDown/Resources/Localizable.xcstrings \
	FlowDownTranslationProvider/Localizable.xcstrings \
	FlowDownWidgets/Localizable.xcstrings

ifeq ($(dirty),1)
	export ALLOW_DIRTY := 1
endif

BUILD_ENV := HOME="$(BUILD_HOME)" XDG_CACHE_HOME="$(XDG_CACHE_HOME)" CLANG_MODULE_CACHE_PATH="$(MODULE_CACHE)" SWIFTPM_MODULECACHE_OVERRIDE="$(MODULE_CACHE)"

define prepare-build-dirs
	mkdir -p "$(BUILD_HOME)" "$(XDG_CACHE_HOME)" "$(MODULE_CACHE)"
endef

define run-localization-script
	for file in $(LOCALIZATION_FILES); do \
		python3 $(1) "$$file"; \
	done
endef

.PHONY: all help \
	build build-ios build-catalyst build-extension \
	test test-unit test-online-e2e \
	install-metal-toolchain package-resolve package-update package-verify scan-license \
	localization-check localization-stale-check \
	archive archive-ios archive-macos \
	chore clean clean-build

all: build

help:
	@echo "Build:"
	@echo "  build                 Build the iOS and Mac Catalyst app"
	@echo "  build-ios             Build the iOS app"
	@echo "  build-catalyst        Build the Mac Catalyst app"
	@echo "  build-extension       Build the translation provider extension"
	@echo ""
	@echo "Test:"
	@echo "  test                  Run the default test flow"
	@echo "  test-unit             Run app tests on the first available iOS simulator"
	@echo "  test-online-e2e       Run online e2e tests"
	@echo ""
	@echo "Packages & licenses:"
	@echo "  install-metal-toolchain  Install the Xcode Metal toolchain"
	@echo "  package-resolve       Resolve SwiftPM packages"
	@echo "  package-update        Upgrade SwiftPM packages"
	@echo "  package-verify        Check Package.resolved keeps the pins Xcode Cloud needs"
	@echo "  scan-license          Refresh open source licenses"
	@echo ""
	@echo "Localization:"
	@echo "  localization-check        Check for missing translations"
	@echo "  localization-stale-check  Prune stale keys and verify completeness"
	@echo ""
	@echo "Archive:"
	@echo "  archive               Archive iOS and macOS release builds"
	@echo "  archive-ios           Archive the iOS release build"
	@echo "  archive-macos         Archive the macOS release build"
	@echo ""
	@echo "Housekeeping:"
	@echo "  chore                 Run localization hygiene and license refresh"
	@echo "  clean-build           Remove repo-local build artifacts"
	@echo "  clean                 Remove repo-local build artifacts and derived data"
	@echo ""
	@echo "Flags:"
	@echo "  dirty=1               Allow flows that intentionally run on a dirty tree"

build: build-ios build-catalyst

build-ios:
	$(prepare-build-dirs)
	$(BUILD_ENV) XCBUILD_LABEL=build-ios $(XCODEBUILD) \
		-scheme $(IOS_SCHEME) \
		-destination "$(IOS_DESTINATION)" \
		build

build-catalyst:
	$(prepare-build-dirs)
	$(BUILD_ENV) XCBUILD_LABEL=build-catalyst $(XCODEBUILD) \
		-scheme $(IOS_SCHEME) \
		-destination "$(CATALYST_DESTINATION)" \
		SUPPORTS_MACCATALYST=YES \
		build

build-extension:
	$(prepare-build-dirs)
	$(BUILD_ENV) XCBUILD_LABEL=build-extension $(XCODEBUILD) \
		-scheme $(EXTENSION_SCHEME) \
		-destination "$(IOS_DESTINATION)" \
		build

test: test-unit

test-unit:
	$(prepare-build-dirs)
	DESTINATION="$$(./Resources/DevKit/scripts/get_first_ios_simulator.sh)"; \
	$(BUILD_ENV) XCBUILD_LABEL=test-unit $(XCODEBUILD) \
		-scheme $(IOS_SCHEME) \
		-destination "$$DESTINATION" \
		test

test-online-e2e: install-metal-toolchain package-resolve
	./Resources/DevKit/scripts/run_online_e2e_tests.sh

install-metal-toolchain:
	./Resources/DevKit/scripts/install-metal-toolchain.sh

package-resolve:
	./Resources/DevKit/scripts/resolve-packages.sh

package-update:
	./Resources/DevKit/scripts/update-packages.sh

package-verify:
	./Resources/DevKit/scripts/required_package_pins.py check

scan-license:
	./Resources/DevKit/scripts/scan.license.sh

localization-check:
	$(call run-localization-script,$(TRANSLATION_CHECK_SCRIPT))

localization-stale-check:
	$(call run-localization-script,$(TRANSLATION_STALE_SCRIPT))

archive:
	./Resources/DevKit/scripts/archive.all.sh all

archive-ios:
	./Resources/DevKit/scripts/archive.all.sh ios

archive-macos:
	./Resources/DevKit/scripts/archive.all.sh macos

chore:
	$(MAKE) localization-stale-check
	$(MAKE) localization-check
	$(MAKE) package-resolve
	$(MAKE) package-verify
	$(MAKE) scan-license dirty=1

clean-build:
	rm -rf "$(ROOT_DIR)/.build" "$(ROOT_DIR)/BuildArtifacts"

clean: clean-build
	rm -rf "$(DERIVED_DATA)"
