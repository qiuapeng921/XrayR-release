#!/bin/bash

# XrayR 快速部署脚本 - 支持自动证书配置
# 使用方法:
#   bash quick_deploy.sh --domain=node1.example.com --provider=cloudflare --apiToken=xxx
#   bash quick_deploy.sh --domain=node1.example.com --provider=alidns --accessKey=xxx --secretKey=xxx

set -e

# 颜色定义
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
plain='\033[0m'

# 默认值
DOMAIN=""
CERT_PROVIDER=""
CERT_EMAIL=""
NODE_TYPE="Trojan"
API_HOST=""
API_KEY=""
NODE_ID=""

# DNS 提供商环境变量
declare -A DNS_ENV

echo -e "${green}========================================${plain}"
echo -e "${green}  XrayR 自动证书部署脚本${plain}"
echo -e "${green}========================================${plain}"
echo ""

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --domain=*)
            DOMAIN="${1#*=}"
            shift
            ;;
        --provider=*)
            CERT_PROVIDER="${1#*=}"
            shift
            ;;
        --email=*)
            CERT_EMAIL="${1#*=}"
            shift
            ;;
        --nodeType=*)
            NODE_TYPE="${1#*=}"
            shift
            ;;
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
        # Cloudflare
        --cfToken=*)
            DNS_ENV[CF_DNS_API_TOKEN]="${1#*=}"
            shift
            ;;
        --cfEmail=*)
            DNS_ENV[CF_API_EMAIL]="${1#*=}"
            shift
            ;;
        --cfKey=*)
            DNS_ENV[CF_API_KEY]="${1#*=}"
            shift
            ;;
        # 阿里云
        --aliAccessKey=*)
            DNS_ENV[ALICLOUD_ACCESS_KEY]="${1#*=}"
            shift
            ;;
        --aliSecretKey=*)
            DNS_ENV[ALICLOUD_SECRET_KEY]="${1#*=}"
            shift
            ;;
        # 腾讯云
        --txSecretId=*)
            DNS_ENV[TENCENTCLOUD_SECRET_ID]="${1#*=}"
            shift
            ;;
        --txSecretKey=*)
            DNS_ENV[TENCENTCLOUD_SECRET_KEY]="${1#*=}"
            shift
            ;;
        # DNSPod
        --dnspodKey=*)
            DNS_ENV[DNSPOD_API_KEY]="${1#*=}"
            shift
            ;;
        *)
            echo -e "${red}未知参数: $1${plain}"
            exit 1
            ;;
    esac
done

# 交互式输入（如果参数未提供）
if [[ -z "$DOMAIN" ]]; then
    echo -e "${yellow}请输入节点域名（如 node1.example.com）:${plain}"
    read -p "> " DOMAIN
fi

if [[ -z "$CERT_PROVIDER" ]]; then
    echo -e "${yellow}请选择 DNS 提供商:${plain}"
    echo "1) Cloudflare"
    echo "2) 阿里云 (alidns)"
    echo "3) 腾讯云 (tencentcloud)"
    echo "4) DNSPod"
    echo "5) HTTP 验证（不使用 DNS）"
    read -p "请选择 [1-5]: " choice
    
    case $choice in
        1) CERT_PROVIDER="cloudflare" ;;
        2) CERT_PROVIDER="alidns" ;;
        3) CERT_PROVIDER="tencentcloud" ;;
        4) CERT_PROVIDER="dnspod" ;;
        5) CERT_PROVIDER="http" ;;
        *) echo -e "${red}无效选择${plain}"; exit 1 ;;
    esac
fi

if [[ -z "$CERT_EMAIL" ]]; then
    read -p "请输入邮箱地址（用于 Let's Encrypt 通知）: " CERT_EMAIL
fi

if [[ -z "$NODE_TYPE" ]]; then
    echo -e "${yellow}请选择节点类型:${plain}"
    echo "1) Trojan"
    echo "2) V2ray (VMess)"
    echo "3) Vless"
    read -p "请选择 [1-3]: " choice
    
    case $choice in
        1) NODE_TYPE="Trojan" ;;
        2) NODE_TYPE="V2ray" ;;
        3) NODE_TYPE="Vless" ;;
        *) echo -e "${red}无效选择${plain}"; exit 1 ;;
    esac
fi

# 获取 DNS API 凭证
if [[ "$CERT_PROVIDER" != "http" ]]; then
    case $CERT_PROVIDER in
        cloudflare)
            if [[ -z "${DNS_ENV[CF_DNS_API_TOKEN]}" ]]; then
                echo -e "${yellow}请输入 Cloudflare API Token:${plain}"
                read -p "> " DNS_ENV[CF_DNS_API_TOKEN]
            fi
            ;;
        alidns)
            if [[ -z "${DNS_ENV[ALICLOUD_ACCESS_KEY]}" ]]; then
                echo -e "${yellow}请输入阿里云 Access Key:${plain}"
                read -p "> " DNS_ENV[ALICLOUD_ACCESS_KEY]
            fi
            if [[ -z "${DNS_ENV[ALICLOUD_SECRET_KEY]}" ]]; then
                echo -e "${yellow}请输入阿里云 Secret Key:${plain}"
                read -p "> " DNS_ENV[ALICLOUD_SECRET_KEY]
            fi
            ;;
        tencentcloud)
            if [[ -z "${DNS_ENV[TENCENTCLOUD_SECRET_ID]}" ]]; then
                echo -e "${yellow}请输入腾讯云 Secret ID:${plain}"
                read -p "> " DNS_ENV[TENCENTCLOUD_SECRET_ID]
            fi
            if [[ -z "${DNS_ENV[TENCENTCLOUD_SECRET_KEY]}" ]]; then
                echo -e "${yellow}请输入腾讯云 Secret Key:${plain}"
                read -p "> " DNS_ENV[TENCENTCLOUD_SECRET_KEY]
            fi
            ;;
        dnspod)
            if [[ -z "${DNS_ENV[DNSPOD_API_KEY]}" ]]; then
                echo -e "${yellow}请输入 DNSPod API Key (格式: id,token):${plain}"
                read -p "> " DNS_ENV[DNSPOD_API_KEY]
            fi
            ;;
    esac
fi

# 获取面板信息
if [[ -z "$API_HOST" ]]; then
    read -p "请输入面板 API 地址: " API_HOST
fi

if [[ -z "$API_KEY" ]]; then
    read -p "请输入面板 API 密钥: " API_KEY
fi

if [[ -z "$NODE_ID" ]]; then
    read -p "请输入节点 ID: " NODE_ID
fi

# 显示配置摘要
echo ""
echo -e "${green}========================================${plain}"
echo -e "${green}配置摘要${plain}"
echo -e "${green}========================================${plain}"
echo -e "域名: ${blue}$DOMAIN${plain}"
echo -e "节点类型: ${blue}$NODE_TYPE${plain}"
echo -e "证书模式: ${blue}$CERT_PROVIDER${plain}"
echo -e "邮箱: ${blue}$CERT_EMAIL${plain}"
echo -e "面板地址: ${blue}$API_HOST${plain}"
echo -e "节点 ID: ${blue}$NODE_ID${plain}"
echo -e "${green}========================================${plain}"
echo ""

read -p "确认配置无误，开始部署？[y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${yellow}已取消部署${plain}"
    exit 0
fi

# 1. 运行 XrayR 安装脚本
echo -e "${green}[1/3] 安装 XrayR...${plain}"
bash <(curl -Ls https://raw.githubusercontent.com/qiuapeng921/XrayR-release/master/install.sh) \
    --apiHost="$API_HOST" \
    --apiKey="$API_KEY" \
    --nodeID="$NODE_ID"

# 2. 修改配置文件
echo -e "${green}[2/3] 配置自动证书...${plain}"

CONFIG_FILE="/etc/XrayR/config.yml"

# 备份原配置
cp "$CONFIG_FILE" "${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

# 修改节点类型
sed -i "s/NodeType: .*/NodeType: $NODE_TYPE/" "$CONFIG_FILE"

# 修改证书配置
if [[ "$CERT_PROVIDER" == "http" ]]; then
    # HTTP 验证模式
    sed -i "s/CertMode: .*/CertMode: http/" "$CONFIG_FILE"
    sed -i "s/CertDomain: .*/CertDomain: \"$DOMAIN\"/" "$CONFIG_FILE"
    sed -i "s/Email: .*/Email: $CERT_EMAIL/" "$CONFIG_FILE"
    sed -i "s/Provider: .*/# Provider: (http mode)/" "$CONFIG_FILE"
else
    # DNS 验证模式
    sed -i "s/CertMode: .*/CertMode: dns/" "$CONFIG_FILE"
    sed -i "s/CertDomain: .*/CertDomain: \"$DOMAIN\"/" "$CONFIG_FILE"
    sed -i "s/Email: .*/Email: $CERT_EMAIL/" "$CONFIG_FILE"
    sed -i "s/Provider: .*/Provider: $CERT_PROVIDER/" "$CONFIG_FILE"
    
    # 更新 DNSEnv
    # 删除现有的 DNSEnv 配置
    sed -i '/DNSEnv:/,/^[^ ]/{/DNSEnv:/!{/^[^ ]/!d}}' "$CONFIG_FILE"
    
    # 添加新的 DNSEnv 配置
    dns_env_config="      DNSEnv:\n"
    for key in "${!DNS_ENV[@]}"; do
        dns_env_config+="        $key: ${DNS_ENV[$key]}\n"
    done
    
    # 在 Email 行后插入 DNSEnv
    sed -i "/Email: $CERT_EMAIL/a\\$dns_env_config" "$CONFIG_FILE"
fi

# 3. 重启服务并查看日志
echo -e "${green}[3/3] 启动服务...${plain}"
XrayR restart

echo ""
echo -e "${green}========================================${plain}"
echo -e "${green}部署完成！${plain}"
echo -e "${green}========================================${plain}"
echo ""
echo -e "正在等待证书申请（可能需要 1-2 分钟）..."
echo ""

sleep 5

# 查看日志
echo -e "${yellow}查看实时日志（按 Ctrl+C 退出）:${plain}"
echo ""
XrayR log

echo ""
echo -e "${green}========================================${plain}"
echo -e "${green}常用命令${plain}"
echo -e "${green}========================================${plain}"
echo -e "查看状态: ${blue}XrayR status${plain}"
echo -e "查看日志: ${blue}XrayR log${plain}"
echo -e "重启服务: ${blue}XrayR restart${plain}"
echo -e "查看配置: ${blue}cat /etc/XrayR/config.yml${plain}"
echo -e "查看证书: ${blue}ls -lh /etc/XrayR/cert/${plain}"
echo -e "${green}========================================${plain}"
