export TARGET 		?= iphone:clang:16.5:14.0
export ARCHS 		?= arm64 arm64e
export USE_DEPS 	?= 1

INSTALL_TARGET_PROCESSES = SpringBoard
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = iOS26Clock

iOS26Clock_FILES     = Clock.x \
                       $(wildcard Shared/*.[xm])
iOS26Clock_CFLAGS    = -fobjc-arc -IShared
iOS26Clock_FRAMEWORKS = UIKit CoreText CoreGraphics
iOS26Clock_USE_MODULES = 0

include $(THEOS)/makefiles/tweak.mk

after-stage::
	ldid -S $(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/iOS26Clock.dylib

SUBPROJECTS += iOS26ClockPrefs
include $(THEOS_MAKE_PATH)/aggregate.mk
