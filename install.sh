#!/bin/bash
set -e

# --- helper functions for logs ---
# 输出信息日志
info() {
    echo '[INFO] ' "$@"
}

# 输出警告日志
warn() {
    RED='\033[0;31m'
    NC='\033[0m' # No Color
    echo -e "${RED}[WARN] ${NC}" "${RED}$@${NC}" >&2
}

# 输出错误日志并退出
fatal() {
    echo '[ERROR] ' "$@" >&2
    exit 1
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

# 下载文件函数
download_files() {
    # 检查参数数量
    if [ "$#" -ne 1 ]; then
        fatal "Usage: download_files <URL>"
        return 1
    fi

    local url=$1
    # 生成保存路径
    local path=".$(echo "$url" | sed -E 's|^https?://[^/]+||')"
    local save_path=$(dirname "$path")

    # 创建保存目录
    if [ ! -d "$save_path" ]; then
        mkdir -p "$save_path" || {
            fatal "Failed to create directory: $save_path"
            return 1
        }
    fi

    # 检查文件是否已存在
    if [ -f "$path" ]; then
        info "File already exists, skipping download: ${path}"
        return 0
    fi

    # 下载文件
    curl -L --insecure --output "${path}" "$url" >/dev/null 2>&1
    local status=$?
    if [ $status -eq 0 ]; then
        info "download success ${path}"
    else
        info "download failed"
        return 2
    fi
}

# 下载资源函数
downloadResource() {
    info "start download w7panel resource!"

    # 定义资源数组
    local resources=(
        # images cilium
        "https://cdn.w7.cc/w7panel/images/cilium.cilium-v1.16.4.tar"
        "https://cdn.w7.cc/w7panel/images/cilium.operator-generic-v1.16.4.tar"
        # images cert-manager
        "https://cdn.w7.cc/w7panel/images/jetstack.cert-manager-cainjector-v1.16.2.tar"
        "https://cdn.w7.cc/w7panel/images/jetstack.cert-manager-controller-v1.16.2.tar"
        "https://cdn.w7.cc/w7panel/images/jetstack.cert-manager-webhook-v1.16.2.tar"
        "https://cdn.w7.cc/w7panel/images/jetstack.cert-manager-startupapicheck-v1.16.2.tar"
        # images longhorn
        "https://cdn.w7.cc/w7panel/images/longhornio.csi-attacher-v4.7.0.tar"
        "https://cdn.w7.cc/w7panel/images/longhornio.csi-node-driver-registrar-v2.12.0.tar"
        "https://cdn.w7.cc/w7panel/images/longhornio.csi-provisioner-v4.0.1-20241007.tar"
        "https://cdn.w7.cc/w7panel/images/longhornio.csi-resizer-v1.12.0.tar"
        "https://cdn.w7.cc/w7panel/images/longhornio.csi-snapshotter-v7.0.2-20241007.tar"
        "https://cdn.w7.cc/w7panel/images/longhornio.livenessprobe-v2.14.0.tar"
        "https://cdn.w7.cc/w7panel/images/longhornio.longhorn-engine-v1.7.2.tar"
        "https://cdn.w7.cc/w7panel/images/longhornio.longhorn-instance-manager-v1.7.2.tar"
        "https://cdn.w7.cc/w7panel/images/longhornio.longhorn-manager-v1.7.2.tar"
        "https://cdn.w7.cc/w7panel/images/longhornio.longhorn-share-manager-v1.7.2.tar"
        # manifests
        "https://cdn.w7.cc/w7panel/manifests/cert-manager.yaml"
        "https://cdn.w7.cc/w7panel/manifests/cilium.yaml"
        "https://cdn.w7.cc/w7panel/manifests/higress.yaml"
        "https://cdn.w7.cc/w7panel/manifests/longhorn.yaml"
        "https://cdn.w7.cc/w7panel/manifests/w7panel-offline.yaml"
        # etc
        "https://cdn.w7.cc/w7panel/etc/registries.yaml"
        "https://cdn.w7.cc/w7panel/etc/sysctl.d/k3s.conf"
        "https://cdn.w7.cc/w7panel/etc/k3s.service.d/override.conf"
    )

    # 遍历资源数组进行下载
    for resource in "${resources[@]}"; do
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

# 获取内网IP
internalIP() {
    if [ -z "$INTERNAL_IP" ]; then
        # 遍历所有网络接口
        for interface in $(ip -o link show | awk -F': ' '{print $2}'); do
            # 排除回环接口
            if [ "$interface" != "lo" ]; then
                INTERNAL=$(ip addr show "$interface" | grep 'inet ' | grep -v '127.0.0.1' | awk '{ print $2 }' | cut -d/ -f1)
                if [ -n "$INTERNAL" ]; then
                    break
                fi
            fi
        done
        echo "$INTERNAL"
    else
        echo "$INTERNAL_IP"
    fi
}

# 处理sysctl配置
etcSysctl() {
    if command -v sysctl &> /dev/null; then
        local ETC_PATH="/etc/sysctl.d"
        mkdir -p "$ETC_PATH" || {
            fatal "Failed to create directory: $ETC_PATH"
            return 1
        }
        chmod -R 755 "$ETC_PATH"
        cp "./w7panel/etc/sysctl.d/k3s.conf" "$ETC_PATH" || {
            fatal "Failed to copy k3s.conf to $ETC_PATH"
            return 1
        }
        sysctl -p >/dev/null 2>&1 || {
            warn "Failed to reload sysctl settings"
        }
    fi
}

# 处理私有仓库配置
etcPrivaterRegistry() {
    local ETC_PATH="/etc/rancher/k3s/"
    mkdir -p "$ETC_PATH" || {
        fatal "Failed to create directory: $ETC_PATH"
        return 1
    }
    cp "./w7panel/etc/registries.yaml" "$ETC_PATH" || {
        fatal "Failed to copy registries.yaml to $ETC_PATH"
        return 1
    }
}

# 处理systemd配置
etcSystemd() {
    local ETC_PATH="/etc/systemd/system/k3s.service.d/"
    mkdir -p "$ETC_PATH" || {
        fatal "Failed to create directory: $ETC_PATH"
        return 1
    }
    cp "./w7panel/etc/k3s.service.d/override.conf" "$ETC_PATH" || {
        fatal "Failed to copy override.conf to $ETC_PATH"
        return 1
    }
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
    info '微擎面板正在安装中，请耐心等待'
    local max_attempts=300
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        local response=$(curl -s --max-time 5 -I "http://$(internalIP):9090")
        local status=$?
        if [ $status -eq 0 ]; then
            if echo "$response" | grep -q "HTTP/"; then
                break
            fi
        fi
        echo -n "."
        sleep 3
        attempt=$((attempt + 1))
    done
}

# 导入镜像
importImages() {
    info "正在导入核心组件镜像，请耐心等待..."
    local IMAGES_DIR="./w7panel/images"
    if [ ! -d "$IMAGES_DIR" ]; then
        return 0
    fi

    for IMAGE_FILE in "$IMAGES_DIR"/*.tar; do
        if [ -f "$IMAGE_FILE" ]; then
            k3s ctr -n=k8s.io images import "$IMAGE_FILE" >/dev/null 2>&1
            local import_status=$?
            if [ $import_status -eq 0 ]; then
                info "镜像导入成功: $IMAGE_FILE"
            else
                info "镜像导入失败: $IMAGE_FILE"
            fi
        else
            info "不是文件: $IMAGE_FILE"
        fi
    done
}

# 安装Helm Charts
installHelmCharts() {
    info 'start install helm charts'
    local M_PATH="/var/lib/rancher/k3s/server/manifests/"
    mkdir -p "$M_PATH"
    cp -r "./w7panel/manifests/." "$M_PATH" || {
        fatal "Failed to copy manifests to $M_PATH"
        return 1
    }
}

# 安装K3S
k3sInstall() {
    info "current server's public network ip: $(publicNetworkIp)"
    curl -sfL https://rancher-mirror.rancher.cn/k3s/k3s-install.sh | \
    K3S_NODE_NAME=server1 K3S_KUBECONFIG_MODE='644' INSTALL_K3S_SKIP_SELINUX_RPM=true INSTALL_K3S_SELINUX_WARN=true INSTALL_K3S_MIRROR=cn INSTALL_K3S_MIRROR_URL=rancher-mirror.rancher.cn \
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

# 主执行函数
main() {
    process_args "$@"

    checkK3SInstalled
    downloadResource

    etcSysctl
    etcSystemd
    etcPrivaterRegistry

    k3sInstall
    importImages
    installHelmCharts
    checkW7panelInstalled

    echo -e "\n=================================================================="
    echo -e "\033[32m内网地址: http://$(internalIP):9090\033[0m"
    echo -e "\033[32m公网地址: http://$(publicNetworkIp):9090\033[0m"
    echo -e "\033[32m微擎面板安装成功，请访问后台设置登录密码！\033[0m"
    echo -e ""
    echo -e "\033[31mwarning:\033[0m"
    echo -e "\033[33m如果您的面板无访问,\033[0m"
    echo -e "\033[33m请确认服务器安全组是否放通 (80|443|6443|9090) 端口\033[0m"
    echo -e "=================================================================="
}

main "$@"
