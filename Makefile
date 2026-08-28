ifneq ($(firstword $(sort 4.4 $(MAKE_VERSION))),4.4)
$(error GNU Make >= 4.4 required, found $(MAKE_VERSION). Run: mise install)
endif

# Full Xcode is required, not just the Command Line Tools: the macOS SDK makes
# @State and other SwiftUI property wrappers macros backed by a SwiftUIMacros
# plugin that only Xcode ships. Without it every @State fails to expand. If the
# active developer dir is the Command Line Tools, borrow an installed Xcode for
# this build rather than making the user run sudo xcode-select.
ifneq (,$(findstring CommandLineTools,$(shell xcode-select -p 2>/dev/null)))
DEVELOPER_DIR := $(firstword $(wildcard /Applications/Xcode.app/Contents/Developer /Applications/Xcode-beta.app/Contents/Developer))
ifeq ($(DEVELOPER_DIR),)
$(error Full Xcode required, none found in /Applications. Install it, then: sudo xcode-select -s /Applications/Xcode.app)
endif
export DEVELOPER_DIR
endif

.ONESHELL:
SHELL       := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.PHONY: all deps build bundle install test lint fmt icons alert alert-banner clean

# EXEC is the binary and SwiftPM product name - no spaces, so ps and pkill
# stay usable. NAME is what the user sees.
EXEC      := YouHaveAMeeting
NAME      := You Have a Meeting
BUNDLE_ID := app.youhaveameeting
VERSION   := 0.1.0
IDENTITY  := YouHaveAMeeting Dev
BIN       := .build/arm64-apple-macosx/release/$(EXEC)
BUNDLE    := build/$(NAME).app
INSTALLED := /Applications/$(NAME).app

all: bundle

deps:
	mise install

build:
	swift build -c release --arch arm64

bundle: build
	./Scripts/bundle.sh "$(BUNDLE)" "$(BIN)" "$(EXEC)" "$(NAME)" \
		"$(BUNDLE_ID)" "$(VERSION)" "$(IDENTITY)"

install: bundle
	# ditto rather than cp: it preserves bundle structure and the code
	# signature, which cp can disturb.
	if pgrep -x "$(EXEC)" > /dev/null; then
		echo "Quitting the running copy first..."
		pkill -x "$(EXEC)" || true
	fi
	rm -rf "$(INSTALLED)"
	ditto "$(BUNDLE)" "$(INSTALLED)"
	codesign --verify --strict "$(INSTALLED)"
	echo "installed $(INSTALLED)"
	echo "Open it from /Applications. Screen Recording permission is per-copy,"
	echo "so grant it again for this one from the menu."

test:
	swift test

lint:
	swiftformat Sources Tests --lint
	swiftlint --strict

fmt:
	swiftformat Sources Tests --quiet

# The app icon is generated art, but the result is committed: a plain build
# must not depend on a drawing step. Re-run this only when the mark changes.
icons:
	mkdir -p build
	swiftc -O Scripts/GenerateAppIcon.swift \
		Sources/YouHaveAMeetingCore/Branding/BellGlyph.swift \
		-o build/generate-app-icon
	./build/generate-app-icon build/AppIcon.iconset
	iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
	echo "wrote Resources/AppIcon.icns"

alert: bundle
	"$(BUNDLE)/Contents/MacOS/$(EXEC)" --test-alert

alert-banner: bundle
	"$(BUNDLE)/Contents/MacOS/$(EXEC)" --test-alert --banner

clean:
	rm -rf .build build
