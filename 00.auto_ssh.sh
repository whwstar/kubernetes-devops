#!/bin/sh
set -o nounset
#set -o errexit

if [ -f ./environment.sh ]; then
    source ./environment.sh
fi

DEST_USER=root
PASSWORD=123456
HOSTS_IP=$NODE_IPS
#if [ $# -ne 3 ]; then
#    echo "Usage:"
#    echo "$0 remoteUser remotePassword hostsFile"
#    exit 1
#fi
which expect
if [[ $? -eq 0 ]];then
	echo "go"
else
	yum install -y expect
fi
count=0
for node in ${NODE_IPS[@]}
do
	cat /etc/hosts | grep ${NODE_NAMES[$count]}
	if [[ $? -eq 0 ]];then	
		echo "$node    ${NODE_NAMES[$count]} has been add"
	else
		echo "$node    ${NODE_NAMES[$count]}">> /etc/hosts
	fi
	count=$(expr $count + 1)
done

SSH_DIR=~/.ssh
SCRIPT_PREFIX=./tmp
echo ===========================
# 1. prepare  directory .ssh
mkdir $SSH_DIR
chmod 700 $SSH_DIR

# 2. generat ssh key
TMP_SCRIPT=$SCRIPT_PREFIX.sh
echo  "#!/usr/bin/expect">$TMP_SCRIPT
echo  "spawn ssh-keygen -b 1024 -t rsa">>$TMP_SCRIPT
echo  "expect *key*">>$TMP_SCRIPT
echo  "send \r">>$TMP_SCRIPT
if [ -f $SSH_DIR/id_rsa ]; then
    echo  "expect *verwrite*">>$TMP_SCRIPT
    echo  "send y\r">>$TMP_SCRIPT
fi
echo  "expect *passphrase*">>$TMP_SCRIPT
echo  "send \r">>$TMP_SCRIPT
echo  "expect *again:">>$TMP_SCRIPT
echo  "send \r">>$TMP_SCRIPT
echo  "interact">>$TMP_SCRIPT

chmod +x $TMP_SCRIPT

/usr/bin/expect $TMP_SCRIPT
rm $TMP_SCRIPT

# 3. generat file authorized_keys
cat $SSH_DIR/id_rsa.pub>>$SSH_DIR/authorized_keys

# 4. chmod 600 for file authorized_keys
chmod 600 $SSH_DIR/authorized_keys
echo ===========================
# 5. copy all files to other hosts
for ip in ${HOSTS_IP[@]}
do
    if [ "x$ip" != "x" ]; then
        echo -------------------------
        TMP_SCRIPT=${SCRIPT_PREFIX}.$ip.sh
        # check known_hosts
        val=`ssh-keygen -F $ip`
        if [ "x$val" == "x" ]; then
            echo "$ip not in $SSH_DIR/known_hosts, need to add"
            val=`ssh-keyscan $ip 2>/dev/null`
            if [ "x$val" == "x" ]; then
                echo "ssh-keyscan $ip failed!"
            else
                echo $val>>$SSH_DIR/known_hosts
            fi
        fi
        echo "copy $SSH_DIR to $ip"

        echo  "#!/usr/bin/expect">$TMP_SCRIPT
        echo  "spawn scp -r  $SSH_DIR $DEST_USER@$ip:~/">>$TMP_SCRIPT
        echo  "expect *assword*">>$TMP_SCRIPT
        echo  "send $PASSWORD\r">>$TMP_SCRIPT
        echo  "interact">>$TMP_SCRIPT

        chmod +x $TMP_SCRIPT
        #echo "/usr/bin/expect $TMP_SCRIPT" >$TMP_SCRIPT.do
        #sh $TMP_SCRIPT.do&

        /usr/bin/expect $TMP_SCRIPT
        rm $TMP_SCRIPT
        echo "copy done."
    fi
done

echo done.
