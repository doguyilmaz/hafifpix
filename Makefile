APP = dist/HafifPix.app
VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)

.PHONY: build test app run install install-cli strings dmg appcast release tap metrics clean

build: strings
	swift build

test: strings
	swift test

app: strings
	bash scripts/build-app.sh

run: app
	open $(APP)

install: app
	rm -rf /Applications/HafifPix.app
	ditto $(APP) /Applications/HafifPix.app
	@echo "Installed to /Applications/HafifPix.app"

install-cli:
	@test -d /Applications/HafifPix.app || { echo "run 'make install' first"; exit 1; }
	@bin=/opt/homebrew/bin; [ -w $$bin ] || bin=/usr/local/bin; \
	ln -sf /Applications/HafifPix.app/Contents/Resources/bin/hafif $$bin/hafif && \
	echo "Symlinked hafif to $$bin/hafif"

# Compile .lproj resources from the String Catalogs. Generated output is
# not committed (see .gitignore); every build target regenerates it.
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
		--title "HafifPix-$(VERSION)" --generate-notes
	./scripts/update-tap.sh $(VERSION) dist/release/HafifPix-$(VERSION).dmg

# Republishes the cask for an existing release, hashing the DMG it downloads.
# Only needed if the release job's cask step was skipped or failed.
# VERSION is the working tree's placeholder, so ask GitHub what shipped.
# Override with `make tap V=1.3.1`.
tap:
	@./scripts/update-tap.sh $(if $(V),$(V),$(shell gh release view --json tagName --jq '.tagName' | sed 's/^v//'))

metrics:
	@./scripts/metrics.sh

clean:
	rm -rf .build dist
