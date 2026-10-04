#!/bin/bash
# ============================================================================
#  DIY Part 2 - 生成 .config (feeds 安装后执行)
#  内容: 加载模板 / 选设备 / 加内核选项 / 选软件包 / 精简 / 验证
# ============================================================================
set -e

echo "============================================================"
echo "  DIY Part 2: 生成 .config"
echo "============================================================"

# ============================================================================
# 1. 基础配置 + 设备选择
# ============================================================================
echo ""
echo "--- 1. 基础配置 ---"

# 加载高功率 WiFi 模板
cp -f defconfig/mt7975-ipailna-high-power.config .config
echo "  [OK] 模板: mt7975-ipailna-high-power.config"

# 禁用其他设备, 只编译 N60 Pro
for dev in glinet_gl-mt6000 jdcloud_re-cp-03 tplink_tl-xdr6086 tplink_tl-xdr6088 \
           xiaomi_redmi-router-ax6000-ubootmod xiaomi_redmi-router-ax6000-stock \
           ruijie_rg-x60-pro ruijie_rg-x60-new ruijie_ew-6000gx-pro; do
    for fmt in mediatek_filogic mediatek_mt7986; do
        sed -i "s/^CONFIG_TARGET_DEVICE_${fmt}_DEVICE_${dev}=y/# CONFIG_TARGET_DEVICE_${fmt}_DEVICE_${dev} is not set/" .config 2>/dev/null || true
        sed -i "s/^CONFIG_TARGET_DEVICE_PACKAGES_${fmt}_DEVICE_${dev}=/# CONFIG_TARGET_DEVICE_PACKAGES_${fmt}_DEVICE_${dev} is not set/" .config 2>/dev/null || true
    done
done

# 启用 N60 Pro
cat >> .config << 'EOF'
CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_netcore_n60-pro=y
CONFIG_TARGET_DEVICE_PACKAGES_mediatek_filogic_DEVICE_netcore_n60-pro=""
CONFIG_TARGET_DEVICE_mediatek_mt7986_DEVICE_netcore_n60-pro=y
CONFIG_TARGET_DEVICE_PACKAGES_mediatek_mt7986_DEVICE_netcore_n60-pro=""
EOF
echo "  [OK] 仅启用 N60 Pro 设备"

# ============================================================================
# 2. daed eBPF 内核选项
# ============================================================================
echo ""
echo "--- 2. daed eBPF 内核选项 ---"
cat >> .config << 'EOF'
CONFIG_DEVEL=y
CONFIG_KERNEL_DEBUG_INFO=y
# CONFIG_KERNEL_DEBUG_INFO_REDUCED is not set
CONFIG_KERNEL_DEBUG_INFO_BTF=y
CONFIG_KERNEL_CGROUPS=y
CONFIG_KERNEL_CGROUP_BPF=y
CONFIG_KERNEL_BPF_EVENTS=y
CONFIG_XDP_SOCKETS=y
CONFIG_BPF_TOOLCHAIN_HOST=y
CONFIG_PACKAGE_kmod-xdp-sockets-diag=y
EOF
echo "  [OK] DEVEL + BTF + cgroup + BPF + XDP + LLVM"

# ============================================================================
# 3. 第一次 defconfig
# ============================================================================
echo ""
echo "--- 3. 第一次 defconfig ---"
make defconfig
echo "  [OK] 完成"

# ============================================================================
# 4. 新增软件包
# ============================================================================
echo ""
echo "--- 4. 新增软件包 ---"

cat >> .config << 'EOF'

# daed (eBPF 透明代理, kenzok8 版, 只装本体)
CONFIG_PACKAGE_daed=y

# EasyTier (虚拟局域网)
CONFIG_PACKAGE_easytier=y
CONFIG_PACKAGE_luci-app-easytier=y

# ddns-go (动态域名)
CONFIG_PACKAGE_ddns-go=y
CONFIG_PACKAGE_luci-app-ddns-go=y

# Samba4 + wsdd2 (USB存储自动共享)
CONFIG_PACKAGE_samba4-server=y
CONFIG_PACKAGE_luci-app-samba4=y
CONFIG_PACKAGE_wsdd2=y
CONFIG_PACKAGE_block-mount=y
CONFIG_PACKAGE_kmod-fs-exfat=y
CONFIG_PACKAGE_kmod-fs-vfat=y
CONFIG_PACKAGE_kmod-fs-ntfs3=y
CONFIG_PACKAGE_ntfs3-mount=y
CONFIG_PACKAGE_kmod-usb-storage=y
CONFIG_PACKAGE_kmod-usb-storage-extras=y
CONFIG_PACKAGE_kmod-usb-storage-uas=y

# 流量统计: vnstat2 + nlbwmon
CONFIG_PACKAGE_vnstat2=y
CONFIG_PACKAGE_vnstat2-image=y
CONFIG_PACKAGE_luci-app-vnstat2=y
CONFIG_PACKAGE_nlbwmon=y
CONFIG_PACKAGE_luci-app-nlbwmon=y

# 主题 + 网页终端
CONFIG_PACKAGE_luci-theme-argon=y
CONFIG_PACKAGE_ttyd=y
CONFIG_PACKAGE_luci-app-ttyd=y

EOF
echo "  [OK] daed / EasyTier / ddns-go / Samba4 / wsdd2 / vnstat2 / nlbwmon / argon / ttyd"

# ============================================================================
# 5. rootfs 分区大小
# ============================================================================
echo ""
echo "--- 5. rootfs 分区大小 ---"
echo 'CONFIG_TARGET_ROOTFS_PARTSIZE=70' >> .config
echo "  [OK] 70MB (overlay ~430MB 可用)"

# ============================================================================
# 6. 第二次 defconfig (补齐依赖)
# ============================================================================
echo ""
echo "--- 6. 第二次 defconfig ---"
make defconfig
echo "  [OK] 完成"

# ============================================================================
# 7. 精简 (只删被替代的 wrtbwmon)
# ============================================================================
echo ""
echo "--- 7. 精简固件 ---"

REMOVE_COUNT=0
remove_pkg() {
    if grep -q "^CONFIG_PACKAGE_${1}=y" .config 2>/dev/null; then
        sed -i "s/^CONFIG_PACKAGE_${1}=y/# CONFIG_PACKAGE_${1} is not set/" .config
        REMOVE_COUNT=$((REMOVE_COUNT + 1))
    fi
}

# wrtbwmon → vnstat2 + nlbwmon 替代
for pkg in luci-app-wrtbwmon wrtbwmon luci-i18n-wrtbwmon-zh-cn; do
    remove_pkg "$pkg"
done
echo "  [A] 被替代: wrtbwmon (→ vnstat2 + nlbwmon)"
echo "  合计移除: ${REMOVE_COUNT} 个包"

# ============================================================================
# 8. 输出包列表
# ============================================================================
echo ""
echo "--- 8. 输出包列表 ---"

PKG_LIST="package-list.txt"
grep "^CONFIG_PACKAGE_.*=y" .config \
    | sed 's/^CONFIG_PACKAGE_//' \
    | sed 's/=y$//' \
    | sort \
    > "$PKG_LIST"

TOTAL_PKGS=$(wc -l < "$PKG_LIST")
echo "  [OK] 共 ${TOTAL_PKGS} 个包, 已写入 ${PKG_LIST}"
echo ""
echo "  LuCI 应用: $(grep -c '^luci-app-' "$PKG_LIST") 个"
echo "  LuCI 主题: $(grep -c '^luci-theme-' "$PKG_LIST") 个"
echo "  内核模块: $(grep -c '^kmod-' "$PKG_LIST") 个"
echo "  其他包:   $(grep -cv -e '^luci-' -e '^kmod-' "$PKG_LIST") 个"

# ============================================================================
# 9. 验证
# ============================================================================
echo ""
echo "=== 验证 ==="

MISSING=0
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
for p in daed \
         ddns-go luci-app-ddns-go \
         easytier luci-app-easytier \
         samba4-server luci-app-samba4 wsdd2 \
         vnstat2 luci-app-vnstat2 nlbwmon luci-app-nlbwmon \
         luci-theme-argon ttyd luci-app-ttyd; do
    require_pkg "$p"
done

echo ""
echo "[核心功能 (确保没被误删)]"
for p in kmod-mt_wifi kmod-mediatek_hnat kmod-tun kmod-tcp-bbr \
         kmod-usb-storage kmod-fs-ext4 kmod-fs-exfat kmod-fs-ntfs3 \
         block-mount ppp ppp-mod-pppoe \
         kmod-nls-base kmod-nls-utf8 libopenssl; do
    require_pkg "$p"
done

if [ "$MISSING" -gt 0 ]; then
    echo ""
    echo "=============================================="
    echo "  [错误] ${MISSING} 个关键包缺失!"
    echo "  已终止, 请检查配置后重试。"
    echo "=============================================="
    exit 1
fi

echo ""
echo "[精简的包]"
for p in luci-app-wrtbwmon wrtbwmon; do
    if grep -q "CONFIG_PACKAGE_${p} is not set" .config 2>/dev/null; then
        echo "  [OK] ${p}: 已移除"
    else
        echo "  [--] ${p}: 不在配置中"
    fi
done

echo ""
echo "[分区大小]"
grep "CONFIG_TARGET_ROOTFS_PARTSIZE" .config

echo ""
echo "  [全部通过] 验证完成"

# ============================================================================
# 完成
# ============================================================================
echo ""
echo "============================================================"
echo "  DIY Part 2 完成!"
echo "============================================================"
echo "  新增: daed (kenzok8版, 仅本体) / EasyTier / ddns-go"
echo "        samba4 / wsdd2"
echo "        vnstat2 / nlbwmon / argon / ttyd"
echo "        USB存储支持 (ext4/exFAT/NTFS3/VFAT)"
echo "  精简: 移除 ${REMOVE_COUNT} 个包 (wrtbwmon 系列)"
echo "  总包数: ${TOTAL_PKGS} 个"
echo "  CPU频率: mtk-cpufreq + cpuinfo 脚本"
echo "  rootfs: 70MB (overlay ~430MB)"
echo "============================================================"
