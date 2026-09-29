include $(THEOS)/makefiles/common.mk

BUNDLE_NAME := Quart17Prefs
Quart17Prefs_FILES := QRootListController.m
Quart17Prefs_FRAMEWORKS := UIKit
Quart17Prefs_PRIVATE_FRAMEWORKS := Preferences
Quart17Prefs_INSTALL_PATH := /Library/PreferenceBundles
Quart17Prefs_CFLAGS := -fobjc-arc
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
Quart17Prefs_CFLAGS += -DQ_ROOTHIDE=1
endif

include $(THEOS_MAKE_PATH)/bundle.mk
