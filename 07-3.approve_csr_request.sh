#!/bin/bash

set -x

if [ -f ./environment.sh ]; then
    source ./environment.sh
fi

#kubelet 启动后使用 --bootstrap-kubeconfig 向 kube-apiserver 发送 CSR 请求，当这个 CSR 被 approve 后，kube-controller-manager 为 kubelet 创建 TLS 客户端证书、私钥和 --kubeletconfig 文件
#注意：kube-controller-manager 需要配置 --cluster-signing-cert-file 和 --cluster-signing-key-file 参数，才会为 TLS Bootstrap 创建证书和私钥
kubectl get csr
kubectl get nodes

#创建三个 ClusterRoleBinding，分别用于自动 approve client、renew client、renew server 证书
function auto_approve_csr(){

cat > $BASE_DIR/work/csr-crb.yaml <<EOF
 # Approve all CSRs for the group "system:bootstrappers"
 kind: ClusterRoleBinding
 apiVersion: rbac.authorization.k8s.io/v1
 metadata:
   name: auto-approve-csrs-for-group
 subjects:
 - kind: Group
   name: system:bootstrappers
   apiGroup: rbac.authorization.k8s.io
 roleRef:
   kind: ClusterRole
   name: system:certificates.k8s.io:certificatesigningrequests:nodeclient
   apiGroup: rbac.authorization.k8s.io
---
 # To let a node of the group "system:nodes" renew its own credentials
 kind: ClusterRoleBinding
 apiVersion: rbac.authorization.k8s.io/v1
 metadata:
   name: node-client-cert-renewal
 subjects:
 - kind: Group
   name: system:nodes
   apiGroup: rbac.authorization.k8s.io
 roleRef:
   kind: ClusterRole
   name: system:certificates.k8s.io:certificatesigningrequests:selfnodeclient
   apiGroup: rbac.authorization.k8s.io
---
# A ClusterRole which instructs the CSR approver to approve a node requesting a
# serving cert matching its client cert.
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: approve-node-server-renewal-csr
rules:
- apiGroups: ["certificates.k8s.io"]
  resources: ["certificatesigningrequests/selfnodeserver"]
  verbs: ["create"]
---
 # To let a node of the group "system:nodes" renew its own server credentials
 kind: ClusterRoleBinding
 apiVersion: rbac.authorization.k8s.io/v1
 metadata:
   name: node-server-cert-renewal
 subjects:
 - kind: Group
   name: system:nodes
   apiGroup: rbac.authorization.k8s.io
 roleRef:
   kind: ClusterRole
   name: approve-node-server-renewal-csr
   apiGroup: rbac.authorization.k8s.io
EOF

}

#查看 kubelet 的情况
function check_kubelet_info(){
kubectl get nodes
#kube-controller-manager 为各 node 生成了 kubeconfig 文件和公私钥
ls -l /etc/kubernetes/kubelet.kubeconfig
ls -l /etc/kubernetes/cert/|grep kubelet

#没有自动生成 kubelet server 证书

} 


#kubelet api 认证和授权
#authentication.anonymous.enabled：设置为 false，不允许匿名访问 10250 端口；
#authentication.x509.clientCAFile：指定签名客户端证书的 CA 证书，开启 HTTPs 证书认证；
#authentication.webhook.enabled=true：开启 HTTPs bearer token 认证；
#authroization.mode=Webhook

#kubelet 收到请求后，使用 clientCAFile 对证书签名进行认证，或者查询 bearer token 是否有效。如果两者都没通过，则拒绝请求，提示 Unauthorized
#curl -s --cacert /etc/kubernetes/cert/ca.pem https://10.1.204.167:10250/metrics
#curl -s --cacert /etc/kubernetes/cert/ca.pem -H "Authorization: Bearer 123456" https://10.1.204.167:10250/metrics
#通过认证后，kubelet 使用 SubjectAccessReview API 向 kube-apiserver 发送请求，查询证书>或 token 对应的 user、group 是否有操作资源的权限(RBAC)
#权限不足的证书
#curl -s --cacert /etc/kubernetes/cert/ca.pem --cert /etc/kubernetes/cert/kube-controller-manager.pem --key /etc/kubernetes/cert/kube-controller-manager-key.pem https://${NODE_IPS[0]}:10250/metrics
#Forbidden (user=system:kube-controller-manager, verb=get, resource=nodes, subresource=metrics)
# 使用部署 kubectl 命令行工具时创建的、具有最高权限的 admin 证书
#curl -s --cacert /etc/kubernetes/cert/ca.pem --cert $BASE_DIR/work/admin.pem --key $BASE_DIR/work/admin-key.pem https://${NODE_IPS[0]}:10250/metrics|head

auto_approve_csr
cd $BASE_DIR/work/
kubectl apply -f csr-crb.yaml
check_kubelet_info
cd -

#预定义的 ClusterRole system:kubelet-api-admin 授予访问 kubelet 所有 API 的权限(kube-apiserver 使用的 kubernetes 证书 User 授予了该权限)
#kubectl describe clusterrole system:kubelet-api-admin

