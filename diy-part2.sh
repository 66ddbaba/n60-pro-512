#!/bin/bash
# ============================================================================
# DIY 脚本 Part 2 - 配置文件生成 (在 feeds 安装之后执行)
# 功能:
#   1. 基于源码自带的 mt7986-ax6000.config 创建 .config
#   2. 禁用其他设备, 只保留 N60 Pro
#   3. 精简: 只移除社区公认无用的插件/工具, 保留所有核心功能
#   4. 添加 daed 内核选项 (BPF/BTF/XDP 支持)
#   5. 添加 daed、EasyTier、luci-theme-argon
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

# ------------------------------------------------------------
# 4. 精简固件: 只移除社区公认无用的插件和工具
#    原则: 保留所有核心路由功能、WiFi、拨号、防火墙
#         保留基础库和常用内核模块, 确保日后 opkg 不缺依赖
# ------------------------------------------------------------
echo ""
echo "--- 1.4 精简固件 (只移除无用插件/工具) ---"

# --- 移除: 代理工具 ssr-plus (用 daed 替代) ---
sed -i 's/^CONFIG_PACKAGE_luci-app-ssr-plus=y/# CONFIG_PACKAGE_luci-app-ssr-plus is not set/' .config
sed -i 's/^CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_NONE_V2RAY=y/# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_NONE_V2RAY is not set/' .config
sed -i 's/^CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_NONE_Client=y/# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_NONE_Client is not set/' .config
sed -i 's/^CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_NONE_Server=y/# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_NONE_Server is not set/' .config
echo "  移除: ssr-plus (用 daed 替代)"

# --- 移除: 调试工具 (日后可 opkg install 按需安装) ---
sed -i 's/^CONFIG_PACKAGE_htop=y/# CONFIG_PACKAGE_htop is not set/' .config
sed -i 's/^CONFIG_PACKAGE_nano=y/# CONFIG_PACKAGE_nano is not set/' .config
sed -i 's/^CONFIG_PACKAGE_kvcedit=y/# CONFIG_PACKAGE_kvcedit is not set/' .config
sed -i 's/^CONFIG_PACKAGE_tcpdump=y/# CONFIG_PACKAGE_tcpdump is not set/' .config
sed -i 's/^CONFIG_PACKAGE_libpcap=y/# CONFIG_PACKAGE_libpcap is not set/' .config
echo "  移除: htop, nano, kvcedit, tcpdump (调试工具, 日后可装)"

# --- 移除: 带宽监控 (非核心, 日后可装) ---
sed -i 's/^CONFIG_PACKAGE_luci-app-wrtbwmon=y/# CONFIG_PACKAGE_luci-app-wrtbwmon is not set/' .config
echo "  移除: luci-app-wrtbwmon (带宽监控, 日后可装)"

# --- 移除: N60 Pro 不需要的 LED 驱动 ---
sed -i 's/^CONFIG_PACKAGE_kmod-leds-ws2812b=y/# CONFIG_PACKAGE_kmod-leds-ws2812b is not set/' .config
echo "  移除: kmod-leds-ws2812b (N60 Pro 不需要)"

# --- 移除: 桥接防火墙 (家庭主路由很少用) ---
sed -i 's/^CONFIG_PACKAGE_kmod-ebtables=y/# CONFIG_PACKAGE_kmod-ebtables is not set/' .config
sed -i 's/^CONFIG_PACKAGE_kmod-ebtables-ipv4=y/# CONFIG_PACKAGE_kmod-ebtables-ipv4 is not set/' .config
sed -i 's/^CONFIG_PACKAGE_kmod-ebtables-ipv6=y/# CONFIG_PACKAGE_kmod-ebtables-ipv6 is not set/' .config
sed -i 's/^CONFIG_PACKAGE_ebtables=y/# CONFIG_PACKAGE_ebtables is not set/' .config
echo "  移除: kmod-ebtables (桥接防火墙, 家庭主路由很少用)"

# --- 移除: 极少使用的 iptables 匹配模块 ---
sed -i 's/^CONFIG_PACKAGE_kmod-ipt-filter=y/# CONFIG_PACKAGE_kmod-ipt-filter is not set/' .config
sed -i 's/^CONFIG_PACKAGE_kmod-ipt-tee=y/# CONFIG_PACKAGE_kmod-ipt-tee is not set/' .config
sed -i 's/^CONFIG_PACKAGE_kmod-ipt-u32=y/# CONFIG_PACKAGE_kmod-ipt-u32 is not set/' .config
sed -i 's/^CONFIG_PACKAGE_kmod-ipt-ipv4options=y/# CONFIG_PACKAGE_kmod-ipt-ipv4options is not set/' .config
echo "  移除: kmod-ipt-filter/tee/u32/ipv4options (极少使用)"

# --- 移除: 对应的 iptables 命令行工具 ---
sed -i 's/^CONFIG_PACKAGE_iptables-mod-filter=y/# CONFIG_PACKAGE_iptables-mod-filter is not set/' .config
sed -i 's/^CONFIG_PACKAGE_iptables-mod-tee=y/# CONFIG_PACKAGE_iptables-mod-tee is not set/' .config
sed -i 's/^CONFIG_PACKAGE_iptables-mod-u32=y/# CONFIG_PACKAGE_iptables-mod-u32 is not set/' .config
sed -i 's/^CONFIG_PACKAGE_iptables-mod-ipv4options=y/# CONFIG_PACKAGE_iptables-mod-ipv4options is not set/' .config
echo "  移除: 对应 iptables-mod 工具"

# --- 移除: terminfo/libncurses (随 htop/nano 移除后不再需要) ---
sed -i 's/^CONFIG_PACKAGE_terminfo=y/# CONFIG_PACKAGE_terminfo is not set/' .config
sed -i 's/^CONFIG_PACKAGE_libncurses=y/# CONFIG_PACKAGE_libncurses is not set/' .config
echo "  移除: terminfo, libncurses (随调试工具移除)"

# --- 移除: IPv6 相关组件 (用户不需要 IPv6) ---
# 注意: 保留 kmod-ipv6 和 kmod-ip6tables (内核基础, 避免隐性依赖问题)
# 只移除 IPv6 用户态工具和服务, 不动内核协议栈
sed -i 's/^CONFIG_PACKAGE_ip6tables-extra=y/# CONFIG_PACKAGE_ip6tables-extra is not set/' .config
sed -i 's/^CONFIG_PACKAGE_ip6tables-nft=y/# CONFIG_PACKAGE_ip6tables-nft is not set/' .config
sed -i 's/^CONFIG_PACKAGE_kmod-ipt-raw6=y/# CONFIG_PACKAGE_kmod-ipt-raw6 is not set/' .config
sed -i 's/^CONFIG_PACKAGE_odhcp6c=y/# CONFIG_PACKAGE_odhcp6c is not set/' .config
sed -i 's/^CONFIG_PACKAGE_odhcpd-ipv6only=y/# CONFIG_PACKAGE_odhcpd-ipv6only is not set/' .config
sed -i 's/^CONFIG_PACKAGE_luci-proto-ipv6=y/# CONFIG_PACKAGE_luci-proto-ipv6 is not set/' .config
sed -i 's/^CONFIG_PACKAGE_luci-proto-6in4=y/# CONFIG_PACKAGE_luci-proto-6in4 is not set/' .config
echo "  移除: IPv6 用户态工具 (ip6tables-extra/nft, raw6, odhcp6c, odhcpd-ipv6only, luci-proto-ipv6/6in4)"
echo "  保留: kmod-ipv6, kmod-ip6tables (内核基础, 避免隐性依赖)"

# --- 移除: 广告过滤 (非核心, 日后可装) ---
sed -i 's/^CONFIG_PACKAGE_blockd=y/# CONFIG_PACKAGE_blockd is not set/' .config
echo "  移除: blockd (广告过滤, 日后可装)"

# --- 移除: 寄存器/PHY 调试工具 ---
sed -i 's/^CONFIG_PACKAGE_regs=y/# CONFIG_PACKAGE_regs is not set/' .config
sed -i 's/^CONFIG_PACKAGE_mii_mgr=y/# CONFIG_PACKAGE_mii_mgr is not set/' .config
echo "  移除: regs, mii_mgr (寄存器/PHY调试工具)"

# --- 移除: 输入设备库 (路由器不需要键盘鼠标等) ---
sed -i 's/^CONFIG_PACKAGE_libfido2=y/# CONFIG_PACKAGE_libfido2 is not set/' .config
sed -i 's/^CONFIG_PACKAGE_libevdev=y/# CONFIG_PACKAGE_libevdev is not set/' .config
sed -i 's/^CONFIG_PACKAGE_libudev-zero=y/# CONFIG_PACKAGE_libudev-zero is not set/' .config
echo "  移除: libfido2, libevdev, libudev-zero (输入设备库, 路由器不需要)"

# --- 移除: SSH 密钥生成 (dropbear 自带, openssh-keygen 多余) ---
sed -i 's/^CONFIG_PACKAGE_openssh-keygen=y/# CONFIG_PACKAGE_openssh-keygen is not set/' .config
echo "  移除: openssh-keygen (dropbear 已提供 SSH)"

# --- 移除: automount (远程网络文件系统按需挂载, 用户需要挂载远程SMB, 保留) ---
# 注意: kmod-fs-autofs4 保留, 用于按需挂载远程网络文件系统
# echo "  不移除: kmod-fs-autofs4 (用于远程文件按需挂载)"

# --- 移除: kvc 配置库 (kvcedit 已移除, 不再需要) ---
sed -i 's/^CONFIG_PACKAGE_libkvcutil=y/# CONFIG_PACKAGE_libkvcutil is not set/' .config
echo "  移除: libkvcutil (kvcedit 配套库)"

# --- 移除: resolveip (DNS解析工具, dnsmasq已提供) ---
sed -i 's/^CONFIG_PACKAGE_resolveip=y/# CONFIG_PACKAGE_resolveip is not set/' .config
echo "  移除: resolveip (DNS解析工具)"

# --- 移除: zram-swap (2GB 内存足够, 不需要内存压缩) ---
sed -i 's/^CONFIG_PACKAGE_zram-swap=y/# CONFIG_PACKAGE_zram-swap is not set/' .config
sed -i 's/^CONFIG_PACKAGE_kmod-zram=y/# CONFIG_PACKAGE_kmod-zram is not set/' .config
echo "  移除: zram-swap (2GB内存足够, 不需要内存压缩)"

# --- 移除: liblzo (zram 移除后不再需要) ---
sed -i 's/^CONFIG_PACKAGE_kmod-lib-lzo=y/# CONFIG_PACKAGE_kmod-lib-lzo is not set/' .config
echo "  移除: kmod-lib-lzo (zram 配套压缩库)"

echo "  精简完成"

# ------------------------------------------------------------
# 5. 添加 daed 内核选项 (eBPF 支持)
# ------------------------------------------------------------
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

# ------------------------------------------------------------
# 6. 添加 daed
# ------------------------------------------------------------
echo ""
echo "--- 1.6 添加 daed ---"
cat >> .config << 'EOF'

# ===== daed 代理工具 =====
CONFIG_PACKAGE_daed=y
CONFIG_PACKAGE_luci-app-daed=y
EOF
echo "  daed 已添加"

# ------------------------------------------------------------
# 7. 添加 EasyTier
# ------------------------------------------------------------
echo ""
echo "--- 1.7 添加 EasyTier ---"
cat >> .config << 'EOF'

# ===== EasyTier 组网工具 =====
CONFIG_PACKAGE_easytier=y
CONFIG_EASYTIER_INCLUDE_WEBCONSOLE=y
CONFIG_PACKAGE_luci-app-easytier=y
EOF
echo "  EasyTier 已添加"

# ------------------------------------------------------------
# 8. 添加 ddns-go (主程序 + LuCI 界面)
# ------------------------------------------------------------
echo ""
echo "--- 1.8 添加 ddns-go (主程序+LuCI) ---"
cat >> .config << 'EOF'

# ===== ddns-go 动态域名 =====
# 主程序二进制在 files/usr/bin/ddns-go (diy-part1.sh 下载)
# 这里只启用 LuCI 管理界面
CONFIG_PACKAGE_luci-app-ddns-go=y
EOF
echo "  ddns-go 已添加 (主程序 + LuCI 界面)"

# ------------------------------------------------------------
# 8.5 添加文件共享 (Samba + CIFS 挂载)
# ------------------------------------------------------------
echo ""
echo "--- 1.85 添加文件共享 (Samba + CIFS) ---"
cat >> .config << 'EOF'

# ===== Samba 网络共享 (共享到局域网) =====
CONFIG_PACKAGE_samba4-server=y
CONFIG_PACKAGE_luci-app-samba4=y
CONFIG_PACKAGE_wsdd2=y

# ===== CIFS 客户端 (挂载远程 SMB) =====
CONFIG_PACKAGE_kmod-fs-cifs=y
CONFIG_PACKAGE_cifsmount=y

# ===== NLS 字符集 (CIFS 需要) =====
CONFIG_PACKAGE_kmod-nls-base=y
CONFIG_PACKAGE_kmod-nls-utf8=y
CONFIG_PACKAGE_kmod-nls-cp437=y
CONFIG_PACKAGE_kmod-nls-iso8859-1=y
EOF
echo "  文件共享已添加 (samba4 + cifs)"

# ------------------------------------------------------------
# 9. 添加 luci-theme-argon 主题
# ------------------------------------------------------------
echo ""
echo "--- 1.8 添加 luci-theme-argon 主题 ---"
cat >> .config << 'EOF'

# ===== Argon 主题 =====
CONFIG_PACKAGE_luci-theme-argon=y
CONFIG_PACKAGE_luci-app-argon-config=y
EOF
echo "  argon 主题已添加"

# ------------------------------------------------------------
# 9. 设置 rootfs 分区大小
# ------------------------------------------------------------
echo ""
echo "--- 1.9 设置 rootfs 分区大小 ---"
echo 'CONFIG_TARGET_ROOTFS_PARTSIZE=480' >> .config
echo "  rootfs 分区大小设为 480MB"

# ------------------------------------------------------------
# 10. 运行 make defconfig 解析依赖关系
# ------------------------------------------------------------
echo ""
echo "--- 1.10 运行 make defconfig 解析依赖 ---"
make defconfig
echo "  配置解析完成"

# ------------------------------------------------------------
# 11. 显示关键配置项
# ------------------------------------------------------------
echo ""
echo "============================================================"
echo "  关键配置项验证:"
echo "============================================================"

echo ""
echo "[目标设备]"
grep "CONFIG_TARGET_DEVICE.*netcore" .config || echo "  (未找到 N60 Pro!)"

echo ""
echo "[代理工具]"
grep -E "CONFIG_PACKAGE_daed|CONFIG_PACKAGE_luci-app-daed" .config || echo "  (未找到 daed!)"
grep -E "CONFIG_KERNEL.*BPF|CONFIG_KERNEL.*BTF|CONFIG_XDP|CONFIG_BPF_TOOLCHAIN" .config || echo "  (未找到 BPF 内核选项!)"

echo ""
echo "[EasyTier]"
grep -E "CONFIG_PACKAGE_easytier|CONFIG_PACKAGE_luci-app-easytier" .config || echo "  (未找到 EasyTier!)"

echo ""
echo "[DDNS]"
grep -E "CONFIG_PACKAGE_luci-app-ddns-go=y" .config || echo "  (未找到 luci-app-ddns-go!)"
ls -lh files/usr/bin/ddns-go 2>/dev/null && echo "  ddns-go 二进制已在 files/ 中" || echo "  (警告: ddns-go 二进制不存在!)"

echo ""
echo "[文件共享]"
grep -E "CONFIG_PACKAGE_samba4-server" .config || echo "  (未找到 samba4-server!)"
grep -E "CONFIG_PACKAGE_luci-app-samba4" .config || echo "  (未找到 luci-app-samba4!)"
grep -E "CONFIG_PACKAGE_kmod-fs-cifs" .config || echo "  (未找到 kmod-fs-cifs!)"

echo ""
echo "[主题]"
grep -E "CONFIG_PACKAGE_luci-theme-argon" .config || echo "  (未找到 argon 主题!)"

echo ""
echo "[核心保留项]"
echo -n "  WiFi驱动: "; grep -c "CONFIG_PACKAGE_kmod-mt_wifi" .config 2>/dev/null | xargs -I{} sh -c '[ {} -gt 0 ] && echo "保留" || echo "缺失!"'
echo -n "  硬件NAT:  "; grep -c "CONFIG_PACKAGE_kmod-mediatek_hnat" .config 2>/dev/null | xargs -I{} sh -c '[ {} -gt 0 ] && echo "保留" || echo "缺失!"'
echo -n "  加速:     "; grep -c "CONFIG_PACKAGE_luci-app-turboacc-mtk" .config 2>/dev/null | xargs -I{} sh -c '[ {} -gt 0 ] && echo "保留" || echo "缺失!"'
echo -n "  WiFi配置: "; grep -c "CONFIG_PACKAGE_luci-app-mtwifi-cfg" .config 2>/dev/null | xargs -I{} sh -c '[ {} -gt 0 ] && echo "保留" || echo "缺失!"'
echo -n "  隧道:     "; grep -c "CONFIG_PACKAGE_kmod-tun" .config 2>/dev/null | xargs -I{} sh -c '[ {} -gt 0 ] && echo "保留" || echo "缺失!"'
echo -n "  BBR:      "; grep -c "CONFIG_PACKAGE_kmod-tcp-bbr" .config 2>/dev/null | xargs -I{} sh -c '[ {} -gt 0 ] && echo "保留" || echo "缺失!"'

echo ""
echo "[已移除]"
grep -q "CONFIG_PACKAGE_luci-app-ssr-plus is not set" .config && echo "  ssr-plus: 已移除" || echo "  ssr-plus: 未处理"
grep -q "CONFIG_PACKAGE_htop is not set" .config && echo "  htop: 已移除" || echo "  htop: 未处理"
grep -q "CONFIG_PACKAGE_tcpdump is not set" .config && echo "  tcpdump: 已移除" || echo "  tcpdump: 未处理"

echo ""
echo "[分区大小]"
grep "CONFIG_TARGET_ROOTFS_PARTSIZE" .config || echo "  (使用默认值)"

echo ""
echo "============================================================"
echo "  DIY Part 2 完成! .config 已生成"
echo "  精简策略: 移除无用插件/调试工具/IPv6用户态/zram"
echo "  保留策略: 核心路由/WiFi/拨号/加速/基础库全保留"
echo "  内置插件: daed, EasyTier, ddns-go, samba4, cifs, argon主题"
echo "  其他插件: 日后通过 opkg 按需安装"
echo "============================================================"
