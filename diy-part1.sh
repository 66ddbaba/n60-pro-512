#!/bin/bash
# ============================================================================
#  DIY Part 1 - 源码修改阶段 (feeds 更新之前执行)
#
#  【这个脚本做什么】
#  在 OpenWrt 源码上做"源码级"修改，包括：
#    1. 修改 DTS 设备树 (告诉内核真实硬件配置)
#    2. 确保设备定义存在 (让编译系统认识 N60 Pro)
#    3. 克隆第三方软件包 (官方 feeds 里没有的)
#    4. 准备二进制文件 (mtk-cpufreq)
#    5. 准备系统配置 (BBR / cpuinfo / uci-defaults)
#
#  【执行时机】
#  clone 源码之后 → feeds update 之前
#  为什么在 feeds update 之前? 因为我们克隆的第三方包要放进 package/ 目录,
#  feeds update 时会扫描到它们并纳入编译系统。
#
#  【files/ 目录概念】
#  OpenWrt 有个特殊机制: files/ 目录下的内容会直接复制到固件的根文件系统。
#  比如 files/usr/bin/xxx → 固件里的 /usr/bin/xxx
#  这是放自定义脚本、配置、二进制文件最简单的方式, 不经过包管理系统。
# ============================================================================
set -e  # 遇到错误立即退出, 避免问题被掩盖

echo "============================================================"
echo "  DIY Part 1: 源码修改"
echo "============================================================"

# ============================================================================
# 1. 自动检测平台文件路径
# ============================================================================
# 【为什么要自动检测?】
# padavanonly 的 immortalwrt-mt798x 仓库结构可能变化:
#   - DTS 文件名可能是 mt7986a-netcore-n60-pro.dts 或带下划线版本
#   - 设备定义可能在 mt7986.mk 或 filogic.mk 里
# 自动检测比写死路径更健壮, 源码仓库更新了也不容易坏。
#
# 【DTS 是什么?】
# DTS = Device Tree Source (设备树源码)
# 就像硬件的"说明书", 告诉内核: 有几个CPU、多少内存、闪存多大、
# 有哪些外设、怎么连... 硬改了硬件就必须改 DTS。
#
# 【MK 是什么?】
# 固件 Makefile, 定义每个设备的编译参数: 用哪个 DTS、输出什么格式、
# 额外装什么包、UBI 参数等。
# ============================================================================
DTS_FILE=""    # DTS 文件路径
FIRMWARE_MK="" # 固件 Makefile 路径

# 按优先级搜索 DTS 文件 (找到第一个就停)
for f in \
    "target/linux/mediatek/dts/mt7986a-netcore-n60-pro.dts" \
    "target/linux/mediatek/dts/mt7986a-netcore_n60-pro.dts" \
    "target/linux/mediatek/dts/mt7986b-netcore-n60-pro.dts"; do
    [ -f "$f" ] && DTS_FILE="$f" && break
done

# 搜索包含 N60 Pro 定义的 MK 文件
for f in \
    "target/linux/mediatek/image/mt7986.mk" \
    "target/linux/mediatek/image/filogic.mk"; do
    if [ -f "$f" ] && grep -q "netcore_n60-pro\|netcore-n60-pro" "$f" 2>/dev/null; then
        FIRMWARE_MK="$f" && break
    fi
done

# 如果没找到带设备定义的 MK, 就用存在的那个 (后面会添加定义)
[ -z "$FIRMWARE_MK" ] && for f in \
    "target/linux/mediatek/image/mt7986.mk" \
    "target/linux/mediatek/image/filogic.mk"; do
    [ -f "$f" ] && FIRMWARE_MK="$f" && break
done

# 提取 DTS 文件名 (不含 .dts 后缀), 用于设备定义
DTS_BASE=$(basename "$DTS_FILE" .dts 2>/dev/null || echo "mt7986a-netcore-n60-pro")

echo ""
echo "--- 1. 平台检测 ---"
echo "  DTS 文件: $DTS_FILE"
echo "  MK  文件: $FIRMWARE_MK"
[ -z "$DTS_FILE" ] && echo "  [错误] 未找到 DTS 文件!" && exit 1
[ -z "$FIRMWARE_MK" ] && echo "  [错误] 未找到固件 MK 文件!" && exit 1

# ============================================================================
# 2. DTS (设备树) 修改
# ============================================================================
# 【为什么要改 DTS?】
# 我们硬改了闪存(512MB)和内存(2GB), 原厂 DTS 是按原版 128MB+512MB 写的。
# 如果不改, 内核只会识别到原来的大小, 硬改的部分就浪费了。
#
# 【三项修改】
#   A. 内存: 512MB → 2GB (硬改了内存芯片)
#   B. 移除 NMBM: 6.6 内核用 UBI 动态管理坏块, NMBM 已淘汰还占空间
#   C. UBI 分区: 128MB → 506.5MB (硬改了闪存, 给系统更多空间)
# ============================================================================
echo ""
echo "--- 2. DTS 修改 ---"

# --- 2A. 内存: 512MB → 2GB ---
# 语法: reg = <起始地址 高位 大小>;  (MT7986 是 64位寻址, 用两个 32位数表示地址)
# 原: memory@40000000 { reg = <0x40000000 0 0x20000000>; };  ← 0x20000000 = 512MB
# 改: memory@40000000 { reg = <0x40000000 0 0x80000000>; };  ← 0x80000000 = 2048MB
if grep -q '0x40000000 0 0x20000000' "$DTS_FILE"; then
    sed -i 's/0x40000000 0 0x20000000/0x40000000 0 0x80000000/' "$DTS_FILE"
    echo "  [OK] 内存: 512MB → 2GB"
else
    echo "  [跳过] 内存已是 2GB 或格式不同"
fi

# --- 2B. 移除 NMBM ---
# NMBM = NAND MediaTek Bad Block Management (联发科坏块管理)
# 这是联发科的私有坏块管理方案, 老内核用的。
# 6.6 内核用 UBI (Unsorted Block Images) 动态管理坏块, 更先进。
# NMBM 占用 32MB 预留空间, 移除后这部分就可用了。
# 要删的三行: mediatek,nmbm; / mediatek,bmt-max-ratio / mediatek,bmt-max-reserved-blocks
if grep -q 'nmbm\|bmt-max' "$DTS_FILE" 2>/dev/null; then
    sed -i '/mediatek,nmbm;/d; /mediatek,bmt-max-ratio/d; /mediatek,bmt-max-reserved-blocks/d' "$DTS_FILE"
    echo "  [OK] 移除 NMBM (释放 32MB)"
else
    echo "  [跳过] 无 NMBM"
fi

# --- 2C. UBI 分区: 128MB → 506.5MB ---
# 【分区布局】
# 512MB NAND 闪存的分区安排 (从低地址到高地址):
#   bl2        : 1MB   (二级引导)
#   uboot-env  : 0.5MB (uboot 环境变量)
#   factory    : 2MB   (出厂校准数据, WiFi校准等)
#   fip        : 2MB   (固件镜像包, 含uboot和ATF)
#   ubi        : ~506.5MB (剩下的全给 UBI, 放固件和数据)
#
# 0x7280000  = 120MB   (原 128MB 布局的 ubi 分区大小)
# 0x1FA80000 = 505MB   (506.5MB 布局的 ubi 分区大小, 取整到 block)
if grep -q '0x7280000' "$DTS_FILE"; then
    sed -i 's/ 0x7280000/ 0x1FA80000/g' "$DTS_FILE"
    echo "  [OK] UBI 分区: 128MB → 506.5MB"
else
    echo "  [跳过] 未找到 128MB 分区定义"
fi

# ============================================================================
# 3. 确保 N60 Pro 设备定义存在
# ============================================================================
# 【设备定义的作用】
# 设备定义告诉编译系统:
#   - 设备叫什么名字 (Netcore N60 Pro)
#   - 用哪个 DTS 文件
#   - 需要额外装什么包 (WiFi 固件等)
#   - 输出什么格式的固件 (sysupgrade.bin / factory.bin 等)
#   - UBI 参数 (block size / page size 等)
#
# 【为什么要移除 IMAGE_SIZE?】
# IMAGE_SIZE 限制固件最大体积, 原版按 128MB 布局设的值很小。
# 我们改了 506.5MB 布局, 不移除的话固件稍微大一点就会报错。
# ============================================================================
echo ""
echo "--- 3. 设备定义 ---"

if grep -q "Device/netcore_n60-pro\|Device/netcore-n60-pro" "$FIRMWARE_MK" 2>/dev/null; then
    # 设备已存在 → 只移除 IMAGE_SIZE 限制
    # sed 语法: /define Device\/xxx/,/endef/ {/IMAGE_SIZE/d}
    # 意思: 在 define Device 和 endef 之间的范围内, 删除含 IMAGE_SIZE 的行
    sed -i '/define Device\/netcore_n60-pro/,/endef/ {/IMAGE_SIZE/d}' "$FIRMWARE_MK" 2>/dev/null || true
    sed -i '/define Device\/netcore-n60-pro/,/endef/ {/IMAGE_SIZE/d}' "$FIRMWARE_MK" 2>/dev/null || true
    echo "  [OK] 已存在, 移除 IMAGE_SIZE 限制"
else
    # 设备不存在 → 添加完整定义
    cat >> "$FIRMWARE_MK" << EOF

define Device/netcore_n60-pro
  DEVICE_VENDOR := Netcore
  DEVICE_MODEL := N60 Pro
  DEVICE_DTS := $DTS_BASE
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
EOF
    echo "  [OK] 已添加 N60 Pro 设备定义"
fi

# ============================================================================
# 4. 克隆第三方软件包
# ============================================================================
# 【默认 feed 里已经有的, 不用克隆!】
# padavanonly 的 immortalwrt-mt798x-6.6 仓库里, 默认 packages + luci feed
# 已经包含了大部分常用包, 直接在 diy-part2.sh 里选上就行:
#   - daed / luci-app-daed        (eBPF 代理)
#   - ddns-go / luci-app-ddns-go  (动态域名)
#   - samba4 / luci-app-samba4    (文件共享)
#   - cifs-utils / luci-app-cifs-mount (CIFS 挂载)
#   - wsdd2                       (网络发现)
#   - vnstat2 / luci-app-vnstat2  (流量统计)
#   - nlbwmon / luci-app-nlbwmon  (设备流量)
#   - ttyd / luci-app-ttyd        (网页终端)
#   - luci-theme-argon            (argon 主题)
#
# 【真正需要克隆的只有 1 个】
#   - luci-app-easytier (EasyTier 的 LuCI 界面, feed 里没有)
#     easytier 主程序也在默认 feed 里, 但界面没有
#
# 【镜像回退机制】
#   第 1-2 次: 直连 GitHub
#   第 3 次:   走 ghproxy 镜像 (国内 CDN, 对付 GitHub 网络抽风)
#
# 【--depth 1 的作用】
# 只克隆最新一次提交, 不下载完整历史, 省时间省空间。
# ============================================================================
echo ""
echo "--- 4. 克隆第三方包 ---"

# 克隆函数: 3 次重试 (前 2 次直连, 第 3 次走镜像)
# 用法: clone_repo <目标目录> <仓库地址> [分支]
clone_repo() {
    local dir="$1"
    local url="$2"
    local branch="${3:-}"
    local name=$(basename "$dir")

    if [ -d "$dir" ]; then
        echo "  [跳过] $name"
        return 0
    fi

    local branch_arg=""
    [ -n "$branch" ] && branch_arg="-b $branch"

    for try in 1 2 3; do
        # 第 3 次走 ghproxy 镜像
        local try_url="$url"
        if [ $try -eq 3 ]; then
            try_url="https://ghproxy.com/${url}"
            echo "    尝试镜像: ghproxy.com"
        fi

        if git clone --depth 1 $branch_arg "$try_url" "$dir" 2>/dev/null; then
            echo "  [OK] $name"
            return 0
        fi
        rm -rf "$dir"
        [ $try -lt 3 ] && sleep 3
    done
    echo "  [失败] $name"
    return 1
}

# ---- 4.1 独立仓库 ----
# 只有 feed 里没有的才需要克隆
clone_repo "package/luci-app-easytier" "https://github.com/EasyTier/luci-app-easytier.git" || true

# ============================================================================
# 5. 系统优化 (BBR + CPU频率 + 默认设置)
# ============================================================================
# 【这一节做什么】
# 全部通过 files/ 目录放进固件, 都是配置文件和小脚本:
#   5.1 BBR 拥塞控制  → 提升高带宽下的网络性能
#   5.2 CPU 频率显示  → 解决 LuCI 不显示真实 CPU 频率的问题
#   5.3 uci-defaults  → 首次启动自动配置 (LAN IP / Samba / ttyd 等)
#   5.4 CIFS 自动重连 → 断线后自动恢复挂载
# ============================================================================
echo ""
echo "--- 5. 系统优化 ---"

# ----------------------------------------------------------------------------
# 5.1 BBR 拥塞控制
# ----------------------------------------------------------------------------
# 【BBR vs CUBIC】
# 默认 OpenWrt 用 CUBIC 拥塞控制算法, 这是 Linux 默认的。
# BBR (Bottleneck Bandwidth and RTT) 是 Google 开发的,
# 在高带宽、长距离 (高延迟) 场景下性能通常比 CUBIC 好。
# 家用千兆宽带 + 出国场景下 BBR 通常更流畅。
#
# 【为什么要两个文件?】
#   /etc/modules.d/tcp-bbr     → 开机时 modprobe 加载 tcp_bbr 内核模块
#   /etc/sysctl.d/12-tcp-bbr.conf → sysctl 服务启动时设置 BBR 为默认算法
# 加载顺序很重要: 必须先加载模块, 再设置 sysctl, 否则 BBR 不生效。
# modules.d 在 sysctl.d 之前执行, 所以分开两个文件刚好。
# ----------------------------------------------------------------------------
mkdir -p files/etc/modules.d files/etc/sysctl.d
echo "tcp_bbr" > files/etc/modules.d/tcp-bbr
cat > files/etc/sysctl.d/12-tcp-bbr.conf << 'EOF'
# fq 是 BBR 推荐的队列调度算法 (BBR 需要 fq or fq_codel)
net.core.default_qdisc = fq
# 设置 BBR 为默认拥塞控制算法
net.ipv4.tcp_congestion_control = bbr
EOF
echo "  [OK] BBR 拥塞控制 (modules.d + sysctl.d)"

# ----------------------------------------------------------------------------
# 5.2 CPU 频率显示 (mtk-cpufreq + cpuinfo 脚本)
# ----------------------------------------------------------------------------
# 【为什么 LuCI 不显示 CPU 频率?】
# MT7986 内核没有 cpufreq 驱动 (联发科没开源), 所以标准的 cpuinfo 脚本
# 读不到频率, 只能显示 "MediaTek MT7986A" 后面是空的。
#
# 【解决方案】
# 用 mtk-cpufreq 这个专用工具, 直接读 CPU 寄存器获取真实频率。
# 这是从能正常显示频率的固件里提取的二进制 (64KB 左右)。
#
# 【工作原理】
#   mtk-cpufreq → 读寄存器, 输出 "MT7986A @ 2.30GHz" 这样的字符串
#   cpuinfo     → LuCI 调用的脚本, 包装 mtk-cpufreq 的输出, 加上核心数和温度
#
# 【为什么不用 autocore 包?】
# autocore 是 OpenWrt 通用的 CPU 信息包, 但它对 MT7986 支持不好
# (MT7986 内核没有 cpufreq 驱动, autocore 读不到频率)。
# 我们完全不装 autocore, 直接自己写 cpuinfo 脚本 + mtk-cpufreq,
# 功能更单一、更可靠, 还省空间。
# ----------------------------------------------------------------------------
mkdir -p files/usr/bin files/sbin

# 复制 mtk-cpufreq 二进制 (从仓库根目录拿)
# GITHUB_WORKSPACE 是 GitHub Actions 的环境变量, 指向仓库根目录
if [ -f "$GITHUB_WORKSPACE/mtk-cpufreq" ]; then
    cp "$GITHUB_WORKSPACE/mtk-cpufreq" files/usr/bin/mtk-cpufreq
    chmod +x files/usr/bin/mtk-cpufreq
    echo "  [OK] mtk-cpufreq (真实 CPU 读频工具)"
else
    echo "  [警告] 未找到 mtk-cpufreq (CPU 频率可能不显示)"
fi

# 自定义 cpuinfo 脚本
# 输出格式: "MT7986A @ 2.30GHz x 4 (48.7°C)"
# LuCI 概览页的 "架构" 行会调用 /sbin/cpuinfo 并显示结果
cat > files/sbin/cpuinfo << 'CPUINFO'
#!/bin/sh
# ============================================================
#  自定义 cpuinfo - 配合 mtk-cpufreq 显示真实 CPU 频率
#  输出格式与 autocore 兼容, LuCI 能正确显示
# ============================================================

# 1. 调用 mtk-cpufreq 获取 CPU 型号和频率 (如 "MT7986A @ 2.30GHz")
MTK_INFO=""
if command -v mtk-cpufreq >/dev/null 2>&1; then
    MTK_INFO=$(mtk-cpufreq 2>/dev/null | head -1 | tr -d '\r')
fi

# 2. 读取温度
#    从 thermal_zone 读, 单位是毫摄氏度 (m°C), 除以 1000 得摄氏度
#    MT7986 有多个 thermal zone, 挨个试找到第一个有效的
TEMP=""
for i in 0 1 2; do
    t=$(cat /sys/class/thermal/thermal_zone${i}/temp 2>/dev/null)
    [ -n "$t" ] && TEMP=$t && break
done
# 转换格式: 48725 → 48.7
[ -n "$TEMP" ] && TEMP=$(awk "BEGIN {printf \"%.1f\", $TEMP/1000}")

# 3. 核心数 (从 /proc/cpuinfo 数 processor 行数)
CORES=$(grep -c "processor" /proc/cpuinfo 2>/dev/null || echo 4)

# 4. 组合输出 (根据有哪些信息输出不同格式)
if [ -n "$MTK_INFO" ] && [ -n "$TEMP" ]; then
    echo "${MTK_INFO} x ${CORES} (${TEMP}°C)"
elif [ -n "$MTK_INFO" ]; then
    echo "${MTK_INFO} x ${CORES}"
else
    # mtk-cpufreq 不可用时的兜底输出
    echo "MediaTek MT7986A x ${CORES}"
fi
CPUINFO
chmod +x files/sbin/cpuinfo
echo "  [OK] cpuinfo 脚本 (调用 mtk-cpufreq + 温度)"

# ----------------------------------------------------------------------------
# 5.3 uci-defaults 初始化脚本
# ----------------------------------------------------------------------------
# 【uci-defaults 是什么?】
# /etc/uci-defaults/ 目录下的所有脚本会在系统首次启动时依次执行,
# 执行完后自动删除 (只执行一次)。
# 相当于 Windows 的 "首次开机设置", 用来配置默认参数。
#
# 【为什么不直接写配置文件?】
# 因为有些配置是 UCI 格式的, 直接写文件容易写错格式。
# 用 uci set/get 命令更安全, 而且能和系统其他配置正确合并。
#
# 【设置内容】
#   - 确保 BBR 生效 (手动触发一次 modprobe + sysctl)
#   - Samba4 多通道 + 访客访问 (局域网共享更方便)
#   - ttyd 免登录 (仅限 LAN 口, 安全)
#   - 默认 LAN IP 改为 10.10.6.1
# ----------------------------------------------------------------------------
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-custom-settings << 'UCIEOF'
#!/bin/sh
# ============================================================
#  首次启动执行一次的自定义设置
#  执行后自动删除 (uci-defaults 机制)
# ============================================================

# --- BBR: 确保生效 ---
# uci-defaults 执行时可能 sysctl 服务还没跑完, 手动触发一下保险
modprobe tcp_bbr 2>/dev/null || true
sysctl -p /etc/sysctl.d/12-tcp-bbr.conf >/dev/null 2>&1 || true

# --- Samba4 优化 ---
# enable_multichannel: SMB 多通道, 多网卡时提升性能
# allow_guest: 允许访客访问 (不用输入密码, 局域网内方便)
if uci get samba4.@samba4[0] >/dev/null 2>&1; then
    uci set samba4.@samba4[0].enable_multichannel='1'
    uci set samba4.@samba4[0].disable_netbios='0'
    uci set samba4.@samba4[0].allow_guest='1'
    uci commit samba4
fi

# --- ttyd 免登录 (仅限 LAN) ---
# interface='@lan': 只监听 LAN 口, 不暴露到 WAN
# command='/bin/login -f root': 自动以 root 登录, 不用输密码
# 安全提示: 仅限信任的局域网使用!
if uci get ttyd.@ttyd[0] >/dev/null 2>&1; then
    uci set ttyd.@ttyd[0].interface='@lan'
    uci set ttyd.@ttyd[0].command='/bin/login -f root'
    uci commit ttyd
fi

# --- 默认 LAN IP ---
# 改成 10.10.6.1, 避免和光猫 (192.168.1.1) 冲突
uci set network.lan.ipaddr='10.10.6.1'
uci set network.lan.netmask='255.255.255.0'
uci commit network

exit 0
UCIEOF
chmod +x files/etc/uci-defaults/99-custom-settings
echo "  [OK] uci-defaults (BBR + Samba + ttyd + LAN IP)"

# ----------------------------------------------------------------------------
# 5.4 CIFS 自动重连 (断线后自动恢复挂载)
# ----------------------------------------------------------------------------
# 【为什么需要这个?】
#   CIFS/SMB 挂载在 Linux 里有个老问题: 网络一断, 挂载点就僵死了,
#   访问会卡住, 而且不会自动恢复。EasyTier 虚拟局域网重启/重连时
#   经常遇到这个问题。
#
# 【工作原理】
#   1. 先检查 UCI 里有没有配置 CIFS 挂载 (没有就啥也不干, 省资源)
#   2. 有挂载的话, 每分钟检查一次挂载点是否正常
#   3. 如果僵死了 (ls 超时), 就 lazy unmount 再重新 mount
#
# 【智能检测】
#   - 只在有 CIFS 挂载配置时才启动 cron 任务
#   - 用 timeout 命令检测, 防止 ls 卡住整个脚本
# ----------------------------------------------------------------------------

# --- 重连脚本 ---
mkdir -p files/usr/bin
cat > files/usr/bin/cifs-reconnect << 'CREOF'
#!/bin/sh
# ============================================================
#  CIFS 自动重连脚本
#  检测 CIFS 挂载是否僵死, 如果是则卸载后重新挂载
# ============================================================

# 从 UCI 读取所有 CIFS 挂载点
get_mount_points() {
    uci show cifs 2>/dev/null | grep "\.path=" | cut -d'=' -f2 | tr -d "'"
}

# 检查挂载点是否正常 (5秒超时, 防止卡住)
is_mount_healthy() {
    local mp="$1"
    # 挂载点不存在 → 不正常
    [ -d "$mp" ] || return 1
    # ls 能在 5 秒内返回 → 正常
    timeout 5 ls "$mp" >/dev/null 2>&1
    return $?
}

# 重新挂载单个挂载点 (根据 UCI 配置名)
remount_share() {
    local cfg="$1"
    local server path username password options

    server=$(uci get "cifs.${cfg}.server" 2>/dev/null)
    path=$(uci get "cifs.${cfg}.path" 2>/dev/null)
    username=$(uci get "cifs.${cfg}.username" 2>/dev/null)
    password=$(uci get "cifs.${cfg}.password" 2>/dev/null)
    options=$(uci get "cifs.${cfg}.options" 2>/dev/null)
    local_path=$(uci get "cifs.${cfg}.path" 2>/dev/null)

    [ -z "$server" ] || [ -z "$path" ] && return 1

    # 先卸载 (lazy unmount, 不管有没有进程占用都强制卸载)
    umount -l "/mnt/${cfg}" 2>/dev/null

    # 构造挂载参数
    local opts=""
    [ -n "$username" ] && opts="${opts},username=${username}"
    [ -n "$password" ] && opts="${opts},password=${password}"
    [ -n "$options" ] && opts="${opts},${options}"
    opts="${opts#,}"  # 去掉开头的逗号

    # 确保挂载目录存在
    mkdir -p "/mnt/${cfg}"

    # 重新挂载
    if [ -n "$opts" ]; then
        mount -t cifs "//${server}${path}" "/mnt/${cfg}" -o "$opts" 2>/dev/null
    else
        mount -t cifs "//${server}${path}" "/mnt/${cfg}" 2>/dev/null
    fi

    return $?
}

# ---- 主程序 ----
# 检查有没有 CIFS 配置 (没有就直接退出)
if ! uci show cifs >/dev/null 2>&1; then
    exit 0
fi

# 遍历所有 mount 类型的配置节
for cfg in $(uci show cifs 2>/dev/null | grep "=mount$" | cut -d'.' -f2 | cut -d'=' -f1); do
    mp="/mnt/${cfg}"

    # 挂载点不存在或没挂载 → 跳过 (可能用户还没配置)
    if ! mountpoint -q "$mp" 2>/dev/null; then
        continue
    fi

    # 检查是否正常
    if is_mount_healthy "$mp"; then
        continue
    fi

    # 不正常 → 尝试重连
    logger -t cifs-reconnect "挂载点 $mp 异常, 尝试重连..."
    if remount_share "$cfg"; then
        logger -t cifs-reconnect "  [OK] 重连成功: $mp"
    else
        logger -t cifs-reconnect "  [失败] 重连失败: $mp"
    fi
done

exit 0
CREOF
chmod +x files/usr/bin/cifs-reconnect
echo "  [OK] CIFS 自动重连脚本"

# --- uci-defaults: 配置 cron 定时任务 ---
# 固定每分钟检查一次, 脚本内部会判断有没有 CIFS 挂载:
#   - 没配置 / 没挂载 → 直接退出, 几乎不耗资源
#   - 有挂载且正常   → 跳过
#   - 有挂载但僵死   → 自动重连
# 这样不管什么时候配置的 CIFS, 都能自动接管
cat >> files/etc/uci-defaults/99-custom-settings << 'CRONEOF'

# --- CIFS 自动重连 (cron 定时任务) ---
# 每分钟检查一次, 脚本内部智能判断是否需要重连
echo "* * * * * /usr/bin/cifs-reconnect" >> /etc/crontabs/root
logger -t uci-defaults "已启用 CIFS 自动重连 (每分钟检测)"
CRONEOF
echo "  [OK] CIFS 重连 cron (每分钟检测, 智能启停)"

# ============================================================================
# 完成
# ============================================================================
echo ""
echo "============================================================"
echo "  DIY Part 1 完成!"
echo "============================================================"
echo "  DTS 修改: 内存 2GB / 无 NMBM / UBI 506.5MB"
echo "  第三方包: EasyTier界面"
echo "  二进制:   mtk-cpufreq"
echo "  系统优化: BBR + CPU频率 + uci-defaults + CIFS自动重连"
echo "============================================================"
