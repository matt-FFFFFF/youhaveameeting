ifneq ($(firstword $(sort 4.4 $(MAKE_VERSION))),4.4)
$(error GNU Make >= 4.4 required, found $(MAKE_VERSION). Run: mise install)
endif

.ONESHELL:
SHELL       := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.PHONY: all deps build bundle install test lint fmt alert alert-banner clean

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

# SwiftLint loads sourcekitdInProc via dyld. With Command Line Tools (no full
# Xcode) that framework is not on the default search path, so point at it.
SOURCEKIT := $(shell xcode-select -p)/usr/lib

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
	DYLD_FRAMEWORK_PATH="$(SOURCEKIT)" swiftlint --strict

fmt:
	swiftformat Sources Tests --quiet

alert: bundle
	"$(BUNDLE)/Contents/MacOS/$(EXEC)" --test-alert

alert-banner: bundle
	"$(BUNDLE)/Contents/MacOS/$(EXEC)" --test-alert --banner

clean:
	rm -rf .build build
