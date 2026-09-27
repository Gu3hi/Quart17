TARGET := iphone:clang:16.5:17.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME := roothide
DEB_ARCH := iphoneos-arm64e
INSTALL_TARGET_PROCESSES := SpringBoard MediaRemoteUI

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := Quart17
Quart17_FILES := Tweak.xm QPlayerView.m QNativeArtwork.m
Quart17_CFLAGS := -fobjc-arc
# RootHide 与标准 Rootless 路径宏区分：roothide 方案用 jbroot()，
# 标准 rootless 直接用 /var/jb 前缀
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
Quart17_CFLAGS += -DQ_ROOTHIDE=1
endif
Quart17_FRAMEWORKS := UIKit AVKit
Quart17_LIBRARIES := substrate

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += preferences
include $(THEOS_MAKE_PATH)/aggregate.mk
