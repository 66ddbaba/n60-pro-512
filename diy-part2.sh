#!/bin/bash
# ============================================================================
#  DIY Part 2 - 生成编译配置 .config (feeds 安装之后执行)
#
#  原则:
#    - 保留所有核心路由功能 (WiFi/拨号/防火墙/加速/USB存储)
#    - 保留基础库和常用内核模块, 确保日后 opkg 不缺依赖
#    - 精简调试工具/不常用模块/被替代的旧插件
#    - 添加 daed / EasyTier / ddns-go / samba4 / 流量统计 / argon
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

# 从 mt7986-ax6000.config 开始 (最接近 N60 Pro 的配置)
cp -f defconfig/mt7986-ax6000.config .config
echo "  [OK] 基础配置: mt7986-ax6000.config"

# 禁用其他设备, 只编译 N60 Pro (省编译时间)
DISABLE_DEVICES=(
    "glinet_gl-mt6000"
    "jdcloud_re-cp-03"
    "tplink_tl-xdr6086"
    "tplink_tl-xdr6088"
    "xiaomi_redmi-router-ax6000-ubootmod"
    "xiaomi_redmi-router-ax6000-stock"
)
for dev in "${DISABLE_DEVICES[@]}"; do
    sed -i "s/^CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_${dev}=y/# CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_${dev} is not set/" .config 2>/dev/null || true
    sed -i "s/^CONFIG_TARGET_DEVICE_PACKAGES_mediatek_filogic_DEVICE_${dev}=/# CONFIG_TARGET_DEVICE_PACKAGES_mediatek_filogic_DEVICE_${dev} is not set/" .config 2>/dev/null || true
done
echo "  [OK] 已禁用其他 ${#DISABLE_DEVICES[@]} 个设备"

# 启用 N60 Pro
cat >> .config << 'EOF'
# N60 Pro 设备
CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_netcore_n60-pro=y
CONFIG_TARGET_DEVICE_PACKAGES_mediatek_filogic_DEVICE_netcore_n60-pro=""
EOF
echo "  [OK] 启用 N60 Pro"

# ==================================================================
# 2. 精简固件
# ==================================================================
echo ""
echo "--- 2. 精简固件 ---"

REMOVE_COUNT=0

# 移除一个包的通用函数 (始终返回 0, 避免触发 set -e)
remove_pkg() {
    local pkg="$1"
    if grep -q "^CONFIG_PACKAGE_${pkg}=y" .config 2>/dev/null; then
        sed -i "s/^CONFIG_PACKAGE_${pkg}=y/# CONFIG_PACKAGE_${pkg} is not set/" .config
        REMOVE_COUNT=$((REMOVE_COUNT + 1))
    fi
    return 0
}

# --- A. 被新增插件替代的 ---
remove_pkg "luci-app-ssr-plus"                    # daed 替代
remove_pkg "luci-app-ssr-plus_INCLUDE_NONE_V2RAY"
remove_pkg "luci-app-ssr-plus_INCLUDE_Shadowsocks_NONE_Client"
remove_pkg "luci-app-ssr-plus_INCLUDE_Shadowsocks_NONE_Server"
remove_pkg "luci-app-wrtbwmon"                     # vnstat2+nlbwmon 替代
remove_pkg "luci-theme-bootstrap-mod"              # argon 替代 (内置 bootstrap 保留)
echo "  [A] 被替代的插件"

# --- B. 调试/诊断工具 (日后可 opkg 按需安装) ---
for pkg in htop nano kvcedit tcpdump libpcap terminfo libncurses regs mii_mgr; do
    remove_pkg "$pkg"
done
remove_pkg "kmod-inet-diag"                       # socket 诊断
echo "  [B] 调试工具"

# --- C. N60 Pro 不需要的硬件驱动 ---
remove_pkg "kmod-leds-ws2812b"                     # WS2812B LED (N60 Pro 没有)
remove_pkg "kmod-ata-core"                         # SATA (N60 Pro 没有)
echo "  [C] 无用硬件驱动"

# --- D. 桥接防火墙 (家庭主路由很少用) ---
for pkg in kmod-ebtables kmod-ebtables-ipv4 kmod-ebtables-ipv6 ebtables; do
    remove_pkg "$pkg"
done
echo "  [D] ebtables 桥接防火墙"

# --- E. 极少用的 iptables 模块 ---
for mod in filter tee u32 ipv4options; do
    remove_pkg "kmod-ipt-${mod}"
    remove_pkg "iptables-mod-${mod}"
done
remove_pkg "kmod-ipt-compat-xtables"               # 旧版 xtables 兼容层
echo "  [E] 不常用 iptables 模块"

# --- F. IPv6 用户态工具 (保留内核 IPv6 基础, 避免隐性依赖) ---
for pkg in ip6tables-extra ip6tables-nft kmod-ipt-raw6 kmod-ip6tables-extra odhcp6c odhcpd-ipv6only luci-proto-ipv6 luci-proto-6in4; do
    remove_pkg "$pkg"
done
echo "  [F] IPv6 用户态工具 (内核保留)"

# --- G. 其他非核心 ---
remove_pkg "blockd"                                # 广告过滤
remove_pkg "libfido2"                              # FIDO (路由器不需要)
remove_pkg "libevdev"                              # 输入设备库
remove_pkg "libudev-zero"                          # udev
remove_pkg "libcbor"                               # libfido2 依赖
remove_pkg "openssh-keygen"                        # dropbear 已提供
remove_pkg "libkvcutil"                            # kvcedit 配套库
remove_pkg "resolveip"                             # dnsmasq 已提供
remove_pkg "zram-swap"                             # 2GB 内存足够
remove_pkg "kmod-zram"
remove_pkg "kmod-lib-lzo"
echo "  [G] 其他非核心"

echo "  合计移除: ${REMOVE_COUNT} 个包"

# ==================================================================
# 3. daed 内核选项 (eBPF 支持)
# ==================================================================
echo ""
echo "--- 3. daed 内核选项 ---"
cat >> .config << 'EOF'
# daed eBPF 支持
CONFIG_KERNEL_DEBUG_INFO=y
# CONFIG_KERNEL_DEBUG_INFO_REDUCED is not set
CONFIG_KERNEL_DEBUG_INFO_BTF=y
CONFIG_KERNEL_BPF_EVENTS=y
CONFIG_XDP_SOCKETS=y
CONFIG_BPF_TOOLCHAIN=y
CONFIG_BPF_TOOLCHAIN_HOST=y
EOF
echo "  [OK] BPF/BTF/XDP 已启用"

# ==================================================================
# 4. 添加软件包
# ==================================================================
echo ""
echo "--- 4. 添加软件包 ---"

cat >> .config << 'EOF'

# ===== 代理: daed (替代 ssr-plus) =====
CONFIG_PACKAGE_daed=y
CONFIG_PACKAGE_luci-app-daed=y

# ===== 组网: EasyTier =====
CONFIG_PACKAGE_easytier=y
CONFIG_EASYTIER_INCLUDE_WEBCONSOLE=y
CONFIG_PACKAGE_luci-app-easytier=y

# ===== DDNS: ddns-go (主程序在 files/, 这里只加界面) =====
CONFIG_PACKAGE_luci-app-ddns-go=y

# ===== 文件共享: Samba4 (共享到局域网) =====
CONFIG_PACKAGE_samba4-server=y
CONFIG_PACKAGE_luci-app-samba4=y
CONFIG_PACKAGE_wsdd2=y

# ===== 文件共享: CIFS 客户端 (挂载远程 SMB) =====
CONFIG_PACKAGE_kmod-fs-cifs=y
CONFIG_PACKAGE_cifsmount=y

# ===== NLS 字符集 (CIFS 需要, 中文不乱码) =====
CONFIG_PACKAGE_kmod-nls-base=y
CONFIG_PACKAGE_kmod-nls-utf8=y
CONFIG_PACKAGE_kmod-nls-cp437=y
CONFIG_PACKAGE_kmod-nls-iso8859-1=y

# ===== 流量统计: vnstat2 (WAN 口精确统计) =====
CONFIG_PACKAGE_vnstat2=y
CONFIG_PACKAGE_vnstat2-image=y
CONFIG_PACKAGE_luci-app-vnstat2=y

# ===== 流量统计: nlbwmon (内网设备统计) =====
CONFIG_PACKAGE_nlbwmon=y
CONFIG_PACKAGE_luci-app-nlbwmon=y

# ===== 主题: argon =====
CONFIG_PACKAGE_luci-theme-argon=y
CONFIG_PACKAGE_luci-app-argon-config=y
EOF
echo "  [OK] daed + EasyTier + ddns-go + samba4 + vnstat2 + nlbwmon + argon"

# ==================================================================
# 5. rootfs 分区大小
# ==================================================================
echo ""
echo "--- 5. rootfs 分区 ---"
# 506.5MB UBI = kernel(~6MB) + rootfs(80MB) + rootfs_data(~420MB)
# 固件实际 ~67MB, 80MB 留 ~13MB 余量, 剩余给 rootfs_data 装插件
echo 'CONFIG_TARGET_ROOTFS_PARTSIZE=80' >> .config
echo "  [OK] rootfs: 80MB, rootfs_data: ~420MB"

# ==================================================================
# 6. 解析依赖 (make defconfig)
# ==================================================================
echo ""
echo "--- 6. make defconfig (解析依赖) ---"
make defconfig
echo "  [OK] 完成"

# ==================================================================
# 7. 验证关键配置
# ==================================================================
echo ""
echo "============================================================"
echo "  配置验证"
echo "============================================================"

check_pkg() {
    grep -q "CONFIG_PACKAGE_${1}=y" .config 2>/dev/null && echo "  [OK] $1" || echo "  [!!] $1 缺失!"
}

echo ""
echo "[目标设备]"
grep "CONFIG_TARGET_DEVICE.*netcore" .config | head -1

echo ""
echo "[内置插件]"
check_pkg "daed"
check_pkg "luci-app-daed"
check_pkg "easytier"
check_pkg "luci-app-easytier"
check_pkg "luci-app-ddns-go"
check_pkg "samba4-server"
check_pkg "kmod-fs-cifs"
check_pkg "luci-app-vnstat2"
check_pkg "luci-app-nlbwmon"
check_pkg "luci-theme-argon"

echo ""
echo "[核心功能 (确保没被误删)]"
for pkg in kmod-mt_wifi kmod-mediatek_hnat kmod-tun kmod-tcp-bbr kmod-usb-storage kmod-fs-ext4 block-mount ppp; do
    check_pkg "$pkg"
done

echo ""
echo "[精简项]"
for pkg in luci-app-ssr-plus htop tcpdump wrtbwmon ebtables zram-swap; do
    if grep -q "CONFIG_PACKAGE_${pkg} is not set" .config; then
        echo "  [OK] ${pkg}: 已移除"
    else
        echo "  [--] ${pkg}: 不在配置中(可能在feeds里)"
    fi
done

echo ""
echo "[分区]"
grep "CONFIG_TARGET_ROOTFS_PARTSIZE" .config

echo ""
echo "============================================================"
echo "  DIY Part 2 完成!"
echo "  精简: ${REMOVE_COUNT} 个包"
echo "  内置: daed / EasyTier / ddns-go / samba4 / vnstat2 / nlbwmon / argon"
echo "  核心: WiFi / 拨号 / 加速 / 防火墙 / USB 存储 / 基础库 全保留"
echo "============================================================"
