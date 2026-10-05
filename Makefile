INSTALL_TARGET_PROCESSES = SpringBoard
ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:15.0

THEOS_PACKAGE_SCHEME ?= rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MiOSTweak MiOSSupport
MiOSTweak_FILES = $(wildcard MiOSTweak/*.x) $(wildcard MiOSTweak/*.m) $(wildcard MiOSTweak/*.c)
MiOSTweak_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
MiOSTweak_FRAMEWORKS = Foundation CoreFoundation UIKit CoreLocation Security CoreTelephony SystemConfiguration

# Crane-style system-daemon support dylib (Phase 1: containermanagerd redirect). Injected only into the
# daemons named in layout/.../MiOSSupport.plist. ARC off-safe: uses manual @autoreleasepool.
MiOSSupport_FILES = $(wildcard MiOSSupport/*.x) $(wildcard MiOSSupport/*.m) $(wildcard MiOSSupport/*.c)
MiOSSupport_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
MiOSSupport_FRAMEWORKS = Foundation CoreFoundation Security

APPLICATION_NAME = MiOS
MiOS_FILES = $(wildcard MiOSApp/*.m) $(wildcard MiOSApp/Controllers/*.m) $(wildcard MiOSApp/Views/*.m) $(wildcard MiOSApp/Models/*.m) $(wildcard MiOSApp/Utils/*.m) $(wildcard MiOSApp/UI/*.m)
MiOS_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
MiOS_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore CoreLocation MapKit
MiOS_PRIVATE_FRAMEWORKS = MobileCoreServices
MiOS_INSTALL_PATH = /Applications
MiOS_CODESIGN_FLAGS = -Sentitlements.plist

TOOL_NAME = miosd mioshelperd mioscli
miosd_FILES = $(wildcard MiOSDaemon/*.m)
miosd_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
miosd_FRAMEWORKS = Foundation
miosd_CODESIGN_FLAGS = -Sdaemon-entitlements.plist
miosd_INSTALL_PATH = /usr/libexec

# Force-inject helper daemon (DoritosHelper equivalent): task_for_pid + thread_create_running.
# Stages dylibs to /var/tmp (sandbox-readable), injects into daemons whose sandbox blocks the
# normal MobileSubstrate/TweakInject dlopen path. Also runs a 30s watchdog that re-injects on respawn.
mioshelperd_FILES = MiOSHelper/MiOSHelper.m
mioshelperd_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -I$(THEOS_PROJECT_DIR)
mioshelperd_FRAMEWORKS = Foundation
mioshelperd_CODESIGN_FLAGS = -Shelper-entitlements.plist
mioshelperd_INSTALL_PATH = /usr/libexec

# CLI tool for direct injection (DoritosCLI equivalent). Has its own task_for_pid-allow so it can
# inject standalone — the bootstrap script uses it without depending on the helper daemon being up.
mioscli_FILES = MiOSCLI/MiOSCLI.m
mioscli_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -I$(THEOS_PROJECT_DIR)
mioscli_FRAMEWORKS = Foundation
mioscli_CODESIGN_FLAGS = -Scli-entitlements.plist
mioscli_INSTALL_PATH = /usr/bin

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/application.mk
include $(THEOS_MAKE_PATH)/tool.mk

# Install a real Debian postinst into the package control archive so the daemon is bootstrapped at
# install time (Theos's after-install/install.exec only runs for `make install` over SSH, not in the
# packaged .deb). Copying into $(THEOS_STAGING_DIR)/DEBIAN bypasses the rootless /var/jb prefixing.
after-stage::
	@mkdir -p "$(THEOS_STAGING_DIR)/DEBIAN"
	@cp "$(THEOS_PROJECT_DIR)/postinst" "$(THEOS_STAGING_DIR)/DEBIAN/postinst"
	@chmod 0755 "$(THEOS_STAGING_DIR)/DEBIAN/postinst"

after-install::
	install.exec "D=/var/mobile/Library/Preferences/MiOS/debug; mkdir -p \"$$D\"; echo \"postinst ran $$(date)\" >> \"$$D/install.log\"; if [ -f /var/jb/usr/libexec/mios-bootstrap.sh ]; then sh /var/jb/usr/libexec/mios-bootstrap.sh; elif [ -f /usr/libexec/mios-bootstrap.sh ]; then sh /usr/libexec/mios-bootstrap.sh; else echo \"bootstrap script NOT found in /var/jb/usr/libexec or /usr/libexec\" >> \"$$D/install.log\"; fi; chown -R 501:501 \"$$D\" 2>/dev/null; killall -9 SpringBoard 2>/dev/null"
