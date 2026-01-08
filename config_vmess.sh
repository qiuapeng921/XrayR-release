#!/bin/bash

# VMess 快速配置脚本
# 用于在已安装 XrayR 的服务器上快速配置 VMess 节点

set -e

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
plain='\033[0m'

CONFIG_FILE="/etc/XrayR/config.yml"

echo -e "${green}========================================${plain}"
echo -e "${green}  VMess 节点快速配置向导${plain}"
echo -e "${green}========================================${plain}"
echo ""

# 检查 XrayR 是否已安装
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${red}错误: 未检测到 XrayR 安装${plain}"
    echo -e "${yellow}请先运行安装脚本:${plain}"
    echo "bash <(curl -Ls https://raw.githubusercontent.com/qiuapeng921/XrayR-release/master/install.sh)"
    exit 1
fi

# 选择传输方式
echo -e "${yellow}请选择 VMess 传输方式:${plain}"
echo "1) WebSocket + TLS + CDN（最推荐，高隐蔽性）"
echo "2) WebSocket + TLS（推荐，高速度）"
echo "3) gRPC + TLS（高性能）"
echo "4) TCP + TLS（简单直接）"
echo "5) TCP（不推荐，无加密）"
read -p "请选择 [1-5]: " transport_choice

case $transport_choice in
    1) 
        TRANSPORT="ws"
        USE_TLS=true
        USE_CDN=true
        echo -e "${green}已选择: WebSocket + TLS + CDN${plain}"
        ;;
    2) 
        TRANSPORT="ws"
        USE_TLS=true
        USE_CDN=false
        echo -e "${green}已选择: WebSocket + TLS${plain}"
        ;;
    3) 
        TRANSPORT="grpc"
        USE_TLS=true
        USE_CDN=false
        echo -e "${green}已选择: gRPC + TLS${plain}"
        ;;
    4) 
        TRANSPORT="tcp"
        USE_TLS=true
        USE_CDN=false
        echo -e "${green}已选择: TCP + TLS${plain}"
        ;;
    5) 
        TRANSPORT="tcp"
        USE_TLS=false
        USE_CDN=false
        echo -e "${yellow}警告: TCP 无加密不安全，仅用于测试！${plain}"
        ;;
    *) 
        echo -e "${red}无效选择${plain}"
        exit 1
        ;;
esac

echo ""

# 如果使用 TLS，询问证书配置
if [[ "$USE_TLS" == true ]]; then
    echo -e "${yellow}请输入节点域名:${plain}"
    read -p "> " DOMAIN
    
    echo -e "${yellow}请选择 DNS 提供商:${plain}"
    echo "1) Cloudflare"
    echo "2) 阿里云 (alidns)"
    echo "3) 腾讯云 (tencentcloud)"
    echo "4) HTTP 验证"
    read -p "请选择 [1-4]: " dns_choice
    
    case $dns_choice in
        1) DNS_PROVIDER="cloudflare" ;;
        2) DNS_PROVIDER="alidns" ;;
        3) DNS_PROVIDER="tencentcloud" ;;
        4) DNS_PROVIDER="http" ;;
        *) echo -e "${red}无效选择${plain}"; exit 1 ;;
    esac
    
    read -p "请输入邮箱地址: " EMAIL
    
    # 获取 DNS API 凭证
    if [[ "$DNS_PROVIDER" != "http" ]]; then
        case $DNS_PROVIDER in
            cloudflare)
                read -p "请输入 Cloudflare API Token: " CF_TOKEN
                ;;
            alidns)
                read -p "请输入阿里云 Access Key: " ALI_ACCESS_KEY
                read -p "请输入阿里云 Secret Key: " ALI_SECRET_KEY
                ;;
            tencentcloud)
                read -p "请输入腾讯云 Secret ID: " TX_SECRET_ID
                read -p "请输入腾讯云 Secret Key: " TX_SECRET_KEY
                ;;
        esac
    fi
fi

# 显示配置摘要
echo ""
echo -e "${green}========================================${plain}"
echo -e "${green}配置摘要${plain}"
echo -e "${green}========================================${plain}"
echo -e "传输方式: ${blue}$TRANSPORT${plain}"
echo -e "使用 TLS: ${blue}$USE_TLS${plain}"
if [[ "$USE_TLS" == true ]]; then
    echo -e "域名: ${blue}$DOMAIN${plain}"
    echo -e "DNS 提供商: ${blue}$DNS_PROVIDER${plain}"
    echo -e "邮箱: ${blue}$EMAIL${plain}"
fi
if [[ "$USE_CDN" == true ]]; then
    echo -e "套用 CDN: ${blue}是${plain}"
fi
echo -e "${green}========================================${plain}"
echo ""

read -p "确认配置无误？[y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${yellow}已取消配置${plain}"
    exit 0
fi

# 备份配置文件
echo -e "${green}备份配置文件...${plain}"
cp "$CONFIG_FILE" "${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

# 修改配置
echo -e "${green}修改配置文件...${plain}"

# 修改节点类型为 V2ray
sed -i 's/NodeType: .*/NodeType: V2ray/' "$CONFIG_FILE"

# 如果使用 TLS，配置证书
if [[ "$USE_TLS" == true ]]; then
    sed -i "s/CertMode: .*/CertMode: $DNS_PROVIDER/" "$CONFIG_FILE"
    sed -i "s/CertDomain: .*/CertDomain: \"$DOMAIN\"/" "$CONFIG_FILE"
    sed -i "s/Email: .*/Email: $EMAIL/" "$CONFIG_FILE"
    
    if [[ "$DNS_PROVIDER" != "http" ]]; then
        sed -i "s/Provider: .*/Provider: $DNS_PROVIDER/" "$CONFIG_FILE"
        
        # 更新 DNSEnv
        case $DNS_PROVIDER in
            cloudflare)
                sed -i "/DNSEnv:/,/^[^ ]/{/DNSEnv:/!{/^[^ ]/!d}}" "$CONFIG_FILE"
                sed -i "/Email: $EMAIL/a\\      DNSEnv:\\n        CF_DNS_API_TOKEN: $CF_TOKEN" "$CONFIG_FILE"
                ;;
            alidns)
                sed -i "/DNSEnv:/,/^[^ ]/{/DNSEnv:/!{/^[^ ]/!d}}" "$CONFIG_FILE"
                sed -i "/Email: $EMAIL/a\\      DNSEnv:\\n        ALICLOUD_ACCESS_KEY: $ALI_ACCESS_KEY\\n        ALICLOUD_SECRET_KEY: $ALI_SECRET_KEY" "$CONFIG_FILE"
                ;;
            tencentcloud)
                sed -i "/DNSEnv:/,/^[^ ]/{/DNSEnv:/!{/^[^ ]/!d}}" "$CONFIG_FILE"
                sed -i "/Email: $EMAIL/a\\      DNSEnv:\\n        TENCENTCLOUD_SECRET_ID: $TX_SECRET_ID\\n        TENCENTCLOUD_SECRET_KEY: $TX_SECRET_KEY" "$CONFIG_FILE"
                ;;
        esac
    fi
else
    sed -i 's/CertMode: .*/CertMode: none/' "$CONFIG_FILE"
fi

# 重启服务
echo -e "${green}重启 XrayR 服务...${plain}"
XrayR restart

echo ""
echo -e "${green}========================================${plain}"
echo -e "${green}配置完成！${plain}"
echo -e "${green}========================================${plain}"
echo ""

# 显示面板配置建议
echo -e "${yellow}面板端配置建议:${plain}"
echo ""

if [[ "$TRANSPORT" == "ws" ]] && [[ "$USE_TLS" == true ]]; then
    echo -e "${blue}节点类型:${plain} V2Ray"
    echo -e "${blue}节点地址:${plain} $DOMAIN"
    echo -e "${blue}连接端口:${plain} 443"
    echo ""
    echo -e "${blue}节点配置 (JSON):${plain}"
    cat << EOF
{
  "network": "ws",
  "security": "tls",
  "networkSettings": {
    "path": "/",
    "headers": {
      "Host": "$DOMAIN"
    }
  },
  "tlsSettings": {
    "serverName": "$DOMAIN",
    "allowInsecure": false
  }
}
EOF
elif [[ "$TRANSPORT" == "grpc" ]] && [[ "$USE_TLS" == true ]]; then
    echo -e "${blue}节点类型:${plain} V2Ray"
    echo -e "${blue}节点地址:${plain} $DOMAIN"
    echo -e "${blue}连接端口:${plain} 443"
    echo ""
    echo -e "${blue}节点配置 (JSON):${plain}"
    cat << EOF
{
  "network": "grpc",
  "security": "tls",
  "networkSettings": {
    "serviceName": "grpc"
  },
  "tlsSettings": {
    "serverName": "$DOMAIN",
    "allowInsecure": false
  }
}
EOF
elif [[ "$TRANSPORT" == "tcp" ]] && [[ "$USE_TLS" == true ]]; then
    echo -e "${blue}节点类型:${plain} V2Ray"
    echo -e "${blue}节点地址:${plain} $DOMAIN"
    echo -e "${blue}连接端口:${plain} 443"
    echo ""
    echo -e "${blue}节点配置 (JSON):${plain}"
    cat << EOF
{
  "network": "tcp",
  "security": "tls",
  "tlsSettings": {
    "serverName": "$DOMAIN",
    "allowInsecure": false
  }
}
EOF
else
    echo -e "${blue}节点类型:${plain} V2Ray"
    echo -e "${blue}节点地址:${plain} 服务器IP"
    echo -e "${blue}连接端口:${plain} 根据面板配置"
    echo ""
    echo -e "${blue}节点配置 (JSON):${plain}"
    cat << EOF
{
  "network": "tcp",
  "security": "none"
}
EOF
fi

echo ""
echo -e "${green}========================================${plain}"
echo -e "${green}常用命令${plain}"
echo -e "${green}========================================${plain}"
echo -e "查看状态: ${blue}XrayR status${plain}"
echo -e "查看日志: ${blue}XrayR log${plain}"
echo -e "重启服务: ${blue}XrayR restart${plain}"
echo -e "查看配置: ${blue}cat /etc/XrayR/config.yml${plain}"
if [[ "$USE_TLS" == true ]]; then
    echo -e "查看证书: ${blue}ls -lh /etc/XrayR/cert/${plain}"
fi
echo -e "${green}========================================${plain}"
echo ""

if [[ "$USE_TLS" == true ]]; then
    echo -e "${yellow}正在等待证书申请（可能需要 1-2 分钟）...${plain}"
    echo -e "${yellow}请查看日志确认证书申请成功${plain}"
    echo ""
    sleep 3
    XrayR log
fi
