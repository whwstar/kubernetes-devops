#!/bin/bash

BASE_DIR=/opt/kubernetes
#################################################################

#kubectl 作为集群的管理工具，需要被授予最高权限，这里创建具有最高权限的 admin 证书。

#创建证书签名请求
#################################################################
#O 为 system:masters，kube-apiserver 收到该证书后将请求的 Group 设置为 system:masters
#预定义的 ClusterRoleBinding cluster-admin 将 Group system:masters 与 Role cluster-admin 绑定，该 Role 授予所有 API的权限
#该证书只会被 kubectl 当做 client 证书使用，所以 hosts 字段为空
#
#################################################################
function create_csr(){
cat > admin-csr.json <<EOF
{
  "CN": "admin",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "system:masters",
      "OU": "mobvoi"
    }
  ]
}
EOF
}

#生成证书和私钥
function generate_ca_private(){
cfssl gencert -ca=$BASE_DIR/work/ca.pem \
  -ca-key=$BASE_DIR/work/ca-key.pem \
  -config=$BASE_DIR/work/ca-config.json \
  -profile=kubernetes admin-csr.json | cfssljson -bare admin
}

#创建 kubeconfig 文件
#kubeconfig 为 kubectl 的配置文件，包含访问 apiserver 的所有信息，如 apiserver 地址、CA 证书和自身使用的证书
##################################################################
#--certificate-authority：验证 kube-apiserver 证书的根证书
#--client-certificate、--client-key：刚生成的 admin 证书和私钥，连接 kube-apiserver 时使用
#--embed-certs=true：将 ca.pem 和 admin.pem 证书内容嵌入到生成的 kubectl.kubeconfig 文件中(不加时，写入的是证书文件路径，后续拷贝 kubeconfig 到其它机器时，还需要单独拷贝证书文件，不方便)
##################################################################
function create_kubeconfig(){
# 设置集群参数
kubectl config set-cluster kubernetes \
  --certificate-authority=$BASE_DIR/work/ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=kubectl.kubeconfig

# 设置客户端认证参数
kubectl config set-credentials admin \
  --client-certificate=$BASE_DIR/work/admin.pem \
  --client-key=$BASE_DIR/work/admin-key.pem \
  --embed-certs=true \
  --kubeconfig=kubectl.kubeconfig

# 设置上下文参数
kubectl config set-context kubernetes \
  --cluster=kubernetes \
  --user=admin \
  --kubeconfig=kubectl.kubeconfig

# 设置默认上下文
kubectl config use-context kubernetes --kubeconfig=kubectl.kubeconfig
}

create_csr
generate_ca_private
create_kubeconfig
