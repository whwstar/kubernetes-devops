#!/bin/bash

set -x

if [ -f ./environment.sh ]; then
    source ./environment.sh
fi


cd addons/coredns/
cp coredns.yaml.base coredns.yaml 
sed -i -e "s/__PILLAR__DNS__DOMAIN__/${CLUSTER_DNS_DOMAIN}/" -e "s/__PILLAR__DNS__SERVER__/${CLUSTER_DNS_SVC_IP}/" coredns.yaml
kubectl create -f coredns.yaml
cd -



