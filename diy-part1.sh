#!/bin/bash
# ============================================================================
#  DIY Part 1 - 源码修改 (feeds 更新之前执行)
#
#  1. 自动检测 DTS / mk 文件路径 (mt7986 或 filogic)
#  2. 修改 DTS: 内存 2GB + 移除 NMBM + UBI 506.5MB
#  3. 确保 netcore_n60-pro 设备定义存在
#  4. 克隆第三方包 (EasyTier / argon / ddns-go 界面)
#  5. ddns-go 预编译二进制 + init 脚本
#  6. uci-defaults: BBR / Samba / ttyd / LAN IP
# ============================================================================
set -e

echo "============================================================"
echo "  DIY Part 1: 源码修改"
echo "============================================================"

# ==================================================================
# 1. 自动检测 DTS / mk 文件
# ==================================================================
DTS_FILE=""
FIRMWARE_MK=""

for f in \
    "target/linux/mediatek/dts/mt7986a-netcore-n60-pro.dts" \
    "target/linux/mediatek/dts/mt7986a-netcore_n60-pro.dts" \
    "target/linux/mediatek/dts/mt7986b-netcore-n60-pro.dts"; do
    [ -f "$f" ] && DTS_FILE="$f" && break
done

for f in \
    "target/linux/mediatek/image/mt7986.mk" \
    "target/linux/mediatek/image/filogic.mk"; do
    if [ -f "$f" ] && grep -q "netcore_n60-pro\|netcore-n60-pro" "$f" 2>/dev/null; then
        FIRMWARE_MK="$f" && break
    fi
done

# mk 里没找到设备定义就用存在的文件
[ -z "$FIRMWARE_MK" ] && for f in \
    "target/linux/mediatek/image/mt7986.mk" \
    "target/linux/mediatek/image/filogic.mk"; do
    [ -f "$f" ] && FIRMWARE_MK="$f" && break
done

DTS_BASE=$(basename "$DTS_FILE" .dts 2>/dev/null || echo "mt7986a-netcore-n60-pro")

echo ""
echo "--- 1. 平台检测 ---"
echo "  DTS: $DTS_FILE"
echo "  MK:  $FIRMWARE_MK"
[ -z "$DTS_FILE" ] && echo "[错误] 未找到 DTS" && exit 1
[ -z "$FIRMWARE_MK" ] && echo "[错误] 未找到 MK" && exit 1

# ==================================================================
# 2. DTS 修改
# ==================================================================
echo ""
echo "--- 2. DTS 修改 ---"

# 内存 512MB -> 2GB
if grep -q '0x40000000 0 0x20000000' "$DTS_FILE"; then
    sed -i 's/0x40000000 0 0x20000000/0x40000000 0 0x80000000/' "$DTS_FILE"
    echo "  [OK] 内存: 2GB"
else
    echo "  [跳过] 内存已是 2GB 或格式不同"
fi

# 移除 NMBM
if grep -q 'nmbm\|bmt-max' "$DTS_FILE" 2>/dev/null; then
    sed -i '/mediatek,nmbm;/d; /mediatek,bmt-max-ratio/d; /mediatek,bmt-max-reserved-blocks/d' "$DTS_FILE"
    echo "  [OK] 移除 NMBM"
else
    echo "  [跳过] 无 NMBM"
fi

# UBI 分区 128MB -> 506.5MB
if grep -q '0x7280000' "$DTS_FILE"; then
    sed -i 's/ 0x7280000/ 0x1FA80000/g' "$DTS_FILE"
    echo "  [OK] UBI: 506.5MB"
else
    echo "  [跳过] 未找到 128MB 分区"
fi

# ==================================================================
# 3. 设备定义
# ==================================================================
echo ""
echo "--- 3. 设备定义 ---"

if grep -q "Device/netcore_n60-pro\|Device/netcore-n60-pro" "$FIRMWARE_MK" 2>/dev/null; then
    sed -i '/define Device\/netcore_n60-pro/,/endef/ {/IMAGE_SIZE/d}' "$FIRMWARE_MK" 2>/dev/null || true
    sed -i '/define Device\/netcore-n60-pro/,/endef/ {/IMAGE_SIZE/d}' "$FIRMWARE_MK" 2>/dev/null || true
    echo "  [OK] 已存在, 移除 IMAGE_SIZE 限制"
else
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
    echo "  [OK] 已添加"
fi

# ==================================================================
# 4. 克隆第三方包
# ==================================================================
echo ""
echo "--- 4. 克隆第三方包 ---"

declare -A REPOS=(
    ["package/luci-app-easytier"]="https://github.com/EasyTier/luci-app-easytier.git"
    ["package/luci-theme-argon"]="https://github.com/jerrykuku/luci-theme-argon.git"
    ["package/luci-app-ddns-go"]="https://github.com/sirpdboy/luci-app-ddns-go.git"
)

for dir in "${!REPOS[@]}"; do
    name=$(basename "$dir")
    if [ -d "$dir" ]; then
        echo "  [跳过] $name"
    else
        git clone --depth 1 "${REPOS[$dir]}" "$dir" 2>/dev/null && echo "  [OK] $name" || echo "  [失败] $name"
    fi
done

# ==================================================================
# 5. ddns-go 二进制 + init 脚本 (files/ 方式, 不参与编译系统)
# ==================================================================
echo ""
echo "--- 5. ddns-go ---"

# 删掉 sirpdboy 仓库里的 ddns-go 源码子包 (避免编译失败)
rm -rf package/luci-app-ddns-go/ddns-go 2>/dev/null && echo "  [OK] 移除源码子包"

mkdir -p files/usr/bin files/etc/init.d files/etc/uci-defaults

# 获取最新版本号
DDNS_VER=$(curl -s --max-time 10 "https://api.github.com/repos/jeessy2/ddns-go/releases/latest" 2>/dev/null \
    | grep -o '"tag_name": *"[^"]*"' | head -1 \
    | sed 's/.*"tag_name": *"//;s/"//')
[ -z "$DDNS_VER" ] && DDNS_VER="v6.17.7"
case "$DDNS_VER" in v*) ;; *) DDNS_VER="v${DDNS_VER}" ;; esac

VER_NO_V="${DDNS_VER#v}"
DL_URL="https://github.com/jeessy2/ddns-go/releases/download/${DDNS_VER}/ddns-go_${VER_NO_V}_linux_arm64.tar.gz"

echo "  版本: $DDNS_VER"

if [ ! -f "files/usr/bin/ddns-go" ]; then
    if curl -L --max-time 60 -o "/tmp/ddns-go.tar.gz" "$DL_URL" 2>/dev/null; then
        mkdir -p /tmp/ddns-go
        tar -xzf "/tmp/ddns-go.tar.gz" -C /tmp/ddns-go 2>/dev/null || true
        [ -f "/tmp/ddns-go/ddns-go" ] && cp /tmp/ddns-go/ddns-go files/usr/bin/ddns-go && chmod +x files/usr/bin/ddns-go && echo "  [OK] 二进制已放入" || echo "  [警告] 解压失败"
        rm -rf /tmp/ddns-go.tar.gz /tmp/ddns-go
    else
        echo "  [警告] 下载失败"
    fi
else
    echo "  [跳过] 已存在"
fi

# init 脚本
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
echo "  [OK] init 脚本"

# ==================================================================
# 6. uci-defaults 系统优化
# ==================================================================
echo ""
echo "--- 6. uci-defaults ---"

cat > files/etc/uci-defaults/99-custom-settings << 'UCIEOF'
#!/bin/sh

# BBR 拥塞控制
sed -i '/tcp_congestion_control/d; /default_qdisc/d' /etc/sysctl.conf
echo 'net.core.default_qdisc = fq' >> /etc/sysctl.conf
echo 'net.ipv4.tcp_congestion_control = bbr' >> /etc/sysctl.conf
sysctl -w net.core.default_qdisc=fq 2>/dev/null || true
sysctl -w net.ipv4.tcp_congestion_control=bbr 2>/dev/null || true

# Samba4 优化
if uci get samba4.@samba4[0] >/dev/null 2>&1; then
    uci set samba4.@samba4[0].enable_multichannel='1'
    uci set samba4.@samba4[0].disable_netbios='0'
    uci set samba4.@samba4[0].allow_guest='1'
fi

# ttyd 免登录
if uci get ttyd.@ttyd[0] >/dev/null 2>&1; then
    uci set ttyd.@ttyd[0].interface='@lan'
    uci set ttyd.@ttyd[0].command='/bin/login -f root'
fi

# 默认 LAN IP
uci set network.lan.ipaddr='10.10.6.1'
uci set network.lan.netmask='255.255.255.0'

uci commit samba4 2>/dev/null || true
uci commit ttyd 2>/dev/null || true
uci commit network

exit 0
UCIEOF
chmod +x files/etc/uci-defaults/99-custom-settings
echo "  [OK] BBR + Samba + ttyd + LAN IP"

# ==================================================================
echo ""
echo "============================================================"
echo "  DIY Part 1 完成"
echo "============================================================"
