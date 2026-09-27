#!/bin/bash
# ============================================================================
# DIY 脚本 Part 1 - 源码修改 (在 feeds 更新之前执行)
# 功能:
#   1. 修改 DTS 设备树: 内存改为 2GB, 移除 NMBM, UBI 分区改为 506.5MB
#   2. 检查/添加 netcore_n60-pro 设备定义到 filogic.mk
#   3. 添加 EasyTier 软件包
#   4. 添加 luci-theme-argon 主题 (含配置工具)
# ============================================================================
set -e

echo "============================================================"
echo "  DIY Part 1: 源码修改"
echo "  目标: N60 Pro 512MB 闪存 + 2GB 内存"
echo "============================================================"

# ------------------------------------------------------------
# 1. 修改 DTS 设备树文件
# ------------------------------------------------------------
DTS_FILE="target/linux/mediatek/dts/mt7986a-netcore-n60-pro.dts"

if [ ! -f "$DTS_FILE" ]; then
    echo "[错误] DTS 文件不存在: $DTS_FILE"
    echo "请检查源码是否正确克隆"
    exit 1
fi

echo ""
echo "--- 1.1 修改内存大小: 512MB -> 2GB ---"
sed -i 's/0x40000000 0 0x20000000/0x40000000 0 0x80000000/' "$DTS_FILE"
echo "  内存已改为 2GB"

echo ""
echo "--- 1.2 移除 NMBM ---"
sed -i '/mediatek,nmbm;/d' "$DTS_FILE"
sed -i '/mediatek,bmt-max-ratio/d' "$DTS_FILE"
sed -i '/mediatek,bmt-max-reserved-blocks/d' "$DTS_FILE"
echo "  NMBM 已移除"

echo ""
echo "--- 1.3 修改 UBI 分区大小: 128MB -> 506.5MB ---"
sed -i 's/0x0580000 0x7280000/0x0580000 0x1FA80000/' "$DTS_FILE"
echo "  UBI 分区已改为 506.5MB"

echo ""
echo "--- 1.4 验证 DTS 修改结果 ---"
echo "  [内存] $(grep 'memory@' -A1 "$DTS_FILE" | grep 'reg')"
echo "  [NMBM] $(grep -c 'nmbm' "$DTS_FILE" || echo 0) 处残留 (应为0)"
echo "  [UBI]  $(grep -A2 'label = "ubi"' "$DTS_FILE" | grep 'reg')"

# ------------------------------------------------------------
# 2. 检查/添加 netcore_n60-pro 设备定义
# ------------------------------------------------------------
FIRMWARE_MK="target/linux/mediatek/image/filogic.mk"

echo ""
echo "--- 2.1 检查 netcore_n60-pro 设备定义 ---"

if grep -q "define Device/netcore_n60-pro" "$FIRMWARE_MK" 2>/dev/null; then
    echo "  设备定义已存在, 移除 IMAGE_SIZE 限制..."
    sed -i '/define Device\/netcore_n60-pro/,/endef/ {/IMAGE_SIZE/d}' "$FIRMWARE_MK"
    echo "  IMAGE_SIZE 已移除"
else
    echo "  设备定义不存在, 正在添加..."
    cat >> "$FIRMWARE_MK" << 'DEVICE_DEF'

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
DEVICE_DEF
    echo "  设备定义已添加"
fi

# ------------------------------------------------------------
# 3. 添加 EasyTier 软件包
# ------------------------------------------------------------
echo ""
echo "--- 3.1 添加 EasyTier ---"

if [ -d "package/luci-app-easytier" ]; then
    echo "  EasyTier 已存在, 跳过"
else
    git clone --depth 1 https://github.com/EasyTier/luci-app-easytier.git package/luci-app-easytier
    echo "  EasyTier 已添加"
fi

# ------------------------------------------------------------
# 4. 添加 luci-theme-argon 主题
# ------------------------------------------------------------
echo ""
echo "--- 4.1 添加 luci-theme-argon 主题 ---"

if [ -d "package/luci-theme-argon" ]; then
    echo "  luci-theme-argon 已存在, 跳过"
else
    git clone --depth 1 https://github.com/jerrykuku/luci-theme-argon.git package/luci-theme-argon
    echo "  luci-theme-argon 已添加"
fi

if [ -d "package/luci-app-argon-config" ]; then
    echo "  luci-app-argon-config 已存在, 跳过"
else
    git clone --depth 1 https://github.com/jerrykuku/luci-app-argon-config.git package/luci-app-argon-config
    echo "  luci-app-argon-config 已添加"
fi

# ------------------------------------------------------------
# 5. 添加 ddns-go (主程序 + LuCI 界面)
# ------------------------------------------------------------
# 方案: 主程序二进制直接放到 files/ 目录 (绕过包编译系统, 最可靠)
#       LuCI 界面从 sirpdboy 克隆, 修改 Makefile 移除对 ddns-go 包的依赖
# ------------------------------------------------------------
echo ""
echo "--- 5.1 下载 ddns-go 预编译二进制到 files/ 目录 ---"

# 自动获取最新版本号 (从 GitHub API)
# ddns-go 文件名格式: ddns-go_6.17.7_linux_arm64.tar.gz (文件名里不带 v)
# URL 路径格式: /download/v6.17.7/ (路径里带 v)
DDNS_GO_VER=""
LATEST_JSON=$(curl -fsSL --connect-timeout 15 "https://api.github.com/repos/jeessy2/ddns-go/releases/latest" 2>/dev/null) || true
if [ -n "$LATEST_JSON" ]; then
    DDNS_GO_VER=$(echo "$LATEST_JSON" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name":\s*"\([^"]*\)".*/\1/' | tr -d ' ')
fi

# 如果 API 获取失败, 使用默认版本兜底
if [ -z "$DDNS_GO_VER" ]; then
    DDNS_GO_VER="v6.17.7"
    echo "  无法获取最新版本, 使用默认: $DDNS_GO_VER"
else
    echo "  最新版本: $DDNS_GO_VER"
fi

DDNS_GO_VER_NO_V="${DDNS_GO_VER#v}"  # 去掉 v 前缀
DDNS_GO_FILE="ddns-go_${DDNS_GO_VER_NO_V}_linux_arm64.tar.gz"
DDNS_GO_URL="https://github.com/jeessy2/ddns-go/releases/download/${DDNS_GO_VER}/${DDNS_GO_FILE}"

mkdir -p files/usr/bin files/etc/init.d files/etc/config

if [ -f "files/usr/bin/ddns-go" ]; then
    echo "  ddns-go 二进制已存在, 跳过下载"
else
    echo "  正在下载 ddns-go ${DDNS_GO_VER} ..."
    echo "  URL: ${DDNS_GO_URL}"
    curl -fSL --connect-timeout 30 --retry 3 -o "/tmp/${DDNS_GO_FILE}" "${DDNS_GO_URL}" || true
    if [ -f "/tmp/${DDNS_GO_FILE}" ] && [ -s "/tmp/${DDNS_GO_FILE}" ]; then
        tar -xzf "/tmp/${DDNS_GO_FILE}" -C /tmp/ 2>/dev/null
        if [ -f "/tmp/ddns-go" ]; then
            cp "/tmp/ddns-go" files/usr/bin/ddns-go
            chmod +x files/usr/bin/ddns-go
            echo "  ddns-go 已放入 files/usr/bin/ddns-go"
            file files/usr/bin/ddns-go | head -1
        else
            echo "  [警告] 解压后未找到 ddns-go 二进制"
        fi
        rm -f "/tmp/${DDNS_GO_FILE}" "/tmp/ddns-go" "/tmp/README.md" "/tmp/LICENSE" 2>/dev/null
    else
        echo "  [警告] ddns-go 下载失败, 固件将不包含 ddns-go 主程序"
        echo "  (不影响其他功能, 编译继续)"
    fi
fi

# 创建 init 启动脚本
if [ ! -f "files/etc/init.d/ddns-go" ]; then
    cat > files/etc/init.d/ddns-go << 'INIT_EOF'
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
INIT_EOF
    chmod +x files/etc/init.d/ddns-go
    echo "  init 脚本已创建"
fi

echo ""
echo "--- 5.2 克隆 luci-app-ddns-go (仅界面) ---"

if [ -d "package/luci-app-ddns-go" ]; then
    echo "  luci-app-ddns-go 已存在, 跳过克隆"
else
    git clone --depth 1 https://github.com/sirpdboy/luci-app-ddns-go.git package/luci-app-ddns-go
    echo "  luci-app-ddns-go 已添加"
fi

echo ""
echo "--- 5.3 修改 luci-app-ddns-go: 移除 ddns-go 依赖 + 删除 ddns-go 子包 ---"

# 删除 ddns-go 子包 (它会尝试从源码编译, 我们已经在 files/ 里放了二进制)
if [ -d "package/luci-app-ddns-go/ddns-go" ]; then
    rm -rf "package/luci-app-ddns-go/ddns-go"
    echo "  已删除 ddns-go 子包 (主程序已在 files/ 中)"
fi

# 修改 luci-app-ddns-go 的 Makefile, 移除对 ddns-go 包的依赖
LUCI_DDNS_MAKEFILE="package/luci-app-ddns-go/Makefile"
if [ -f "$LUCI_DDNS_MAKEFILE" ]; then
    # 移除 DEPENDS 中的 +ddns-go
    sed -i 's/+ddns-go//g' "$LUCI_DDNS_MAKEFILE"
    # 清理多余空格
    sed -i 's/DEPENDS:= /DEPENDS:=/' "$LUCI_DDNS_MAKEFILE"
    sed -i 's/  */ /g' "$LUCI_DDNS_MAKEFILE"
    echo "  已移除 luci-app-ddns-go 对 ddns-go 包的依赖"
    grep 'DEPENDS' "$LUCI_DDNS_MAKEFILE" | head -1
fi

# ------------------------------------------------------------
# 完成
# ------------------------------------------------------------
echo ""
echo "============================================================"
echo "  DIY Part 1 完成!"
echo "  - DTS: 2GB 内存 + 无 NMBM + 506.5MB UBI"
echo "  - 设备: netcore_n60-pro 已就绪"
echo "  - 包: EasyTier, luci-theme-argon, ddns-go(主程序+LuCI)"
echo "  - 其他 sirpdboy 软件: 不编译, 日后通过 opkg 安装"
echo "============================================================"
