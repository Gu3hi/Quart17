TARGET := iphone:clang:16.5:17.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME := roothide
DEB_ARCH := iphoneos-arm64e
INSTALL_TARGET_PROCESSES := SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := Quart17
Quart17_FILES := Tweak.xm QPlayerView.m
Quart17_CFLAGS := -fobjc-arc
Quart17_FRAMEWORKS := UIKit AVKit
Quart17_LIBRARIES := substrate

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += preferences
include $(THEOS_MAKE_PATH)/aggregate.mk
