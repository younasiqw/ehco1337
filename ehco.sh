#!/bin/bash
# https://github.com/sjlleo/ehco.sh
# Version: 0.1
# Description: Ehco Tunnel configuration script
# Author: sjlleo
# Thank You For Using
#
#                    GNU GENERAL PUBLIC LICENSE
#                       Version 3, 29 June 2007
#
# Copyright (C) 2007 Free Software Foundation, Inc. <https://fsf.org/>
# Everyone is permitted to copy and distribute verbatim copies
# of this license document, but changing it is not allowed.

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

[[ $EUID -ne 0 ]] && echo -e "[Error]请以root用户或者sudo提权运行本脚本！" && exit 1

ehco_version="1.0.7"
ehco_conf_dir="/usr/local/ehco/"
CPUFrame=$(arch)
SysID=$(cat /etc/os-release | grep ^ID=)

if [ ! -d $ehco_conf_dir ]; then
	mkdir $ehco_conf_dir
fi

python_model_check()
{
  if python3 -c "import $1" >/dev/null 2>&1
  then
      echo "1"
  else
      echo "0"
  fi
}

InitialEhco() {
    if [ ! -e "/usr/bin/ehco" ]; then
    	url="https://github.com/Ehco1996/ehco/releases/download/v$ehco_version/ehco_${ehco_version}_linux_$1"
    	echo "[Info]开始下载ehco文件..."
    	wget -O /usr/bin/ehco $url &> /dev/null
    	if [ $? -ne 0 ]; then
    		echo "[Info]wget包缺失，开始安装wget"
    		InstallWget
    		wget -O /usr/bin/ehco $url &> /dev/null
    	fi
    	echo "[Done]下载完成"
    	chmod +x /usr/bin/ehco
    	InitialEhcoConfigure
    	AddSystemService
	else
	    echo "您已安装Ehco，无需重复安装"
    fi
}

InstallWget() {
	case ${SysID} in
	*centos*)
		echo "[Info]安装wget包..."
		yum install wget -y &> /dev/null
		;;
	*debian*)
		echo "[Info]更新APT源..."
		apt update &> /dev/null
		echo "安装wget包..."
		apt install wget -y &> /dev/null
		;;
	*ubuntu*)
		echo "[Info]更新APT源..."
		apt update &> /dev/null
		echo "[Info]安装wget包..."
		apt install wget -y &> /dev/null
		;;
	*)
		echo "[Error]未知系统，请自行安装wget"
		exit 1
		;;
	esac
}

InitialEhcoConfigure() {
		echo "
{	
	\"web_port\": 9000,
	\"web_token\": \"leo123leo\",
	\"enable_ping\": false,
	\"relay_configs\":[
	]
}" > $ehco_conf_dir/ehco.json

    systemctl restart ehco &> /dev/null

	echo "[Success]已初始化配置文件"
}

AddSystemService() {
	case ${SysID} in
	*centos*)
		systemctlDIR="/usr/lib/systemd/system/"
		;;
	*debian*)
		systemctlDIR="/etc/systemd/system/"
		;;
	*ubuntu*)
		systemctlDIR="/etc/systemd/system/"
		;;
	*)
		echo "[Error]未知系统，请自行添加Systemctl"
		exit 1
		;;
	esac
	echo "[Unit]
Description=Ehco Tunnel Service
After=network.target

[Service]
Type=simple
Restart=always

WoringDirectory=/usr/bin/ehco
ExecStart=/usr/bin/ehco -c /usr/local/ehco/ehco.json

[Install]
WantedBy=multi-user.target" > $systemctlDIR/ehco.service
	systemctl daemon-reload
	systemctl start ehco.service
	systemctl enable ehco.service
}

AddNewRelay() {
    echo "正在检测必要组件是否工作正常.."
    netstat -help &> /dev/null
    if [ $? -ne 0 ]; then
        echo "net-tools包缺失，正在安装..."
        case ${SysID} in
    	*centos*)
    		yum install net-tools -y &> null
    		;;
    	*debian*)
    	    apt-get update &> null
    		apt-get install net-tools -y &> null
    		;;
    	*ubuntu*)
    	    apt-get update &> null
    		apt-get install net-tools -y &> null
    		;;
    	*)
    		echo "[Error]未知系统，请自行安装net-tools包"
    		exit 1
    		;;
    	esac
    else
        echo "一切正常，继续添加中转..."
    fi
	echo "添加新的中转记录"
	if [ $(cat $ehco_conf_dir/ehco.json | grep -c listen) -gt 1 ]; then
		endl=","
	fi
	echo -e "请选择当前模式：\n1.中转模式（在中转节点上部署）\n2.落地模式（在落地节点上部署）"
	read -p "请输入序号：" relayModule
	case {$relayModule} in 
		# 中转模式
		*1*)
		while true; do
			read -p "请输入本机监听端口：" listenPort
			if [ $(netstat -tlpn | grep -c "\b$listenPort\b") -gt 0 ]; then
				echo "端口已经被占用！"
			else
				break
			fi
		done

		read -p "请输入远程IP地址：" remoteIP
		read -p "请输入远程主机端口：" remotePort
		echo -e "请选择传输协议（需与落地一致）：\n1.mwss（稳定性极高且延时最低但传输速率最差）\n2.wss（较好的稳定性及较快的传输速率但延时较高）\n3.raw（无隧道直接转发、效率极高但无抗干扰能力）"
		read -p "输入序号：" num
		case {$num} in
			*1*)
				transport_type=mwss
				conf="\n\t{\n\t\t\"listen\": \"0.0.0.0:$listenPort\",\n\t\t\"listen_type\": \"raw\",\n\t\t\"transport_type\": \"$transport_type\",\n\t\t\"tcp_remotes\": [\"wss:\/\/$remoteIP:$remotePort\"],\n\t\t\"udp_remotes\": [\"$remoteIP:$remotePort\"]\n\t}$endl"
				;;
			*2*)
				transport_type=wss
				conf="\n\t{\n\t\t\"listen\": \"0.0.0.0:$listenPort\",\n\t\t\"listen_type\": \"raw\",\n\t\t\"transport_type\": \"$transport_type\",\n\t\t\"tcp_remotes\": [\"wss:\/\/$remoteIP:$remotePort\"],\n\t\t\"udp_remotes\": [\"$remoteIP:$remotePort\"]\n\t}$endl"
				;;
			*3*)
				transport_type=raw
				conf="\n\t{\n\t\t\"listen\": \"0.0.0.0:$listenPort\",\n\t\t\"listen_type\": \"raw\",\n\t\t\"transport_type\": \"$transport_type\",\n\t\t\"tcp_remotes\": [\"$remoteIP:$remotePort\"],\n\t\t\"udp_remotes\": [\"$remoteIP:$remotePort\"]\n\t}$endl"
				;;
		esac
		unset num
		
		sed -i "s/\"relay_configs\"\:\[/&$conf/" $ehco_conf_dir/ehco.json
		;;


		# 落地模式
		*2*)
		while true; do
			read -p "请输入本机监听端口：" listenPort
			if [ $(netstat -tlpn | grep -c "\b$listenPort\b") -gt 0 ]; then
				echo "端口已经被占用！"
			else
				break
			fi
		done

		read -p "请输入流量目标端口：" remotePort
		echo -e "请选择传输协议：\n1.mwss（稳定性极高且延时最低但传输速率最差）\n2.wss（较好的稳定性及较快的传输速率但延时较高）\n3.raw（无隧道直接转发、效率极高但无抗干扰能力）"
		read -p "输入序号（需与中转一致）：" num
		case {$num} in
			*1*)
				transport_type=mwss
				;;
			*2*)
				transport_type=wss
				;;
			*3*)
				transport_type=raw
				;;
		esac
		unset num
		conf="\n\t{\n\t\t\"listen\": \"0.0.0.0:$listenPort\",\n\t\t\"listen_type\": \"$transport_type\",\n\t\t\"transport_type\": \"raw\",\n\t\t\"tcp_remotes\": [\"0.0.0.0:$remotePort\"],\n\t\t\"udp_remotes\": [\"0.0.0.0:$remotePort\"]\n\t}$endl"
		sed -i "s/\"relay_configs\"\:\[/&$conf/" $ehco_conf_dir/ehco.json
		;;
		
		# 中继模式（这个坑以后再填）
		*100*)
		while true; do
			read -p "请输入本机监听端口：" listenPort
			if [ $(netstat -tlpn | grep -c "\b$listenPort\b") -gt 0 ]; then
				echo "端口已经被占用！"
			else
				break
			fi
		done
		read -p "请输入下一个链路的IP地址：" remoteIP
		read -p "请输入下一个链路的端口：" remotePort
		echo -e "请选择传输协议（监听端，请与上一个链路的中转传输协议保持一致）：\n1.mwss（稳定性极高且延时最低但传输速率最差）\n2.wss（较好的稳定性及较快的传输速率但延时较高）\n3.raw（无隧道直接转发、效率极高但无抗干扰能力）"
		read -p "输入序号（需与中转一致）：" num
		case {$num} in
			*1*)
				listen_type=mwss
				;;
			*2*)
				listen_type=wss
				;;
			*3*)
				listen_type=raw
				;;
		esac
		unset num
		echo -e "请选择传输协议（发送端，请与下一个链路的中转传输协议保持一致）：\n1.mwss（稳定性极高且延时最低但传输速率最差）\n2.wss（较好的稳定性及较快的传输速率但延时较高）\n3.raw（无隧道直接转发、效率极高但无抗干扰能力）"
		read -p "输入序号（需与中转一致）：" num
		case {$num} in
			*1*)
				transport_type=mwss
				;;
			*2*)
				transport_type=wss
				;;
			*3*)
				transport_type=raw
				;;
		esac
		unset num
	esac
	unset relayModule
	systemctl restart ehco
	echo "[Success]添加中转成功"
}

installEhco() {
	case {$CPUFrame} in
		*x86_64*)
			InitialEhco amd64
			;;
		*)
		    InitialEhco arm64
	esac
}

uninstallEhco() {
	systemctl stop ehco
	systemctl disable ehco
	rm -rf /usr/local/ehco/
	rm -f /usr/bin/ehco
	echo "[Success]卸载成功"
}

stopEhco() {
	systemctl stop ehco
	systemctl disable ehco
	echo "[Success]Ehco已暂停"
}

startEhco() {
	systemctl start ehco
	systemctl enable ehco
	echo "[Success]Ehco已开启"
}

rebootEhco() {
	systemctl restart ehco
	echo "[Success]Ehco已重启"
}

ConfPy() {
	case ${SysID} in
	*centos*)
		python3 -h &> null
		if [ $? -ne 0 ]; then
			echo "[Info]缺少Python3包，正在安装...这可能将花费若干分钟"
			yum install python3 -y &> null
		fi
		;;
	*debian*)
		python3 -h &> null
		if [ $? -ne 0 ]; then
			echo "[Info]缺少Python3包，正在安装...这可能将花费若干分钟"
			apt-get update &> null
			apt-get install python3 -y &> null
		fi
		;;
	*ubuntu*)
		python3 -h &> null
		if [ $? -ne 0 ]; then
			echo "[Info]缺少Python3包，正在安装...这可能将花费若干分钟"
			apt-get update &> null
			apt-get install python3 -y &> null
		fi
		;;
	*)
		python3 -h &> null
		if [ $? -ne 0 ]; then
			echo "[Error]未知系统，请自行安装Python3包"
			exit 1
		fi
		;;
	esac
	# 检查Python3模块环境
	result=`python_model_check dbus`
	if [ $result == 1 ]
	then
		echo "check python3-dbus......ok"
	else
		echo "check python3-dbus......no"
	    case ${SysID} in
		*centos*)
			ehco "[info]添加并更新EPEL源中..."
			yum install epel-release -y &> /dev/null
			echo "[Info]安装python3-dbus包..."
			yum install python3-dbus -y &> /dev/null
			;;
		*debian*)
			echo "[Info]更新APT源..."
			apt-get update &> /dev/null
			echo "[Info]安装python3-dbus包...对于系统性能较差的VPS，可能将花费若干分钟"
			apt-get install python3-dbus -y &> /dev/null
			;;
		*ubuntu*)
			echo "[Info]更新APT源..."
			apt-get update &> /dev/null
			echo "[Info]安装python3-dbus包..."
			apt-get install python3-dbus -y &> /dev/null
			;;
		*)
			echo "[Error]未知系统，请自行安装python3-dbus"
			exit 1
	    	;;
	  esac
	fi
	result=`python_model_check requests`
	if [ $result == 1 ]
	then
		echo "check requests......ok"
	else
		echo "check requests......no"
		echo "[Info] 开始安装requests包"
	 	pip3 install requests &> /dev/null
	 	
	 	if [ $? -ne 0 ]; then
	 		echo "[Info]检测到Minimal精简版系统，未内置pip管理工具"
	 		case ${SysID} in
			*centos*)
				echo "[Info]开始安装python3-pip包..."
				yum install python3-pip -y &> /dev/null
				;;
			*debian*)
				echo "[Info]更新APT源..."
				apt update &> /dev/null
				echo "[Info]开始安装python3-pip包..."
				apt install python3-pip -y &> /dev/null
				;;
			*ubuntu*)
				echo "[Info]更新APT源..."
				apt update &> /dev/null
				echo "[Info]开始安装python3-pip包..."
				apt install python3-pip -y &> /dev/null
				;;
			*)
				echo "[Error]未知系统，请自行安装python3-pip"
				exit 1
				;;
			esac
			pip3 install requests &> /dev/null
		fi
	fi
	# 脚本文件
	if [ ! -e "/usr/local/ehco/configurev01.py" ]; then
		echo "[Info]下载脚本文件中..."
		wget -O /usr/local/ehco/configurev01.py "https://cdn.jsdelivr.net/gh/sjlleo/ehco.sh/configurev01.py" &> null
	fi
	python3 /usr/local/ehco/configurev01.py
}

showMenu() {
	clear
	echo -e "Ehco 一键配置脚本 beta by sjlleo\n\n1. 安装Ehco\n2. 卸载Ehco\n3. 停止Ehco\n4. 启动Ehco\n5. 重启Ehco\n6. 添加记录\n7. 查看修改删除记录（需安装Python3依赖）\n8. 初始化配置\n"

	read -p "请输入选项：" num

	case ${num} in
	1)
		installEhco
		AddNewRelay
		;;
	2)
		uninstallEhco
		;;
	3)
		stopEhco
		;;
	4)
		startEhco
		;;
	5)
		rebootEhco
		;;		
	6)
		AddNewRelay
		;;
	7)
		ConfPy
		;;
	8)
		InitialEhcoConfigure
		systemctl restart ehco
		;;
	esac
}


showMenu
