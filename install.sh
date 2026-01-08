#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

# 解析命令行参数
API_HOST=""
API_KEY=""
NODE_ID=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --apiHost=*)
            API_HOST="${1#*=}"
            shift
            ;;
        --apiKey=*)
            API_KEY="${1#*=}"
            shift
            ;;
        --nodeID=*)
            NODE_ID="${1#*=}"
            shift
            ;;
        *)
            # 如果是版本号参数，保留给后面使用
            if [[ ! $1 =~ ^-- ]]; then
                VERSION_ARG="$1"
            fi
            shift
            ;;
    esac
done

# check os
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
    case $ID in
        debian|ubuntu|centos|rhel|fedora|rocky|alma)
            release=$ID
            ;;
        alpine)
            release="alpine"
            ;;
        *)
            release="unknown"
            ;;
    esac
elif [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue 2>/dev/null | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue 2>/dev/null | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue 2>/dev/null | grep -Eqi "alpine"; then
    release="alpine"
elif cat /proc/version 2>/dev/null | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version 2>/dev/null | grep -Eqi "ubuntu"; then
    release="ubuntu"
else
    echo -e "${red}未检测到系统版本！${plain}\n"
    echo -e "${yellow}支持的系统: Ubuntu, Debian, CentOS, Alpine Linux${plain}\n"
    exit 1
fi

arch=$(arch)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64-v8a"
elif [[ $arch == "s390x" ]]; then
    arch="s390x"
else
    arch="64"
    echo -e "${red}检测架构失败，使用默认架构: ${arch}${plain}"
fi

echo "架构: ${arch}"

if [ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ] ; then
    echo "本软件不支持 32 位系统(x86)，请使用 64 位系统(x86_64)，如果检测有误，请联系作者"
    exit 2
fi

os_version=""

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]] || [[ x"${release}" == x"rhel" ]] || [[ x"${release}" == x"fedora" ]] || [[ x"${release}" == x"rocky" ]] || [[ x"${release}" == x"alma" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}请使用 CentOS 7 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}请使用 Ubuntu 16 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}请使用 Debian 8 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"alpine" ]]; then
    if [[ ${os_version} -lt 3 ]]; then
        echo -e "${red}请使用 Alpine Linux 3.0 或更高版本的系统！${plain}\n" && exit 1
    fi
fi

install_base() {
    if [[ x"${release}" == x"centos" ]] || [[ x"${release}" == x"rhel" ]] || [[ x"${release}" == x"fedora" ]] || [[ x"${release}" == x"rocky" ]] || [[ x"${release}" == x"alma" ]]; then
        yum install epel-release -y
        yum install wget curl unzip tar crontabs socat -y
    elif [[ x"${release}" == x"alpine" ]]; then
        apk update
        apk add --no-cache wget curl unzip tar socat ca-certificates tzdata
        apk add --no-cache openrc
    else
        apt update -y
        apt install wget curl unzip tar cron socat -y
    fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ x"${release}" == x"alpine" ]]; then
        if [[ ! -f /etc/init.d/xrayr ]]; then
            return 2
        fi
        if rc-service xrayr status 2>/dev/null | grep -q "started"; then
            return 0
        else
            return 1
        fi
    else
        if [[ ! -f /etc/systemd/system/XrayR.service ]]; then
            return 2
        fi
        temp=$(systemctl status XrayR | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
        if [[ x"${temp}" == x"running" ]]; then
            return 0
        else
            return 1
        fi
    fi
}

install_acme() {
    curl https://get.acme.sh | sh
}

install_XrayR() {
    if [[ -e /usr/local/XrayR/ ]]; then
        rm /usr/local/XrayR/ -rf
    fi

    mkdir /usr/local/XrayR/ -p
	cd /usr/local/XrayR/

    if  [ $# == 0 ] ;then
        last_version=$(curl -Ls "https://api.github.com/repos/XrayR-project/XrayR/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}检测 XrayR 版本失败，可能是超出 Github API 限制，请稍后再试，或手动指定 XrayR 版本安装${plain}"
            exit 1
        fi
        echo -e "检测到 XrayR 最新版本：${last_version}，开始安装"
        wget -q -N --no-check-certificate -O /usr/local/XrayR/XrayR-linux.zip https://github.com/XrayR-project/XrayR/releases/download/${last_version}/XrayR-linux-${arch}.zip
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 XrayR 失败，请确保你的服务器能够下载 Github 的文件${plain}"
            exit 1
        fi
    else
        if [[ $1 == v* ]]; then
            last_version=$1
	else
	    last_version="v"$1
	fi
        url="https://github.com/XrayR-project/XrayR/releases/download/${last_version}/XrayR-linux-${arch}.zip"
        echo -e "开始安装 XrayR ${last_version}"
        wget -q -N --no-check-certificate -O /usr/local/XrayR/XrayR-linux.zip ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 XrayR ${last_version} 失败，请确保此版本存在${plain}"
            exit 1
        fi
    fi

    unzip XrayR-linux.zip
    rm XrayR-linux.zip -f
    chmod +x XrayR
    mkdir /etc/XrayR/ -p
    
    # 配置服务
    if [[ x"${release}" == x"alpine" ]]; then
        # 为 Alpine 配置 OpenRC 服务
        if [[ -f xrayr.initd ]]; then
            cp xrayr.initd /etc/init.d/xrayr
            chmod +x /etc/init.d/xrayr
        else
            file="https://github.com/qiuapeng921/XrayR-release/raw/master/xrayr.initd"
            wget -q -N --no-check-certificate -O /etc/init.d/xrayr ${file}
            chmod +x /etc/init.d/xrayr
        fi
        rc-update add xrayr default
        rc-service xrayr stop 2>/dev/null
        echo -e "${green}XrayR ${last_version}${plain} 安装完成，已设置开机自启"
    else
        rm /etc/systemd/system/XrayR.service -f
        file="https://github.com/qiuapeng921/XrayR-release/raw/master/XrayR.service"
        wget -q -N --no-check-certificate -O /etc/systemd/system/XrayR.service ${file}
        systemctl daemon-reload
        systemctl stop XrayR
        systemctl enable XrayR
        echo -e "${green}XrayR ${last_version}${plain} 安装完成，已设置开机自启"
    fi
    cp geoip.dat /etc/XrayR/
    cp geosite.dat /etc/XrayR/
    rm config.yml -f

    if [[ ! -f /etc/XrayR/config.yml ]]; then
        # 从 GitHub 下载配置文件模板
        echo -e "${yellow}正在下载配置文件模板...${plain}"
        wget -q -N --no-check-certificate -O /etc/XrayR/config.yml https://raw.githubusercontent.com/qiuapeng921/XrayR-release/master/config.yml
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载配置文件失败，请检查网络连接${plain}"
            exit 1
        fi
        echo -e ""
        echo -e "${green}开始配置 XrayR${plain}"
        
        # 如果命令行参数存在，使用命令行参数；否则交互式输入
        if [[ -n "$API_HOST" ]] && [[ -n "$API_KEY" ]] && [[ -n "$NODE_ID" ]]; then
            # 使用命令行参数
            api_host="$API_HOST"
            api_key="$API_KEY"
            node_id="$NODE_ID"
            echo -e "${green}使用命令行参数配置${plain}"
        else
            # 交互式输入
            echo -e "请输入面板信息（直接回车使用默认值）："
            echo -e ""
            
            # 读取 ApiHost
            if [[ -z "$API_HOST" ]]; then
                read -p "请输入 ApiHost (默认: http://127.0.0.1:667): " api_host
                api_host=${api_host:-http://127.0.0.1:667}
            else
                api_host="$API_HOST"
            fi
            
            # 读取 ApiKey
            if [[ -z "$API_KEY" ]]; then
                read -p "请输入 ApiKey (默认: 123): " api_key
                api_key=${api_key:-123}
            else
                api_key="$API_KEY"
            fi
            
            # 读取 NodeID
            if [[ -z "$NODE_ID" ]]; then
                read -p "请输入 NodeID (默认: 41): " node_id
                node_id=${node_id:-41}
            else
                node_id="$NODE_ID"
            fi
        fi
        
        # 使用兼容的方式修改配置文件，替换占位符
        config_file="/etc/XrayR/config.yml"
        sed "s|\${APIHOST}|${api_host}|g" ${config_file} > ${config_file}.tmp && mv ${config_file}.tmp ${config_file}
        sed "s|\${APIKEY}|${api_key}|g" ${config_file} > ${config_file}.tmp && mv ${config_file}.tmp ${config_file}
        sed "s|\${NODEID}|${node_id}|g" ${config_file} > ${config_file}.tmp && mv ${config_file}.tmp ${config_file}
        
        echo -e ""
        echo -e "${green}配置已更新：${plain}"
        echo -e "  ApiHost: ${api_host}"
        echo -e "  ApiKey: ${api_key}"
        echo -e "  NodeID: ${node_id}"
        echo -e ""
        echo -e "更多配置请编辑: ${yellow}/etc/XrayR/config.yml${plain}"
        echo -e "详细教程: https://github.com/XrayR-project/XrayR"
    else
        if [[ x"${release}" == x"alpine" ]]; then
            rc-service xrayr start
        else
            systemctl start XrayR
        fi
        sleep 2
        check_status
        echo -e ""
        if [[ $? == 0 ]]; then
            echo -e "${green}XrayR 重启成功${plain}"
        else
            echo -e "${red}XrayR 可能启动失败，请稍后使用 XrayR log 查看日志信息，若无法启动，则可能更改了配置格式，请前往 wiki 查看：https://github.com/XrayR-project/XrayR/wiki${plain}"
        fi
    fi

    if [[ ! -f /etc/XrayR/dns.json ]]; then
        cp dns.json /etc/XrayR/
    fi
    if [[ ! -f /etc/XrayR/route.json ]]; then
        cp route.json /etc/XrayR/
    fi
    if [[ ! -f /etc/XrayR/custom_outbound.json ]]; then
        cp custom_outbound.json /etc/XrayR/
    fi
    if [[ ! -f /etc/XrayR/custom_inbound.json ]]; then
        cp custom_inbound.json /etc/XrayR/
    fi
    if [[ ! -f /etc/XrayR/rulelist ]]; then
        cp rulelist /etc/XrayR/
    fi
    curl -o /usr/bin/XrayR -Ls https://raw.githubusercontent.com/qiuapeng921/XrayR-release/master/XrayR.sh
    chmod +x /usr/bin/XrayR
    ln -s /usr/bin/XrayR /usr/bin/xrayr # 小写兼容
    chmod +x /usr/bin/xrayr
    cd $cur_dir
    rm -f install.sh
    echo -e ""
    echo "XrayR 管理脚本使用方法 (兼容使用xrayr执行，大小写不敏感): "
    echo "------------------------------------------"
    echo "XrayR                    - 显示管理菜单 (功能更多)"
    echo "XrayR start              - 启动 XrayR"
    echo "XrayR stop               - 停止 XrayR"
    echo "XrayR restart            - 重启 XrayR"
    echo "XrayR status             - 查看 XrayR 状态"
    echo "XrayR enable             - 设置 XrayR 开机自启"
    echo "XrayR disable            - 取消 XrayR 开机自启"
    echo "XrayR log                - 查看 XrayR 日志"
    echo "XrayR update             - 更新 XrayR"
    echo "XrayR update x.x.x       - 更新 XrayR 指定版本"
    echo "XrayR config             - 显示配置文件内容"
    echo "XrayR install            - 安装 XrayR"
    echo "XrayR uninstall          - 卸载 XrayR"
    echo "XrayR version            - 查看 XrayR 版本"
    echo "------------------------------------------"
}

echo -e "${green}开始安装${plain}"
install_base
# install_acme
install_XrayR $VERSION_ARG
