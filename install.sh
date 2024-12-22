#!/bin/bash
set -e
set -o noglob

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


localTestIp() {
  echo ${LOCAL_TEST_IP:=172.16.1.117}
}

isLocal() {
  if [ "${IS_LOCAL:-0}" -eq 1 ]; then return 0; else return 1; fi
}


# PUBLIC_IP=
publicNetworkIp(){
    #publicIp 为空，则重新获取publicIp
    if [ -z "$PUBLIC_IP" ]; then
        PUBLIC_IP=$(curl -s ifconfig.me);
        echo $PUBLIC_IP
    else
        echo "$PUBLIC_IP"
    fi
}


apiServerUrl(){
    echo "https://$(publicNetworkIp):6443"
}
offlineUrl(){
    echo "http://$(publicNetworkIp):9090"
}



modifyK3sFileWatch()
{
    if command -v sysctl &> /dev/null; then

        CTL_PATH="/etc/sysctl.d"
        sudo mkdir -p $CTL_PATH
        sudo chmod -R 777 $CTL_PATH
cat > ${CTL_PATH}/k3s.conf <<- EOF
fs.inotify.max_user_instances = 81920
fs.inotify.max_user_watches = 524288
EOF
        sudo sysctl -p;
    fi
}


checkK3SInstalled()
{
    info 'start check server is installed 检测k3s是否已安装'
    if  [ -x /usr/local/bin/k3s ]; then
            warn "K3s has been installed , Please execute /usr/local/bin/k3s-uninstall.sh to uninstall k3s "
            warn "K3s 已安装 , 请先执行　/usr/local/bin/k3s-uninstall.sh 命令卸载 "
            exit
        fi
}

# Install k3s
k3sInstall(){
   info "current server's public network ip : $(publicNetworkIp)"
   curl -sfL https://rancher-mirror.rancher.cn/k3s/k3s-install.sh | K3S_KUBECONFIG_MODE='644' INSTALL_K3S_SKIP_SELINUX_RPM=true INSTALL_K3S_SELINUX_WARN=true INSTALL_K3S_MIRROR=cn INSTALL_K3S_MIRROR_URL=rancher-mirror.rancher.cn \
   sh -s - --write-kubeconfig-mode 644 \
   --tls-san "$(publicNetworkIp)" \
   --advertise-address "$(publicNetworkIp)" \
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

userAgent(){
    [ -z ${USER_AGENT} ] &&USER_AGENT="w7_shell"
    echo $USER_AGENT
}


installUuid(){
    [ -z ${UUID} ] &&UUID=''
        echo $UUID
}

installClusterTitle(){
    [ -z ${CLUSTER_TITLE} ] &&CLUSTER_TITLE='default'
        echo $CLUSTER_TITLE
}




kubeConfig(){
    # cat ~/k3s.yaml
    kubectl get secret/w7 -o yaml #后端转为kubeconfig 文件
    return $?
}


k3sToken()
{
    sudo cat /var/lib/rancher/k3s/server/node-token
    return $?
}


privateDockerRegistry(){
FILE="/etc/rancher/k3s/registries.yaml"
FILE_TMP="./registries.yaml"
NODE_PORT_IP=$(publicNetworkIp)
cat > ${FILE_TMP} <<- EOF
mirrors:
  docker.io:
    endpoint:
      - "https://mirror.ccs.tencentyun.com"
      - "https://registry.cn-hangzhou.aliyuncs.com"
      - "https://docker.m.daocloud.io"
      - "https://docker.1panel.live"
  quay.io:
    endpoint:
      - "https://quay.m.daocloud.io"
      - "https://quay.dockerproxy.com"
  gcr.io:
    endpoint:
      - "https://gcr.m.daocloud.io"
      - "https://gcr.dockerproxy.com"
  ghcr.io:
    endpoint:
      - "https://ghcr.m.daocloud.io"
      - "https://ghcr.dockerproxy.com"
  k8s.gcr.io:
    endpoint:
      - "https://k8s-gcr.m.daocloud.io"
      - "https://k8s.dockerproxy.com"
  registry.k8s.io:
    endpoint:
      - "https://k8s.m.daocloud.io"
      - "https://k8s.dockerproxy.com"
  mcr.microsoft.com:
    endpoint:
      - "https://mcr.m.daocloud.io"
      - "https://mcr.dockerproxy.com"
  nvcr.io:
    endpoint:
      - "https://nvcr.m.daocloud.io"
  registry.local.w7.cc:
  "*":
EOF

sudo mkdir -p /etc/rancher/k3s
sudo mv $FILE_TMP $FILE
rm -rf $FILE_TMP
}

installCertManager() {
info '开始安装cert-manager证书管理工具';
sudo cat > ./cert-manager.yaml <<- EOF
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: cert-manager
  namespace: kube-system
spec:
  chart: https://cdn.w7.cc/k3s/cert-manager-v1.10.1.tgz
  version: v1.10.1
  targetNamespace: cert-manager
  createNamespace: true
  set:
    webhook.enabled: "false"
    installCRDs: "false"
EOF
sudo mv ./cert-manager.yaml /var/lib/rancher/k3s/server/manifests/
}

installCilium() {
info 'Install the Cilium';
FILENAME="cilium.yaml"
FILE="/var/lib/rancher/k3s/server/manifests/${FILENAME}"
FILE_TMP="./${FILENAME}"
cat > ${FILE_TMP} <<- EOF
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: cilium
  namespace: kube-system
spec:
  chart: https://cdn.w7.cc/k3s/cilium-1.16.4.tgz
  version: 1.16.4
  targetNamespace: kube-system
  bootstrap: true
  set:
    operator.replicas: 1
    nodeIPAM.enabled: "true"
    ipam.operator.clusterPoolIPv4PodCIDRList: "10.42.0.0/16"
    kubeProxyReplacement: "true"
    envoy.enabled: "false"
    bandwidthManager.enabled: "true"
    k8sServiceHost: "127.0.0.1"
    k8sServicePort: "6444"
EOF

sudo mkdir -p /var/lib/rancher/k3s/server/manifests
sudo mv $FILE_TMP $FILE
rm -f $FILE_TMP
}




optimizeK3sConfig() {
info "optimize k3s"
FILE_PATH="/etc/systemd/system/k3s.service.d"
sudo mkdir -p $FILE_PATH
sudo chmod -R 777 $FILE_PATH
cat > ${FILE_PATH}/override.conf <<- EOF
[Service]
Environment="GOGC=10"
EOF
}

tip() {
    warn '请确认服务器安全组是否放通 80 443端口，否则交付域名无法正常绑定成功'
}

installLonghornDriver() {
    info "开始安装longhorn驱动"
    kubectl apply -f https://console.w7.cc/yaml/longhorn/open-iscsi-install.yaml
}

installLonghorn() {
info "开始安装longhorn"
FILENAME="longhorn.yaml"
FILE="/var/lib/rancher/k3s/server/manifests/${FILENAME}"
HIGRESS_FILE="./${FILENAME}"
cat > ${HIGRESS_FILE} <<- EOF
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: longhorn
  namespace: kube-system
spec:
  chart: https://cdn.w7.cc/k3s/longhorn-1.7.2.tgz
  version: v1.7.2
  targetNamespace: longhorn-system
  createNamespace: true
  set:
    longhornUI.replicas: 0
    csi.attacherReplicaCount: 1
    csi.provisionerReplicaCount: 1
    csi.resizerReplicaCount: 1
    csi.snapshotterReplicaCount: 1
    defaultSettings.storageReservedPercentageForDefaultDisk: "0"
EOF
sudo mkdir -p /var/lib/rancher/k3s/server/manifests
sudo mv $HIGRESS_FILE $FILE
rm -f $HIGRESS_FILE
}

installCertManagerCrd() {
  kubectl apply -f https://cdn.w7.cc/k3s/cert-manager/v1.10.1/cert-manager.crds.yaml
}

installCertManagerClusterIssuer() {
cat > ./clusterissuer.yaml <<- EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: w7-letsencrypt-prod
spec:
  acme:
    # The ACME server URL
    server: https://acme-v02.api.letsencrypt.org/directory
    # Email address used for ACME registration
    email: 446897682@qq.com
    # Name of a secret used to store the ACME account private key
    privateKeySecretRef:
      name: w7-letsencrypt-prod
    # Enable the HTTP-01 challenge provider
    solvers:
      - http01:
          ingress:
            class: higress
EOF
 kubectl apply -f ./clusterissuer.yaml
}

installHigress() {
info '开始安装higress';
info 'Install the higress';
FILENAME="higress.yaml"
FILE="/var/lib/rancher/k3s/server/manifests/${FILENAME}"
HIGRESS_FILE="./higress.yaml"
cat > ${HIGRESS_FILE} <<- EOF
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: higress
  namespace: kube-system
spec:
  chart: https://cdn.w7.cc/k3s/higress-2.0.4.tgz
  version: v2.0.4
  targetNamespace: higress-system
  createNamespace: true
  set:
    higress-core.gateway.service.loadBalancerClass: "io.cilium/node"
    global.ingressClass: "higress"
    higress-core.gateway.replicas: 1
    higress-core.gateway.resources.limits.cpu: 0
    higress-core.gateway.resources.limits.memory: 0
    higress-core.gateway.resources.requests.cpu: 0
    higress-core.gateway.resources.requests.memory: 0
    higress-core.controller.replicas: 1
    higress-core.controller.resources.requests.cpu: 0
    higress-core.controller.resources.requests.memory: 0
    higress-core.controller.resources.limits.cpu: 0
    higress-core.controller.resources.limits.memory: 0
    higress-core.pilot.replicaCount: 1
    higress-core.pilot.resources.requests.cpu: 0
    higress-core.pilot.resources.requests.memory: 0
    higress-core.downstream.connectionBufferLimits: 3276800
    higress-console.replicaCount: 0
    higress-console.resources.requests.cpu: 0
    higress-console.resources.requests.memory: 0

EOF
sudo mkdir -p /var/lib/rancher/k3s/server/manifests
sudo mv $HIGRESS_FILE $FILE
rm -f $HIGRESS_FILE
}


installHigressEnvoy() {
info '开始安装higress-envoy';
info 'Install the higress envoy';
FILENAME="higress-envoy.yaml"
FILE="/var/lib/rancher/k3s/server/manifests/${FILENAME}"
HIGRESS_FILE="./higress-envoy.yaml"
cat > ${HIGRESS_FILE} <<- EOF
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: dis-tls
  namespace: higress-system
spec:
  configPatches:
  - applyTo: FILTER_CHAIN
    match:
      context: GATEWAY
      listener:
        name: 0.0.0.0_443
    patch:
      operation: MERGE
      value:
        transport_socket:
          name: envoy.transport_sockets.tls
          typed_config:
            '@type': type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.DownstreamTlsContext
            common_tls_context:
              tls_params:
                tls_maximum_protocol_version: TLSv1_3
                tls_minimum_protocol_version: TLSv1_1
  workloadSelector:
    labels:
      app: higress-gateway

EOF
sudo mkdir -p /var/lib/rancher/k3s/server/manifests
sudo mv $HIGRESS_FILE $FILE
rm -f $HIGRESS_FILE
}

createNs() {
  kubectl create namespace cert-manager || true
  kubectl create namespace higress-system || true
}

installNfsCommon() {
  info "开始安装nfs-common"
if [ -f /etc/debian_version ]; then
    # Debian/Ubuntu 系统
    info "Detected Debian/Ubuntu system."
    if dpkg -s nfs-common &> /dev/null; then
        info "nfs-common is already installed."
    else
        info "Installing nfs-common..."
        sudo apt-get update
        sudo apt-get install -y nfs-common
    fi
elif [ -f /etc/redhat-release ]; then
    # CentOS/RHEL 系统
    info "Detected CentOS/RHEL system."
    if rpm -q nfs-utils &> /dev/null; then
        info "nfs-utils is already installed."
    else
        info "Installing nfs-utils..."
        sudo yum install -y nfs-utils
    fi
else
    warn "Unsupported system. 请手动安装nfs-common"
fi
}

offlineInstall() {
info "开始离线安装"
OFFLINE_FILE="./k8s-offline.yaml"
cat > ${OFFLINE_FILE} <<- EOF
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: offlineui
  namespace: kube-system
spec:
  chart: https://cdn.w7.cc/k3s/k8s-offline-1.0.15.tgz
  version: v1.0.15
  targetNamespace: default
  createNamespace: true
  set:
    servicelb.loadBalancerClass: "io.cilium/node"
    register.create: "${REGISTER_CLUSTER}"
    register.apiServerUrl: "$(apiServerUrl)"
    register.thirdPartyCDToken: "${AUTH_TOKEN}"
    register.offlineUrl: "$(offlineUrl)"
    register.userAgent: "${USER_AGENT}"
    register.needInitUser: "true"

EOF
kubectl apply -f ${OFFLINE_FILE}
}

{
    modifyK3sFileWatch
    checkK3SInstalled
    installCilium
    installHigress #安装higress
    installHigressEnvoy #tls 证书问题
    installCertManager # 安装certmanager
    installLonghorn
    privateDockerRegistry
    optimizeK3sConfig
    k3sInstall
    tip


    installNfsCommon
    installLonghornDriver

    installCertManagerCrd
    installCertManagerClusterIssuer
    kubectl apply -f https://console.w7.cc/yaml/quanxian/w7.yaml

    offlineInstall
    info "面板正在安装中，请等待安装完成后，访问后台设置登录密码！"
    info "后台地址: http://$(publicNetworkIp):9090"
}