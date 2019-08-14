#!/bin/bash

#清理防火墙规则，设置默认转发策略
function disable_firewalld(){
    systemctl stop firewalld
    systemctl disable firewalld
    iptables -F && iptables -X && iptables -F -t nat && iptables -X -t nat
    iptables -P FORWARD ACCEPT
}

#同时注释 /etc/fstab 中相应的条目，防止开机自动挂载 swap 分区
function disable_swap(){
    swapoff -a
    sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
}

#关闭selinux
function disable_selinux(){
    setenforce 0
    sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
}

#linux 系统开启了 dnsmasq 后(如 GUI 环境)，将系统 DNS Server 设置为 127.0.0.1，这会导致 docker 容器无法解析域名
function disable_dnsmasq(){
    systemctl stop dnsmasq
    systemctl disable dnsmasq
}

#加载内核模块相关
function add_kernel_about(){
    modprobe ip_vs_rr
    modprobe br_netfilter
}

#优化内核参数
function optimization_kernel(){
cat > kubernetes.conf <<EOF
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
net.ipv4.tcp_tw_recycle=0
vm.swappiness=0 # 禁止使用 swap 空间，只有当系统 OOM 时才允许使用它
vm.overcommit_memory=1 # 不检查物理内存是否够用
vm.panic_on_oom=0 # 开启 OOM
fs.inotify.max_user_instances=8192
fs.inotify.max_user_watches=1048576
fs.file-max=52706963
fs.nr_open=52706963
net.ipv6.conf.all.disable_ipv6=1
net.netfilter.nf_conntrack_max=2310720
EOF
cp kubernetes.conf  /etc/sysctl.d/kubernetes.conf
sysctl -p /etc/sysctl.d/kubernetes.conf
}

#设置系统时区
function set_timezone(){
# 调整系统 TimeZone
    timedatectl set-timezone Asia/Shanghai

# 将当前的 UTC 时间写入硬件时钟
    timedatectl set-local-rtc 0

# 重启依赖于系统时间的服务
    systemctl restart rsyslog 
    systemctl restart crond
}

function disable_no_needserver(){
systemctl stop postfix && systemctl disable postfix
}

#设置 rsyslogd 和 systemd journald
#systemd 的 journald 是 Centos 7 缺省的日志记录工具，它记录了所有系统、内核、Service Unit 的日志。
#相比 systemd，journald 记录的日志有如下优势：
#可以记录到内存或文件系统；(默认记录到内存，对应的位置为 /run/log/jounal)；
#可以限制占用的磁盘空间、保证磁盘剩余空间；
#可以限制日志文件大小、保存的时间；
#journald 默认将日志转发给 rsyslog，这会导致日志写了多份，/var/log/messages 中包含了太多无关日志，不方便后续查看，同时也影响系统性能。
function rsyslogd_set(){
mkdir /var/log/journal # 持久化保存日志的目录
mkdir /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/99-prophet.conf <<EOF
[Journal]
# 持久化保存到磁盘
Storage=persistent

# 压缩历史日志
Compress=yes

SyncIntervalSec=5m
RateLimitInterval=30s
RateLimitBurst=1000

# 最大占用空间 10G
SystemMaxUse=10G

# 单日志文件最大 200M
SystemMaxFileSize=200M

# 日志保存时间 2 周
MaxRetentionSec=2week

# 不将日志转发到 syslog
ForwardToSyslog=no
EOF
systemctl restart systemd-journald
}


disable_firewalld
disable_swap
disable_selinux
add_kernel_about
optimization_kernel
set_timezone
disable_no_needserver
rsyslogd_set
