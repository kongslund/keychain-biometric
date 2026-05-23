BINARY       = keychain-biometric
INSTALL_PATH = /usr/local/bin/$(BINARY)
BUILD_PATH   = .build/release/$(BINARY)

.PHONY: build test install uninstall

build:
	swift build -c release

test:
	DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

install: build
	sudo chflags noschg "$(INSTALL_PATH)" 2>/dev/null || true
	sudo cp "$(BUILD_PATH)" "$(INSTALL_PATH)"
	sudo chown root:wheel "$(INSTALL_PATH)"
	sudo chmod 755 "$(INSTALL_PATH)"
	sudo chflags schg "$(INSTALL_PATH)"
	@echo "Installed $(BINARY) to $(INSTALL_PATH)"

uninstall:
	sudo chflags noschg "$(INSTALL_PATH)"
	sudo rm "$(INSTALL_PATH)"
	@echo "Removed $(INSTALL_PATH)"
