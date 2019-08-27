#!/bin/bash

set -x

if [ -f ./environment.sh ]; then
    source ./environment.sh
fi

#kube-proxy 运行在所有 worker 节点上，它监听 apiserver 中 service 和 endpoint 的变化情况，创建路由规则以提供服务 IP 和负载均衡功能
#使用 ipvs 模式的 kube-proxy 的部署方式

function create_csr(){
#CN：指定该证书的 User 为 system:kube-proxy；
#预定义的 RoleBinding system:node-proxier 将User system:kube-proxy 与 Role system:node-proxier 绑定，该 Role 授予了调用 kube-apiserver Proxy 相关 API 的权限；
#该证书只会被 kube-proxy 当做 client 证书使用，所以 hosts 字段为空
cat > $BASE_DIR/work/kube-proxy-csr.json <<EOF
{
  "CN": "system:kube-proxy",
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

function generate_crt_key(){
cfssl gencert -ca=$BASE_DIR/work/ca.pem \
  -ca-key=$BASE_DIR/work/ca-key.pem \
  -config=$BASE_DIR/work/ca-config.json \
  -profile=kubernetes  kube-proxy-csr.json | cfssljson -bare kube-proxy
}

function create_kubeconfig(){
#设置集群参数
kubectl config set-cluster kubernetes \
  --certificate-authority=$BASE_DIR/work/ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=kube-proxy.kubeconfig

# 设置客户端认证参数
kubectl config set-credentials kube-proxy \
  --client-certificate=kube-proxy.pem \
  --client-key=kube-proxy-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-proxy.kubeconfig

#设置上下文参数
kubectl config set-context default \
  --cluster=kubernetes \
  --user=kube-proxy \
  --kubeconfig=kube-proxy.kubeconfig
#设置默认上下文
kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig
}


function distribution_kubeconfig(){
for node_name in ${ADD_NODES[@]}
  do
    echo ">>> ${node_name}"
    scp kube-proxy.kubeconfig $USERNAME@${node_name}:/etc/kubernetes/
  done
}

function create_kubeproxy_unit(){
#bindAddress: 监听地址；
#clientConnection.kubeconfig: 连接 apiserver 的 kubeconfig 文件；
#clusterCIDR: kube-proxy 根据 --cluster-cidr 判断集群内部和外部流量，指定 --cluster-cidr 或 --masquerade-all 选项后 kube-proxy 才会对访问 Service IP 的请求做 SNAT；
#hostnameOverride: 参数值必须与 kubelet 的值一致，否则 kube-proxy 启动后会找不到该 Node，从而不会创建任何 ipvs 规则；
#mode: 使用 ipvs 模式
#从 v1.10 开始，kube-proxy 部分参数可以配置文件中配置。可以使用 --write-config-to 选项生成该配置文件
cat > kube-proxy-config.yaml.template <<EOF
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
clientConnection:
  burst: 200
  kubeconfig: "/etc/kubernetes/kube-proxy.kubeconfig"
  qps: 100
bindAddress: ##NODE_IP##
healthzBindAddress: ##NODE_IP##:10256
metricsBindAddress: ##NODE_IP##:10249
enableProfiling: true
clusterCIDR: ${CLUSTER_CIDR}
hostnameOverride: ##NODE_NAME##
mode: "ipvs"
portRange: ""
kubeProxyIPTablesConfiguration:
  masqueradeAll: false
kubeProxyIPVSConfiguration:
  scheduler: rr
  excludeCIDRs: []
EOF

#创建kube-proxy systemd unit 文件
cat > kube-proxy.service <<EOF
[Unit]
Description=Kubernetes Kube-Proxy Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target

[Service]
WorkingDirectory=${K8S_DIR}/kube-proxy
ExecStart=$BASE_DIR/bin/kube-proxy \\
  --config=/etc/kubernetes/kube-proxy-config.yaml \\
  --logtostderr=true \\
  --v=2
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

}

function distribution_proxy_config(){
addnodes_len=${#ADD_NODES[@]}
for (( i=0; i < $addnodes_len; i++ ))
  do 
    echo ">>> ${ADD_NODES[i]}"
    sed -e "s/##NODE_NAME##/${ADD_NODES[i]}/" -e "s/##NODE_IP##/${ADDNODES_IP[i]}/" kube-proxy-config.yaml.template > kube-proxy-config-${ADD_NODES[i]}.yaml.template
    scp kube-proxy-config-${ADD_NODES[i]}.yaml.template $USERNAME@${ADD_NODES[i]}:/etc/kubernetes/kube-proxy-config.yaml
  done
}

function distribution_unit(){
for node_name in ${ADD_NODES[@]}
  do 
    echo ">>> ${node_name}"
    scp kube-proxy.service $USERNAME@${node_name}:/etc/systemd/system/
  done
}


function start_kube_proxy(){
for node_ip in ${ADDNODES_IP[@]}
  do
    echo ">>> ${node_ip}"
    ssh $USERNAME@${node_ip} "mkdir -p ${K8S_DIR}/kube-proxy"
    ssh $USERNAME@${node_ip} "modprobe ip_vs_rr"
    ssh $USERNAME@${node_ip} "systemctl daemon-reload && systemctl enable kube-proxy && systemctl restart kube-proxy"
  done
}

function check_status(){
for node_ip in ${ADDNODES_IP[@]}
  do
    echo ">>> ${node_ip}"
    ssh $USERNAME@${node_ip} "systemctl status kube-proxy|grep Active"
  done
}

#查看 ipvs 路由规则
function check_ipvs_rule(){
for node_ip in ${ADDNODES_IP[@]}
  do
    echo ">>> ${node_ip}"
    ssh $USERNAME@${node_ip} "/usr/sbin/ipvsadm -ln"
  done

}


#部署kube-proxy
function deploy_kube_proxy(){
create_csr
cd $BASE_DIR/work
generate_crt_key
create_kubeconfig
distribution_kubeconfig
create_kubeproxy_unit
distribution_proxy_config
distribution_unit
start_kube_proxy
}

function check(){
check_status
check_ipvs_rule
}

deploy_kube_proxy
check
