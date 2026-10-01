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
#  为什么在 feeds install 之后? 因为 feeds install 之后所有软件包才被注册,
#  这时候才能选/取消它们。
#
#  【.config 是什么】
#  .config 是 Linux/OpenWrt 的内核级配置文件, 每行一个配置项:
#    CONFIG_PACKAGE_xxx=y    → 编入固件 (build-in)
#    CONFIG_PACKAGE_xxx=m    → 编译成模块 (.ipk), 不进固件
#    # CONFIG_PACKAGE_xxx is not set → 不编译
#
#  【精简原则】
#  1. 核心功能绝不碰: WiFi / 拨号 / 防火墙 / 基础库 / 加密模块
#  2. 被新插件替代的旧插件 → 移除
#  3. 调试/诊断工具 → 移除 (需要时 opkg 装)
#  4. 不用的硬件驱动 → 移除
#  5. 不影响核心功能的可选模块 → 移除
#  6. 后期拓展需要的依赖 → 保留 (比如文件系统、网络协议)
# ============================================================================
set -e  # 遇到错误立即退出

echo "============================================================"
echo "  DIY Part 2: 生成 .config"
echo "============================================================"

# ============================================================================
# 1. 基础配置 + 设备选择
# ============================================================================
# 【为什么用 mt7975-ipailna-high-power.config?】
# 这是社区 (237 等大佬) 推荐的高功率配置模板, 特点:
#   - 使用 WARP v2 固件 (WiFi 性能更好)
#   - 启用 iPA/iLNA (集成功率放大器/低噪声放大器)
#   - WiFi 功率可以跑到 25dBm (原厂限制较低)
#
# 简单说就是 "让 WiFi 更强" 的配置模板。
#
# 【为什么禁用其他设备?】
# 编译系统默认会编译所有支持的设备, 但我们只需要 N60 Pro。
# 禁用其他设备可以节省编译时间 (少编译很多设备专用的包)。
# ============================================================================
echo ""
echo "--- 1. 基础配置 ---"

# 加载高功率模板
cp -f defconfig/mt7975-ipailna-high-power.config .config
echo "  [OK] 模板: mt7975-ipailna-high-power.config"

# 禁用其他设备 (减少编译时间)
# 支持 mediatek_filogic 和 mediatek_mt7986 两种命名格式
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
# 2. 精简固件 (移除不必要的包)
# ============================================================================
# 【怎么判断能不能删?】
#  判断标准:
#    1. 是不是核心功能? (WiFi/拨号/防火墙/基础库 → 不能删)
#    2. 有没有替代品? (有更好的新插件 → 删旧的)
#    3. 普通用户用不用得到? (调试工具 → 删, 需要时再装)
#    4. 硬件有没有? (N60 Pro 没有的设备驱动 → 删)
#    5. 会不会影响后期拓展? (基础库/文件系统 → 尽量留)
#
# 【remove_pkg 函数】
#  从 .config 中取消一个包的选中 (=y → is not set)
#  用 REMOVE_COUNT 计数, 最后显示总共删了多少个。
#  始终 return 0 避免触发 set -e (包不存在不是错误)。
# ============================================================================
echo ""
echo "--- 2. 精简固件 ---"

REMOVE_COUNT=0

remove_pkg() {
    if grep -q "^CONFIG_PACKAGE_${1}=y" .config 2>/dev/null; then
        sed -i "s/^CONFIG_PACKAGE_${1}=y/# CONFIG_PACKAGE_${1} is not set/" .config
        REMOVE_COUNT=$((REMOVE_COUNT + 1))
    fi
    return 0  # 始终返回 0, 包不存在也不算错误
}

# ---- A. 被新插件替代的旧插件 ----
# daed 是 eBPF 实现的代理, 性能比 ssr-plus 好
remove_pkg "luci-app-ssr-plus"
# vnstat2 + nlbwmon 已经覆盖了 wrtbwmon 的功能
remove_pkg "luci-app-wrtbwmon"
# argon 主题替代默认 bootstrap-mod
remove_pkg "luci-theme-bootstrap-mod"
echo "  [A] 被替代的旧插件"

# ---- B. 调试 / 诊断工具 ----
# 这些工具普通用户用不到, 需要时 opkg install 就行
# htop: 进程监控 (top 足够用)
# nano: 文本编辑器 (vi 够用)
# tcpdump: 抓包 (高级用户才用)
# kvcedit / libkvcutil: KVC 配置工具
# regs / mii_mgr: 寄存器/MII 调试工具
for pkg in htop nano kvcedit tcpdump libpcap \
           terminfo libncurses regs mii_mgr kmod-inet-diag libkvcutil; do
    remove_pkg "$pkg"
done
echo "  [B] 调试/诊断工具"

# ---- C. 不需要的硬件驱动 ----
# N60 Pro 没有这些硬件, 留着浪费空间
# kmod-leds-ws2812b: WS2812B 彩灯驱动 (N60 Pro 没有)
# kmod-ata-core: SATA 接口驱动 (N60 Pro 没有 SATA)
remove_pkg "kmod-leds-ws2812b"
remove_pkg "kmod-ata-core"
echo "  [C] 无用硬件驱动"

# ---- D. 桥接防火墙 (ebtables) ----
# ebtables 是二层桥接防火墙, 家庭主路由几乎用不到
# 我们用 iptables/nftables (三层) 就够了
for pkg in kmod-ebtables kmod-ebtables-ipv4 kmod-ebtables-ipv6 ebtables; do
    remove_pkg "$pkg"
done
echo "  [D] ebtables (桥接防火墙)"

# ---- E. 不常用 iptables 模块 ----
# 这些是 iptables 的小众模块, 普通用户用不到
# filter/tee/u32/ipv4options 都是比较冷门的匹配模块
# compat-xtables 是旧版兼容层, 6.6 内核不需要
for mod in filter tee u32 ipv4options; do
    remove_pkg "kmod-ipt-${mod}"
    remove_pkg "iptables-mod-${mod}"
done
remove_pkg "kmod-ipt-compat-xtables"
echo "  [E] 不常用 iptables 模块"

# ---- F. IPv6 用户态工具 (内核保留) ----
# 为什么只删用户态不删内核?
#   内核 IPv6 协议栈很小, 而且有些程序可能隐性依赖它
#   用户态工具 (odhcp6c / ip6tables 等) 占空间大, 而且用户明确说不用 IPv6
# 这样既省空间, 又不会因为缺内核支持导致奇怪的问题
for pkg in ip6tables-extra ip6tables-nft kmod-ipt-raw6 kmod-ip6tables-extra \
           odhcp6c odhcpd-ipv6only luci-proto-ipv6 luci-proto-6in4; do
    remove_pkg "$pkg"
done
echo "  [F] IPv6 用户态工具"

# ---- G. 其他非核心包 ----
# blockd: 块设备自动挂载 (我们用 block-mount, 更轻量)
# libfido2 / libcbor: FIDO 安全密钥支持 (很少人用)
# libevdev / libudev-zero: 输入设备库 (路由器不需要键盘鼠标)
# openssh-keygen: SSH 密钥生成 (dropbear 够用)
# resolveip: DNS 解析工具 (busybox 有 nslookup)
# zram-swap / kmod-zram / kmod-lib-lzo: 内存压缩 (2GB 内存用不上)
for pkg in blockd libfido2 libevdev libudev-zero libcbor \
           openssh-keygen resolveip \
           zram-swap kmod-zram kmod-lib-lzo; do
    remove_pkg "$pkg"
done
echo "  [G] 其他非核心包"

# ---- H. 网页诊断/统计界面 ----
# luci-app-diag-core: 网络诊断网页界面 (ping/traceroute 等, 命令行也能用)
# luci-app-statistics: 实时统计页面 (vnstat2 + nlbwmon 已经覆盖)
remove_pkg "luci-app-diag-core"
remove_pkg "luci-app-statistics"
echo "  [H] 诊断/统计网页界面"

echo "  合计移除: ${REMOVE_COUNT} 个包"

# ============================================================================
# 3. daed 内核选项 (eBPF 支持)
# ============================================================================
# 【daed 为什么需要内核改配置?】
# daed 是基于 eBPF (extended Berkeley Packet Filter) 的代理工具。
# eBPF 允许在内核里运行沙盒程序, 性能很高但需要内核支持。
#
# 【这些选项的作用】
#   DEBUG_INFO / DEBUG_INFO_BTF: 调试信息 + BTF (BPF Type Format)
#     → daed 需要 BTF 来解析内核类型信息, 才能正确加载 eBPF 程序
#     → 注意: 这会让内核变大一些 (增加 ~2-3MB), 但 daed 必须要
#   BPF_EVENTS: BPF 事件追踪
#   XDP_SOCKETS: XDP (eXpress Data Path) 支持, 高性能数据路径
#   BPF_TOOLCHAIN_HOST: 用主机的 LLVM 编译 BPF 程序
#     → 而不是用 OpenWrt 自带的 (可能版本不够)
#
# 【为什么要主机 LLVM?】
# BPF 程序需要用 clang/llvm 编译。build.yml 中已经安装了系统的 llvm/clang,
# 这里配置让编译系统用主机的工具链来编译 BPF 程序。
# ============================================================================
echo ""
echo "--- 3. daed eBPF 内核选项 ---"
cat >> .config << 'EOF'
# BTF 调试信息 (daed 必需, 没有的话 eBPF 程序加载失败)
CONFIG_KERNEL_DEBUG_INFO=y
# CONFIG_KERNEL_DEBUG_INFO_REDUCED is not set
CONFIG_KERNEL_DEBUG_INFO_BTF=y
# BPF 事件追踪支持
CONFIG_KERNEL_BPF_EVENTS=y
# XDP 高性能数据路径
CONFIG_XDP_SOCKETS=y
# 用主机 LLVM 编译 BPF 程序 (确保版本足够新)
CONFIG_BPF_TOOLCHAIN=y
CONFIG_BPF_TOOLCHAIN_HOST=y
EOF
echo "  [OK] BPF + BTF + XDP (daed 必需)"

# ============================================================================
# 4. 添加软件包
# ============================================================================
# 【选包原则】
#  1. 用户明确要求的 → 必加
#  2. 核心功能依赖 → 必加
#  3. 常用而且小的 → 加
#  4. 不常用而且大的 → 不加 (需要时 opkg 装)
#
# 【y vs m】
#  =y → 编入固件 (build-in), 刷完就能用
#  =m → 编译成 .ipk 模块, 不进固件 (后期 opkg 安装)
#  我们都用 =y, 因为要确保刷完就能用。
#
# 【包列表按功能分组】
#  方便阅读和修改, 想加/减某个功能直接在对应组里改就行。
# ============================================================================
echo ""
echo "--- 4. 添加软件包 ---"

cat >> .config << 'EOF'

# =====================================================
#  4.1 代理: daed (eBPF 实现)
# =====================================================
# 为什么选 daed 而不是 ssr-plus / passwall?
#   - eBPF 实现, 性能高, 不占用户态 CPU
#   - 代码相对简洁, 维护活跃
#   - 支持各种协议 (VMess / VLESS / Trojan / Shadowsocks 等)
# daed: 主程序 (eBPF 内核模块 + 用户态守护进程)
# luci-app-daed: LuCI 管理界面
CONFIG_PACKAGE_daed=y
CONFIG_PACKAGE_luci-app-daed=y

# =====================================================
#  4.2 组网: EasyTier (虚拟局域网)
# =====================================================
# EasyTier: 点对点 VPN, 可以把不同地方的设备组成一个虚拟局域网
# 比如: 家里的路由器 + 公司的电脑 + 手机, 都在同一个 10.0.0.0/24 网段
# easytier: 主程序
# luci-app-easytier: LuCI 管理界面
CONFIG_PACKAGE_easytier=y
CONFIG_PACKAGE_luci-app-easytier=y

# =====================================================
#  4.3 DDNS: ddns-go (动态域名)
# =====================================================
# 为什么选 ddns-go 而不是 luci-app-ddns?
#   - 支持的 DNS 服务商更多 (阿里云/Cloudflare/腾讯云 等几十种)
#   - Web 界面更友好
#   - 自动更新方便
# 注意: 主程序 ddns-go 二进制在 diy-part1.sh 中通过 files/ 方式放入
#       这里只选 LuCI 界面
CONFIG_PACKAGE_luci-app-ddns-go=y

# =====================================================
#  4.4 文件共享: Samba4 (服务端) + CIFS (客户端)
# =====================================================
# Samba4 服务端: 把路由器上插的 U 盘/移动硬盘共享给局域网设备
#   Windows / Mac / 手机 / 电视 都能访问
# samba4-server: Samba 4 服务端
# luci-app-samba4: LuCI 管理界面
CONFIG_PACKAGE_samba4-server=y
CONFIG_PACKAGE_luci-app-samba4=y

# CIFS 客户端: 挂载远程 SMB 共享到路由器
#   比如: 通过 EasyTier 挂载远程电脑的共享文件夹, 再共享给本地局域网
# kmod-fs-cifs: CIFS 文件系统内核模块
# kmod-nls-utf8: UTF-8 字符集 (中文文件名不乱码)
# kmod-nls-base: NLS 基础模块
CONFIG_PACKAGE_kmod-fs-cifs=y
CONFIG_PACKAGE_kmod-nls-base=y
CONFIG_PACKAGE_kmod-nls-utf8=y
# cifsmount: 命令行挂载 CIFS 共享的工具 (LuCI 挂载界面依赖)
CONFIG_PACKAGE_cifsmount=y

# wsdd2: Web Service Discovery 守护进程
#   Windows 的"网络邻居"发现设备靠这个, 没有的话 Windows 网上邻居里看不到路由器
#   虽然 samba4 也有 WSD 支持, 但 wsdd2 更轻量、兼容性更好
CONFIG_PACKAGE_wsdd2=y

# =====================================================
#  4.5 流量统计: WAN口 + 内网设备
# =====================================================
# 两个工具互补, 不重复:
#   vnstat2  → 统计 WAN 口总流量 (按月/日/小时), 适合看每月用了多少
#   nlbwmon  → 统计内网每个设备的流量 (基于 conntrack), 适合看谁用得多
#
# vnstat2: 轻量级网络流量监控 (第二代, 比 vnstat v1 更好)
# vnstat2-image: 图片生成支持 (LuCI 界面画图表需要)
# luci-app-vnstat2: LuCI 管理界面
CONFIG_PACKAGE_vnstat2=y
CONFIG_PACKAGE_vnstat2-image=y
CONFIG_PACKAGE_luci-app-vnstat2=y

# nlbwmon: 基于连接追踪的带宽监控
#   优点: 轻量, 不需要抓包, 直接读 conntrack
#   缺点: 只能看当前连接的设备, 重启后数据会丢
# luci-app-nlbwmon: LuCI 管理界面
CONFIG_PACKAGE_nlbwmon=y
CONFIG_PACKAGE_luci-app-nlbwmon=y

# =====================================================
#  4.6 主题 + 终端
# =====================================================
# argon 主题: 现代风格主题, 比默认 bootstrap 好看
#   支持明暗主题切换、响应式布局、移动端适配
CONFIG_PACKAGE_luci-theme-argon=y

# ttyd: 网页终端
#   在浏览器里就能用命令行, 不用装 SSH 客户端
#   配合 uci-defaults 设置免登录, 局域网内很方便
CONFIG_PACKAGE_ttyd=y
CONFIG_PACKAGE_luci-app-ttyd=y

# 【注意】
# CPU 频率显示不靠 autocore-arm 包 (它对 MT7986 支持不好)。
# 我们用 mtk-cpufreq 二进制 + 自定义 cpuinfo 脚本 (在 diy-part1.sh 的 files/ 里),
# 直接读寄存器获取真实频率, 比 autocore 更准确。
# 所以不选 autocore-arm, 避免冗余。
EOF
echo "  [OK] 包选择完成 (daed + EasyTier + ddns-go + Samba + CIFS + wsdd2 + cifsmount + vnstat2 + nlbwmon + argon + ttyd)"

# ============================================================================
# 5. rootfs 分区大小
# ============================================================================
# 【UBI 布局概念】
# 整个 UBI 分区 (~506.5MB) 被分成两部分:
#   rootfs      : squashfs 只读分区, 放固件本体 (系统 + 内置插件)
#   rootfs_data : overlay 可写分区, 放配置 + 后装的插件
#
# 【为什么设 80MB?】
# 当前固件大小估算:
#   内核 + 基础系统: ~30MB
#   WiFi 固件 + 驱动: ~10MB
#   内置插件 (daed/easytier/samba 等): ~20-25MB
#   其他 (主题/工具/库): ~5-10MB
#   合计: ~65-75MB
# 设 80MB 留 5-15MB 余量, 防止加包后超容。
#
# 剩下的 ~420MB 全给 rootfs_data (overlay), 装插件空间非常充足。
#
# 【注意】
# 这个值是 squashfs 的最大大小, 实际固件如果只有 60MB, 就只占 60MB。
# 设大了不会浪费空间, 只是限制了"最大能多大"。
# ============================================================================
echo ""
echo "--- 5. rootfs 分区大小 ---"
echo 'CONFIG_TARGET_ROOTFS_PARTSIZE=80' >> .config
echo "  [OK] 80MB (rootfs_data 约 420MB 可用)"

# ============================================================================
# 6. make defconfig
# ============================================================================
# 【这一步为什么重要?】
# 我们手动往 .config 里加了很多行, 但可能有问题:
#   1. 依赖缺失: 选了 A 包, 但它依赖的 B 包没选
#   2. 配置冲突: 两个互斥的选项同时选了
#   3. 格式错误: 手写的配置项格式不对
#
# make defconfig 会:
#   1. 自动补齐所有依赖
#   2. 处理冲突 (按优先级保留)
#   3. 生成合法的、完整的 .config
#
# 这一步必须做, 否则编译可能出各种奇怪的错误。
# ============================================================================
echo ""
echo "--- 6. make defconfig (补齐依赖) ---"
make defconfig
echo "  [OK] defconfig 完成"

# ============================================================================
# 7. 验证 (检查关键包是否正确选中)
# ============================================================================
# 【为什么要验证?】
# 编译一次要 2-3 小时, 如果关键包没选上, 白等半天。
# 编译前先检查一下, 有问题能及时发现。
#
# 【检查哪些】
#   - 设备是否正确选中
#   - 核心功能包 (代理/组网/DDNS/共享/统计)
#   - 主题和工具
#   - 核心驱动 (WiFi/NAT/USB/存储)
#   - 确认已移除的包确实不在
#   - 分区大小是否正确
# ============================================================================
echo ""
echo "=== 验证 ==="

# check 函数: 检查一个包是否被 =y 选中
check() {
    if grep -q "CONFIG_PACKAGE_${1}=y" .config 2>/dev/null; then
        echo "  [OK] $1"
    else
        echo "  [!!] $1 缺失!"
    fi
}

echo "[设备]"
grep "CONFIG_TARGET_DEVICE.*netcore" .config | head -1

echo ""
echo "[代理 / 组网 / DDNS]"
for p in daed luci-app-daed easytier luci-app-easytier luci-app-ddns-go; do
    check "$p"
done

echo ""
echo "[文件共享]"
for p in samba4-server luci-app-samba4 kmod-fs-cifs kmod-nls-utf8 wsdd2 cifsmount; do
    check "$p"
done

echo ""
echo "[流量统计]"
for p in vnstat2 vnstat2-image luci-app-vnstat2 nlbwmon luci-app-nlbwmon; do
    check "$p"
done

echo ""
echo "[主题 / 工具]"
for p in luci-theme-argon ttyd luci-app-ttyd; do
    check "$p"
done

echo ""
echo "[CPU 频率 (靠 mtk-cpufreq + cpuinfo 脚本, 不靠包)]"
echo "  (验证方式: 刷固件后看 LuCI 概览页是否显示频率)"

echo ""
echo "[核心功能 (确保没被误删)]"
for p in kmod-mt_wifi kmod-mediatek_hnat kmod-tun kmod-tcp-bbr \
         kmod-usb-storage kmod-fs-ext4 block-mount ppp; do
    check "$p"
done

echo ""
echo "[精简验证 (确认已移除)]"
for p in luci-app-ssr-plus htop tcpdump ebtables zram-swap; do
    if grep -q "CONFIG_PACKAGE_${p} is not set" .config; then
        echo "  [OK] ${p}: 已移除"
    else
        echo "  [--] ${p}: 不在配置中 (默认就没有)"
    fi
done

echo ""
echo "[分区]"
grep "CONFIG_TARGET_ROOTFS_PARTSIZE" .config

# ============================================================================
# 完成
# ============================================================================
echo ""
echo "============================================================"
echo "  DIY Part 2 完成!"
echo "============================================================"
echo "  精简: 移除 ${REMOVE_COUNT} 个包"
echo "  内置: daed / EasyTier / ddns-go"
echo "        samba4 / CIFS挂载 / wsdd2 / cifsmount"
echo "        vnstat2 / nlbwmon"
echo "        argon / ttyd"
echo "  CPU频率: mtk-cpufreq + cpuinfo 脚本 (不靠 autocore 包)"
echo "  rootfs: 80MB (overlay ~420MB)"
echo "============================================================"
