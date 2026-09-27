#!/bin/bash
# ============================================================================
#  DIY Part 1 - 源码修改 (feeds 更新之前执行)
#
#  设备: 磊科 N60 Pro (512MB 闪存 + 2GB 内存 硬改版)
#  布局: 506.5MB UBI (移除 NMBM)
#
#  功能:
#    1. 修改 DTS: 内存 2GB + 移除 NMBM + UBI 506.5MB
#    2. 确保 netcore_n60-pro 设备定义存在
#    3. 克隆第三方软件包 (EasyTier / argon 主题 / ddns-go 界面)
#    4. 下载 ddns-go 预编译二进制到 files/ 目录
# ============================================================================
set -e

echo "============================================================"
echo "  DIY Part 1: 源码修改"
echo "  N60 Pro - 512MB 闪存 + 2GB 内存 + 506.5MB 布局"
echo "============================================================"

# ==================================================================
# 1. DTS 设备树修改
# ==================================================================
DTS_FILE="target/linux/mediatek/dts/mt7986a-netcore-n60-pro.dts"

[ ! -f "$DTS_FILE" ] && echo "[错误] DTS 不存在: $DTS_FILE" && exit 1

echo ""
echo "--- 1. 修改 DTS 设备树 ---"

# 内存: 512MB -> 2GB
sed -i 's/0x40000000 0 0x20000000/0x40000000 0 0x80000000/' "$DTS_FILE"
echo "  [OK] 内存: 2GB"

# 移除 NMBM (联发科坏块管理, 新内核用 UBI 替代)
sed -i '/mediatek,nmbm;/d; /mediatek,bmt-max-ratio/d; /mediatek,bmt-max-reserved-blocks/d' "$DTS_FILE"
echo "  [OK] 移除 NMBM"

# UBI 分区: 128MB -> 506.5MB (512MB - bl2/u-boot/factory/fip = 506.5MB)
sed -i 's/0x0580000 0x7280000/0x0580000 0x1FA80000/' "$DTS_FILE"
echo "  [OK] UBI 分区: 506.5MB"

# 验证
echo "  验证: $(grep 'memory@' -A1 "$DTS_FILE" | grep 'reg' | tr -s ' ')"
echo "  验证: NMBM 残留 $(grep -c 'nmbm' "$DTS_FILE" || echo 0) 处"

# ==================================================================
# 2. 设备定义 (filogic.mk)
# ==================================================================
FIRMWARE_MK="target/linux/mediatek/image/filogic.mk"

echo ""
echo "--- 2. 设备定义 ---"

if grep -q "define Device/netcore_n60-pro" "$FIRMWARE_MK" 2>/dev/null; then
    # 已存在则移除 IMAGE_SIZE 限制 (大分区需要)
    sed -i '/define Device\/netcore_n60-pro/,/endef/ {/IMAGE_SIZE/d}' "$FIRMWARE_MK"
    echo "  [OK] 设备定义已存在, 已移除 IMAGE_SIZE 限制"
else
    # 不存在则添加完整定义
    cat >> "$FIRMWARE_MK" << 'EOF'

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
EOF
    echo "  [OK] 设备定义已添加"
fi

# ==================================================================
# 3. 克隆第三方软件包
# ==================================================================
echo ""
echo "--- 3. 克隆第三方软件包 ---"

# 定义要克隆的仓库: 目标目录=仓库地址
# 使用数组遍历, 避免重复代码
declare -A REPOS=(
    ["package/luci-app-easytier"]="https://github.com/EasyTier/luci-app-easytier.git"
    ["package/luci-theme-argon"]="https://github.com/jerrykuku/luci-theme-argon.git"
    ["package/luci-app-argon-config"]="https://github.com/jerrykuku/luci-app-argon-config.git"
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
# 4. ddns-go - 下载预编译二进制到 files/ 目录
#    (不用 OpenWrt 包系统, 直接放二进制最可靠, 避免 Go 交叉编译问题)
# ==================================================================
echo ""
echo "--- 4. ddns-go 主程序 ---"

# files/ 目录是 OpenWrt 的"直接覆盖层", 里面的文件会原样放到固件根文件系统
mkdir -p files/usr/bin files/etc/init.d

# 自动获取最新版本
DDNS_VER=""
API_JSON=$(curl -fsSL --connect-timeout 10 "https://api.github.com/repos/jeessy2/ddns-go/releases/latest" 2>/dev/null) || true
if [ -n "$API_JSON" ]; then
    DDNS_VER=$(echo "$API_JSON" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name":\s*"\([^"]*\)".*/\1/' | tr -d ' ')
fi

# API 失败用默认版本兜底
if [ -z "$DDNS_VER" ]; then
    DDNS_VER="v6.17.7"
    echo "  版本获取失败, 使用默认: $DDNS_VER"
else
    echo "  最新版本: $DDNS_VER"
fi

# 文件名不带 v, URL 路径带 v
VER_NO_V="${DDNS_VER#v}"
DL_FILE="ddns-go_${VER_NO_V}_linux_arm64.tar.gz"
DL_URL="https://github.com/jeessy2/ddns-go/releases/download/${DDNS_VER}/${DL_FILE}"

# 下载 (失败不中断编译, 只是固件里没有 ddns-go)
if [ ! -f "files/usr/bin/ddns-go" ]; then
    echo "  下载中..."
    curl -fSL --connect-timeout 20 --retry 2 -o "/tmp/$DL_FILE" "$DL_URL" || true
    if [ -s "/tmp/$DL_FILE" ]; then
        tar -xzf "/tmp/$DL_FILE" -C /tmp/ ddns-go 2>/dev/null
        if [ -f "/tmp/ddns-go" ]; then
            cp "/tmp/ddns-go" files/usr/bin/ddns-go
            chmod +x files/usr/bin/ddns-go
            echo "  [OK] 已放入 files/usr/bin/ddns-go"
        else
            echo "  [警告] 解压后未找到二进制"
        fi
        rm -f "/tmp/$DL_FILE" "/tmp/ddns-go"
    else
        echo "  [警告] 下载失败, 固件将不包含 ddns-go"
    fi
else
    echo "  [跳过] 已存在"
fi

# init 启动脚本 (procd 托管, 开机自启, 默认监听 9876)
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
# 5. ddns-go - 处理 LuCI 界面
#    sirpdboy 的仓库里有 ddns-go 子包(尝试源码编译), 需要删掉它
#    同时移除 Makefile 里对 ddns-go 包的依赖
# ==================================================================
echo ""
echo "--- 5. ddns-go LuCI 界面 ---"

DDNS_LUCI_DIR="package/luci-app-ddns-go"

if [ -d "$DDNS_LUCI_DIR" ]; then
    # 删除 ddns-go 子包 (我们已经在 files/ 里放了二进制)
    if [ -d "$DDNS_LUCI_DIR/ddns-go" ]; then
        rm -rf "$DDNS_LUCI_DIR/ddns-go"
        echo "  [OK] 已删除 ddns-go 子包"
    fi

    # 移除 Makefile 中的 +ddns-go 依赖
    MK="$DDNS_LUCI_DIR/Makefile"
    if [ -f "$MK" ]; then
        sed -i 's/+ddns-go//g; s/DEPENDS:= /DEPENDS:=/; s/  */ /g' "$MK"
        echo "  [OK] 已移除 ddns-go 包依赖"
    fi
else
    echo "  [跳过] luci-app-ddns-go 不存在"
fi

# ==================================================================
# 完成
# ==================================================================
echo ""
echo "============================================================"
echo "  DIY Part 1 完成!"
echo "  DTS:  2GB 内存 + 无 NMBM + 506.5MB UBI"
echo "  设备: netcore_n60-pro"
echo "  包:   EasyTier, argon 主题, ddns-go(主程序+界面)"
echo "============================================================"
