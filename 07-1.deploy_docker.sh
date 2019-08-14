#!/bin/bash

set -x

if [ -f ./environment.sh ]; then
    source ./environment.sh
fi

function deploy_docker(){
for node_ip in ${NODE_IPS[@]}
  do
    echo ">>> ${node_ip}"
    scp bin/docker/*  $USERNAME@${node_ip}:$BASE_DIR/bin/
    ssh $USERNAME@${node_ip} "chmod +x $BASE_DIR/bin/*"
  done

}

#EOF 前后有双引号，这样 bash 不会替换文档中的变量，如 $DOCKER_NETWORK_OPTIONS (这些环境变量是 systemd 负责替换的。)；

#dockerd 运行时会调用其它 docker 命令，如 docker-proxy，所以需要将 docker 命令所在的目录加到 PATH 环境变量中；

#flanneld 启动时将网络配置写入 /run/flannel/docker 文件中，dockerd 启动前读取该文件中的环境变量 DOCKER_NETWORK_OPTIONS ，然后设置 docker0 网桥网段；

#如果指定了多个 EnvironmentFile 选项，则必须将 /run/flannel/docker 放在最后(确保 docker0 使用 flanneld 生成的 bip 参数)

function create_unit(){
cat > $BASE_DIR/work/docker.service <<"EOF"
[Unit]
Description=Docker Application Container Engine
Documentation=http://docs.docker.io

[Service]
WorkingDirectory=##DOCKER_DIR##
Environment="PATH=##BASE_DIR##/bin:/bin:/sbin:/usr/bin:/usr/sbin"
EnvironmentFile=-/run/flannel/docker
ExecStart=##BASE_DIR##/bin/dockerd $DOCKER_NETWORK_OPTIONS
ExecReload=/bin/kill -s HUP $MAINPID
Restart=on-failure
RestartSec=5
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
Delegate=yes
KillMode=process

[Install]
WantedBy=multi-user.target
EOF

sed -i -e "s|##DOCKER_DIR##|${DOCKER_DIR}|"  -e "s|##BASE_DIR##|${BASE_DIR}|" docker.service


cat > $BASE_DIR/work/docker-daemon.json <<EOF
{
    "registry-mirrors": ["https://docker.mirrors.ustc.edu.cn","https://hub-mirror.c.163.com"],
    "insecure-registries": ["mobvoi-u.docker.com"],
    "max-concurrent-downloads": 20,
    "live-restore": true,
    "max-concurrent-uploads": 10,
    "debug": true,
    "data-root": "${DOCKER_DIR}/data",
    "exec-root": "${DOCKER_DIR}/exec",
    "log-opts": {
      "max-size": "100m",
      "max-file": "5"
    }
}
EOF

}

function scp_config(){
for node_ip in ${NODE_IPS[@]}
  do
    echo ">>> ${node_ip}"
    scp docker.service $USERNAME@${node_ip}:/etc/systemd/system/
    ssh $USERNAME@${node_ip} "mkdir -p  /etc/docker/ ${DOCKER_DIR}/{data,exec}"
    scp docker-daemon.json $USERNAME@${node_ip}:/etc/docker/daemon.json
  done

}

function start_docker(){
for node_ip in ${NODE_IPS[@]}
  do
    echo ">>> ${node_ip}"
    ssh $USERNAME@${node_ip} "systemctl daemon-reload && systemctl enable docker && systemctl restart docker"
  done
}

function check_status(){
for node_ip in ${NODE_IPS[@]}
  do
    echo ">>> ${node_ip}"
    ssh $USERNAME@${node_ip} "systemctl status docker|grep Active"
  done
}

#检查 docker0 网桥
function check_docker_bridge(){
for node_ip in ${NODE_IPS[@]}
  do
    echo ">>> ${node_ip}"
    ssh ${USERNAME}@${node_ip} "/usr/sbin/ip addr show flannel.1 && /usr/sbin/ip addr show docker0"
  done
}

function deploy(){
    deploy_docker
    cd $BASE_DIR/work
    create_unit
    scp_config
    cd -
}
deploy
start_docker
check_status
check_docker_bridge
