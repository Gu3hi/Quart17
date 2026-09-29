export TARGET := iphone:clang:16.5:17.0
export ARCHS := arm64 arm64e
export THEOS_PACKAGE_SCHEME := roothide
export DEB_ARCH := iphoneos-arm64e
export INSTALL_TARGET_PROCESSES := SpringBoard MediaRemoteUI

include $(THEOS)/makefiles/common.mk

SUBPROJECTS += springboard
SUBPROJECTS += uikit
SUBPROJECTS += preferences
include $(THEOS_MAKE_PATH)/aggregate.mk
