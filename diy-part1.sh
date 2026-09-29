#!/bin/bash
# ============================================================================
#  DIY Part 1 - 源码修改 (feeds 更新之前执行)
#
#  设备: 磊科 N60 Pro (512MB 闪存 + 2GB 内存 硬改版)
#  布局: 506.5MB UBI (移除 NMBM)
#
#  功能:
#    1. 自动检测 mt7986 / filogic 目标
#    2. 修改 DTS: 内存 2GB + 移除 NMBM + UBI 506.5MB
#    3. 确保 netcore_n60-pro 设备定义存在
#    4. 克隆第三方软件包 (EasyTier / argon / ddns-go 界面)
#    5. 下载 ddns-go 预编译二进制到 files/ 目录
#    6. uci-defaults 系统优化
# ============================================================================
set -e

echo "============================================================"
echo "  DIY Part 1: 源码修改"
echo "  N60 Pro - 512MB 闪存 + 2GB 内存 + 506.5MB 布局"
echo "============================================================"

# ==================================================================
# 0. 自动检测目标平台 (mt7986 或 filogic)
# ==================================================================
DTS_FILE=""
FIRMWARE_MK=""
DTS_BASE="mt7986a-netcore-n60-pro"

# 先找 DTS 文件
for candidate in \
    "target/linux/mediatek/dts/mt7986a-netcore-n60-pro.dts" \
    "target/linux/mediatek/dts/mt7986a-netcore_n60-pro.dts" \
    "target/linux/mediatek/dts/mt7986b-netcore-n60-pro.dts"; do
    if [ -f "$candidate" ]; then
        DTS_FILE="$candidate"
        DTS_BASE=$(basename "$candidate" .dts)
        break
    fi
done

# 找设备定义 mk 文件
for candidate in \
    "target/linux/mediatek/image/mt7986.mk" \
    "target/linux/mediatek/image/filogic.mk"; do
    if [ -f "$candidate" ] && grep -q "netcore_n60-pro\|netcore-n60-pro" "$candidate" 2>/dev/null; then
        FIRMWARE_MK="$candidate"
        break
    fi
done

# 如果 mk 文件里找不到, 就用存在的那个
if [ -z "$FIRMWARE_MK" ]; then
    for candidate in \
        "target/linux/mediatek/image/mt7986.mk" \
        "target/linux/mediatek/image/filogic.mk"; do
        if [ -f "$candidate" ]; then
            FIRMWARE_MK="$candidate"
            break
        fi
    done
fi

echo ""
echo "--- 0. 目标平台检测 ---"
echo "  DTS 文件: $DTS_FILE"
echo "  固件 MK:  $FIRMWARE_MK"
echo "  DTS 基础名: $DTS_BASE"

[ -z "$DTS_FILE" ] && echo "[错误] 未找到 DTS 文件" && exit 1
[ -z "$FIRMWARE_MK" ] && echo "[错误] 未找到固件 mk 文件" && exit 1

# ==================================================================
# 1. DTS 设备树修改
# ==================================================================
echo ""
echo "--- 1. 修改 DTS 设备树 ---"

# 内存: 512MB -> 2GB
if grep -q '0x40000000 0 0x20000000' "$DTS_FILE"; then
    sed -i 's/0x40000000 0 0x20000000/0x40000000 0 0x80000000/' "$DTS_FILE"
    echo "  [OK] 内存: 2GB"
else
    echo "  [跳过] 内存已是 2GB 或格式不同"
fi

# 移除 NMBM (联发科坏块管理, 新内核用 UBI 替代)
NMBM_COUNT=$(grep -c 'nmbm\|bmt-max' "$DTS_FILE" 2>/dev/null || echo 0)
if [ "$NMBM_COUNT" -gt 0 ]; then
    sed -i '/mediatek,nmbm;/d; /mediatek,bmt-max-ratio/d; /mediatek,bmt-max-reserved-blocks/d' "$DTS_FILE"
    echo "  [OK] 移除 NMBM (删除了 $NMBM_COUNT 处)"
else
    echo "  [跳过] 未发现 NMBM (可能本来就没有)"
fi

# UBI 分区: 128MB -> 506.5MB
# 匹配 pattern: <起始地址> 0x7280000 (128MB) -> 0x1FA80000 (506.5MB)
if grep -q '0x7280000' "$DTS_FILE"; then
    sed -i 's/0x0580000 0x7280000/0x0580000 0x1FA80000/' "$DTS_FILE"
    # 也试试其他可能的起始地址
    grep -q '0x7280000' "$DTS_FILE" && sed -i 's/ 0x7280000/ 0x1FA80000/g' "$DTS_FILE" || true
    echo "  [OK] UBI 分区: 506.5MB"
else
    echo "  [警告] 未找到 128MB UBI 分区, 检查当前分区配置:"
    grep -i 'ubi\|partition' "$DTS_FILE" | head -10 || true
fi

# 验证
MEM_LINE=$(grep 'memory@' -A1 "$DTS_FILE" | grep 'reg' | tr -s ' ' | head -1)
NMBM_REMAIN=$(grep -c 'nmbm' "$DTS_FILE" 2>/dev/null || echo 0)
echo "  验证: 内存 $MEM_LINE"
echo "  验证: NMBM 残留 $NMBM_REMAIN 处"

# ==================================================================
# 2. 设备定义 (mk 文件)
# ==================================================================
echo ""
echo "--- 2. 设备定义 ---"

if grep -q "Device/netcore_n60-pro\|Device/netcore-n60-pro" "$FIRMWARE_MK" 2>/dev/null; then
    # 已存在, 移除 IMAGE_SIZE 限制
    sed -i '/define Device\/netcore_n60-pro/,/endef/ {/IMAGE_SIZE/d}' "$FIRMWARE_MK" 2>/dev/null || true
    sed -i '/define Device\/netcore-n60-pro/,/endef/ {/IMAGE_SIZE/d}' "$FIRMWARE_MK" 2>/dev/null || true
    echo "  [OK] 设备定义已存在, 已移除 IMAGE_SIZE 限制"
else
    # 不存在, 添加完整定义
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
    echo "  [OK] 设备定义已添加到 $FIRMWARE_MK"
fi

# ==================================================================
# 3. 克隆第三方软件包
# ==================================================================
echo ""
echo "--- 3. 克隆第三方软件包 ---"

declare -A REPOS=(
    ["package/luci-app-easytier"]="https://github.com/EasyTier/luci-app-easytier.git"
    ["package/luci-theme-argon"]="https://github.com/jerrykuku/luci-theme-argon.git"
    ["package/luci-app-ddns-go"]="https://github.com/sirpdboy/luci-app-ddns-go.git"
)

for dir in "${!REPOS[@]}"; do
    url="${REPOS[$dir]}"
    name=$(basename "$dir")
    if [ -d "$dir" ]; then
        echo "  [跳过] $name (已存在)"
    else
        git clone --depth 1 "$url" "$dir" 2>/dev/null && echo "  [OK] $name" || echo "  [失败] $name"
    fi
done

# ==================================================================
# 4. ddns-go - 移除 ddns-go 子包, 用 files/ 方式放二进制
# ==================================================================
echo ""
echo "--- 4. ddns-go 主程序 ---"

# 如果 sirpdboy 的仓库里有 ddns-go/ 子包, 删掉它 (避免编译失败)
DDNS_GO_SUBPKG="package/luci-app-ddns-go/ddns-go"
if [ -d "$DDNS_GO_SUBPKG" ]; then
    rm -rf "$DDNS_GO_SUBPKG"
    echo "  [OK] 移除 ddns-go 源码子包 (改用预编译二进制)"
fi

# files/ 目录: 直接覆盖到固件根文件系统
mkdir -p files/usr/bin files/etc/init.d

# 从 GitHub 获取最新版本号
DDNS_VER=""
if command -v curl &>/dev/null; then
    DDNS_VER=$(curl -s --max-time 10 "https://api.github.com/repos/jeessy2/ddns-go/releases/latest" 2>/dev/null | grep -o '"tag_name": *"[^"]*"' | head -1 | sed 's/.*"tag_name": *"//;s/"//')
fi

# API 失败用默认值
if [ -z "$DDNS_VER" ]; then
    DDNS_VER="v6.17.7"
    echo "  (API 获取失败, 使用默认版本 $DDNS_VER)"
else
    echo "  最新版本: $DDNS_VER"
fi

# 确保版本号以 v 开头
case "$DDNS_VER" in v*) ;; *) DDNS_VER="v${DDNS_VER}" ;; esac

# 文件名不带 v (官方命名格式: ddns-go_6.17.7_linux_arm64.tar.gz)
VER_NO_V="${DDNS_VER#v}"
DL_FILE="ddns-go_${VER_NO_V}_linux_arm64.tar.gz"
DL_URL="https://github.com/jeessy2/ddns-go/releases/download/${DDNS_VER}/${DL_FILE}"

if [ ! -f "files/usr/bin/ddns-go" ]; then
    echo "  下载: $DL_URL"
    if curl -L --max-time 60 -o "/tmp/$DL_FILE" "$DL_URL" 2>/dev/null; then
        mkdir -p /tmp/ddns-go
        tar -xzf "/tmp/$DL_FILE" -C /tmp/ddns-go 2>/dev/null || true
        if [ -f "/tmp/ddns-go/ddns-go" ]; then
            cp "/tmp/ddns-go/ddns-go" files/usr/bin/ddns-go
            chmod +x files/usr/bin/ddns-go
            echo "  [OK] 已放入 files/usr/bin/ddns-go"
        else
            echo "  [警告] 解压后未找到二进制"
        fi
        rm -rf "/tmp/$DL_FILE" "/tmp/ddns-go"
    else
        echo "  [警告] 下载失败, 固件将不包含 ddns-go"
    fi
else
    echo "  [跳过] 已存在"
fi

# init 启动脚本
if [ ! -f "files/etc/init.d/ddns-go" ]; then
    cat > files/etc/init.d/ddns-go << 'INIT'
#!/bin/sh /etc/rc.common
START=99
STOP=10
USE_PROCD=1
PROG=/usr/bin/ddns-go

start_service() {
    procd_open_instance
    procd_set_param command $PROG -l :9876 -f 300
    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}
INIT
    chmod +x files/etc/init.d/ddns-go
    echo "  [OK] init 脚本已创建"
fi

# ==================================================================
# 5. uci-defaults 系统优化
# ==================================================================
echo ""
echo "--- 5. uci-defaults 系统优化 ---"

mkdir -p files/etc/uci-defaults

cat > files/etc/uci-defaults/99-custom-settings << 'UCIEOF'
#!/bin/sh
# 自定义默认设置, 首次启动时执行一次
# 功率相关严格使用 high-power.config 模板, 此处不做额外修改

# --- 1. BBR 拥塞控制 (替代默认 CUBIC) ---
uci set system.@system[0].congctl='bbr' 2>/dev/null || true
echo 'net.core.default_qdisc = fq' >> /etc/sysctl.conf
echo 'net.ipv4.tcp_congestion_control = bbr' >> /etc/sysctl.conf

# --- 2. Samba4 优化 (多通道 + 访客访问) ---
if uci get samba4.@samba4[0] >/dev/null 2>&1; then
    uci set samba4.@samba4[0].enable_multichannel='1'
    uci set samba4.@samba4[0].disable_netbios='0'
    uci set samba4.@samba4[0].allow_guest='1'
fi

# --- 3. ttyd 免登录 (仅限 LAN 口) ---
if uci get ttyd.@ttyd[0] >/dev/null 2>&1; then
    uci set ttyd.@ttyd[0].interface='@lan'
    uci set ttyd.@ttyd[0].command='/bin/login -f root'
fi

# --- 4. 默认 LAN IP ---
uci set network.lan.ipaddr='10.10.6.1'
uci set network.lan.netmask='255.255.255.0'

# --- 5. 提交 ---
uci commit system
uci commit samba4 2>/dev/null || true
uci commit ttyd 2>/dev/null || true
uci commit network

# --- 6. 应用 sysctl ---
sysctl -p >/dev/null 2>&1 || true

exit 0
UCIEOF
chmod +x files/etc/uci-defaults/99-custom-settings
echo "  [OK] uci-defaults 优化脚本已创建"

# ==================================================================
# 完成
# ==================================================================
echo ""
echo "============================================================"
echo "  DIY Part 1 完成!"
echo "  DTS:  2GB 内存 + 无 NMBM + 506.5MB UBI"
echo "  设备: netcore_n60-pro"
echo "  包:   EasyTier, argon 主题, ddns-go(主程序+界面)"
echo "  优化: BBR + Samba + ttyd免登录 + LAN IP 10.10.6.1"
echo "============================================================"
