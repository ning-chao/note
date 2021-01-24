#!/bin/bash

# 网卡名获取
NIC=`ifconfig | head -n 1 | awk -F:  '{print $1}'`
NETMASK=255.255.255.0
IP_FILE=ifcfg-$NIC
IP1=172.18.126.15
IP2=172.18.126.16
IP3=172.18.126.17
IP4=172.18.126.18
HN1=mc0
HN2=mc1
HN3=mc2
HN4=mc3

#修改机器名称
echo "修改机器名称："
echo -n "输入机器名："
read hostname
hostnamectl set-hostname $hostname


#修改网络
read -p "是否需要修改IP，Y/N？ " cip
        if [ $cip = y -o $cip = Y ];then
        	echo "修改机器IP"
		echo "输入本机IP："
		read ip
		sed -i 's/^BOOTPROTO.*$/BOOTPROTO=static/' /etc/sysconfig/network-scripts/$IP_FILE
		sed -i 's/^ONBOOT.*$/BOOTPROTO=static/' /etc/sysconfig/network-scripts/$IP_FILE
		sed -i 's/^IPV6INIT.*/IPV6INIT=no/' /etc/sysconfig/network-scripts/$IP_FILE
		sed -i 's/^IPV6_AUTOCONF.*&/IPV6_AUTOCONF=no/' /etc/sysconfig/network-scripts/$IP_FILE
		sed -i 's/^IPV6_DEFROUTE.*/IPV6_DEFROUTE=no/' /etc/sysconfig/network-scripts/$IP_FILE
		sed -i 's/^IPV6_FAILURE_FATAL.*/IPV6_FAILURE_FATAL=no/' /etc/sysconfig/network-scripts/$IP_FILE
		echo "IPADDR=$ip" >> /etc/sysconfig/network-scripts/$IP_FILE
		echo "NETMASK=$NETMASK" >> /etc/sysconfig/network-scripts/$IP_FILE
		echo "网络配置文件修改完成"
	elif [ $cip = n -o $cip = N ];then
                echo "IP不需要修改"
        else
                read -p "30s后将自动执行下一步" -t 30
        fi
:<<!
echo "修改机器IP"
echo "输入本机IP："
read ip
sed -i 's/^BOOTPROTO.*$/BOOTPROTO=static/' /etc/sysconfig/network-scripts/$IP_FILE
sed -i 's/^ONBOOT.*$/BOOTPROTO=static/' /etc/sysconfig/network-scripts/$IP_FILE
sed -i 's/^IPV6INIT.*/IPV6INIT=no/' /etc/sysconfig/network-scripts/$IP_FILE
sed -i 's/^IPV6_AUTOCONF.*&/IPV6_AUTOCONF=no/' /etc/sysconfig/network-scripts/$IP_FILE
sed -i 's/^IPV6_DEFROUTE.*/IPV6_DEFROUTE=no/' /etc/sysconfig/network-scripts/$IP_FILE
sed -i 's/^IPV6_FAILURE_FATAL.*/IPV6_FAILURE_FATAL=no/' /etc/sysconfig/network-scripts/$IP_FILE
echo "IPADDR=$ip" >> /etc/sysconfig/network-scripts/$IP_FILE
echo "NETMASK=$NETMASK" >> /etc/sysconfig/network-scripts/$IP_FILE
echo "网络配置文件修改完成"
!

#重启网络
systemctl restart network
if [ $? -eq 0 ];then
	echo "网络已经正常重启"
else
	echo "网络异常"
	exit
fi

# 修改hosts文件
cat >> /etc/hosts << EOF
$IP1 $HN1
$IP2 $HN2
$IP3 $HN3
$IP4 $HN4
EOF
echo "已添加hosts文件"
cat /etc/hosts
# 禁用IPV6
cat >> /etc/sysctl.conf << EOF
net.ipv6.conf.all.disable_ipv6=1
EOF

cat >> /etc/sysconfig/network << EOF
        NETWORKING_IPV6=no
EOF

sysctl -p


ifconfig $NIC | grep 'inet6'

if [ $? -eq 0 ];then
	echo "IPV6未禁用"
else
	echo "IPV6已禁用"
fi

#关闭防火墙
systemctl disable firewalld
systemctl stop firewalld
echo "防火墙已关闭并禁用"

#关闭SELinux
sed -i '/SELINUX/s/enforcing/disabled/' /etc/selinux/config
setenforce 0
echo "SELinux已关闭并禁用"

#生成SSH密钥
echo "生成SSH密钥"
ssh-keygen -t rsa


#同步时间
read -p "输入当前时间：" CurrentTime
date -s "$CurrentTime"
hwclock -w
echo "时间已同步"

systemctl restart ntpd
if [ $? -eq 0 ];then
	echo "ntp已安装"
else	
	read -p "ntp未安装，是否安装，Y/N？ " go
	if [ $go = y -o $go = Y ];then
		yum install -y ntp
	elif [ $go = n -o $go = N ];then 
		echo "未安装。。略过"
	else
		read -p "30s后将自动执行下一步" -t 30
	fi
fi

#修改ntp配置文件
if [ $hostname = $HN1 ];then
	read -p "输入当前网段：" net
	sed -i '/mask/a restrict $net mask 255.255.255.0 nomodify notrap' /etc/ntp.conf
	sed -i '/^server/s/^/#/' /etc/ntp.conf
	sed -i '/3.centos.pool.ntp.org/a server mc0\nfudge 127.127.1.0 stratum 8' /etc/ntp.conf
	echo "ntp配置修改完成"
elif [ $hostname != $HN1 ];then
	sed -i '/^server/s/^/#/' /etc/ntp.conf
#	sed -i '/3.centos.pool.ntp.org/a server mc0\nfudge 127.127.1.0 stratum 8' /etc/ntp.conf
	echo "ntp配置修改完成"
fi

systemctl  restart ntpd  #启动ntpd服务
systemctl enable ntpd.service  #设置ntpd服务为开机启动

#配置进程限制：打开文件数
cat >> /etc/security/limits.conf << EOF
* -  nofile 65536
* soft/hard nproc  65536
EOF
echo "打开文件限制数量已修改"

#swappiness
#vm.swappiness=0代表尽量使用物理内存，数字越大代表可使用虚拟内存（即swap分区）越多
grep "vm.swappiness" /etc/sysctl.conf >> /dev/null

if [ $? -eq 0 ];then
	echo "vm.swappiness已存在"
else
	cat >> /etc/sysctl.conf << EOF
	vm.swappiness=10
EOF
fi
	
echo "swappiness已修改"
sysctl -p

#禁用透明大页面压缩，因为它可能带来CPU利用过高的问题此处设置为never
sed -i '$aecho never > /sys/kernel/mm/transparent_hugepage/defrag\necho never > /sys/kernel/mm/transparent_hugepage/defrag' /etc/rc.local
echo "关闭透明大页面压缩"


#创建目录
if test -d /home/share
then
	echo "share目录已存在"
else
	mkdir /home/share
fi



