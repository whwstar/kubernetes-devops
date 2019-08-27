#!/bin/bash

set -x
if [ -f ./environment.sh ]; then
    source ./environment.sh
fi
count=0
for host in ${ADD_NODES[@]}
do
    echo ">>> $host"
    ssh $USERNAME@$host   "yum install -y conntrack ntpdate ntp ipvsadm ipset jq iptables curl sysstat libseccomp wget"
    ssh $USERNAME@$host   "yum install -y epel-release"
#创建部署目录
    scp /etc/hosts $USERNAME@$host:/etc/hosts 
    scp -r $PWD/scripts $USERNAME@$host:$BASE_DIR/
    ssh $USERNAME@$host "cd $BASE_DIR/scripts && sh init.sh"
    ssh $USERNAME@$host   "mkdir -p  $BASE_DIR/{bin,work} /etc/{kubernetes,etcd}/cert"
    ssh $USERNAME@$host   " useradd -m docker"
    ssh $USERNAME@$host   "echo 'PATH=$BASE_DIR/bin:\$PATH' >>/root/.bashrc && source /root/.bashrc"
    count=$(expr $count + 1)
    scp environment.sh $USERNAME@$host:$BASE_DIR/bin
    ssh $USERNAME@$host "chmod +x $BASE_DIR/bin/*"
done

