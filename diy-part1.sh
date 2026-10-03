#!/bin/bash
# ============================================================================
#  DIY Part 1 - 源码修改 (feeds 更新前执行)
#  内容: DTS修改 / 设备定义 / 第三方包克隆 / files/ 自定义文件
# ============================================================================
set -e

echo "============================================================"
echo "  DIY Part 1: 源码修改"
echo "============================================================"

# ============================================================================
# 1. 检测平台文件路径
# ============================================================================
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

[ -z "$FIRMWARE_MK" ] && for f in \
    "target/linux/mediatek/image/mt7986.mk" \
    "target/linux/mediatek/image/filogic.mk"; do
    [ -f "$f" ] && FIRMWARE_MK="$f" && break
done

DTS_BASE=$(basename "$DTS_FILE" .dts 2>/dev/null || echo "mt7986a-netcore-n60-pro")

echo ""
echo "--- 1. 平台检测 ---"
echo "  DTS: $DTS_FILE"
echo "  MK : $FIRMWARE_MK"
[ -z "$DTS_FILE" ] && echo "  [错误] 未找到 DTS 文件!" && exit 1
[ -z "$FIRMWARE_MK" ] && echo "  [错误] 未找到固件 MK 文件!" && exit 1

# ============================================================================
# 2. DTS 修改
# ============================================================================
echo ""
echo "--- 2. DTS 修改 ---"

# 2A. 内存: 512MB → 2GB
if grep -q '0x40000000 0 0x20000000' "$DTS_FILE"; then
    sed -i 's/0x40000000 0 0x20000000/0x40000000 0 0x80000000/' "$DTS_FILE"
    echo "  [OK] 内存: 512MB → 2GB"
else
    echo "  [跳过] 内存已是 2GB 或格式不同"
fi

# 2B. 移除 NMBM (释放 32MB 空间)
if grep -q 'nmbm\|bmt-max' "$DTS_FILE" 2>/dev/null; then
    sed -i '/mediatek,nmbm;/d; /mediatek,bmt-max-ratio/d; /mediatek,bmt-max-reserved-blocks/d' "$DTS_FILE"
    echo "  [OK] 移除 NMBM"
else
    echo "  [跳过] 无 NMBM"
fi

# 2C. UBI 分区: 128MB → 506.5MB
if grep -q '0x7280000' "$DTS_FILE"; then
    sed -i 's/ 0x7280000/ 0x1FA80000/g' "$DTS_FILE"
    echo "  [OK] UBI 分区: 128MB → 506.5MB"
else
    echo "  [跳过] 未找到 128MB 分区定义"
fi

# ============================================================================
# 3. 设备定义
# ============================================================================
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
    echo "  [OK] 已添加 N60 Pro 设备定义"
fi

# ============================================================================
# 4. 克隆第三方软件包
# ============================================================================
echo ""
echo "--- 4. 克隆第三方包 ---"

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

# luci-app-easytier: feed 里没有
clone_repo "package/luci-app-easytier" "https://github.com/EasyTier/luci-app-easytier.git" || true

# ============================================================================
# 5. 系统优化 (files/ 目录)
# ============================================================================
echo ""
echo "--- 5. 系统优化 ---"

# 5.1 BBR 拥塞控制
# 全部通过 uci-defaults 实现: 加载模块 + 设置sysctl + 写配置文件(持久化)
# 不使用 modules-boot.d / sysctl.d 文件方式, 避免时序问题
echo "  [OK] BBR 拥塞控制 (通过 uci-defaults 设置)"

# 5.2 CPU 频率显示 (mtk-cpufreq + cpuinfo)
mkdir -p files/usr/bin files/sbin

if [ -f "$GITHUB_WORKSPACE/mtk-cpufreq" ]; then
    cp "$GITHUB_WORKSPACE/mtk-cpufreq" files/usr/bin/mtk-cpufreq
    chmod +x files/usr/bin/mtk-cpufreq
    echo "  [OK] mtk-cpufreq"
else
    echo "  [警告] 未找到 mtk-cpufreq"
fi

cat > files/sbin/cpuinfo << 'CPUINFO'
#!/bin/sh
# 自定义 cpuinfo - 在原始架构信息后追加 CPU 型号/频率/温度
# 输出格式: "ARMv8 Processor rev 4 (v8l) x 4 (MT7986A @ 2.30GHz 48.2°C)"

# 1. 读取原始架构信息
HW_INFO=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^ *//')
[ -z "$HW_INFO" ] && HW_INFO=$(grep -m1 "Hardware" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^ *//')
[ -z "$HW_INFO" ] && HW_INFO="ARMv8 Processor"

# 2. 核心数
CORES=$(grep -c "processor" /proc/cpuinfo 2>/dev/null || echo 4)

# 3. mtk-cpufreq 读取型号和频率
MTK_INFO=""
if command -v mtk-cpufreq >/dev/null 2>&1; then
    MTK_INFO=$(mtk-cpufreq 2>/dev/null | head -1 | tr -d '\r')
fi

# 4. 温度
TEMP=""
for i in 0 1 2; do
    t=$(cat /sys/class/thermal/thermal_zone${i}/temp 2>/dev/null)
    [ -n "$t" ] && TEMP=$t && break
done
[ -n "$TEMP" ] && TEMP=$(awk "BEGIN {printf \"%.1f\", $TEMP/1000}")

# 5. 拼接输出 (原始架构信息 + 括号内追加 CPU/频率/温度)
if [ -n "$MTK_INFO" ] && [ -n "$TEMP" ]; then
    echo "${HW_INFO} x ${CORES} (${MTK_INFO} ${TEMP}°C)"
elif [ -n "$MTK_INFO" ]; then
    echo "${HW_INFO} x ${CORES} (${MTK_INFO})"
else
    echo "${HW_INFO} x ${CORES}"
fi
CPUINFO
chmod +x files/sbin/cpuinfo
echo "  [OK] cpuinfo 脚本"

# 5.3 uci-defaults 初始化
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-custom-settings << 'UCIEOF'
#!/bin/sh
# 首次启动执行一次, 执行后自动删除

# BBR 拥塞控制 (通过 turboacc 配置启用, 防止被 turboacc 覆盖)
uci set turboacc.config.bbr_cca='1'
uci commit turboacc
logger -t uci-defaults "BBR 拥塞控制: 已通过 turboacc 启用"

# IPK 软件源改为中科大镜像
# 默认源: mirrors.vsean.net/openwrt → 中科大: mirrors.ustc.edu.cn/immortalwrt
if [ -f /etc/opkg/distfeeds.conf ]; then
    sed -i 's|mirrors.vsean.net/openwrt|mirrors.ustc.edu.cn/immortalwrt|g' /etc/opkg/distfeeds.conf
    logger -t uci-defaults "IPK 软件源已切换为中科大镜像"
fi

# Samba4: 多通道 + 访客访问
if uci get samba4.@samba4[0] >/dev/null 2>&1; then
    uci set samba4.@samba4[0].enable_multichannel='1'
    uci set samba4.@samba4[0].disable_netbios='0'
    uci set samba4.@samba4[0].allow_guest='1'
    uci commit samba4
fi

# ttyd: LAN 免登录
if uci get ttyd.@ttyd[0] >/dev/null 2>&1; then
    uci set ttyd.@ttyd[0].interface='@lan'
    uci set ttyd.@ttyd[0].command='/bin/login -f root'
    uci commit ttyd
fi

# 默认 LAN IP
uci set network.lan.ipaddr='10.10.6.1'
uci set network.lan.netmask='255.255.255.0'
uci commit network

# 主机名
uci set system.@system[0].hostname='N60_Pro'
uci commit system

exit 0
UCIEOF
chmod +x files/etc/uci-defaults/99-custom-settings
echo "  [OK] uci-defaults (BBR + 主机名 + 中科大源 + Samba + ttyd + LAN IP)"

# 5.4 USB 磁盘自动共享 (hotplug + samba4)
mkdir -p files/etc/hotplug.d/block
cat > files/etc/hotplug.d/block/50-usb-samba << 'HPEOF'
#!/bin/sh
# USB 磁盘热插拔 - 自动添加/移除 Samba 共享
# 触发: block add/remove 事件

[ "$ACTION" = "add" -o "$ACTION" = "remove" ] || exit 0
[ -z "$DEVICENAME" ] && exit 0

# 只处理分区 (sda1, sdb2 等, 跳过整块盘 sda)
echo "$DEVICENAME" | grep -qE '[0-9]+$' || exit 0

MOUNT_POINT=""

# 查找挂载点
find_mount() {
    local dev="/dev/$1"
    while read -r line; do
        case "$line" in
            "$dev "*)
                echo "$line" | awk '{print $2}'
                return 0
                ;;
        esac
    done < /proc/mounts
    return 1
}

update_samba_share() {
    local action="$1"
    local name="$2"
    local path="$3"

    case "$action" in
        add)
            # 检查是否已存在同名共享
            if uci get "samba4.${name}" >/dev/null 2>&1; then
                return 0
            fi
            uci set "samba4.${name}=sambashare"
            uci set "samba4.${name}.name=${name}"
            uci set "samba4.${name}.path=${path}"
            uci set "samba4.${name}.read_only=no"
            uci set "samba4.${name}.guest_ok=yes"
            uci set "samba4.${name}.create_mask=0777"
            uci set "samba4.${name}.dir_mask=0777"
            uci commit samba4
            /etc/init.d/samba4 reload 2>/dev/null
            logger -t usb-samba "添加共享: ${name} -> ${path}"
            ;;
        remove)
            if uci get "samba4.${name}" >/dev/null 2>&1; then
                uci delete "samba4.${name}"
                uci commit samba4
                /etc/init.d/samba4 reload 2>/dev/null
                logger -t usb-samba "移除共享: ${name}"
            fi
            ;;
    esac
}

# 等几秒让挂载完成
if [ "$ACTION" = "add" ]; then
    sleep 3
fi

MOUNT_POINT=$(find_mount "$DEVICENAME")

if [ "$ACTION" = "add" ] && [ -n "$MOUNT_POINT" ]; then
    SHARE_NAME=$(basename "$MOUNT_POINT")
    [ -z "$SHARE_NAME" ] && SHARE_NAME="$DEVICENAME"
    update_samba_share "add" "$SHARE_NAME" "$MOUNT_POINT"
elif [ "$ACTION" = "remove" ]; then
    # 移除时可能已经卸载了, 用设备名反查共享名
    for s in $(uci show samba4 2>/dev/null | grep "=sambashare" | cut -d. -f2 | cut -d= -f1); do
        sp=$(uci get "samba4.${s}.path" 2>/dev/null)
        if echo "$sp" | grep -q "$DEVICENAME"; then
            update_samba_share "remove" "$s" "$sp"
        fi
    done
fi

exit 0
HPEOF
chmod +x files/etc/hotplug.d/block/50-usb-samba
echo "  [OK] USB 磁盘自动共享 (hotplug + samba4)"

# ============================================================================
# 完成
# ============================================================================
echo ""
echo "============================================================"
echo "  DIY Part 1 完成!"
echo "============================================================"
echo "  DTS: 内存 2GB / 无 NMBM / UBI 506.5MB"
echo "  第三方包: luci-app-easytier"
echo "  系统优化: BBR(uci-defaults) + CPU频率 + 中科大软件源"
echo "  USB存储: 自动挂载 + 自动Samba共享 + ext4/exFAT/NTFS3/VFAT"
echo "============================================================"
