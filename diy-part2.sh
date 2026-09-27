#!/bin/bash
# ============================================================================
# DIY 脚本 Part 2 - 配置文件生成 (在 feeds 安装之后执行)
# 功能:
#   1. 基于源码自带的 mt7986-ax6000.config 创建 .config
#   2. 禁用其他设备, 只保留 N60 Pro
#   3. 精简: 移除社区公认无用的插件/工具, 保留所有核心功能
#   4. 添加 daed 内核选项 (BPF/BTF/XDP 支持)
#   5. 添加 daed、EasyTier、ddns-go、Samba4、流量统计、argon 主题
#   6. 保留基础库和内核模块, 确保日后 opkg 安装软件不会缺依赖
#   7. 设置 rootfs 分区大小
# ============================================================================
set -e

echo "============================================================"
echo "  DIY Part 2: 生成编译配置文件 .config"
echo "============================================================"

# ------------------------------------------------------------
# 1. 从基础配置开始
# ------------------------------------------------------------
echo ""
echo "--- 1.1 加载基础配置 mt7986-ax6000.config ---"
cp -f defconfig/mt7986-ax6000.config .config
echo "  基础配置已复制"

# ------------------------------------------------------------
# 2. 禁用其他设备 (只编译 N60 Pro)
# ------------------------------------------------------------
echo ""
echo "--- 1.2 禁用其他设备 ---"

sed -i 's/^CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_glinet_gl-mt6000=y/# CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_glinet_gl-mt6000 is not set/' .config
sed -i 's/^CONFIG_TARGET_DEVICE_PACKAGES_mediatek_filogic_DEVICE_glinet_gl-mt6000=/# CONFIG_TARGET_DEVICE_PACKAGES_mediatek_filogic_DEVICE_glinet_gl-mt6000 is not set/' .config

sed -i 's/^CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_jdcloud_re-cp-03=y/# CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_jdcloud_re-cp-03 is not set/' .config
sed -i 's/^CONFIG_TARGET_DEVICE_PACKAGES_mediatek_filogic_DEVICE_jdcloud_re-cp-03=/# CONFIG_TARGET_DEVICE_PACKAGES_mediatek_filogic_DEVICE_jdcloud_re-cp-03 is not set/' .config

sed -i 's/^CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_tplink_tl-xdr6086=y/# CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_tplink_tl-xdr6086 is not set/' .config
sed -i 's/^CONFIG_TARGET_DEVICE_PACKAGES_mediatek_filogic_DEVICE_tplink_tl-xdr6086=/# CONFIG_TARGET_DEVICE_PACKAGES_mediatek_filogic_DEVICE_tplink_tl-xdr6086 is not set/' .config

sed -i 's/^CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_tplink_tl-xdr6088=y/# CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_tplink_tl-xdr6088 is not set/' .config
sed -i 's/^CONFIG_TARGET_DEVICE_PACKAGES_mediatek_filogic_DEVICE_tplink_tl-xdr6088=/# CONFIG_TARGET_DEVICE_PACKAGES_mediatek_filogic_DEVICE_tplink_tl-xdr6088 is not set/' .config

sed -i 's/^CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_xiaomi_redmi-router-ax6000-ubootmod=y/# CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_xiaomi_redmi-router-ax6000-ubootmod is not set/' .config
sed -i 's/^CONFIG_TARGET_DEVICE_PACKAGES_mediatek_filogic_DEVICE_xiaomi_redmi-router-ax6000-ubootmod=/# CONFIG_TARGET_DEVICE_PACKAGES_mediatek_filogic_DEVICE_xiaomi_redmi-router-ax6000-ubootmod is not set/' .config

sed -i 's/^CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_xiaomi_redmi-router-ax6000-stock=y/# CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_xiaomi_redmi-router-ax6000-stock is not set/' .config
sed -i 's/^CONFIG_TARGET_DEVICE_PACKAGES_mediatek_filogic_DEVICE_xiaomi_redmi-router-ax6000-stock=/# CONFIG_TARGET_DEVICE_PACKAGES_mediatek_filogic_DEVICE_xiaomi_redmi-router-ax6000-stock is not set/' .config

echo "  其他设备已禁用"

# ------------------------------------------------------------
# 3. 启用 N60 Pro 设备
# ------------------------------------------------------------
echo ""
echo "--- 1.3 启用 N60 Pro 设备 ---"
cat >> .config << 'EOF'

# ===== N60 Pro 设备 =====
CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_netcore_n60-pro=y
CONFIG_TARGET_DEVICE_PACKAGES_mediatek_filogic_DEVICE_netcore_n60-pro=""
EOF
echo "  N60 Pro 已启用"

# ============================================================
# 4. 精简固件
#    原则: 保留所有核心路由功能、WiFi、拨号、防火墙
#         保留基础库和常用内核模块, 确保日后 opkg 不缺依赖
# ============================================================
echo ""
echo "--- 1.4 精简固件 ---"

# --- A. 被新增插件替代的默认包 ---

# ssr-plus 被 daed 替代
sed -i 's/^CONFIG_PACKAGE_luci-app-ssr-plus=y/# CONFIG_PACKAGE_luci-app-ssr-plus is not set/' .config
sed -i 's/^CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_NONE_V2RAY=y/# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_NONE_V2RAY is not set/' .config
sed -i 's/^CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_NONE_Client=y/# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_NONE_Client is not set/' .config
sed -i 's/^CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_NONE_Server=y/# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_NONE_Server is not set/' .config
echo "  移除: ssr-plus (被 daed 替代)"

# wrtbwmon 被 vnstat2+nlbwmon 替代
sed -i 's/^CONFIG_PACKAGE_luci-app-wrtbwmon=y/# CONFIG_PACKAGE_luci-app-wrtbwmon is not set/' .config
echo "  移除: wrtbwmon (被 vnstat2+nlbwmon 替代)"

# luci-theme-bootstrap-mod 被 argon 替代 (内置 bootstrap 仍保留作备用)
sed -i 's/^CONFIG_PACKAGE_luci-theme-bootstrap-mod=y/# CONFIG_PACKAGE_luci-theme-bootstrap-mod is not set/' .config
echo "  移除: luci-theme-bootstrap-mod (被 argon 替代, 内置 bootstrap 保留)"

# --- B. 调试工具 (日后可 opkg install 按需安装) ---
sed -i 's/^CONFIG_PACKAGE_htop=y/# CONFIG_PACKAGE_htop is not set/' .config
sed -i 's/^CONFIG_PACKAGE_nano=y/# CONFIG_PACKAGE_nano is not set/' .config
sed -i 's/^CONFIG_PACKAGE_kvcedit=y/# CONFIG_PACKAGE_kvcedit is not set/' .config
sed -i 's/^CONFIG_PACKAGE_tcpdump=y/# CONFIG_PACKAGE_tcpdump is not set/' .config
sed -i 's/^CONFIG_PACKAGE_libpcap=y/# CONFIG_PACKAGE_libpcap is not set/' .config
sed -i 's/^CONFIG_PACKAGE_terminfo=y/# CONFIG_PACKAGE_terminfo is not set/' .config
sed -i 's/^CONFIG_PACKAGE_libncurses=y/# CONFIG_PACKAGE_libncurses is not set/' .config
echo "  移除: htop, nano, kvcedit, tcpdump, terminfo, libncurses (调试工具)"

# --- C. N60 Pro 不需要的硬件驱动 ---
sed -i 's/^CONFIG_PACKAGE_kmod-leds-ws2812b=y/# CONFIG_PACKAGE_kmod-leds-ws2812b is not set/' .config
sed -i 's/^CONFIG_PACKAGE_kmod-ata-core=y/# CONFIG_PACKAGE_kmod-ata-core is not set/' .config
echo "  移除: kmod-leds-ws2812b, kmod-ata-core (N60 Pro 无此硬件)"

# --- D. 桥接防火墙 (家庭主路由很少用) ---
sed -i 's/^CONFIG_PACKAGE_kmod-ebtables=y/# CONFIG_PACKAGE_kmod-ebtables is not set/' .config
sed -i 's/^CONFIG_PACKAGE_kmod-ebtables-ipv4=y/# CONFIG_PACKAGE_kmod-ebtables-ipv4 is not set/' .config
sed -i 's/^CONFIG_PACKAGE_kmod-ebtables-ipv6=y/# CONFIG_PACKAGE_kmod-ebtables-ipv6 is not set/' .config
sed -i 's/^CONFIG_PACKAGE_ebtables=y/# CONFIG_PACKAGE_ebtables is not set/' .config
echo "  移除: ebtables 全家桶 (桥接防火墙)"

# --- E. 极少使用的 iptables 匹配模块 ---
sed -i 's/^CONFIG_PACKAGE_kmod-ipt-filter=y/# CONFIG_PACKAGE_kmod-ipt-filter is not set/' .config
sed -i 's/^CONFIG_PACKAGE_kmod-ipt-tee=y/# CONFIG_PACKAGE_kmod-ipt-tee is not set/' .config
sed -i 's/^CONFIG_PACKAGE_kmod-ipt-u32=y/# CONFIG_PACKAGE_kmod-ipt-u32 is not set/' .config
sed -i 's/^CONFIG_PACKAGE_kmod-ipt-ipv4options=y/# CONFIG_PACKAGE_kmod-ipt-ipv4options is not set/' .config
sed -i 's/^CONFIG_PACKAGE_iptables-mod-filter=y/# CONFIG_PACKAGE_iptables-mod-filter is not set/' .config
sed -i 's/^CONFIG_PACKAGE_iptables-mod-tee=y/# CONFIG_PACKAGE_iptables-mod-tee is not set/' .config
sed -i 's/^CONFIG_PACKAGE_iptables-mod-u32=y/# CONFIG_PACKAGE_iptables-mod-u32 is not set/' .config
sed -i 's/^CONFIG_PACKAGE_iptables-mod-ipv4options=y/# CONFIG_PACKAGE_iptables-mod-ipv4options is not set/' .config
echo "  移除: kmod-ipt-filter/tee/u32/ipv4options + 对应 iptables-mod"

# --- F. 旧版兼容层 (nftables 已是默认) ---
sed -i 's/^CONFIG_PACKAGE_kmod-ipt-compat-xtables=y/# CONFIG_PACKAGE_kmod-ipt-compat-xtables is not set/' .config
echo "  移除: kmod-ipt-compat-xtables (旧版 xtables 兼容层)"

# --- G. 调试诊断工具 ---
sed -i 's/^CONFIG_PACKAGE_kmod-inet-diag=y/# CONFIG_PACKAGE_kmod-inet-diag is not set/' .config
echo "  移除: kmod-inet-diag (socket 诊断, 调试用)"

# --- H. IPv6 用户态工具 (用户不需要 IPv6) ---
# 保留 kmod-ipv6 和 kmod-ip6tables (内核基础, 避免隐性依赖)
sed -i 's/^CONFIG_PACKAGE_ip6tables-extra=y/# CONFIG_PACKAGE_ip6tables-extra is not set/' .config
sed -i 's/^CONFIG_PACKAGE_ip6tables-nft=y/# CONFIG_PACKAGE_ip6tables-nft is not set/' .config
sed -i 's/^CONFIG_PACKAGE_kmod-ipt-raw6=y/# CONFIG_PACKAGE_kmod-ipt-raw6 is not set/' .config
sed -i 's/^CONFIG_PACKAGE_kmod-ip6tables-extra=y/# CONFIG_PACKAGE_kmod-ip6tables-extra is not set/' .config
sed -i 's/^CONFIG_PACKAGE_odhcp6c=y/# CONFIG_PACKAGE_odhcp6c is not set/' .config
sed -i 's/^CONFIG_PACKAGE_odhcpd-ipv6only=y/# CONFIG_PACKAGE_odhcpd-ipv6only is not set/' .config
sed -i 's/^CONFIG_PACKAGE_luci-proto-ipv6=y/# CONFIG_PACKAGE_luci-proto-ipv6 is not set/' .config
sed -i 's/^CONFIG_PACKAGE_luci-proto-6in4=y/# CONFIG_PACKAGE_luci-proto-6in4 is not set/' .config
echo "  移除: IPv6 用户态工具 (保留 kmod-ipv6/ip6tables 内核基础)"

# --- I. 广告过滤 (非核心) ---
sed -i 's/^CONFIG_PACKAGE_blockd=y/# CONFIG_PACKAGE_blockd is not set/' .config
echo "  移除: blockd (广告过滤)"

# --- J. 寄存器/PHY 调试工具 ---
sed -i 's/^CONFIG_PACKAGE_regs=y/# CONFIG_PACKAGE_regs is not set/' .config
sed -i 's/^CONFIG_PACKAGE_mii_mgr=y/# CONFIG_PACKAGE_mii_mgr is not set/' .config
echo "  移除: regs, mii_mgr (寄存器/PHY 调试)"

# --- K. 输入设备库 (路由器不需要键盘鼠标) ---
sed -i 's/^CONFIG_PACKAGE_libfido2=y/# CONFIG_PACKAGE_libfido2 is not set/' .config
sed -i 's/^CONFIG_PACKAGE_libevdev=y/# CONFIG_PACKAGE_libevdev is not set/' .config
sed -i 's/^CONFIG_PACKAGE_libudev-zero=y/# CONFIG_PACKAGE_libudev-zero is not set/' .config
sed -i 's/^CONFIG_PACKAGE_libcbor=y/# CONFIG_PACKAGE_libcbor is not set/' .config
echo "  移除: libfido2, libevdev, libudev-zero, libcbor (输入设备库)"

# --- L. SSH 密钥生成 (dropbear 自带) ---
sed -i 's/^CONFIG_PACKAGE_openssh-keygen=y/# CONFIG_PACKAGE_openssh-keygen is not set/' .config
echo "  移除: openssh-keygen (dropbear 已提供)"

# --- M. kvc 配置库 (kvcedit 已移除) ---
sed -i 's/^CONFIG_PACKAGE_libkvcutil=y/# CONFIG_PACKAGE_libkvcutil is not set/' .config
echo "  移除: libkvcutil (kvcedit 配套)"

# --- N. DNS 解析工具 (dnsmasq 已提供) ---
sed -i 's/^CONFIG_PACKAGE_resolveip=y/# CONFIG_PACKAGE_resolveip is not set/' .config
echo "  移除: resolveip (dnsmasq 已提供)"

# --- O. zram 内存压缩 (2GB 内存足够) ---
sed -i 's/^CONFIG_PACKAGE_zram-swap=y/# CONFIG_PACKAGE_zram-swap is not set/' .config
sed -i 's/^CONFIG_PACKAGE_kmod-zram=y/# CONFIG_PACKAGE_kmod-zram is not set/' .config
sed -i 's/^CONFIG_PACKAGE_kmod-lib-lzo=y/# CONFIG_PACKAGE_kmod-lib-lzo is not set/' .config
echo "  移除: zram-swap, kmod-zram, kmod-lib-lzo (2GB 内存不需要)"

echo "  精简完成"

# ============================================================
# 5. 添加 daed 内核选项 (eBPF 支持)
# ============================================================
echo ""
echo "--- 1.5 添加 daed 内核选项 ---"
cat >> .config << 'EOF'

# ===== daed 内核选项 (eBPF 支持) =====
CONFIG_KERNEL_DEBUG_INFO=y
# CONFIG_KERNEL_DEBUG_INFO_REDUCED is not set
CONFIG_KERNEL_DEBUG_INFO_BTF=y
CONFIG_KERNEL_BPF_EVENTS=y
CONFIG_XDP_SOCKETS=y
CONFIG_BPF_TOOLCHAIN=y
CONFIG_BPF_TOOLCHAIN_HOST=y
EOF
echo "  daed 内核选项已添加"

# ============================================================
# 6. 添加 daed 代理工具
# ============================================================
echo ""
echo "--- 1.6 添加 daed ---"
cat >> .config << 'EOF'

# ===== daed 代理工具 (替代 ssr-plus) =====
CONFIG_PACKAGE_daed=y
CONFIG_PACKAGE_luci-app-daed=y
EOF
echo "  daed 已添加"

# ============================================================
# 7. 添加 EasyTier 组网工具
# ============================================================
echo ""
echo "--- 1.7 添加 EasyTier ---"
cat >> .config << 'EOF'

# ===== EasyTier 组网工具 =====
CONFIG_PACKAGE_easytier=y
CONFIG_EASYTIER_INCLUDE_WEBCONSOLE=y
CONFIG_PACKAGE_luci-app-easytier=y
EOF
echo "  EasyTier 已添加"

# ============================================================
# 8. 添加 ddns-go (LuCI 界面, 主程序在 files/)
# ============================================================
echo ""
echo "--- 1.8 添加 ddns-go ---"
cat >> .config << 'EOF'

# ===== ddns-go 动态域名 =====
# 主程序二进制在 files/usr/bin/ddns-go (diy-part1.sh 下载)
# 这里只启用 LuCI 管理界面
CONFIG_PACKAGE_luci-app-ddns-go=y
EOF
echo "  ddns-go 已添加"

# ============================================================
# 9. 添加文件共享 (Samba + CIFS 挂载)
# ============================================================
echo ""
echo "--- 1.9 添加文件共享 ---"
cat >> .config << 'EOF'

# ===== Samba 网络共享 (共享到局域网) =====
CONFIG_PACKAGE_samba4-server=y
CONFIG_PACKAGE_luci-app-samba4=y
CONFIG_PACKAGE_wsdd2=y

# ===== CIFS 客户端 (挂载远程 SMB) =====
CONFIG_PACKAGE_kmod-fs-cifs=y
CONFIG_PACKAGE_cifsmount=y

# ===== NLS 字符集 (CIFS 需要, 中文文件名不乱码) =====
CONFIG_PACKAGE_kmod-nls-base=y
CONFIG_PACKAGE_kmod-nls-utf8=y
CONFIG_PACKAGE_kmod-nls-cp437=y
CONFIG_PACKAGE_kmod-nls-iso8859-1=y
EOF
echo "  文件共享已添加 (samba4 + cifs)"

# ============================================================
# 10. 添加流量统计 (vnstat2 + nlbwmon, 替代 wrtbwmon)
# ============================================================
echo ""
echo "--- 1.10 添加流量统计 ---"
cat >> .config << 'EOF'

# ===== vnstat2: WAN 口精确流量统计 (按接口/月/日/小时) =====
CONFIG_PACKAGE_vnstat2=y
CONFIG_PACKAGE_vnstat2-image=y
CONFIG_PACKAGE_luci-app-vnstat2=y

# ===== nlbwmon: 内网各设备流量统计 (基于 conntrack) =====
CONFIG_PACKAGE_nlbwmon=y
CONFIG_PACKAGE_luci-app-nlbwmon=y
EOF
echo "  流量统计已添加 (vnstat2 + nlbwmon)"

# ============================================================
# 11. 添加 luci-theme-argon 主题
# ============================================================
echo ""
echo "--- 1.11 添加 argon 主题 ---"
cat >> .config << 'EOF'

# ===== Argon 主题 (替代 bootstrap-mod) =====
CONFIG_PACKAGE_luci-theme-argon=y
CONFIG_PACKAGE_luci-app-argon-config=y
EOF
echo "  argon 主题已添加"

# ============================================================
# 12. 设置 rootfs 分区大小
# ============================================================
echo ""
echo "--- 1.12 设置 rootfs 分区大小 ---"
# 506.5MB UBI = kernel(~6MB) + rootfs(100MB) + rootfs_data(~400MB)
# 固件实际 ~61MB, rootfs 设 100MB 留余量, 剩余给 rootfs_data 装插件
echo 'CONFIG_TARGET_ROOTFS_PARTSIZE=100' >> .config
echo "  rootfs: 100MB, rootfs_data: ~400MB"

# ============================================================
# 13. 运行 make defconfig 解析依赖
# ============================================================
echo ""
echo "--- 1.13 运行 make defconfig ---"
make defconfig
echo "  配置解析完成"

# ============================================================
# 14. 验证关键配置
# ============================================================
echo ""
echo "============================================================"
echo "  关键配置验证"
echo "============================================================"

echo ""
echo "[目标设备]"
grep "CONFIG_TARGET_DEVICE.*netcore" .config || echo "  (未找到!)"

echo ""
echo "[代理工具 daed]"
grep -E "CONFIG_PACKAGE_daed=y|CONFIG_PACKAGE_luci-app-daed=y" .config || echo "  (未找到!)"
grep -E "CONFIG_KERNEL.*BPF|CONFIG_KERNEL.*BTF|CONFIG_XDP|CONFIG_BPF_TOOLCHAIN" .config | head -3

echo ""
echo "[组网 EasyTier]"
grep -E "CONFIG_PACKAGE_easytier=y|CONFIG_PACKAGE_luci-app-easytier=y" .config || echo "  (未找到!)"

echo ""
echo "[DDNS]"
grep "CONFIG_PACKAGE_luci-app-ddns-go=y" .config || echo "  (未找到!)"
ls -lh files/usr/bin/ddns-go 2>/dev/null && echo "  二进制: OK" || echo "  二进制: 缺失!"

echo ""
echo "[文件共享]"
grep "CONFIG_PACKAGE_samba4-server=y" .config || echo "  samba4: 缺失!"
grep "CONFIG_PACKAGE_kmod-fs-cifs=y" .config || echo "  cifs: 缺失!"

echo ""
echo "[流量统计]"
grep "CONFIG_PACKAGE_luci-app-vnstat2=y" .config || echo "  vnstat2: 缺失!"
grep "CONFIG_PACKAGE_luci-app-nlbwmon=y" .config || echo "  nlbwmon: 缺失!"

echo ""
echo "[主题]"
grep "CONFIG_PACKAGE_luci-theme-argon=y" .config || echo "  argon: 缺失!"

echo ""
echo "[核心保留项]"
for pkg in kmod-mt_wifi kmod-mediatek_hnat luci-app-turboacc-mtk luci-app-mtwifi-cfg kmod-tun kmod-tcp-bbr kmod-usb-storage kmod-fs-vfat kmod-fs-ext4 block-mount; do
    cnt=$(grep -c "CONFIG_PACKAGE_${pkg}" .config 2>/dev/null || echo 0)
    if [ "$cnt" -gt 0 ]; then
        echo "  $pkg: OK"
    else
        echo "  $pkg: 缺失!"
    fi
done

echo ""
echo "[已移除项]"
for pkg in luci-app-ssr-plus htop tcpdump wrtbwmon ebtables zram-swap blockd kvcedit; do
    if grep -q "CONFIG_PACKAGE_${pkg} is not set" .config; then
        echo "  $pkg: 已移除"
    else
        echo "  $pkg: 未处理"
    fi
done

echo ""
echo "[分区大小]"
grep "CONFIG_TARGET_ROOTFS_PARTSIZE" .config || echo "  (使用默认值)"

echo ""
echo "============================================================"
echo "  DIY Part 2 完成!"
echo "  精简: ssr-plus/wrtbwmon/bootstrap-mod/调试工具/IPv6/zram 等 ~37 个包"
echo "  内置: daed, EasyTier, ddns-go, samba4, cifs, vnstat2, nlbwmon, argon"
echo "  保留: WiFi/拨号/加速/防火墙/USB存储/基础库全保留"
echo "============================================================"
