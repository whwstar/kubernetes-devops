#!/bin/bash

set -x
if [ -f ./environment.sh ]; then
    source ./environment.sh
fi
#部署高可用kube-scheduler集群
#该集群包含 3 个节点，启动后将通过竞争选举机制产生一个 leader 节点，其它节点为阻塞状态。当 leader 节点不可用后，剩余节点将再次进行选举产生新的 leader 节点，从而保证服务的可用性

function create_config(){
#创建证书签名请求
#hosts 列表包含所有 kube-scheduler 节点 IP；
#CN 和 O 均为 system:kube-scheduler，kubernetes 内置的 ClusterRoleBindings system:kube-scheduler 将赋予 kube-scheduler 工作所需的权限
cat > $BASE_DIR/work/kube-scheduler-csr.json <<EOF
{
    "CN": "system:kube-scheduler",
    "hosts": [
      "127.0.0.1",
      "10.1.204.167",
      "10.1.204.168",
      "10.1.204.166"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
      {
        "C": "CN",
        "ST": "BeiJing",
        "L": "BeiJing",
        "O": "system:kube-scheduler",
        "OU": "mobvoi"
      }
    ]
}
EOF

#创建 kube-scheduler 配置文件
#--kubeconfig：指定 kubeconfig 文件路径，kube-scheduler 使用它连接和验证 kube-apiserver；
#--leader-elect=true：集群运行模式，启用选举功能；被选为 leader 的节点负责处理工作，其它节点为阻塞状态
cat >$BASE_DIR/work/kube-scheduler.yaml.template <<EOF
apiVersion: kubescheduler.config.k8s.io/v1alpha1
kind: KubeSchedulerConfiguration
bindTimeoutSeconds: 600
clientConnection:
  burst: 200
  kubeconfig: "/etc/kubernetes/kube-scheduler.kubeconfig"
  qps: 100
enableContentionProfiling: false
enableProfiling: true
hardPodAffinitySymmetricWeight: 1
healthzBindAddress: ##NODE_IP##:10251
leaderElection:
  leaderElect: true
metricsBindAddress: ##NODE_IP##:10251
EOF

#创建 kube-scheduler systemd unit 模板文件

cat > $BASE_DIR/work/kube-scheduler.service.template <<EOF
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
WorkingDirectory=${K8S_DIR}/kube-scheduler
ExecStart=${BASE_DIR}/bin/kube-scheduler \\
  --config=/etc/kubernetes/kube-scheduler.yaml \\
  --bind-address=##NODE_IP## \\
  --secure-port=10259 \\
  --port=0 \\
  --tls-cert-file=/etc/kubernetes/cert/kube-scheduler.pem \\
  --tls-private-key-file=/etc/kubernetes/cert/kube-scheduler-key.pem \\
  --authentication-kubeconfig=/etc/kubernetes/kube-scheduler.kubeconfig \\
  --client-ca-file=/etc/kubernetes/cert/ca.pem \\
  --requestheader-allowed-names="" \\
  --requestheader-client-ca-file=/etc/kubernetes/cert/ca.pem \\
  --requestheader-extra-headers-prefix="X-Remote-Extra-" \\
  --requestheader-group-headers=X-Remote-Group \\
  --requestheader-username-headers=X-Remote-User \\
  --authorization-kubeconfig=/etc/kubernetes/kube-scheduler.kubeconfig \\
  --logtostderr=true \\
  --v=2
Restart=always
RestartSec=5
StartLimitInterval=0

[Install]
WantedBy=multi-user.target
EOF

}

function generate_key(){
#生成证书和私钥
cfssl gencert -ca=$BASE_DIR/work/ca.pem \
  -ca-key=$BASE_DIR/work/ca-key.pem \
  -config=$BASE_DIR/work/ca-config.json \
  -profile=kubernetes kube-scheduler-csr.json | cfssljson -bare kube-scheduler

#kube-scheduler 使用 kubeconfig 文件访问 apiserver，该文件提供了 apiserver 地址、嵌入的 CA 证书和 kube-scheduler 证书
kubectl config set-cluster kubernetes \
  --certificate-authority=$BASE_DIR/work/ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=kube-scheduler.kubeconfig

kubectl config set-credentials system:kube-scheduler \
  --client-certificate=kube-scheduler.pem \
  --client-key=kube-scheduler-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-scheduler.kubeconfig

kubectl config set-context system:kube-scheduler \
  --cluster=kubernetes \
  --user=system:kube-scheduler \
  --kubeconfig=kube-scheduler.kubeconfig

kubectl config use-context system:kube-scheduler --kubeconfig=kube-scheduler.kubeconfig

for (( i=0; i < 3; i++ ))
  do
    sed -e "s/##NODE_NAME##/${NODE_NAMES[i]}/" -e "s/##NODE_IP##/${NODE_IPS[i]}/" kube-scheduler.yaml.template > kube-scheduler-${NODE_IPS[i]}.yaml
    sed -e "s/##NODE_NAME##/${NODE_NAMES[i]}/" -e "s/##NODE_IP##/${NODE_IPS[i]}/" kube-scheduler.service.template > kube-scheduler-${NODE_IPS[i]}.service
  done

}

function scp_config(){
for node_ip in ${NODE_IPS[@]}
  do
    echo ">>> ${node_ip}"
    scp kube-scheduler*.pem ${USERNAME}@${node_ip}:/etc/kubernetes/cert/
    scp kube-scheduler.kubeconfig ${USERNAME}@${node_ip}:/etc/kubernetes/
    scp kube-scheduler-${node_ip}.yaml ${USERNAME}@${node_ip}:/etc/kubernetes/kube-scheduler.yaml
    scp kube-scheduler-${node_ip}.service ${USERNAME}@${node_ip}:/etc/systemd/system/kube-scheduler.service
  done
}

function start_kube_scheduler(){
for node_ip in ${NODE_IPS[@]}
  do
    echo ">>> ${node_ip}"
    ssh ${USERNAME}@${node_ip} "mkdir -p ${K8S_DIR}/kube-scheduler"
    ssh ${USERNAME}@${node_ip} "systemctl daemon-reload && systemctl enable kube-scheduler && systemctl restart kube-scheduler"
  done
}

function check_status(){
for node_ip in ${NODE_IPS[@]}
  do
    echo ">>> ${node_ip}"
    ssh ${USERNAME}@${node_ip} "systemctl status kube-scheduler|grep Active"
  done
}

#查看输出的 metrics
function check_metrics(){
#10251：接收 http 请求，非安全端口，不需要认证授权
#10259：接收 https 请求，安全端口，需要认证授权
curl -s http://127.0.0.1:10251/metrics |head
curl -s --cacert $BASE_DIR/work/ca.pem --cert $BASE_DIR/work/admin.pem --key $BASE_DIR/work/admin-key.pem https://10.1.204.167:10259/metrics |head

#查看当前的 leader
kubectl get endpoints kube-scheduler --namespace=kube-system  -o yaml
}


function deploy_kube_scheduler(){
    create_config
    cd $BASE_DIR/work/
    generate_key
    scp_config
    cd -
}
deploy_kube_scheduler
start_kube_scheduler
check_status
sleep 10 
check_metrics
