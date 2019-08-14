#!/bin/bash

set -x
if [[ -f ./environment.sh ]];then
    source ./environment.sh
fi

function deploy_nginx(){ 
for node_ip in ${NODE_IPS[@]}
  do
    echo ">>> ${node_ip}"
    ssh $USERNAME@${node_ip} "mkdir -p $BASE_DIR/kube-nginx/{conf,logs,sbin}"
    scp bin/nginx $USERNAME@$node_ip:$BASE_DIR/kube-nginx/sbin/kube-nginx
    ssh $USERNAME@${node_ip} "chmod +x $BASE_DIR/kube-nginx/sbin/*"
  done

}

function create_nginx_config(){
cat > $BASE_DIR/work/kube-nginx.conf <<EOF
worker_processes 1;

events {
    worker_connections  1024;
}

stream {
    upstream backend {
        hash $remote_addr consistent;
        server 10.1.204.167:6443        max_fails=3 fail_timeout=30s;
        server 10.1.204.168:6443        max_fails=3 fail_timeout=30s;
        server 10.1.204.166:6443        max_fails=3 fail_timeout=30s;
    }

    server {
        listen 127.0.0.1:8443;
        proxy_connect_timeout 1s;
        proxy_pass backend;
    }
}
EOF

cat > $BASE_DIR/work/kube-nginx.service <<EOF
[Unit]
Description=kube-apiserver nginx proxy
After=network.target
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
ExecStartPre=$BASE_DIR/kube-nginx/sbin/kube-nginx -c $BASE_DIR/kube-nginx/conf/kube-nginx.conf -p $BASE_DIR/kube-nginx -t
ExecStart=$BASE_DIR/kube-nginx/sbin/kube-nginx -c $BASE_DIR/kube-nginx/conf/kube-nginx.conf -p $BASE_DIR/kube-nginx
ExecReload=$BASE_DIR/kube-nginx/sbin/kube-nginx -c $BASE_DIR/kube-nginx/conf/kube-nginx.conf -p $BASE_DIR/kube-nginx -s reload
PrivateTmp=true
Restart=always
RestartSec=5
StartLimitInterval=0
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
}

function scp_nginx_config(){
for node_ip in ${NODE_IPS[@]}
  do
    echo ">>> ${node_ip}"
    scp kube-nginx.conf  $USERNAME@${node_ip}:$BASE_DIR/kube-nginx/conf/kube-nginx.conf
    scp kube-nginx.service $USERNAME@${node_ip}:/etc/systemd/system/
  done

}

#启动 kube-nginx 服务
function start_kube_nginx(){
for node_ip in ${NODE_IPS[@]}
  do
    echo ">>> ${node_ip}"
    ssh $USERNAME@${node_ip} "systemctl daemon-reload && systemctl enable kube-nginx && systemctl restart kube-nginx"
  done
}

function check_kube_nginx(){
for node_ip in ${NODE_IPS[@]}
  do
    echo ">>> ${node_ip}"
    ssh $USERNAME@${node_ip} "systemctl status kube-nginx |grep 'Active:'"
  done
}

function deploy_kube_nginx(){
    deploy_nginx
    create_nginx_config
    start_kube_nginx
    cd $BASE_DIR/work/
    scp_nginx_config
    cd -
}
deploy_kube_nginx
check_kube_nginx


