#!/bin/bash

servers=(kube-apiserver kubelet kube-proxy kube-controller-manager flanneld etcd)

for i in ${servers[@]}
do
	echo "服务 $i 状态： "
	systemctl status $i | grep Active | awk '{print $2 $3}'
done
