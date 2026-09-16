export TARGET 		?= iphone:clang:16.5:14.0
export ARCHS 		?= arm64 arm64e
export USE_DEPS 	?= 1

INSTALL_TARGET_PROCESSES = SpringBoard
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = BigTimeFix

BigTimeFix_FILES     = BigTimeFix.x
BigTimeFix_CFLAGS    = -fobjc-arc
BigTimeFix_FRAMEWORKS = UIKit QuartzCore CoreGraphics CoreText
BigTimeFix_USE_MODULES = 0
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
BigTimeFix_LIBRARIES += roothide
BigTimeFix_LDFLAGS += -L$(THEOS_VENDOR_LIB_PATH)/iphone/roothide -lsubstrate
endif

include $(THEOS)/makefiles/tweak.mk

after-stage::
	ldid -S $(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/BigTimeFix.dylib
