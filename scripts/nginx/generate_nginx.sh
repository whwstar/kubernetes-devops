#!/bin/bash

wget http://nginx.org/download/nginx-1.15.3.tar.gz
tar -xzvf nginx-1.15.3.tar.gz
cd nginx-1.15.3
#--with-stream：开启 4 层透明转发(TCP Proxy)功能
#--without-xxx：关闭所有其他功能，这样生成的动态链接二进制程序依赖最小
mkdir nginx-prefix
./configure --with-stream --without-http --prefix=$(pwd)/nginx-prefix --without-http_uwsgi_module --without-http_scgi_module --without-http_fastcgi_module

make && make install

#查看nginx版本
./nginx-prefix/sbin/nginx -v

#查看 nginx 动态链接的库
ldd ./nginx-prefix/sbin/nginx
