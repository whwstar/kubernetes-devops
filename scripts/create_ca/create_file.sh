#!/bin/bash

#CA 证书是集群所有节点共享的，只需要创建一个 CA 证书，后续创建的所有证书都由它签名
#CA 配置文件用于配置根证书的使用场景 (profile) 和具体参数 (usage，过期时间、服务端认证、客户端认证、加密等)，后续在签名其它证书时需要指定特定场景
function create_ca_config(){
cat > ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "87600h"
    },
    "profiles": {
      "kubernetes": {
        "usages": [
            "signing",
            "key encipherment",
            "server auth",
            "client auth"
        ],
        "expiry": "87600h"
      }
    }
  }
}
EOF
}


#创建证书签名请求文件
function create_ca_request(){
cat > ca-csr.json <<EOF
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
      "OU": "4Paradigm"
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
    create_ca_request
    cfssl gencert -initca ca-csr.json | cfssljson -bare ca
}

generate_ca
