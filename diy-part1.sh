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
# sirpdboy 的 luci-app-ddns-go 仓库自带了 ddns-go 源码编译子包,
# 它尝试从 Go 源码交叉编译, 但 GitHub Actions 环境不支持, 会失败.
# 解决方案: 克隆后替换 ddns-go/Makefile 为预编译二进制下载版本.
# ------------------------------------------------------------
echo ""
echo "--- 5.1 克隆 luci-app-ddns-go (含 ddns-go 子包) ---"

if [ -d "package/luci-app-ddns-go" ]; then
    echo "  luci-app-ddns-go 已存在, 跳过克隆"
else
    git clone --depth 1 https://github.com/sirpdboy/luci-app-ddns-go.git package/luci-app-ddns-go
    echo "  luci-app-ddns-go 已添加"
fi

echo ""
echo "--- 5.2 替换 ddns-go Makefile (预编译二进制, 不从源码编译) ---"

DDNS_GO_SUBDIR="package/luci-app-ddns-go/ddns-go"

if [ -d "$DDNS_GO_SUBDIR" ]; then
    # 备份原 Makefile
    cp "$DDNS_GO_SUBDIR/Makefile" "$DDNS_GO_SUBDIR/Makefile.orig" 2>/dev/null || true

    # 获取原 Makefile 中的版本号
    OLD_VER=$(grep -m1 'PKG_VERSION' "$DDNS_GO_SUBDIR/Makefile" 2>/dev/null | sed 's/.*:=\s*//' | tr -d ' \r\n"')
    if [ -z "$OLD_VER" ]; then
        OLD_VER="v6.7.2"
    fi
    echo "  原 Makefile 版本: $OLD_VER"

    # 确保有 init 脚本
    mkdir -p "$DDNS_GO_SUBDIR/files"
    if [ ! -f "$DDNS_GO_SUBDIR/files/ddns-go.init" ]; then
        cat > "$DDNS_GO_SUBDIR/files/ddns-go.init" << 'INIT_EOF'
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
        chmod +x "$DDNS_GO_SUBDIR/files/ddns-go.init"
        echo "  创建了 init 脚本"
    fi

    # 用预编译二进制版本替换 Makefile (引号 heredoc, 全部字面量)
    cat > "$DDNS_GO_SUBDIR/Makefile" << 'DDNS_GO_MK'
include $(TOPDIR)/rules.mk

PKG_NAME:=ddns-go
PKG_VERSION:=__DDNSGO_VER__
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)_$(PKG_VERSION)_linux_arm64.tar.gz
PKG_SOURCE_URL:=https://github.com/jeessy2/ddns-go/releases/download/$(PKG_VERSION)/
PKG_HASH:=skip

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=DDNS
  TITLE:=Simple and easy-to-use DDNS tool
  URL:=https://github.com/jeessy2/ddns-go
  DEPENDS:=+ca-bundle
endef

define Package/$(PKG_NAME)/description
  Simple and easy-to-use DDNS tool.
  Supports Alibaba Cloud, Tencent Cloud, Cloudflare and 50+ providers.
endef

define Build/Prepare
  mkdir -p $(PKG_BUILD_DIR)
  tar -xzf $(DL_DIR)/$(PKG_SOURCE) -C $(PKG_BUILD_DIR)
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
  $(INSTALL_DIR) $(1)/usr/bin
  $(INSTALL_BIN) $(PKG_BUILD_DIR)/ddns-go $(1)/usr/bin/ddns-go
  $(INSTALL_DIR) $(1)/etc/init.d
  $(INSTALL_BIN) ./files/ddns-go.init $(1)/etc/init.d/ddns-go
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
DDNS_GO_MK

    # 替换版本号占位符
    sed -i "s/__DDNSGO_VER__/${OLD_VER}/" "$DDNS_GO_SUBDIR/Makefile"

    echo "  ddns-go Makefile 已替换为预编译二进制下载版本"
    echo "  版本: ${OLD_VER}"
else
    echo "  [警告] ddns-go 子目录不存在, sirpdboy 仓库结构可能已变化"
    echo "  将创建独立的 ddns-go 包..."

    mkdir -p package/ddns-go/files
    cat > package/ddns-go/Makefile << 'FALLBACK_MK'
include $(TOPDIR)/rules.mk

PKG_NAME:=ddns-go
PKG_VERSION:=v6.7.2
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)_$(PKG_VERSION)_linux_arm64.tar.gz
PKG_SOURCE_URL:=https://github.com/jeessy2/ddns-go/releases/download/$(PKG_VERSION)/
PKG_HASH:=skip

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=DDNS
  TITLE:=Simple and easy-to-use DDNS tool
  URL:=https://github.com/jeessy2/ddns-go
  DEPENDS:=+ca-bundle
endef

define Package/$(PKG_NAME)/description
  Simple and easy-to-use DDNS tool.
endef

define Build/Prepare
  mkdir -p $(PKG_BUILD_DIR)
  tar -xzf $(DL_DIR)/$(PKG_SOURCE) -C $(PKG_BUILD_DIR)
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
  $(INSTALL_DIR) $(1)/usr/bin
  $(INSTALL_BIN) $(PKG_BUILD_DIR)/ddns-go $(1)/usr/bin/ddns-go
  $(INSTALL_DIR) $(1)/etc/init.d
  $(INSTALL_BIN) ./files/ddns-go.init $(1)/etc/init.d/ddns-go
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
FALLBACK_MK

    cat > package/ddns-go/files/ddns-go.init << 'INIT_FALLBACK'
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
INIT_FALLBACK
    chmod +x package/ddns-go/files/ddns-go.init
    echo "  独立 ddns-go 包已创建 (备用方案)"
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
