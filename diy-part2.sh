#!/bin/bash
# ============================================================================
#  DIY Part 2 - 生成 .config (feeds 安装之后执行)
#
#  【这个脚本做什么】
#  配置编译选项, 选择/取消软件包, 调整内核参数, 最后用 make defconfig
#  生成合法的最终 .config 配置文件。
#
#  【执行时机】
#  feeds install 之后 → make download 之前
#
#  【配置依据】
#  模板: mt7975-ipailna-high-power.config
#  本脚本只改"我们明确需要改变"的配置:
#    - 增加: 模板默认没有、但我们需要的包
#    - 移除: 模板默认有、但我们不需要的包
#    - 不动: 模板有且我们也需要的 (不重复写 =y)
#
#  为什么要这么做? 让脚本最精简, 改动最小化, 模板升级了也不容易出问题。
# ============================================================================
set -e  # 遇到错误立即退出

echo "============================================================"
echo "  DIY Part 2: 生成 .config"
echo "============================================================"

# ============================================================================
# 1. 基础配置 + 设备选择
# ============================================================================
echo ""
echo "--- 1. 基础配置 ---"

# 加载高功率模板 (社区推荐, WARP v2 + iPA/iLNA 高功率)
cp -f defconfig/mt7975-ipailna-high-power.config .config
echo "  [OK] 模板: mt7975-ipailna-high-power.config"

# 禁用其他设备 (只编译 N60 Pro, 省时间)
# 模板默认启用了 gl-mt6000 / xdr6086 / xdr6088 / ax6000 / rg-x60 / ew-6000gx-pro 等
for dev in glinet_gl-mt6000 jdcloud_re-cp-03 tplink_tl-xdr6086 tplink_tl-xdr6088 \
           xiaomi_redmi-router-ax6000-ubootmod xiaomi_redmi-router-ax6000-stock \
           ruijie_rg-x60-pro ruijie_rg-x60-new ruijie_ew-6000gx-pro; do
    for fmt in mediatek_filogic mediatek_mt7986; do
        sed -i "s/^CONFIG_TARGET_DEVICE_${fmt}_DEVICE_${dev}=y/# CONFIG_TARGET_DEVICE_${fmt}_DEVICE_${dev} is not set/" .config 2>/dev/null || true
        sed -i "s/^CONFIG_TARGET_DEVICE_PACKAGES_${fmt}_DEVICE_${dev}=/# CONFIG_TARGET_DEVICE_PACKAGES_${fmt}_DEVICE_${dev} is not set/" .config 2>/dev/null || true
    done
done

# 启用 N60 Pro (两种格式都加, 确保生效)
cat >> .config << 'EOF'
CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_netcore_n60-pro=y
CONFIG_TARGET_DEVICE_PACKAGES_mediatek_filogic_DEVICE_netcore_n60-pro=""
CONFIG_TARGET_DEVICE_mediatek_mt7986_DEVICE_netcore_n60-pro=y
CONFIG_TARGET_DEVICE_PACKAGES_mediatek_mt7986_DEVICE_netcore_n60-pro=""
EOF
echo "  [OK] 仅启用 N60 Pro 设备"

# ============================================================================
# 2. daed 内核选项 (eBPF 支持)
# ============================================================================
# daed 是 eBPF 透明代理, 需要内核支持 BPF + BTF + cgroup。
# 模板默认配置不全, 这里手动补全。
#
# 关键配置:
#   DEVEL=y                 → 开发模式 (BPF 工具链选项可见的前提)
#   DEBUG_INFO=y            → 完整调试信息 (BTF 的基础)
#   DEBUG_INFO_BTF=y        → BTF 类型信息 (daed 运行必需)
#   CGROUPS / CGROUP_BPF    → cgroup + BPF 支持
#   BPF_EVENTS / XDP_SOCKETS → BPF 事件 + XDP socket
#   BPF_TOOLCHAIN_HOST=y    → 用主机 LLVM 编译 BPF 程序
#   kmod-xdp-sockets-diag   → daed 运行时依赖的内核模块
#
# 代价: 内核增加 ~2-3MB (BTF 信息), daed 必需。
# ============================================================================
echo ""
echo "--- 2. daed eBPF 内核选项 ---"
cat >> .config << 'EOF'
# ---- 基础: 开发模式 (BPF 选项可见的前提) ----
CONFIG_DEVEL=y

# ---- 内核: 调试信息 + BTF ----
CONFIG_KERNEL_DEBUG_INFO=y
# 不能精简调试信息 (精简了 BTF 不完整, dae 加载失败)
# CONFIG_KERNEL_DEBUG_INFO_REDUCED is not set
CONFIG_KERNEL_DEBUG_INFO_BTF=y

# ---- 内核: cgroup + BPF ----
CONFIG_KERNEL_CGROUPS=y
CONFIG_KERNEL_CGROUP_BPF=y
CONFIG_KERNEL_BPF_EVENTS=y
CONFIG_XDP_SOCKETS=y

# ---- BPF 工具链: 用主机 LLVM ----
CONFIG_BPF_TOOLCHAIN_HOST=y

# ---- 内核模块: daed 运行时依赖 ----
CONFIG_PACKAGE_kmod-xdp-sockets-diag=y
EOF
echo "  [OK] DEVEL + BTF + cgroup + BPF + XDP + LLVM (daed 必需)"

# ============================================================================
# 3. 第一次 make defconfig (基础配置)
# ============================================================================
# 分两次 defconfig 的原因:
#   第一次: 先稳定内核配置 (BPF/BTF 等), 让所有内核符号解析完成
#   第二次: 加完软件包后再跑一次, 补齐依赖
# 这样 daed 这种依赖内核配置的包不会被踢掉。
# ============================================================================
echo ""
echo "--- 3. 第一次 defconfig (内核 + 基础配置) ---"
make defconfig
echo "  [OK] 第一次 defconfig 完成"

# ============================================================================
# 4. 新增软件包 (模板默认没有、我们需要的)
# ============================================================================
# 【原则】
#  模板默认已经有的包, 这里不重复写 =y (避免冗余)
#  只写模板默认没有、但我们明确需要的。
#
#  注意: 放在第一次 defconfig 之后, 确保内核配置已就绪,
#       依赖内核功能的包 (如 daed) 不会被踢掉。
# ============================================================================
echo ""
echo "--- 4. 新增软件包 ---"

cat >> .config << 'EOF'

# ---- 4.1 代理: daed (eBPF 透明代理) ----
# 模板默认: 没有 (但 packages feed 里有, 只是默认没选)
# daed: 主程序 (带 dashboard 的 dae 版本)
# luci-app-daed: LuCI 管理界面
# 依赖: v2ray-geodata (geoip + geosite 数据包), 第二次 defconfig 会自动补齐
CONFIG_PACKAGE_daed=y
CONFIG_PACKAGE_luci-app-daed=y

# ---- 4.2 组网: EasyTier (虚拟局域网) ----
# 模板默认: 没有
# easytier: 主程序 (feeds 里有, 但默认不选)
# luci-app-easytier: LuCI 界面 (我们在 diy-part1.sh 克隆的)
CONFIG_PACKAGE_easytier=y
CONFIG_PACKAGE_luci-app-easytier=y

# ---- 4.3 DDNS: ddns-go (动态域名) ----
# 模板默认: 没有 (但 packages + luci feed 里都有, 只是默认没选)
# ddns-go: 主程序 (支持 IPv4/IPv6 动态域名解析)
# luci-app-ddns-go: LuCI 管理界面
CONFIG_PACKAGE_ddns-go=y
CONFIG_PACKAGE_luci-app-ddns-go=y

# ---- 4.4 文件共享: Samba4 + CIFS 挂载 + wsdd2 ----
# 模板默认: 都没有 (模板只有 vfat, 没有 samba/cifs)
# samba4-server: Samba 4 服务端 (局域网共享 U 盘/硬盘)
# luci-app-samba4: LuCI 管理界面
CONFIG_PACKAGE_samba4-server=y
CONFIG_PACKAGE_luci-app-samba4=y

# kmod-fs-cifs: CIFS 客户端内核模块 (挂载远程 SMB 共享必须)
# cifsmount: CIFS 挂载工具 (mount.cifs 命令, cifs-utils 源码包编译出来)
# luci-app-cifs-mount: LuCI 挂载管理界面 (配置存在 UCI 里, 开机自动挂载)
#   配合 diy-part1.sh 里的 cifs-reconnect 脚本, 断线后自动重连
#
# 【注意: 包名是 cifsmount, 不是 cifs-utils!】
#   cifs-utils 是源码目录的名字, 编译出来的二进制包叫 cifsmount。
#   写 CONFIG_PACKAGE_cifs-utils=y 是无效的。
CONFIG_PACKAGE_kmod-fs-cifs=y
CONFIG_PACKAGE_cifsmount=y
CONFIG_PACKAGE_luci-app-cifs-mount=y

# wsdd2: Windows 网络发现 (WSD) 守护进程
#   没有的话 Windows 网上邻居看不到路由器
CONFIG_PACKAGE_wsdd2=y

# ---- 4.5 流量统计: vnstat2 + nlbwmon ----
# 模板默认: 没有 (模板带 wrtbwmon, 我们后面会删掉)
# vnstat2: 第二代流量统计 (比 v1 好)
# vnstat2-image: 生成图表 (LuCI 界面需要)
# luci-app-vnstat2: LuCI 界面
CONFIG_PACKAGE_vnstat2=y
CONFIG_PACKAGE_vnstat2-image=y
CONFIG_PACKAGE_luci-app-vnstat2=y

# nlbwmon: 基于 conntrack 的设备级流量统计
# luci-app-nlbwmon: LuCI 界面
CONFIG_PACKAGE_nlbwmon=y
CONFIG_PACKAGE_luci-app-nlbwmon=y

# ---- 4.6 主题 + 网页终端 ----
# 模板默认: 没有 (模板带 bootstrap-mod, 我们后面会删掉)
# argon: 现代风格主题
CONFIG_PACKAGE_luci-theme-argon=y

# ttyd: 网页终端 (浏览器里直接用命令行)
# luci-app-ttyd: LuCI 界面
CONFIG_PACKAGE_ttyd=y
CONFIG_PACKAGE_luci-app-ttyd=y
# ---- 4.11 确保 MTK WiFi 配置依赖 (防止精简误删) ----
# mtwifi-cfg → datconf-lua → libkvcutil, 这条依赖链有时 defconfig 拉不全
# 显式写 =y 确保都选上
CONFIG_PACKAGE_libkvcutil=y
CONFIG_PACKAGE_datconf-lua=y
CONFIG_PACKAGE_kmod-inet-diag=y

EOF
echo "  [OK] 新增: daed / ddns-go / EasyTier / Samba / CIFS(cifsmount) / wsdd2 / vnstat2 / nlbwmon / argon / ttyd + MTK依赖保障"

# ============================================================================
# 5. rootfs 分区大小
# ============================================================================
# 模板默认 rootfs 是按 128MB 布局设的, 我们 506.5MB 布局可以设大一点。
# 设 80MB: 留 5-15MB 余量, 剩下 ~420MB 给 overlay (装插件空间非常充足)
# ============================================================================
echo ""
echo "--- 5. rootfs 分区大小 ---"
echo 'CONFIG_TARGET_ROOTFS_PARTSIZE=80' >> .config
echo "  [OK] 80MB (overlay ~420MB 可用)"

# ============================================================================
# 6. 第二次 make defconfig (补齐软件包依赖)
# ============================================================================
# 加完所有软件包后再跑一次 defconfig, 自动补齐所有依赖。
# 这次内核配置已经就绪, 不会把依赖内核的包踢掉了。
# ============================================================================
echo ""
echo "--- 6. 第二次 defconfig (补齐软件包依赖) ---"
make defconfig
echo "  [OK] 第二次 defconfig 完成"

# ============================================================================
# 7. 精简 (prune_packages)
# ============================================================================
# 【为什么在第二次 defconfig 之后才精简?】
# make defconfig 会自动补齐所有依赖。如果先删再 defconfig,
# 某些包可能作为依赖被重新 =y, 白删了。
# 在 defconfig 之后删, 确保我们明确要删的不会被带回来。
# ============================================================================

# remove_pkg: 取消一个包 (=y → is not set)
REMOVE_COUNT=0
remove_pkg() {
    if grep -q "^CONFIG_PACKAGE_${1}=y" .config 2>/dev/null; then
        sed -i "s/^CONFIG_PACKAGE_${1}=y/# CONFIG_PACKAGE_${1} is not set/" .config
        REMOVE_COUNT=$((REMOVE_COUNT + 1))
    fi
    return 0
}

echo ""
echo "--- 7. 精简固件 (只删模板/defconfig 默认有的) ---"

# ---- A. 被新插件替代的 (模板默认有, 我们用更好的替代了) ----
# wrtbwmon → vnstat2 + nlbwmon (功能更强, 更准)
remove_pkg "luci-app-wrtbwmon"
remove_pkg "luci-i18n-wrtbwmon-zh-cn"
echo "  [A] 被替代: wrtbwmon (+中文翻译)"

# 【ssr-plus 和 bootstrap-mod 呢?】
# 模板里只是有它们的子选项配置 (如 INCLUDE_xxx),
# 但主包本身默认就不是 =y, 所以不需要 remove_pkg。

# ---- B. 调试工具 (模板默认有, 普通用户用不到) ----
# htop / nano → busybox 的 top/vi 够用, 需要时 opkg 装
# tcpdump / libpcap → 抓包工具, 很少用
# regs / mii_mgr → 寄存器/MII 调试, 普通用户不用
# kvcedit / datconf → KVC 配置工具 (主程序, 普通用户不用)
#
# 【保留的】
#   libncurses + terminfo: 才几十KB, 后期装 htop/nano 需要
#   libkvcutil: datconf-lua 依赖, mtwifi-cfg 需要 (不能删)
#   datconf-lua: mtwifi-cfg 依赖 (不能删)
#   kmod-inet-diag: turboacc-mtk 依赖 (不能删)
for pkg in htop nano tcpdump libpcap regs mii_mgr \
           kvcedit datconf; do
    remove_pkg "$pkg"
done
echo "  [B] 调试工具 (htop/nano/tcpdump/regs/mii_mgr/kvcedit/datconf)"

# ---- C. 冷门 iptables 模块 (模板默认有, 家用用不到) ----
# filter / tee / u32 / ipv4options: 非常冷门的匹配模块
# compat-xtables: 旧版 iptables 兼容层, 6.6 内核用 nftables 不需要
# ipmark: 数据包标记, 很少用 (依赖 compat-xtables, 要删一起删)
for mod in filter tee u32 ipv4options ipmark; do
    remove_pkg "kmod-ipt-${mod}"
    remove_pkg "iptables-mod-${mod}"
done
remove_pkg "kmod-ipt-compat-xtables"
echo "  [C] 冷门 iptables 模块 (filter/tee/u32/ipv4options/compat/ipmark)"

# ---- D. IPv6 用户态工具 (内核保留) ----
# 你明确说不用 IPv6, 尽量精简用户态工具
# ip6tables 系列: IPv6 防火墙工具
# kmod-ipt-raw6: IPv6 raw 表
# odhcp6c: DHCPv6 客户端
# luci-proto-ipv6 / 6in4: LuCI IPv6 协议界面
# odhcpd-ipv6only: IPv6 守护进程
#
# 【保留的】
#   kmod-ipt-nat6: turboacc-mtk (硬件加速) 依赖, 不能删
for pkg in ip6tables ip6tables-extra ip6tables-nft \
           kmod-ip6tables kmod-ip6tables-extra kmod-ipt-raw6 \
           odhcp6c odhcpd-ipv6only luci-proto-ipv6 luci-proto-6in4; do
    remove_pkg "$pkg"
done
echo "  [D] IPv6 用户态工具 (内核保留, 留 kmod-ipt-nat6 给 turboacc)"

# ---- E. zram 内存压缩 (模板默认有, 2GB 内存不需要) ----
# zram-swap: 用户态脚本
# kmod-zram: 内核模块
# kmod-lib-lzo: LZO 压缩库
for pkg in zram-swap kmod-zram kmod-lib-lzo; do
    remove_pkg "$pkg"
done
echo "  [E] zram 内存压缩 (2GB 不需要)"

# ---- F. 其他 (模板默认有, 但我们不需要) ----
# openssh-keygen: SSH 密钥生成 (dropbear 够用)
# openssh-sftp-server: SFTP 服务器 (scp 够用)
# resolveip: DNS 解析工具 (busybox nslookup 够用)
# kmod-ata-core: SATA 驱动 (N60 Pro 没有 SATA)
# kmod-leds-ws2812b: WS2812B 彩灯驱动 (N60 Pro 没有)
# kmod-fs-btrfs: Btrfs 文件系统 (N60 Pro 用 squashfs, 不需要)
# libfido2 / libcbor: FIDO 安全密钥 (路由器不需要)
# libevdev: 输入设备库 (路由器不需要键盘鼠标)
# usbutils: lsusb 等 USB 诊断工具 (依赖 libevdev, 一起删)
# haveged: 随机数熵生成器 (6.6 内核有更好的随机源, 不需要)
#
# 【保留的】
#   blockd: U 盘自动挂载, 几十KB, 留着方便
#   libudev-zero: usbutils 依赖但我们删了 usbutils, 它也跟着没了
for pkg in openssh-keygen openssh-sftp-server resolveip \
           kmod-ata-core kmod-leds-ws2812b kmod-fs-btrfs \
           libfido2 libcbor libevdev usbutils \
           haveged; do
    remove_pkg "$pkg"
done
echo "  [F] 其他 (openssh/btrfs/fido2/evdev/usbutils/ata/ws2812b/haveged)"

echo "  合计移除: ${REMOVE_COUNT} 个包"

# ============================================================================
# 8. 验证 (关键包缺失直接退出, 不白编译)
# ============================================================================
# 【为什么要验证?】
# 编译一次要 2-3 小时, 如果关键包没选上, 白等半天。
# 验证失败直接 exit 1, 让工作流提前失败, 省时间。
#
# 【两类检查】
#   1. 必需包 (必须 =y, 缺了直接退出)
#   2. 核心功能包 (确保没被误删, 缺了直接退出)
#   3. 精简包 (只做信息展示, 不强制 - 本来就没有的也算正常)
# ============================================================================
echo ""
echo "=== 验证 ==="

MISSING=0

# require_pkg: 检查包是否 =y, 缺失就计数
require_pkg() {
    if grep -q "CONFIG_PACKAGE_${1}=y" .config 2>/dev/null; then
        echo "  [OK] $1"
    else
        echo "  [缺失] $1"
        MISSING=$((MISSING + 1))
    fi
}

echo ""
echo "[必需包 (缺了直接退出)]"
for p in daed luci-app-daed ddns-go luci-app-ddns-go \
         easytier luci-app-easytier \
         samba4-server luci-app-samba4 \
         kmod-fs-cifs cifsmount luci-app-cifs-mount wsdd2 \
         vnstat2 luci-app-vnstat2 nlbwmon luci-app-nlbwmon \
         luci-theme-argon ttyd luci-app-ttyd; do
    require_pkg "$p"
done

echo ""
echo "[核心功能 (确保没被误删)]"
for p in kmod-mt_wifi kmod-mediatek_hnat kmod-tun kmod-tcp-bbr \
         kmod-usb-storage kmod-fs-ext4 block-mount ppp ppp-mod-pppoe \
         kmod-nls-base kmod-nls-utf8 libopenssl libncurses; do
    require_pkg "$p"
done

# 有缺失就直接退出, 不继续编译
if [ "$MISSING" -gt 0 ]; then
    echo ""
    echo "=============================================="
    echo "  [错误] ${MISSING} 个关键包缺失!"
    echo "  已终止, 请检查配置后重试。"
    echo "=============================================="
    exit 1
fi

# 精简包只做信息展示, 不强制退出 (本来就没有的也算正常)
check_removed() {
    if grep -q "CONFIG_PACKAGE_${1} is not set" .config 2>/dev/null; then
        echo "  [OK] ${1}: 已移除"
    else
        echo "  [--] ${1}: 不在配置中 (默认就没有)"
    fi
}

echo ""
echo "[精简的包 (信息展示)]"
for p in luci-app-wrtbwmon htop nano zram-swap odhcp6c; do
    check_removed "$p"
done

echo ""
echo "[分区大小]"
grep "CONFIG_TARGET_ROOTFS_PARTSIZE" .config

echo ""
echo "  [全部通过] 关键包验证完成"

# ============================================================================
# 完成
# ============================================================================
echo ""
echo "============================================================"
echo "  DIY Part 2 完成!"
echo "============================================================"
echo "  新增: daed / EasyTier / ddns-go"
echo "        samba4 / CIFS挂载 / wsdd2"
echo "        vnstat2 / nlbwmon"
echo "        argon / ttyd"
echo "  精简: 移除 ${REMOVE_COUNT} 个包"
echo "  CPU频率: mtk-cpufreq + cpuinfo 脚本 (不靠 autocore 包)"
echo "  rootfs: 80MB (overlay ~420MB)"
echo "============================================================"
