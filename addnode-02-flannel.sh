#!/bin/bash

set -x
if [[ -f ./environment.sh ]];then
    source ./environment.sh
fi

function scp_flanneld(){
for host in ${ADD_NODES[@]}
do
    echo ">>> $host"
    ssh $USERNAME@$host "mkdir -p $BASE_DIR/bin/"
    scp $PWD/bin/{flanneld,mk-docker-opts.sh} $USERNAME@$host:$BASE_DIR/bin
    ssh $USERNAME@$host "chmod +x $BASE_DIR/bin/*"
done
}

#flanneld 从 etcd 集群存取网段分配信息，而 etcd 集群启用了双向 x509 证书认证，所以需要为 flanneld 生成证书和私钥
#该证书只会被 kubectl 当做 client 证书使用，所以 hosts 字段为空
function create_flannel_request(){
cat > $BASE_DIR/work/flanneld-csr.json <<EOF
{
  "CN": "flanneld",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "k8s",
      "OU": "mobvoi"
    }
  ]
}
EOF
}

#生成证书和私钥
function generate_private_key(){
cfssl gencert -ca=$BASE_DIR/work/ca.pem \
  -ca-key=$BASE_DIR/work/ca-key.pem \
  -config=$BASE_DIR/work/ca-config.json \
  -profile=kubernetes flanneld-csr.json | cfssljson -bare flanneld
}

#将生成的证书和私钥分发到所有节点
function scp_private_key(){
for node_ip in ${ADD_NODES[@]}
  do
    echo ">>> ${node_ip}"
    ssh $USERNAME@${node_ip} "mkdir -p /etc/flanneld/cert"
    scp $BASE_DIR/work/{ca*.pem,ca-config.json} $USERNAME@${node_ip}:/etc/kubernetes/cert/
    scp flanneld*.pem $USERNAME@${node_ip}:/etc/flanneld/cert
  done
}


#mk-docker-opts.sh 脚本将分配给 flanneld 的 Pod 子网段信息写入 /run/flannel/docker 文件，后续 docker 启动时使用这个文件中的环境变量配置 docker0 网桥
#flanneld 使用系统缺省路由所在的接口与其它节点通信，对于有多个网络接口（如内网和公网）的节点，可以用 -iface 参数指定通信接口
#flanneld 运行时需要 root 权限
#-ip-masq: flanneld 为访问 Pod 网络外的流量设置 SNAT 规则，同时将传递给 Docker 的变量 --ip-masq（/run/flannel/docker 文件中）设置为 false，这样 Docker 将不再创建 SNAT 规则； Docker 的 --ip-masq 为 true 时，创建的 SNAT 规则比较“暴力”：将所有本节点 Pod 发起的、访问非 docker0 接口的请求做 SNAT，这样访问其他节点 Pod 的请求来源 IP 会被设置为 flannel.1 接口的 IP，导致目的 Pod 看不到真实的来源 Pod IP。 flanneld 创建的 SNAT 规则比较温和，只对访问非 Pod 网段的请求做 SNAT

function create_flannel_unit(){
cat > $BASE_DIR/work/flanneld.service << EOF
[Unit]
Description=Flanneld overlay address etcd agent
After=network.target
After=network-online.target
Wants=network-online.target
After=etcd.service
Before=docker.service

[Service]
Type=notify
ExecStart=$BASE_DIR/bin/flanneld \\
  -etcd-cafile=/etc/kubernetes/cert/ca.pem \\
  -etcd-certfile=/etc/flanneld/cert/flanneld.pem \\
  -etcd-keyfile=/etc/flanneld/cert/flanneld-key.pem \\
  -etcd-endpoints=${ETCD_ENDPOINTS} \\
  -etcd-prefix=${FLANNEL_ETCD_PREFIX} \\
  -iface=${IFACE} \\
  -ip-masq
ExecStartPost=$BASE_DIR/bin/mk-docker-opts.sh -k DOCKER_NETWORK_OPTIONS -d /run/flannel/docker
Restart=always
RestartSec=5
StartLimitInterval=0

[Install]
WantedBy=multi-user.target
RequiredBy=docker.service
EOF
}

#分发 flanneld systemd unit 文件到所有节点
function scp_unit_node(){
for node_ip in ${ADD_NODES[@]}
  do
    echo ">>> ${node_ip}"
    scp flanneld.service $USERNAME@${node_ip}:/etc/systemd/system/
  done
}

#启动各个节点flannel
function start_flanneld_server(){
for node_ip in ${ADD_NODES[@]}
  do
    echo ">>> ${node_ip}"
    ssh root@${node_ip} "systemctl daemon-reload && systemctl enable flanneld && systemctl restart flanneld"
  done
}

#检查各个节点启动结果
function check_start_result(){
for node_ip in ${ADD_NODES[@]}
  do
    echo ">>> ${node_ip}"
    ssh root@${node_ip} "systemctl status flanneld|grep Active"
  done
}

#检查分配给各 flanneld 的 Pod 网段信息
function check_netinfo(){
etcdctl \
  --endpoints=${ETCD_ENDPOINTS} \
  --ca-file=/etc/kubernetes/cert/ca.pem \
  --cert-file=/etc/flanneld/cert/flanneld.pem \
  --key-file=/etc/flanneld/cert/flanneld-key.pem \
  get ${FLANNEL_ETCD_PREFIX}/config
}

function check_subnet(){
etcdctl \
  --endpoints=${ETCD_ENDPOINTS} \
  --ca-file=/etc/kubernetes/cert/ca.pem \
  --cert-file=/etc/flanneld/cert/flanneld.pem \
  --key-file=/etc/flanneld/cert/flanneld-key.pem \
  ls ${FLANNEL_ETCD_PREFIX}/subnets
}
function deploy_flannel(){
scp_flanneld
create_flannel_request
cd $BASE_DIR/work
#igenerate_private_key
scp_private_key
#insert_netinfo_etcd
create_flannel_unit
scp_unit_node
start_flanneld_server
cd -
}

deploy_flannel
check_start_result
check_netinfo
check_subnet
