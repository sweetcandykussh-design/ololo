INSTALL_TARGET_PROCESSES = SpringBoard
ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:15.0

THEOS_PACKAGE_SCHEME ?= rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MiOSTweak
MiOSTweak_FILES = $(wildcard MiOSTweak/*.x) $(wildcard MiOSTweak/*.m) $(wildcard MiOSTweak/*.c)
MiOSTweak_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
MiOSTweak_FRAMEWORKS = Foundation CoreFoundation UIKit CoreLocation Security CoreTelephony SystemConfiguration

APPLICATION_NAME = MiOS
MiOS_FILES = $(wildcard MiOSApp/*.m) $(wildcard MiOSApp/Controllers/*.m) $(wildcard MiOSApp/Views/*.m) $(wildcard MiOSApp/Models/*.m) $(wildcard MiOSApp/Utils/*.m) $(wildcard MiOSApp/UI/*.m)
MiOS_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
MiOS_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore CoreLocation MapKit
MiOS_PRIVATE_FRAMEWORKS = MobileCoreServices
MiOS_INSTALL_PATH = /Applications
MiOS_CODESIGN_FLAGS = -Sentitlements.plist

TOOL_NAME = miosd
miosd_FILES = $(wildcard MiOSDaemon/*.m)
miosd_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
miosd_FRAMEWORKS = Foundation
miosd_CODESIGN_FLAGS = -Sdaemon-entitlements.plist
miosd_INSTALL_PATH = /usr/libexec

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/application.mk
include $(THEOS_MAKE_PATH)/tool.mk

after-install::
	install.exec "sh /var/jb/usr/libexec/mios-bootstrap.sh 2>/dev/null || sh /usr/libexec/mios-bootstrap.sh 2>/dev/null"
