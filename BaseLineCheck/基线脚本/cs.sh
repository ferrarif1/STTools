#! /bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/root/bin

####文件备份
cp -p /etc/pam.d/system-auth{,.bak} &&\
cp -p /etc/pam.d/passwd{,.bak} &&\
cp -p /etc/pam.d/common-password{,.bak} &&\
cp -p /etc/login.defs{,.bak} &&\
cp -p /etc/profile{,.bak} &&\
cp -p /etc/rsyslog.conf{,.bak} &&\
cp -p /etc/ssh/sshd_config{,.bak} &&\
cp -p /etc/security/limits.conf{,.bak} &&\
cp -p /etc/hosts.allow{,.bak} &&\
cp -p /etc/hosts.deny{,.bak} &&\
cp -p /etc/host.conf{,.bak}

for i in `cat bf.txt`;
do
	if [ -f "$i.bak"  ];then
		echo "已存在"
	else
		cp -p $i{,.bak}
	fi
done

####口令锁定策略加固
if [ `echo $?` -eq 0 ];then
	if [ `cat /etc/pam.d/system-auth | grep -n ^auth.*required.*pam_tally2.so |wc -l` -eq 0 ];then
		echo 'auth required pam_tally2.so deny=5 onerr=fail no_magic_root unlock_time=180' >> /etc/pam.d/system-auth
	else
		#hs=`cat /etc/pam.d/system-auth | grep -n ^auth.*required.*pam_tally2.so | awk -F: '{ print $1 }'
		sed -i -r 's#^(auth).*(required).*(pam_tally2.so).*$#\1 \2 \3 deny=5 onerr=fail no_magic_root unlock_time=180#g' /etc/pam.d/system-auth
		#sed -i -r ''$hs's/.*/auth required pam_tally2.so deny=5 onerr=fail no_magic_root unlock_time=180/g' /etc/pam.d/system-auth
	fi
else
	echo "口令锁定策略执行错误"
	exit 0
fi

###口令生存周期
if [ `echo $?` -eq 0 ];then
	sz=(90 10 7)
	wz=(PASS_MAX_DAYS  PASS_MIN_DAYS PASS_WARN_AGE)
	for i in 0 1 2;
	do
		if [ `cat /etc/login.defs | grep -n ^${wz[$i]} |wc -l` -eq 0 ];then
			echo ${wz[$i]}	${sz[$i]} >> /etc/login.defs
		else
			sed -i -r 's#^('"${wz[$i]}"').*$#\1 '"${sz[$i]}"'#g' /etc/login.defs
		fi
	done	
else
	echo "口令生存周期策略执行错误"
	exit 0
fi

###口令复杂度
if [ `echo $?` -eq 0 ];then
	if [ `cat /etc/pam.d/system-auth | grep -n  "^.*password requisite.*pam_cracklib.so.*$" |wc -l` -eq 0 ];then
		echo 'password requisite  pam_cracklib.so try_first_pass retry=3 dcredit=-1 lcredit=-1 ucredit=-1 ocredit=-1 minlen=8' >> /etc/pam.d/system-auth
	else
		#hs= `cat /etc/pam.d/system-auth | grep -n  ^.*password requisite.*pam_cracklib.so.*$ | awk -F: '{ print $1 }'
		sed -i -r 's#^(password).*(requisitie).*(pam_cracklib.so).*$#\1 \2 \3 try_first_pass retry=3 dcredit=-1 lcredit=-1 ucredit=-1 ocredit=-1 minlen=8#g' /etc/pam.d/system-auth
		#sed -i -r ''$hs's/.*/password requisite  pam_cracklib.so try_first_pass retry=3 dcredit=-1 lcredit=-1 ucredit=-1 ocredit=-1 minlen=8/g' /etc/pam.d/system-auth
	fi
else
	echo "口令复杂策略执行错误"
	exit 0
fi

###锁定无关账户
if [ `echo $?` -eq 0 ];then
	for i in `cat yh.txt`;
	do
		if [ `cat /etc/passwd | grep $i|wc -l` -ne 0 ];then
			passwd -l $i
			usermod -s /bin/false username
		else
			echo "不存在此账户"
		fi
	done
	echo '完毕'
else
	echo "锁定无关账户执行错误"
	exit 0
fi

###口令重复次数设置
if [ `echo $?` -eq 0 ];then
	touch /etc/security/opasswd
    chown root:root /etc/security/opasswd
    chmod 600 /etc/security/opasswd
	if [ `grep "^.*pam_unix.so.*remember" /etc/pam.d/system-auth | wc -l` -eq 0 ];then
		sed -i -r 's#^(password.*pam_unix.so.*)$#\1 remember=5#g' /etc/pam.d/system-auth
	else
		sed -i -r 's#^(password.*pam_unix.so.*)remember=[0-9]*(.*)#\1 remember=5 \2#g' /etc/pam.d/system-auth
	fi
else
	echo "口令重复次数设置执行错误"
	exit 0
fi

###文件目录缺省权限设置
if [ `echo $?` -eq 0 ];then
	if [ `grep -E "umask *027|TMOUT=300|export TMOUT|HISTFILESIZE=5|HISTSIZE=5" /etc/profile | wc -l` -eq 0 ];then
		echo "umask 027" >> /etc/profile
		echo "TMOUT=300" >> /etc/profile
		echo "export TMOUT" >> /etc/profile
		echo "HISTFILESIZE=5" >> /etc/profile
		echo "HISTSIZE=5" >> /etc/profile
	#	source  /etc/profile
	else
		echo "***"
	fi
else
	echo "文件目录缺省权限执行错误"
	exit
fi

###修改SSH的Banner警告信息
if [ `echo $?` -eq 0 ];then
	touch /etc/ssh_banner
    chown bin:bin /etc/ssh_banner
    chmod 644 /etc/ssh_banner
    echo " Authorized only. All activity will be monitored and reported " > /etc/ssh_banner
else
	echo "修改SSH的Banner执行错误"
	exit
fi

###记录安全事件日志（需手动创建/var/adm目录）
if [ `echo $?` -eq 0 ];then
	echo "*.err;kern.debug;daemon.notice /var/adm/messages" >> /etc/rsyslog.conf
	if [ -f /var/adm/messages ];then
		echo '***'
	else
		touch /var/adm/messages
		chmod 666 /var/adm/messages
		/etc/init.d/syslog restart
	fi
else
	echo "事件日志修改执行错误"
	exit
fi

###创建普通用户
if [ `echo $?` -eq 0 ];then
	read -p "输入用户名：" yhm
	read -p "输入密码：" mm
	i=`cat /etc/passwd | cut -f1 -d':' | grep -w "$yhm" -c`
	if [ $yhm == '' ];then
		echo "请输入用户名"
		exit
	elif [ $i -le 0 ]; then
		useradd "$yhm" &&\
		echo "$mm"|passwd --stdin "$yhm"
		if [ -f /etc/sudoers.bak ];then
			echo '***'
		else
			cp /etc/sudoers{,.bak}
		fi
	echo "$yhm ALL=(ALL) NOPASSWD: ALL" >>/etc/sudoers
	else
	#显示用户存在
		echo "用户已存在"
		exit
	fi
else
	echo "创建用户失败"
	exit
fi

###修改ssh配置文件
if [ `echo $?` -eq 0 ];then
	sed -i -r 's/^#Port.*/Port 22/g' /etc/ssh/sshd_config
	sed -i -r 's/^#PermitRootLogin.*/PermitRootLogin no/g' /etc/ssh/sshd_config
	sed -i -r 's/^Protocol.*/Protocol 2/g' /etc/ssh/sshd_config
#	/etc/init.d/sshd restart
else
	echo "SSH配置文件修改执行错误"
	exit
fi

###系统core dump状态
if [ `echo $?` -eq 0 ];then
	if [ `cat /etc/security/limits.conf | grep ".*soft *core"|wc -l` -eq 0 ];then
		echo  "* soft core 0" >> /etc/security/limits.conf
	else
		sed -i -r 's/.*soft *core.*/ * soft core 0/g' /etc/security/limits.conf
	fi
	if [ `cat /etc/security/limits.conf | grep ".*hard *core"|wc -l` -eq 0 ];then
		echo  "* hard core 0" >> /etc/security/limits.conf
	else
		sed -i -r 's/.*hard *core.*/ * hard core 0/g' /etc/security/limits.conf
	fi
else
	echo "系统core dump状态执行错误"
	exit
fi

###禁用NFS
if [ `echo $?` -eq 0 ];then
	chkconfig --level 235 nfs off
else
	echo "禁用NFS执行错误"
	exit
fi

###禁止IP源路由
if [ `echo $?` -eq 0 ];then
	for f in `find /proc/sys/net/ipv4/conf/ -name accept_source_route`
    do
       echo 0 > $f
    done
else
	echo "禁止IP源路由错误"
	exit
fi

###更改主机解析顺序
if [ `echo $?` -eq 0 ];then
	echo "order hosts,bind" >> /etc/host.conf
	echo "multi on  " >> /etc/host.conf
	echo "nospoof on " >> /etc/host.conf
else
	echo "禁止IP源路由错误"
	exit
fi

