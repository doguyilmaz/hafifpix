APP = dist/HafifPix.app
VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)

.PHONY: build test app run install install-cli icon dmg appcast release clean

build:
	swift build

test:
	swift test

app:
	bash scripts/build-app.sh

run: app
	open $(APP)

install: app
	rm -rf /Applications/HafifPix.app
	ditto $(APP) /Applications/HafifPix.app
	@echo "Installed to /Applications/HafifPix.app"

install-cli:
	@test -d /Applications/HafifPix.app || { echo "run 'make install' first"; exit 1; }
	ln -sf /Applications/HafifPix.app/Contents/Resources/bin/hafif /usr/local/bin/hafif
	@echo "Symlinked hafif to /usr/local/bin/hafif"

icon:
	swift scripts/make-icon-from-art.swift Resources/icon-art.png .build/AppIcon.iconset
	iconutil -c icns .build/AppIcon.iconset -o Resources/AppIcon.icns

# Recompile .lproj resources after editing the catalogs in Localization/.
strings:
	xcrun xcstringstool compile Localization/HafifPixApp.xcstrings --output-directory Sources/HafifPixApp/Resources
	xcrun xcstringstool compile Localization/HafifPixCore.xcstrings --output-directory Sources/HafifPixCore/Resources

dmg: app
	bash scripts/make-dmg.sh

appcast:
	rm -rf dist/release && mkdir -p dist/release
	cp dist/HafifPix-$(VERSION).dmg dist/release/
	.build/artifacts/sparkle/Sparkle/bin/generate_appcast dist/release \
		--download-url-prefix "https://github.com/doguyilmaz/hafifpix/releases/download/v$(VERSION)/"

release: appcast
	gh release create v$(VERSION) dist/release/HafifPix-$(VERSION).dmg dist/release/appcast.xml \
		--title "HafifPix $(VERSION)" --generate-notes

clean:
	rm -rf .build dist
