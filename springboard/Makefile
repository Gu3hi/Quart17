TWEAK_NAME = Quart17
Quart17_FILES = Tweak.xm ../QPlayerView.m ../QNativeArtwork.m
Quart17_CFLAGS = -fobjc-arc -I..
# RootHide 与标准 Rootless 路径宏区分：roothide 方案用 jbroot()，
# 标准 rootless 直接用 /var/jb 前缀
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
Quart17_CFLAGS += -DQ_ROOTHIDE=1
endif
Quart17_FRAMEWORKS = UIKit AVKit
Quart17_LIBRARIES = substrate

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
