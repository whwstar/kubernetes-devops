#!/bin/bash

set -x

if [ -f ./environment.sh ]; then
    source ./environment.sh
fi

mkdir -p $BASE_DIR/{cert,bin}
cp $PWD/bin/cfssl* $BASE_DIR/bin/
chmod +x $BASE_DIR/bin/*
cd  $PWD/work
#CA 证书是集群所有节点共享的，只需要创建一个 CA 证书，后续创建的所有证书都由它签名
#CA 配置文件用于配置根证书的使用场景 (profile) 和具体参数 (usage，过期时间、服务端认证、客户端认证、加密等)，后续在签名其它证书时需要指定特定场景
function create_ca_config(){
#signing：表示该证书可用于签名其它证书，生成的 ca.pem 证书中 CA=TRUE
#server auth：表示 client 可以用该该证书对 server 提供的证书进行验证
#client auth：表示 server 可以用该该证书对 client 提供的证书进行验证
cat > $BASE_DIR/work/ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "876000h"
    },
    "profiles": {
      "kubernetes": {
        "usages": [
            "signing",
            "key encipherment",
            "server auth",
            "client auth"
        ],
        "expiry": "876000h"
      }
    }
  }
}
EOF
}


#创建证书签名请求文件
function create_csr(){
#CN：Common Name，kube-apiserver 从证书中提取该字段作为请求的用户名 (User Name)，浏览器使用该字段验证网站是否合法；
#O：Organization，kube-apiserver 从证书中提取该字段作为请求用户所属的组 (Group)
#kube-apiserver 将提取的 User、Group 作为 RBAC 授权的用户标识

cat > $BASE_DIR/work/ca-csr.json <<EOF
{
  "CN": "kubernetes",
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
  ],
  "ca": {
    "expiry": "876000h"
 }
}
EOF
}

function generate_ca() {
    create_ca_config
    create_csr
    cd $BASE_DIR/work
    cfssl gencert -initca ca-csr.json | cfssljson -bare ca
}

generate_ca
for host in ${NODE_IPS[@]}
do
    echo ">>>$host"
    scp  $BASE_DIR/work/{ca*.pem,ca-config.json} $USERNAME@$host:/etc/kubernetes/cert/
done
cd -

