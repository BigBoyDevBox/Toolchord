DERIVED := build/DerivedData
APP := $(DERIVED)/Build/Products/Release/Toolchord.app

.PHONY: project app run install test snapshots benchmark icon clean

## Generate Toolchord.xcodeproj from project.yml (requires XcodeGen).
project:
	xcodegen generate

## Build the release app bundle.
app: project
	xcodebuild -project Toolchord.xcodeproj -scheme Toolchord -configuration Release -derivedDataPath $(DERIVED) build

## Build and open the app.
run: app
	open "$(APP)"

## Copy the release build to /Applications.
install: app
	ditto "$(APP)" /Applications/Toolchord.app

## Run the unit tests (core tools, session, and Mac logic).
test:
	swift test

## Render palette states to build/snapshots for design review.
snapshots:
	swift build --product toolchord-snapshots
	"$$(swift build --show-bin-path)/toolchord-snapshots" build/snapshots

## Time every command on 10 KiB and 1 MiB inputs in a release build.
benchmark:
	swift build -c release --product toolchord-snapshots
	"$$(swift build -c release --show-bin-path)/toolchord-snapshots" --benchmark

## Regenerate the Icon Composer app icon in App/AppIcon.icon.
icon:
	swift Scripts/make-icon.swift

clean:
	rm -rf build .build Toolchord.xcodeproj
