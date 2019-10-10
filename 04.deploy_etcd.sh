#!/bin/bash

set -x
if [[ -f ./environment.sh ]];then
    source ./environment.sh
fi

function scp_etcd(){
for host in ${NODE_IPS[@]}
do
    echo ">>> $host"
    scp $PWD/bin/etcd* $USERNAME@$host:$BASE_DIR/bin
    ssh $USERNAME@$host "chmod +x $BASE_DIR/bin/*"
done
}
function create_etcd_csr(){
cat > $BASE_DIR/work/etcd-csr.json <<EOF
{
  "CN": "etcd",
  "hosts": [
    "127.0.0.1",
    "${NODE_IPS[0]}",
    "${NODE_IPS[1]}",
    "${NODE_IPS[2]}"
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
      "O": "k8s",
      "OU": "mobvoi"
    }
  ]
}
EOF
}

function generate_private_key(){
cfssl gencert -ca=$BASE_DIR/work/ca.pem \
    -ca-key=$BASE_DIR/work/ca-key.pem \
    -config=$BASE_DIR/work/ca-config.json \
    -profile=kubernetes etcd-csr.json | cfssljson -bare etcd

for host in ${NODE_IPS[@]}
do
    echo ">>> $host"
    scp $PWD/etcd*.pem $USERNAME@$host:/etc/etcd/cert/
done
}

function create_etcd_unit_template(){
cat > $BASE_DIR/work/etcd.service.template <<EOF
[Unit]
Description=Etcd Server
After=network.target
After=network-online.target
Wants=network-online.target
Documentation=https://github.com/coreos

[Service]
Type=notify
WorkingDirectory=${ETCD_DATA_DIR}
ExecStart=${BASE_DIR}/bin/etcd \\
  --data-dir=${ETCD_DATA_DIR} \\
  --wal-dir=${ETCD_WAL_DIR} \\
  --name=##NODE_NAME## \\
  --cert-file=/etc/etcd/cert/etcd.pem \\
  --key-file=/etc/etcd/cert/etcd-key.pem \\
  --trusted-ca-file=/etc/kubernetes/cert/ca.pem \\
  --peer-cert-file=/etc/etcd/cert/etcd.pem \\
  --peer-key-file=/etc/etcd/cert/etcd-key.pem \\
  --peer-trusted-ca-file=/etc/kubernetes/cert/ca.pem \\
  --peer-client-cert-auth \\
  --client-cert-auth \\
  --listen-peer-urls=https://##NODE_IP##:2380 \\
  --initial-advertise-peer-urls=https://##NODE_IP##:2380 \\
  --listen-client-urls=https://##NODE_IP##:2379,http://127.0.0.1:2379 \\
  --advertise-client-urls=https://##NODE_IP##:2379 \\
  --initial-cluster-token=etcd-cluster-0 \\
  --initial-cluster=${ETCD_NODES} \\
  --initial-cluster-state=new \\
  --max-request-bytes=33554432 \\
  --quota-backend-bytes=8589934592 \\
  --heartbeat-interval=250 \\
  --election-timeout=2000
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
}

function generate_node_unit(){
len=${#NODE_NAMES[*]}
for (( i=0; i < $len; i++ ))
  do
    sed -e "s/##NODE_NAME##/${NODE_NAMES[i]}/" -e "s/##NODE_IP##/${NODE_IPS[i]}/" etcd.service.template > etcd-${NODE_IPS[i]}.service 
  done
}

function scp_etcd_unit(){
for node_ip in ${NODE_IPS[@]}
  do
    echo ">>> ${node_ip}"
    scp etcd-${node_ip}.service $USERNAME@${node_ip}:/etc/systemd/system/etcd.service
  done
}

#
function start_etcd_server(){
for node_ip in ${NODE_IPS[@]}
  do
    echo ">>> ${node_ip}"
    ssh ${USERNAME}@${node_ip} "mkdir -p ${ETCD_DATA_DIR} ${ETCD_WAL_DIR}"
    ssh ${USERNAME}@${node_ip} "systemctl daemon-reload && systemctl enable etcd && systemctl restart etcd " &
  done
} 

#验证服务状态
function check_start_result(){
for node_ip in ${NODE_IPS[@]}
  do
    echo ">>> ${node_ip} result"
    ssh $USERNAME@${node_ip} "systemctl status etcd|grep Active"
  done
}
#验证服务状态
function check_etct_status(){
for node_ip in ${NODE_IPS[@]}
  do
    echo ">>> ${node_ip}"
    ETCDCTL_API=3 $BASE_DIR/bin/etcdctl \
    --endpoints=https://${node_ip}:2379 \
    --cacert=/etc/kubernetes/cert/ca.pem \
    --cert=/etc/etcd/cert/etcd.pem \
    --key=/etc/etcd/cert/etcd-key.pem endpoint health
  done

}

function check_leader(){
ETCDCTL_API=3 $BASE_DIR/bin/etcdctl \
  -w table --cacert=/etc/kubernetes/cert/ca.pem \
  --cert=/etc/etcd/cert/etcd.pem \
  --key=/etc/etcd/cert/etcd-key.pem \
  --endpoints=${ETCD_ENDPOINTS} endpoint status 
}

function deploy_etcd_cluster(){
scp_etcd
create_etcd_csr
create_etcd_unit_template
cd $BASE_DIR/work
generate_private_key
generate_node_unit
scp_etcd_unit
start_etcd_server
}

deploy_etcd_cluster
check_start_result
check_etct_status
check_leader
