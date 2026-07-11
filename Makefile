APP = dist/HafifPix.app

.PHONY: build test app run install install-cli icon clean

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
	swift scripts/make-icon.swift .build/AppIcon.iconset
	iconutil -c icns .build/AppIcon.iconset -o Resources/AppIcon.icns

clean:
	rm -rf .build dist
