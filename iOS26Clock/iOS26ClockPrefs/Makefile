include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = iOS26ClockPrefs

iOS26ClockPrefs_FILES = $(wildcard *.m) ../Shared/CLSharedSupport.m ../Shared/CL_OSVersionShim.m
iOS26ClockPrefs_FRAMEWORKS = UIKit CoreText CoreGraphics
iOS26ClockPrefs_INSTALL_PATH = /Library/PreferenceBundles
iOS26ClockPrefs_CFLAGS = -fobjc-arc -I../Shared
ifndef THEOS_TARGET_NAME_IS_SIMULATOR
iOS26ClockPrefs_PRIVATE_FRAMEWORKS = Preferences
endif
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
iOS26ClockPrefs_LIBRARIES += roothide
endif

include $(THEOS_MAKE_PATH)/bundle.mk

after-stage::
	ldid -S $(THEOS_STAGING_DIR)/Library/PreferenceBundles/iOS26ClockPrefs.bundle/iOS26ClockPrefs
