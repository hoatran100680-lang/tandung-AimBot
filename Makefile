export SDKROOT = /usr/local/iPhoneOS14.0.sdk
ARCHS = arm64
TARGET = iphone:clang:14.0
ENTITLEMENTS = entitlements.plist

include /home/tandung/theos/makefiles/common.mk

TOOL_NAME = AimBot
AimBot_FILES = AimBot.mm

include /home/tandung/theos/makefiles/tool.mk
