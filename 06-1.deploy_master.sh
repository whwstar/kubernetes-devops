#!/bin/bash

set -x
if [[ -f ./environment.sh ]];then
    source ./environment.sh
fi

for node_ip in ${NODE_IPS[@]}
  do
    echo ">>> ${node_ip}"
    scp ./bin/{kube-apiserver,kube-controller-manager,kube-proxy,kube-scheduler,kubelet,kubeadm} $USERNAME@${node_ip}:$BASE_DIR/bin/
    ssh root@${node_ip} "chmod +x $BASE_DIR/bin/*"
  done
