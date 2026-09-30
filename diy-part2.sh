#!/bin/bash
# ============================================================================
#  DIY Part 2 - 生成 .config (feeds 安装之后执行)
#
#  模板: mt7975-ipailna-high-power.config (237高功率版)
#  原则: 保留核心功能 + 基础库, 精简调试工具/不常用模块
# ============================================================================
set -e

echo "============================================================"
echo "  DIY Part 2: 生成 .config"
echo "============================================================"

# ==================================================================
# 1. 基础配置 + 设备选择
# ==================================================================
echo ""
echo "--- 1. 基础配置 ---"

cp -f defconfig/mt7975-ipailna-high-power.config .config
echo "  [OK] mt7975-ipailna-high-power.config"

# 禁用其他设备 (两种命名格式都试)
for dev in glinet_gl-mt6000 jdcloud_re-cp-03 tplink_tl-xdr6086 tplink_tl-xdr6088 \
           xiaomi_redmi-router-ax6000-ubootmod xiaomi_redmi-router-ax6000-stock \
           ruijie_rg-x60-pro ruijie_rg-x60-new ruijie_ew-6000gx-pro; do
    for fmt in mediatek_filogic mediatek_mt7986; do
        sed -i "s/^CONFIG_TARGET_DEVICE_${fmt}_DEVICE_${dev}=y/# CONFIG_TARGET_DEVICE_${fmt}_DEVICE_${dev} is not set/" .config 2>/dev/null || true
        sed -i "s/^CONFIG_TARGET_DEVICE_PACKAGES_${fmt}_DEVICE_${dev}=/# CONFIG_TARGET_DEVICE_PACKAGES_${fmt}_DEVICE_${dev} is not set/" .config 2>/dev/null || true
    done
done

# 启用 N60 Pro
cat >> .config << 'EOF'
CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_netcore_n60-pro=y
CONFIG_TARGET_DEVICE_PACKAGES_mediatek_filogic_DEVICE_netcore_n60-pro=""
CONFIG_TARGET_DEVICE_mediatek_mt7986_DEVICE_netcore_n60-pro=y
CONFIG_TARGET_DEVICE_PACKAGES_mediatek_mt7986_DEVICE_netcore_n60-pro=""
EOF
echo "  [OK] N60 Pro 已启用"

# ==================================================================
# 2. 精简固件
# ==================================================================
echo ""
echo "--- 2. 精简 ---"

REMOVE_COUNT=0
remove_pkg() {
    if grep -q "^CONFIG_PACKAGE_${1}=y" .config 2>/dev/null; then
        sed -i "s/^CONFIG_PACKAGE_${1}=y/# CONFIG_PACKAGE_${1} is not set/" .config
        REMOVE_COUNT=$((REMOVE_COUNT + 1))
    fi
    return 0
}

# A. 被替代的插件
remove_pkg "luci-app-ssr-plus"
remove_pkg "luci-app-ssr-plus_INCLUDE_NONE_V2RAY"
remove_pkg "luci-app-ssr-plus_INCLUDE_Shadowsocks_NONE_Client"
remove_pkg "luci-app-ssr-plus_INCLUDE_Shadowsocks_NONE_Server"
remove_pkg "luci-app-wrtbwmon"
remove_pkg "luci-theme-bootstrap-mod"
echo "  [A] 被替代的插件"

# B. 调试工具
for pkg in htop nano kvcedit tcpdump libpcap terminfo libncurses regs mii_mgr kmod-inet-diag; do
    remove_pkg "$pkg"
done
echo "  [B] 调试工具"

# C. 无用硬件驱动
remove_pkg "kmod-leds-ws2812b"
remove_pkg "kmod-ata-core"
echo "  [C] 无用驱动"

# D. 桥接防火墙
for pkg in kmod-ebtables kmod-ebtables-ipv4 kmod-ebtables-ipv6 ebtables; do
    remove_pkg "$pkg"
done
echo "  [D] ebtables"

# E. 不常用 iptables 模块
for mod in filter tee u32 ipv4options; do
    remove_pkg "kmod-ipt-${mod}"
    remove_pkg "iptables-mod-${mod}"
done
remove_pkg "kmod-ipt-compat-xtables"
echo "  [E] iptables 模块"

# F. IPv6 用户态 (内核保留)
for pkg in ip6tables-extra ip6tables-nft kmod-ipt-raw6 kmod-ip6tables-extra \
           odhcp6c odhcpd-ipv6only luci-proto-ipv6 luci-proto-6in4; do
    remove_pkg "$pkg"
done
echo "  [F] IPv6 用户态"

# G. 其他非核心
for pkg in blockd libfido2 libevdev libudev-zero libcbor openssh-keygen \
           libkvcutil resolveip zram-swap kmod-zram kmod-lib-lzo; do
    remove_pkg "$pkg"
done
echo "  [G] 其他"

# H. 诊断/统计网页界面
remove_pkg "luci-app-diag-core"
remove_pkg "luci-app-statistics"
echo "  [H] 诊断/统计界面"

echo "  合计移除: ${REMOVE_COUNT} 个包"

# ==================================================================
# 3. daed 内核选项 (eBPF)
# ==================================================================
echo ""
echo "--- 3. daed 内核选项 ---"
cat >> .config << 'EOF'
CONFIG_KERNEL_DEBUG_INFO=y
# CONFIG_KERNEL_DEBUG_INFO_REDUCED is not set
CONFIG_KERNEL_DEBUG_INFO_BTF=y
CONFIG_KERNEL_BPF_EVENTS=y
CONFIG_XDP_SOCKETS=y
CONFIG_BPF_TOOLCHAIN=y
CONFIG_BPF_TOOLCHAIN_HOST=y
EOF
echo "  [OK] BPF/BTF/XDP"

# ==================================================================
# 4. 添加软件包
# ==================================================================
echo ""
echo "--- 4. 添加软件包 ---"

cat >> .config << 'EOF'

# 代理: daed
CONFIG_PACKAGE_daed=y
CONFIG_PACKAGE_luci-app-daed=y

# 组网: EasyTier
CONFIG_PACKAGE_easytier=y
CONFIG_EASYTIER_INCLUDE_WEBCONSOLE=y
CONFIG_PACKAGE_luci-app-easytier=y

# DDNS: ddns-go (界面, 主程序在 files/)
CONFIG_PACKAGE_luci-app-ddns-go=y

# 文件共享: Samba4 + CIFS
CONFIG_PACKAGE_samba4-server=y
CONFIG_PACKAGE_luci-app-samba4=y
CONFIG_PACKAGE_wsdd2=y
CONFIG_PACKAGE_kmod-fs-cifs=y
CONFIG_PACKAGE_cifsmount=y
CONFIG_PACKAGE_kmod-nls-base=y
CONFIG_PACKAGE_kmod-nls-utf8=y
CONFIG_PACKAGE_kmod-nls-cp437=y
CONFIG_PACKAGE_kmod-nls-iso8859-1=y

# 流量统计
CONFIG_PACKAGE_vnstat2=y
CONFIG_PACKAGE_vnstat2-image=y
CONFIG_PACKAGE_luci-app-vnstat2=y
CONFIG_PACKAGE_nlbwmon=y
CONFIG_PACKAGE_luci-app-nlbwmon=y

# 主题 + 终端 + 硬件信息
CONFIG_PACKAGE_luci-theme-argon=y
CONFIG_PACKAGE_ttyd=y
CONFIG_PACKAGE_luci-app-ttyd=y
CONFIG_PACKAGE_autocore-arm=y
EOF
echo "  [OK] daed + EasyTier + ddns-go + samba4 + vnstat2 + nlbwmon + argon + ttyd + autocore"

# ==================================================================
# 5. rootfs 分区大小
# ==================================================================
echo ""
echo "--- 5. rootfs ---"
echo 'CONFIG_TARGET_ROOTFS_PARTSIZE=80' >> .config
echo "  [OK] 80MB"

# ==================================================================
# 6. make defconfig
# ==================================================================
echo ""
echo "--- 6. make defconfig ---"
make defconfig
echo "  [OK]"

# ==================================================================
# 7. 验证
# ==================================================================
echo ""
echo "=== 验证 ==="

check() { grep -q "CONFIG_PACKAGE_${1}=y" .config 2>/dev/null && echo "  [OK] $1" || echo "  [!!] $1 缺失"; }

echo "[设备]"
grep "CONFIG_TARGET_DEVICE.*netcore" .config | head -1

echo "[插件]"
for p in daed luci-app-daed easytier luci-app-easytier luci-app-ddns-go \
         samba4-server kmod-fs-cifs luci-app-vnstat2 luci-app-nlbwmon \
         luci-theme-argon ttyd luci-app-ttyd autocore-arm; do
    check "$p"
done

echo "[核心]"
for p in kmod-mt_wifi kmod-mediatek_hnat kmod-tun kmod-tcp-bbr \
         kmod-usb-storage kmod-fs-ext4 block-mount ppp; do
    check "$p"
done

echo "[精简]"
for p in luci-app-ssr-plus htop tcpdump wrtbwmon ebtables zram-swap; do
    grep -q "CONFIG_PACKAGE_${p} is not set" .config && echo "  [OK] ${p}: 已移除" || echo "  [--] ${p}: 不在配置中"
done

echo "[分区]"
grep "CONFIG_TARGET_ROOTFS_PARTSIZE" .config

echo ""
echo "============================================================"
echo "  DIY Part 2 完成"
echo "  精简: ${REMOVE_COUNT} 个包"
echo "  内置: daed / EasyTier / ddns-go / samba4 / vnstat2 / nlbwmon / argon / ttyd / autocore"
echo "============================================================"
