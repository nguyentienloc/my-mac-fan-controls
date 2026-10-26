APP := build/FanControl.app
SIGN_ID ?= Developer ID Application: 5WEB VIET NAM TECHNOLOGY JOINT STOCK COMPANY (99G56BJA4B)
NOTARY_PROFILE ?= fancontrol-notary
VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
DMG := build/FanControl-$(VERSION).dmg
# Hardened runtime + timestamp: bắt buộc để notarize
CODESIGN := codesign --force --options runtime --timestamp -s "$(SIGN_ID)"

.PHONY: build test app install dmg notarize clean

build:
	swift build -c release

test:
	swift test

app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/FanControlApp $(APP)/Contents/MacOS/FanControl
	cp .build/release/fanctld $(APP)/Contents/Resources/fanctld
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp Resources/local.fancontrol.daemon.plist $(APP)/Contents/Resources/
	$(CODESIGN) $(APP)/Contents/Resources/fanctld
	$(CODESIGN) $(APP)
	codesign --verify --strict --deep $(APP)

install: app
	rm -rf /Applications/FanControl.app
	cp -R $(APP) /Applications/

dmg: app
	rm -rf build/dmg $(DMG)
	mkdir -p build/dmg
	cp -R $(APP) build/dmg/
	ln -s /Applications build/dmg/Applications
	hdiutil create -volname "Fan Control" -srcfolder build/dmg -ov -format UDZO $(DMG)
	codesign --force --timestamp -s "$(SIGN_ID)" $(DMG)

# Cần keychain profile: xcrun notarytool store-credentials $(NOTARY_PROFILE) --apple-id <email> --team-id 99G56BJA4B
notarize: dmg
	xcrun notarytool submit $(DMG) --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple $(DMG)
	spctl --assess --type open --context context:primary-signature -v $(DMG)

clean:
	rm -rf .build build
