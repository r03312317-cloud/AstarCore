#!/bin/sh
# 此脚本保留本工程使用的原始启动或构建流程，具体路径和参数没有在注释版中改变。
set -eu
# The minimal simulation BSP has no network device/stack. Do not start the
# Buildroot skeleton's default networking service and report misleading FAIL.
rm -f "$1/etc/init.d/S40network"
