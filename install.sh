#!/bin/bash
set -e

# --- helper functions for logs ---
info()
{
    echo '[INFO] ' "$@"
}

warn()
{
    RED='\033[0;31m'
    NC='\033[0m' # No Color
    echo -e "${RED}[WARN] ${NC}" "${RED}$@${NC}" >&2
}
fatal()
{
    echo '[ERROR] ' "$@" >&2
    exit 1
}

# --- add quotes to command arguments ---
quote() {
    for arg in "$@"; do
        printf '%s\n' "$arg" | sed "s/'/'\\\\''/g;1s/^/'/;\$s/\$/'/"
    done
}

# --- add indentation and trailing slash to quoted args ---
quote_indent() {
    printf ' \\\n'
    for arg in "$@"; do
        printf '\t%s \\\n' "$(quote "$arg")"
    done
}

# --- escape most punctuation characters, except quotes, forward slash, and space ---
escape() {
    printf '%s' "$@" | sed -e 's/\([][!#$%&()*;<=>?\_`{|}]\)/\\\1/g;'
}

# --- escape double quotes ---
escape_dq() {
    printf '%s' "$@" | sed -e 's/"/\\"/g'
}

eval set -- $(escape "$@") $(quote "$@")
	
download_files() {
	if [ "$#" -ne 1 ]; then
		fatal "Usage: download_files <URL>"
		return 1
	fi
	
	local url=$1
	local path=".$(echo "$url" | sed -E 's|^https?://[^/]+||')"
	local save_path=$(dirname "$path")
	
	if [ ! -d "$save_path" ]; then
		mkdir -p "$save_path"
	fi

	if [ -f "$path" ]; then
		info "File already exists, skipping download: ${path}"
		return 0
	fi
	
	curl -L --insecure --output "${path}" "$url" >/dev/null 2>&1
	
	if [ $? -eq 0 ]; then
		info "download success ${path}"
	else
		info "download failed"
		return 2
	fi
}


downloadResource() {
	info "start download w7panel resource!"

	# images
	download_files 'https://cdn.w7.cc/w7panel/images/cilium.cilium-v1.16.4.tar'
	download_files 'https://cdn.w7.cc/w7panel/images/cilium.operator-generic-v1.16.4.tar'
	download_files 'https://cdn.w7.cc/w7panel/images/jetstack.cert-manager-cainjector-v1.16.2.tar'
	download_files 'https://cdn.w7.cc/w7panel/images/jetstack.cert-manager-controller-v1.16.2.tar'
	download_files 'https://cdn.w7.cc/w7panel/images/jetstack.cert-manager-webhook-v1.16.2.tar'
	download_files 'https://cdn.w7.cc/w7panel/images/jetstack.cert-manager-startupapicheck-v1.16.2.tar'
	
	# manifests
	download_files 'https://cdn.w7.cc/w7panel/manifests/cert-manager.yaml'
	download_files 'https://cdn.w7.cc/w7panel/manifests/cilium.yaml'
	download_files 'https://cdn.w7.cc/w7panel/manifests/higress.yaml'
	download_files 'https://cdn.w7.cc/w7panel/manifests/longhorn.yaml'
	download_files 'https://cdn.w7.cc/w7panel/manifests/w7panel-offline.yaml'

	# etc
	download_files 'https://cdn.w7.cc/w7panel/etc/registries.yaml'
	download_files 'https://cdn.w7.cc/w7panel/etc/sysctl.d/k3s.conf'
	download_files 'https://cdn.w7.cc/w7panel/etc/k3s.service.d/override.conf'
}

# PUBLIC_IP=
publicNetworkIp() {
	#publicIp 为空，则重新获取publicIp
	if [ -z "$PUBLIC_IP" ]; then
		PUBLIC_IP=$(curl -s ifconfig.me);
		echo $PUBLIC_IP
	else
		echo $PUBLIC_IP
	fi
}

internalIP() {
	if [ -z "$INTERNAL_IP" ]; then
		INTERNAL=$(ip addr show eth0 | grep 'inet ' | grep -v '127.0.0.1' | awk '{ print $2 }' | cut -d/ -f1);
		echo $INTERNAL
	else
		echo $INTERNAL
	fi
}

etcSysctl() {
	if command -v sysctl &> /dev/null; then
		ETC_PATH="/etc/sysctl.d"
		mkdir -p $ETC_PATH
		chmod -R 755 $ETC_PATH
		cp "./w7panel/etc/sysctl.d/k3s.conf" $ETC_PATH
		sysctl -p >/dev/null 2>&1
	fi
}

etcPrivaterRegistry(){
	ETC_PATH="/etc/rancher/k3s/"
	mkdir -p $ETC_PATH
	cp "./w7panel/etc/registries.yaml" $ETC_PATH
}

etcSystemd(){
	ETC_PATH="/etc/systemd/system/k3s.service.d/"
	mkdir -p $ETC_PATH
	cp "./w7panel/etc/k3s.service.d/override.conf" $ETC_PATH
}

checkK3SInstalled() {
	info 'start check server is installed 检测k3s是否已安装'
	if  [ -x /usr/local/bin/k3s ]; then
		warn "K3s has been installed , Please execute /usr/local/bin/k3s-uninstall.sh to uninstall k3s "
		warn "K3s 已安装 , 请先执行　/usr/local/bin/k3s-uninstall.sh 命令卸载 "
		exit
	fi
}

checkW7panelInstalled() {
	info '微擎面板正在安装中，请耐心等待'
	max_attempts=300
	attempt=0
	while [ $attempt -lt $max_attempts ]; do
		response=$(echo $(curl -s --max-time 5 -I "http://$(internalIP):9090"))
		
		if [ $? -eq 0 ]; then
			if echo "$response" | grep -q "HTTP/"; then
				break
			fi
		fi
		
		echo -n "."
		sleep 3
		attempt=$((attempt + 1))
	done
}

importImages() {
	info "开始导入核心组件镜像"
	IMAGES_DIR="./w7panel/images"
	if [ ! -d "$IMAGES_DIR" ]; then
		return 0
	fi

	for IMAGE_FILE in "$IMAGES_DIR"/*.tar; do
		if [ -f "$IMAGE_FILE" ]; then
			k3s ctr -n=k8s.io images import "$IMAGE_FILE" >/dev/null 2>&1

			if [ $? -eq 0 ]; then
				info "镜像导入成功: $IMAGE_FILE"
			else
				info "镜像导入失败: $IMAGE_FILE"
			fi
		else
			info "不是文件: $IMAGE_FILE"
		fi
	done
}

installHelmCharts() {
	info 'start install helm charts'
	M_PATH="/var/lib/rancher/k3s/server/manifests/"
	mkdir -p $M_PATH $C_PATH
	
	cp -r "./w7panel/manifests/." $M_PATH
}

# Install k3s
k3sInstall() {
	info "current server's public network ip: $(publicNetworkIp)"
	curl -sfL https://rancher-mirror.rancher.cn/k3s/k3s-install.sh | K3S_KUBECONFIG_MODE='644' INSTALL_K3S_SKIP_SELINUX_RPM=true INSTALL_K3S_SELINUX_WARN=true INSTALL_K3S_MIRROR=cn INSTALL_K3S_MIRROR_URL=rancher-mirror.rancher.cn \
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

{
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