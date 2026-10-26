APP := build/FanControl.app

.PHONY: build test app install clean

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
	codesign --force -s - $(APP)/Contents/Resources/fanctld
	codesign --force -s - $(APP)

install: app
	rm -rf /Applications/FanControl.app
	cp -R $(APP) /Applications/

clean:
	rm -rf .build build
