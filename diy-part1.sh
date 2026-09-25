#!/bin/bash
# ============================================================================
# DIY 脚本 Part 1 - 源码修改 (在 feeds 更新之前执行)
# 功能:
#   1. 修改 DTS 设备树: 内存改为 2GB, 移除 NMBM, UBI 分区改为 506.5MB
#   2. 检查/添加 netcore_n60-pro 设备定义到 filogic.mk
#   3. 添加 EasyTier 软件包
#   4. 添加 luci-theme-argon 主题 (含配置工具)
# ============================================================================
set -e

echo "============================================================"
echo "  DIY Part 1: 源码修改"
echo "  目标: N60 Pro 512MB 闪存 + 2GB 内存"
echo "============================================================"

# ------------------------------------------------------------
# 1. 修改 DTS 设备树文件
# ------------------------------------------------------------
DTS_FILE="target/linux/mediatek/dts/mt7986a-netcore-n60-pro.dts"

if [ ! -f "$DTS_FILE" ]; then
    echo "[错误] DTS 文件不存在: $DTS_FILE"
    echo "请检查源码是否正确克隆"
    exit 1
fi

echo ""
echo "--- 1.1 修改内存大小: 512MB -> 2GB ---"
sed -i 's/0x40000000 0 0x20000000/0x40000000 0 0x80000000/' "$DTS_FILE"
echo "  内存已改为 2GB"

echo ""
echo "--- 1.2 移除 NMBM ---"
sed -i '/mediatek,nmbm;/d' "$DTS_FILE"
sed -i '/mediatek,bmt-max-ratio/d' "$DTS_FILE"
sed -i '/mediatek,bmt-max-reserved-blocks/d' "$DTS_FILE"
echo "  NMBM 已移除"

echo ""
echo "--- 1.3 修改 UBI 分区大小: 128MB -> 506.5MB ---"
sed -i 's/0x0580000 0x7280000/0x0580000 0x1FA80000/' "$DTS_FILE"
echo "  UBI 分区已改为 506.5MB"

echo ""
echo "--- 1.4 验证 DTS 修改结果 ---"
echo "  [内存] $(grep 'memory@' -A1 "$DTS_FILE" | grep 'reg')"
echo "  [NMBM] $(grep -c 'nmbm' "$DTS_FILE" || echo 0) 处残留 (应为0)"
echo "  [UBI]  $(grep -A2 'label = "ubi"' "$DTS_FILE" | grep 'reg')"

# ------------------------------------------------------------
# 2. 检查/添加 netcore_n60-pro 设备定义
# ------------------------------------------------------------
FIRMWARE_MK="target/linux/mediatek/image/filogic.mk"

echo ""
echo "--- 2.1 检查 netcore_n60-pro 设备定义 ---"

if grep -q "define Device/netcore_n60-pro" "$FIRMWARE_MK" 2>/dev/null; then
    echo "  设备定义已存在, 移除 IMAGE_SIZE 限制..."
    sed -i '/define Device\/netcore_n60-pro/,/endef/ {/IMAGE_SIZE/d}' "$FIRMWARE_MK"
    echo "  IMAGE_SIZE 已移除"
else
    echo "  设备定义不存在, 正在添加..."
    cat >> "$FIRMWARE_MK" << 'DEVICE_DEF'

define Device/netcore_n60-pro
  DEVICE_VENDOR := Netcore
  DEVICE_MODEL := N60 Pro
  DEVICE_DTS := mt7986a-netcore-n60-pro
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7986-firmware mt7986-wo-firmware
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  KERNEL_IN_UBI := 1
  IMAGES += factory.bin
  IMAGE/factory.bin := append-ubi | check-size
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += netcore_n60-pro
DEVICE_DEF
    echo "  设备定义已添加"
fi

# ------------------------------------------------------------
# 3. 添加 EasyTier 软件包
# ------------------------------------------------------------
echo ""
echo "--- 3.1 添加 EasyTier ---"

if [ -d "package/luci-app-easytier" ]; then
    echo "  EasyTier 已存在, 跳过"
else
    git clone --depth 1 https://github.com/EasyTier/luci-app-easytier.git package/luci-app-easytier
    echo "  EasyTier 已添加"
fi

# ------------------------------------------------------------
# 4. 添加 luci-theme-argon 主题
# ------------------------------------------------------------
echo ""
echo "--- 4.1 添加 luci-theme-argon 主题 ---"

if [ -d "package/luci-theme-argon" ]; then
    echo "  luci-theme-argon 已存在, 跳过"
else
    git clone --depth 1 https://github.com/jerrykuku/luci-theme-argon.git package/luci-theme-argon
    echo "  luci-theme-argon 已添加"
fi

if [ -d "package/luci-app-argon-config" ]; then
    echo "  luci-app-argon-config 已存在, 跳过"
else
    git clone --depth 1 https://github.com/jerrykuku/luci-app-argon-config.git package/luci-app-argon-config
    echo "  luci-app-argon-config 已添加"
fi

# ------------------------------------------------------------
# 5. 添加 ddns-go (sirpdboy)
# ------------------------------------------------------------
echo ""
echo "--- 5.1 添加 ddns-go (sirpdboy) ---"

if [ -d "package/luci-app-ddns-go" ]; then
    echo "  luci-app-ddns-go 已存在, 跳过"
else
    git clone --depth 1 https://github.com/sirpdboy/luci-app-ddns-go.git package/luci-app-ddns-go
    echo "  luci-app-ddns-go 已添加"
fi

# ------------------------------------------------------------
# 完成
# ------------------------------------------------------------
echo ""
echo "============================================================"
echo "  DIY Part 1 完成!"
echo "  - DTS: 2GB 内存 + 无 NMBM + 506.5MB UBI"
echo "  - 设备: netcore_n60-pro 已就绪"
echo "  - 包: EasyTier, luci-theme-argon, ddns-go"
echo "  - 其他 sirpdboy 软件: 不编译, 日后通过 opkg 安装"
echo "============================================================"
