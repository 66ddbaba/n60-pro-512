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
mkdir -p files/etc/modules.d files/etc/sysctl.d
echo "tcp_bbr" > files/etc/modules.d/tcp-bbr
cat > files/etc/sysctl.d/12-tcp-bbr.conf << 'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
echo "  [OK] BBR 拥塞控制"

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
# 自定义 cpuinfo - 配合 mtk-cpufreq 显示真实 CPU 频率
# 输出格式与 autocore 兼容, LuCI 能正确显示

# 1. CPU 型号和频率
MTK_INFO=""
if command -v mtk-cpufreq >/dev/null 2>&1; then
    MTK_INFO=$(mtk-cpufreq 2>/dev/null | head -1 | tr -d '\r')
fi

# 2. 温度
TEMP=""
for i in 0 1 2; do
    t=$(cat /sys/class/thermal/thermal_zone${i}/temp 2>/dev/null)
    [ -n "$t" ] && TEMP=$t && break
done
[ -n "$TEMP" ] && TEMP=$(awk "BEGIN {printf \"%.1f\", $TEMP/1000}")

# 3. 核心数
CORES=$(grep -c "processor" /proc/cpuinfo 2>/dev/null || echo 4)

# 4. 输出
if [ -n "$MTK_INFO" ] && [ -n "$TEMP" ]; then
    echo "${MTK_INFO} x ${CORES} (${TEMP}°C)"
elif [ -n "$MTK_INFO" ]; then
    echo "${MTK_INFO} x ${CORES}"
else
    echo "MediaTek MT7986A x ${CORES}"
fi
CPUINFO
chmod +x files/sbin/cpuinfo
echo "  [OK] cpuinfo 脚本"

# 5.3 uci-defaults 初始化
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-custom-settings << 'UCIEOF'
#!/bin/sh
# 首次启动执行一次, 执行后自动删除

# BBR 确保生效
modprobe tcp_bbr 2>/dev/null || true
sysctl -p /etc/sysctl.d/12-tcp-bbr.conf >/dev/null 2>&1 || true

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

exit 0
UCIEOF
chmod +x files/etc/uci-defaults/99-custom-settings
echo "  [OK] uci-defaults (BBR + Samba + ttyd + LAN IP)"

# 5.4 CIFS 自动重连
mkdir -p files/usr/bin
cat > files/usr/bin/cifs-reconnect << 'CREOF'
#!/bin/sh
# CIFS 自动重连 - 检测挂载僵死并自动恢复

# 读取所有 CIFS 挂载点
get_mount_points() {
    uci show cifs 2>/dev/null | grep "\.path=" | cut -d'=' -f2 | tr -d "'"
}

# 检查挂载是否正常 (5秒超时)
is_mount_healthy() {
    local mp="$1"
    [ -d "$mp" ] || return 1
    timeout 5 ls "$mp" >/dev/null 2>&1
    return $?
}

# 重新挂载单个共享
remount_share() {
    local cfg="$1"
    local server share path username password options

    server=$(uci get "cifs.${cfg}.server" 2>/dev/null)
    share=$(uci get "cifs.${cfg}.share" 2>/dev/null)
    path=$(uci get "cifs.${cfg}.path" 2>/dev/null)
    username=$(uci get "cifs.${cfg}.username" 2>/dev/null)
    password=$(uci get "cifs.${cfg}.password" 2>/dev/null)
    options=$(uci get "cifs.${cfg}.options" 2>/dev/null)

    [ -z "$server" ] || [ -z "$share" ] && return 1
    [ -z "$path" ] && path="/mnt/${cfg}"

    umount -l "$path" 2>/dev/null

    local opts=""
    [ -n "$username" ] && opts="${opts},username=${username}"
    [ -n "$password" ] && opts="${opts},password=${password}"
    [ -n "$options" ] && opts="${opts},${options}"
    opts="${opts#,}"

    mkdir -p "$path"

    if [ -n "$opts" ]; then
        mount -t cifs "//${server}/${share}" "$path" -o "$opts" 2>/dev/null
    else
        mount -t cifs "//${server}/${share}" "$path" 2>/dev/null
    fi
    return $?
}

# 主程序
if ! uci show cifs >/dev/null 2>&1; then
    exit 0
fi

for cfg in $(uci show cifs 2>/dev/null | grep "=mount$" | cut -d'.' -f2 | cut -d'=' -f1); do
    mp=$(uci get "cifs.${cfg}.path" 2>/dev/null)
    [ -z "$mp" ] && mp="/mnt/${cfg}"

    if ! mountpoint -q "$mp" 2>/dev/null; then
        continue
    fi

    if is_mount_healthy "$mp"; then
        continue
    fi

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

# 添加 cron 定时任务
cat >> files/etc/uci-defaults/99-custom-settings << 'CRONEOF'

# CIFS 自动重连 cron (每分钟检测)
echo "* * * * * /usr/bin/cifs-reconnect" >> /etc/crontabs/root
logger -t uci-defaults "已启用 CIFS 自动重连"
CRONEOF
echo "  [OK] CIFS 自动重连"

# ============================================================================
# 完成
# ============================================================================
echo ""
echo "============================================================"
echo "  DIY Part 1 完成!"
echo "============================================================"
echo "  DTS: 内存 2GB / 无 NMBM / UBI 506.5MB"
echo "  第三方包: luci-app-easytier"
echo "  系统优化: BBR + CPU频率 + uci-defaults + CIFS自动重连"
echo "============================================================"
