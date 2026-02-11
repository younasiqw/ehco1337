#!/bin/bash

# =========================================================
# Ehco 管理脚本 (Ubuntu/Debian 适配版)
# 版本: v1.1.4 适配
# =========================================================

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
SKYBLUE='\033[0;36m'
PLAIN='\033[0m'

# --- 基础变量 ---
EHCO_BIN="/usr/local/bin/ehco"
EHCO_CONF_DIR="/etc/ehco"
EHCO_CONF_FILE="${EHCO_CONF_DIR}/config.json"
SYSTEMD_FILE="/etc/systemd/system/ehco.service"

# --- 端口黑名单 ---
BLOCKED_PORTS=(80 443 8080 8443 8000 1080)

# --- 检查 Root 权限 ---
[[ $EUID -ne 0 ]] && echo -e "${RED}错误: 必须使用 root 用户运行此脚本！${PLAIN}" && exit 1

# --- 基础函数 ---

install_base() {
    echo -e "${YELLOW}正在更新系统并安装依赖...${PLAIN}"
    apt update -y
    apt install -y wget curl jq tar
}

check_sys() {
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        ARCH_STR="amd64"
    elif [[ "$ARCH" == "aarch64" ]]; then
        ARCH_STR="arm64"
    else
        echo -e "${RED}不支持的架构: $ARCH${PLAIN}"
        exit 1
    fi
}

check_port_valid() {
    local port=$1
    # 检查范围
    if [[ $port -lt 1 || $port -gt 65535 ]]; then
        echo -e "${RED}端口必须在 1-65535 之间${PLAIN}"
        return 1
    fi
    # 检查黑名单
    for blocked in "${BLOCKED_PORTS[@]}"; do
        if [[ $port -eq $blocked ]]; then
            echo -e "${RED}警告: 端口 $port 在您的封禁列表中 (80,443,8080,8443,8000,1080)${PLAIN}"
            return 1
        fi
    done
    return 0
}

# --- 功能函数 ---

install_ehco() {
    install_base
    check_sys
    
    echo -e "${GREEN}检测到系统架构: ${ARCH_STR}${PLAIN}"
    
    # 检查本地是否有安装包
    LOCAL_FILE=""
    if [[ -f "./ehco" ]]; then
        echo -e "${YELLOW}检测到当前目录下存在 ehco 文件。${PLAIN}"
        read -p "是否使用本地文件进行安装? [y/n]: " use_local
        if [[ "$use_local" == "y" ]]; then
            LOCAL_FILE="./ehco"
        fi
    fi

    if [[ -n "$LOCAL_FILE" ]]; then
        cp "$LOCAL_FILE" "$EHCO_BIN"
    else
        echo -e "${YELLOW}正在从 GitHub 下载 Ehco v1.1.4 ($ARCH_STR)...${PLAIN}"
        DOWNLOAD_URL="https://github.com/Ehco1996/ehco/releases/download/v1.1.4/ehco_linux_${ARCH_STR}"
        wget -O "$EHCO_BIN" "$DOWNLOAD_URL"
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}下载失败，请检查网络或手动上传 ehco 文件到当前目录重新运行。${PLAIN}"
            exit 1
        fi
    fi

    chmod +x "$EHCO_BIN"
    
    # 创建配置目录
    mkdir -p "$EHCO_CONF_DIR"
    if [[ ! -f "$EHCO_CONF_FILE" ]]; then
        echo '{"relays": []}' > "$EHCO_CONF_FILE"
    fi

    # 配置 Systemd
    cat > "$SYSTEMD_FILE" <<EOF
[Unit]
Description=Ehco Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=${EHCO_BIN} -c ${EHCO_CONF_FILE}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ehco
    systemctl start ehco
    
    echo -e "${GREEN}Ehco 安装完成并已设置为开机自启！${PLAIN}"
    pause
}

uninstall_ehco() {
    echo -e "${YELLOW}正在卸载 Ehco...${PLAIN}"
    systemctl stop ehco
    systemctl disable ehco
    rm -f "$SYSTEMD_FILE"
    systemctl daemon-reload
    rm -f "$EHCO_BIN"
    # 保留配置文件以便重装，如需删除可解开下行注释
    # rm -rf "$EHCO_CONF_DIR"
    echo -e "${GREEN}卸载完成！${PLAIN}"
    pause
}

restart_ehco() {
    systemctl restart ehco
    echo -e "${GREEN}Ehco 服务已重启${PLAIN}"
    pause
}

init_config() {
    echo -e "${RED}!!! 警告 !!!${PLAIN}"
    echo -e "此操作将清空所有现有隧道配置。"
    read -p "确认初始化配置文件吗? [y/n] (默认n): " confirm
    if [[ "$confirm" == "y" ]]; then
        echo '{"relays": []}' > "$EHCO_CONF_FILE"
        echo -e "${GREEN}配置文件已初始化。${PLAIN}"
        restart_ehco
    else
        echo -e "${YELLOW}操作取消，返回上一级。${PLAIN}"
    fi
}

# --- 菜单 UI 函数 ---

# 4级/5级 UI: 选择传输协议
select_transport_protocol() {
    # $1: "encrypt" or "decrypt"
    local mode=$1
    local title=""
    
    if [[ "$mode" == "encrypt" ]]; then
        title="4级协议UI (加密)"
    else
        title="5级解密UI"
    fi

    echo -e "------------------------------------------------"
    echo -e "${SKYBLUE}$title${PLAIN}"
    echo -e "------------------------------------------------"
    echo -e "1. ws 隧道"
    echo -e "2. wss 隧道"
    echo -e "3. mwss 隧道"
    echo -e "${YELLOW}注意: 同一则转发，中转与落地传输类型必须对应！${PLAIN}"
    echo -e "------------------------------------------------"
    
    read -p "请选择协议 [1-3]: " proto_num
    case $proto_num in
        1) echo "ws" ;;
        2) echo "wss" ;;
        3) echo "mwss" ;;
        *) echo "ws" ;; # 默认
    esac
}

# 3级 UI: 添加中转
add_forward_rule() {
    echo -e "------------------------------------------------"
    echo -e "${SKYBLUE}3级中转UI: 添加规则${PLAIN}"
    echo -e "------------------------------------------------"
    echo -e "1. TCP+UDP流量转发, 不加密"
    echo -e "   ${YELLOW}说明: 一般设置在国内中转机上${PLAIN}"
    echo -e "2. 加密隧道流量转发"
    echo -e "   ${YELLOW}说明: 用于转发原本加密等级较低的流量, 一般设置在国内中转机上${PLAIN}"
    echo -e "   ${YELLOW}选择此协议意味着你还有一台机器用于接收此加密流量, 之后须在那台机器上配置协议[3]进行对接${PLAIN}"
    echo -e "3. 解密由ehco传输而来的流量并转发"
    echo -e "   ${YELLOW}说明: 对于经由ehco加密中转的流量, 通过此选项进行解密并转发给本机的代理服务端口或转发给其他远程机器${PLAIN}"
    echo -e "   ${YELLOW}一般设置在用于接收中转流量的国外机器上${PLAIN}"
    echo -e "0. 返回上一级"
    echo -e "------------------------------------------------"
    
    read -p "请选择转发类型 [0-3]: " fwd_type

    if [[ "$fwd_type" == "0" ]]; then return; fi

    # 获取本地监听端口
    while true; do
        read -p "请输入本地监听端口 (本机入口): " listen_port
        check_port_valid "$listen_port" && break
    done

    local transport_type=""
    local remote_addr=""
    local remote_port=""
    
    # 根据类型处理逻辑
    case $fwd_type in
        1) # TCP+UDP (Raw)
            read -p "请输入目标服务器 IP (IPv4/IPv6): " remote_addr
            read -p "请输入目标服务器端口: " remote_port
            
            # 使用 jq 添加 raw 配置
            # 格式: { "listen": ":port", "target": "ip:port" }
            tmp_json=$(mktemp)
            jq --arg lp ":$listen_port" --arg tgt "$remote_addr:$remote_port" \
               '.relays += [{"listen": $lp, "target": $tgt}]' \
               "$EHCO_CONF_FILE" > "$tmp_json" && mv "$tmp_json" "$EHCO_CONF_FILE"
            ;;
            
        2) # 加密转发 (本机作为 Client)
            transport_type=$(select_transport_protocol "encrypt")
            read -p "请输入接收端(落地机) IP: " remote_addr
            read -p "请输入接收端(落地机) 监听端口: " remote_port
            
            # 格式: { "listen": ":port", "target": "ip:port", "type": "client", "transport": { "type": "ws" } }
            tmp_json=$(mktemp)
            jq --arg lp ":$listen_port" \
               --arg tgt "$remote_addr:$remote_port" \
               --arg tt "$transport_type" \
               '.relays += [{"listen": $lp, "target": $tgt, "type": "client", "transport": {"type": $tt}}]' \
               "$EHCO_CONF_FILE" > "$tmp_json" && mv "$tmp_json" "$EHCO_CONF_FILE"
            ;;
            
        3) # 解密转发 (本机作为 Server)
            transport_type=$(select_transport_protocol "decrypt")
            echo -e "请输入解密后转发的目标地址 (例如 127.0.0.1 或 其他远程IP)"
            read -p "目标 IP: " remote_addr
            read -p "目标端口: " remote_port
            
            # 格式: { "listen": ":port", "target": "ip:port", "type": "server", "transport": { "type": "ws" } }
            tmp_json=$(mktemp)
            jq --arg lp ":$listen_port" \
               --arg tgt "$remote_addr:$remote_port" \
               --arg tt "$transport_type" \
               '.relays += [{"listen": $lp, "target": $tgt, "type": "server", "transport": {"type": $tt}}]' \
               "$EHCO_CONF_FILE" > "$tmp_json" && mv "$tmp_json" "$EHCO_CONF_FILE"
            ;;
        *)
            echo "输入错误"
            return
            ;;
    esac
    
    echo -e "${GREEN}添加成功！正在重启 Ehco 以应用更改...${PLAIN}"
    restart_ehco
}

# 2级 UI: 隧道管理
menu_tunnel() {
    while true; do
        echo -e "------------------------------------------------"
        echo -e "${SKYBLUE}2级隧道UI: 隧道管理${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "1. 添加隧道中转"
        echo -e "2. 查看隧道信息"
        echo -e "3. 初始化配置文件"
        echo -e "0. 返回主菜单"
        echo -e "------------------------------------------------"
        
        read -p "请选择 [0-3]: " sub_opt
        case $sub_opt in
            1) add_forward_rule ;;
            2) 
                echo -e "${YELLOW}当前配置文件内容 ($EHCO_CONF_FILE):${PLAIN}"
                jq . "$EHCO_CONF_FILE"
                pause
                ;;
            3) init_config ;;
            0) break ;;
            *) echo -e "${RED}输入错误${PLAIN}" ;;
        esac
    done
}

# 主菜单
show_menu() {
    clear
    echo -e "------------------------------------------------"
    echo -e "${SKYBLUE}Ehco 一键管理脚本 (Linux)${PLAIN}"
    echo -e "------------------------------------------------"
    echo -e "1. 安装 Ehco (自动识别架构, 自动添加开机自启)"
    echo -e "2. 卸载 Ehco (自动移除开机自启)"
    echo -e "3. 重启 Ehco"
    echo -e "4. 查看当前隧道信息 / 管理隧道 (进入二级菜单)"
    echo -e "0. 退出脚本"
    echo -e "------------------------------------------------"
    
    read -p "请选择操作 [0-4]: " num
    case $num in
        1) install_ehco ;;
        2) uninstall_ehco ;;
        3) restart_ehco ;;
        4) 
            if [[ ! -f "$EHCO_BIN" ]]; then
                echo -e "${RED}请先安装 Ehco!${PLAIN}"
                pause
            else
                menu_tunnel
            fi
            ;;
        0) exit 0 ;;
        *) echo -e "${RED}请输入正确的数字 [0-4]${PLAIN}" ;;
    esac
}

pause() {
    read -p "按回车键继续..."
}

# --- 脚本入口 ---
while true; do
    show_menu
done
