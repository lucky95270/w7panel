#!/bin/bash
set -e

# 检查终端是否支持颜色输出
if [ -t 1 ]; then
    INFO_COLOR='\033[0m'
    WARN_COLOR='\033[33m'
    ERROR_COLOR='\033[31m'
    SUCCESS_COLOR='\033[32m'
    NC='\033[0m' # No Color
else
    INFO_COLOR=''
    WARN_COLOR=''
    ERROR_COLOR=''
    SUCCESS_COLOR=''
    NC=''
fi

# 信息日志
info() {
    printf "${INFO_COLOR}[INFO]${NC} %s\n" "$*"
}

# 警告日志
warn() {
    printf "${WARN_COLOR}[WARN] %s${NC}\n" "$*" >&2
}

# 成功日志
success() {
    printf "${SUCCESS_COLOR}[SUCCESS]${NC} %s\n" "$*"
}

# 错误日志
fatal() {
    printf "${ERROR_COLOR}[ERROR] %s${NC}\n" "$*" >&2
    exit 1
}

# 提示日志
tips() {
    printf "${SUCCESS_COLOR}%s${NC}\n" "$*"
}

# --- add quotes to command arguments ---
# 给命令参数添加引号
quote() {
    for arg in "$@"; do
        printf '%s\n' "$arg" | sed "s/'/'\\\\''/g;1s/^/'/;\$s/\$/'/"
    done
}

# --- add indentation and trailing slash to quoted args ---
# 给引用的参数添加缩进和反斜杠
quote_indent() {
    printf ' \\\n'
    for arg in "$@"; do
        printf '\t%s \\\n' "$(quote "$arg")"
    done
}

# --- escape most punctuation characters, except quotes, forward slash, and space ---
# 转义大多数标点符号，除了引号、斜杠和空格
escape() {
    printf '%s' "$@" | sed -e 's/\([][!\#$%&()*;<=>?\_`{|}]\)/\\\1/g;'
}

# --- escape double quotes ---
# 转义双引号
escape_dq() {
    printf '%s' "$@" | sed -e 's/"/\\"/g'
}

# 处理命令行参数
process_args() {
    eval set -- $(escape "$@") $(quote "$@")
}

# 进度条函数
show_progress() {
    local pid=$1
    local delay=0.75
    local spinstr="|/-\\"
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf "${WARN_COLOR} [%c]  ${NC}" "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# 下载文件函数
download_files() {
    local url=$1
    local path=".$(echo "$url" | sed -E 's|^https?://[^/]+||')"
    local save_path=$(dirname "$path")
    local filename=$(basename "$path")
    mkdir -p "$save_path" || fatal "创建目录失败: $save_path"

    if [ -f "$path" ]; then
        info "文件已存在: ${path}"
        return 0
    fi

    wget -q --show-progress --progress=bar:force:noscroll --no-check-certificate -c --timeout=10 --tries=20 --retry-connrefused -O "$path" "$url" || {
        rm -f "$path"
        fatal "下载失败: $url, 请稍后重试！"
    }
}

# 载资源函数
downloadResource() {
    info "开始下载微擎面板资源..."
    local resources="
        https://cdn.w7.cc/w7panel/images/cilium.cilium-v1.16.4.tar
        https://cdn.w7.cc/w7panel/images/cilium.operator-generic-v1.16.4.tar
        https://cdn.w7.cc/w7panel/images/jetstack.cert-manager-cainjector-v1.16.2.tar
        https://cdn.w7.cc/w7panel/images/jetstack.cert-manager-controller-v1.16.2.tar
        https://cdn.w7.cc/w7panel/images/jetstack.cert-manager-webhook-v1.16.2.tar
        https://cdn.w7.cc/w7panel/images/jetstack.cert-manager-startupapicheck-v1.16.2.tar
        https://cdn.w7.cc/w7panel/images/longhornio.csi-attacher-v4.7.0.tar
        https://cdn.w7.cc/w7panel/images/longhornio.csi-node-driver-registrar-v2.12.0.tar
        https://cdn.w7.cc/w7panel/images/longhornio.csi-provisioner-v4.0.1-20241007.tar
        https://cdn.w7.cc/w7panel/images/longhornio.csi-resizer-v1.12.0.tar
        https://cdn.w7.cc/w7panel/images/longhornio.csi-snapshotter-v7.0.2-20241007.tar
        https://cdn.w7.cc/w7panel/images/longhornio.livenessprobe-v2.14.0.tar
        https://cdn.w7.cc/w7panel/images/longhornio.longhorn-engine-v1.7.2.tar
        https://cdn.w7.cc/w7panel/images/longhornio.longhorn-instance-manager-v1.7.2.tar
        https://cdn.w7.cc/w7panel/images/longhornio.longhorn-manager-v1.7.2.tar
        https://cdn.w7.cc/w7panel/images/longhornio.longhorn-share-manager-v1.7.2.tar
        https://cdn.w7.cc/w7panel/manifests/cert-manager.yaml
        https://cdn.w7.cc/w7panel/manifests/cilium.yaml
        https://cdn.w7.cc/w7panel/manifests/higress.yaml
        https://cdn.w7.cc/w7panel/manifests/longhorn.yaml
        https://cdn.w7.cc/w7panel/manifests/w7panel-offline.yaml
        https://cdn.w7.cc/w7panel/etc/registries.yaml
        https://cdn.w7.cc/w7panel/etc/sysctl.d/k3s.conf
        https://cdn.w7.cc/w7panel/etc/systemd/k3s.service.env
    "

    for resource in $resources; do
        download_files "$resource"
    done
}

# 获取公网IP
publicNetworkIp() {
    # publicIp 为空，则重新获取publicIp
    if [ -z "$PUBLIC_IP" ]; then
        PUBLIC_IP=$(curl -s ifconfig.me)
        echo "$PUBLIC_IP"
    else
        echo "$PUBLIC_IP"
    fi
}

# 获取内网IP（兼容多系统）
internalIP() {
    if [ -z "$INTERNAL_IP" ]; then
        INTERNAL_IP=$(
            ip -o -4 addr show | \
            awk '{print $4}' | \
            grep -v '127.0.0.1' | \
            cut -d/ -f1 | \
            head -1
        )
        [ -z "$INTERNAL_IP" ] && INTERNAL_IP=$(hostname -I | awk '{print $1}')
        echo "$INTERNAL_IP"
    else
        echo "$INTERNAL_IP"
    fi
}

# 处理sysctl配置
etcSysctl() {
    if command -v sysctl &> /dev/null; then
        local ETC_PATH="/etc/sysctl.d"
        sudo mkdir -p "$ETC_PATH" || {
            fatal "Failed to create directory: $ETC_PATH"
            return 1
        }
        sudo chmod -R 755 "$ETC_PATH"
        sudo cp "./w7panel/etc/sysctl.d/k3s.conf" "$ETC_PATH" || {
            fatal "Failed to copy k3s.conf to $ETC_PATH"
            return 1
        }
        sudo sysctl --system >/dev/null 2>&1 || {
            warn "Failed to reload sysctl settings"
        }
    fi
}

# 处理私有仓库配置
etcPrivaterRegistry() {
    local ETC_PATH="/etc/rancher/k3s/"
    sudo mkdir -p "$ETC_PATH" || {
        fatal "Failed to create directory: $ETC_PATH"
        return 1
    }
    sudo cp "./w7panel/etc/registries.yaml" "$ETC_PATH" || {
        fatal "Failed to copy registries.yaml to $ETC_PATH"
        return 1
    }
}

# 处理systemd配置
etcSystemd() {
    local ETC_PATH="/etc/systemd/system/"
    if [ -f "./w7panel/etc/systemd/k3s.service.env" ]; then
        cat "./w7panel/etc/systemd/k3s.service.env" | sudo tee -a "$ETC_PATH/k3s.service.env" > /dev/null || {
            fatal "Failed to append content to $ETC_PATH/k3s.service.env"
        }
    fi

    # 重新加载 systemd 管理器配置
    sudo systemctl daemon-reload || {
        fatal "Failed to reload systemd manager configuration"
    }

    # 重启 k3s.service
    sudo systemctl restart k3s.service || {
        fatal "Failed to restart k3s.service"
    }
    info "k3s.service has been restarted successfully."
}

# 检查K3S是否已安装
checkK3SInstalled() {
    info 'start check server is installed 检测k3s是否已安装'
    if [ -x /usr/local/bin/k3s ]; then
        warn "K3s has been installed , Please execute /usr/local/bin/k3s-uninstall.sh to uninstall k3s "
        warn "K3s 已安装 , 请先执行　/usr/local/bin/k3s-uninstall.sh 命令卸载 "
        exit
    fi
}

# 检查微擎面板是否安装成功
checkW7panelInstalled() {
    printf "${INFO_COLOR}[INFO]${NC} %s" "微擎面板正在初始化，预计需要3-5分钟，请耐心等待..."
    local spinpid
    while true; do
        curl -s --max-time 2 -I "http://$(internalIP):9090" | grep -q "HTTP/" && break
        sleep 1 &
        show_progress $! &
        spinpid=$!
        wait $spinpid
    done
    echo
}

# 导入镜像
importImages() {
    local IMAGES_DIR="./w7panel/images"
    [ ! -d "$IMAGES_DIR" ] && return 0

    local total=$(ls $IMAGES_DIR/*.tar 2>/dev/null | wc -l)
    local count=0
    for IMAGE_FILE in $IMAGES_DIR/*.tar; do
        count=$((count+1))
        info "导入镜像中 [$count/$total] $(basename $IMAGE_FILE)"
        sudo /usr/local/bin/k3s ctr -n=k8s.io images import "$IMAGE_FILE" >/dev/null 2>&1 || {
            warn "镜像导入失败: $(basename $IMAGE_FILE)"
        }
    done
}

# 安装Helm Charts
installHelmCharts() {
    info 'start install helm charts'
    local M_PATH="/var/lib/rancher/k3s/server/manifests/"
    sudo cp -r "./w7panel/manifests/." "$M_PATH" || {
        fatal "Failed to copy manifests to $M_PATH"
        return 1
    }
}

# 安装K3S
k3sInstall() {
    info "current server's public network ip: $(publicNetworkIp)"
    curl -sfL https://rancher-mirror.cdn.w7.cc/k3s/k3s-install.sh | \
    K3S_NODE_NAME=server1 K3S_KUBECONFIG_MODE='644' INSTALL_K3S_SKIP_SELINUX_RPM=true INSTALL_K3S_SELINUX_WARN=true INSTALL_K3S_MIRROR=cn INSTALL_K3S_MIRROR_URL=rancher-mirror.cdn.w7.cc \
    sh -s - --write-kubeconfig-mode 644 \
        --tls-san "$(internalIP)" \
        --system-default-registry "registry.cn-hangzhou.aliyuncs.com" \
        --kubelet-arg="image-gc-high-threshold=70" \
        --kubelet-arg="image-gc-low-threshold=60" \
        --node-label "w7.public-ip=$(publicNetworkIp)" \
        --embedded-registry \
        --flannel-backend "none" \
        --disable-network-policy \
        --disable-kube-proxy \
        --disable "local-storage,traefik"
}

# 检测并安装 zram 模块
check_and_install_zram() {
    # 先尝试加载模块
    sudo modprobe zram num_devices=1 > /dev/null 2>&1 || true
    
    if ! lsmod | grep -q zram; then
        info "未检测到 zram 内核模块，尝试安装..."
        # 检测发行版
        if [ -f /etc/redhat-release ]; then
            # Red Hat 系（如 CentOS、Fedora）
            sudo yum update -y
            sudo yum install -y kernel-modules-extra
        elif [ -f /etc/debian_version ]; then
            # Debian 系（如 Ubuntu、Debian）
            sudo apt-get update -y
            sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -o Dpkg::Options::="--force-confold"
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y linux-modules-extra-$(uname -r)
        elif [ -f /etc/arch-release ]; then
            # Arch Linux
            sudo pacman -Syu --noconfirm
            sudo pacman -S --noconfirm linux-headers
        else
            info "无法识别的发行版，请手动安装 zram 模块"
            return 1
        fi
        # 再次尝试加载模块
        sudo modprobe zram num_devices=1
        if [ $? -ne 0 ]; then
            info "安装后仍无法加载 zram 模块，请手动检查"
            return 1
        fi
        info "zram 模块已成功加载"
    else
        info "zram 内核模块已存在"
    fi
}

# 创建内存压缩
setupZram() {
    # 检测并安装 zram 模块
    check_and_install_zram || return 1
    
    # 检测 Swap 交换空间并删除
    non_zram_swap=$(grep -E '^[^#].*\sswap\s' /etc/fstab | awk '{print $1}')
    if [ -n "$non_zram_swap" ]; then
        info "检测到 Swap 交换空间，开始删除..."
        for swap in $non_zram_swap; do
            # 检查交换空间是否已挂载
            if swapon --show | grep -q "^$swap"; then
                sudo swapoff "$swap"
            fi
            if [ -f "$swap" ]; then
                sudo rm "$swap"
            fi
            # 从 /etc/fstab 中删除对应的挂载信息
            temp_file=$(mktemp)
            awk -v swap="$swap" '$1 != swap {print}' /etc/fstab > "$temp_file"
            sudo mv "$temp_file" /etc/fstab
        done
        info "Swap 交换空间已删除"
    fi

    # 检查是否已经存在 zram 设备作为交换空间
    if ! swapon --show | grep -q '^/dev/zram'; then
        info "未检测到 ZRAM Swap 空间，开始创建并设置 4GB 的 ZRAM Swap 空间..."
        # 加载 zram 模块
        sudo modprobe zram num_devices=1

        # 设置 zram 设备的压缩算法为 lz4hc
        echo "lz4hc" | sudo tee /sys/block/zram0/comp_algorithm > /dev/null 2>&1 || true
        
        # 设置 zram 设备的大小为 4GB
        echo "4G" | sudo tee /sys/block/zram0/disksize > /dev/null 2>&1 || true
        
        # 格式化 zram 设备为交换空间
        sudo mkswap /dev/zram0 2>/dev/null || true

        # 启用 zram 设备作为交换空间
        sudo swapon /dev/zram0

        info "ZRAM Swap 空间已成功创建"
    else
        info "已检测到 ZRAM Swap 空间，跳过创建步骤"
    fi
}


# 系统检查
checkDependencies() {
    command -v curl >/dev/null || fatal "请先安装 curl"
    command -v wget >/dev/null || fatal "请先安装 wget"
    command -v ip >/dev/null || fatal "需要 iproute2 工具包"
}

# 主执行函数
main() {
    process_args "$@"

    checkDependencies
    checkK3SInstalled
    downloadResource

    etcSysctl
    etcPrivaterRegistry
    
    setupZram
    
    k3sInstall
    importImages
    installHelmCharts
    etcSystemd
    checkW7panelInstalled

    tips "=================================================================="
    tips "公网地址: http://$(publicNetworkIp):9090"
    tips "内网地址: http://$(internalIP):9090"
    tips "微擎面板安装成功，请访问后台设置登录密码！"
    tips ""
    warn "如果您的面板无访问："
    warn "请确认服务器安全组是否放通 (80|443|6443|9090) 端口"
    tips "=================================================================="
}

main "$@"
