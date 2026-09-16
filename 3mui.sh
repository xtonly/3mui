#!/bin/bash

# ================= 颜色定义 =================
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

# ================= 基础配置 =================
BASE_DIR="/opt/3m-ui"
DATA_DIR="${BASE_DIR}/data"
IMAGE_NAME="kazeyukiro/3m-ui:latest"
CONTAINER_DATA_DIR="/etc/x-ui" 
DEFAULT_PORT="12053"

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误：本脚本需要 root 权限执行！${PLAIN}"
        exit 1
    fi
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}未检测到 Docker，正在自动安装...${PLAIN}"
        curl -fsSL https://get.docker.com | bash -s docker
        systemctl enable --now docker
    fi
}

open_ports() {
    local port=$1
    echo -e "${YELLOW}>>> 正在防火墙中严格放行 ${port} 端口 (不再放行 2053)...${PLAIN}"
    if command -v ufw &> /dev/null; then
        ufw allow ${port}/tcp >/dev/null 2>&1
        ufw allow ${port}/udp >/dev/null 2>&1
    fi
    if command -v firewall-cmd &> /dev/null; then
        firewall-cmd --zone=public --add-port=${port}/tcp --permanent >/dev/null 2>&1
        firewall-cmd --zone=public --add-port=${port}/udp --permanent >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    fi
    if command -v iptables &> /dev/null; then
        iptables -I INPUT -p tcp --dport ${port} -j ACCEPT >/dev/null 2>&1
        iptables -I INPUT -p udp --dport ${port} -j ACCEPT >/dev/null 2>&1
    fi
}

show_info() {
    if ! docker ps -a --format '{{.Names}}' | grep -Eq "^3m-ui$"; then
        echo -e "${RED}未检测到运行中的 3m-ui 容器！${PLAIN}"
        return
    fi
    LOCAL_IP=$(curl -s4m8 ip.sb || curl -s4m8 ipinfo.io/ip)
    
    echo -e ""
    echo -e "${GREEN}==================================================================${PLAIN}"
    echo -e "${GREEN} 🚀 3m-ui 面板信息查询${PLAIN}"
    echo -e "${GREEN}==================================================================${PLAIN}"
    echo -e " 🌐 ${YELLOW}安全访问地址 :${PLAIN} http://${LOCAL_IP}:${DEFAULT_PORT}"
    echo -e " 👤 ${YELLOW}默认用户名   :${PLAIN} admin"
    echo -e " 🔑 ${YELLOW}默认密码     :${PLAIN} admin"
    echo -e "${GREEN}==================================================================${PLAIN}"
}

install_panel() {
    check_docker
    if docker ps -a --format '{{.Names}}' | grep -Eq "^3m-ui$"; then
        echo -e "${YELLOW}检测到 3m-ui 已存在，请先卸载！${PLAIN}"
        return
    fi
    
    echo -e "${GREEN}>>> 第一步: 创建目录并启动容器初始化数据库...${PLAIN}"
    mkdir -p "${DATA_DIR}"
    
    # 尝试拉取，如果失败不退出，依赖本地镜像启动
    docker pull ${IMAGE_NAME} >/dev/null 2>&1
    
    docker run -d --name 3m-ui --restart unless-stopped --network host -v ${DATA_DIR}:${CONTAINER_DATA_DIR} ${IMAGE_NAME}
    if [ $? -ne 0 ]; then
        echo -e "${RED}容器启动失败！如果你没有本地镜像，请先自行 build 镜像。${PLAIN}"
        return
    fi
    
    # 等待数据库文件生成
    sleep 3
    echo -e "${YELLOW}>>> 第二步: 停止容器，准备通过数据库底层修改端口...${PLAIN}"
    docker stop 3m-ui >/dev/null 2>&1
    
    echo -e "${YELLOW}>>> 第三步: 运行 SQLite 微型容器注入 12053 端口...${PLAIN}"
    # 使用 alpine 临时容器直接修改宿主机映射出来的 sqlite 数据库
    docker run --rm -v ${DATA_DIR}:/data alpine sh -c "apk add --no-cache sqlite && \
        sqlite3 /data/x-ui.db \"REPLACE INTO settings (key, value) VALUES ('webPort', '${DEFAULT_PORT}');\""
        
    echo -e "${YELLOW}>>> 第四步: 重新启动容器应用新端口...${PLAIN}"
    docker start 3m-ui >/dev/null 2>&1
    open_ports ${DEFAULT_PORT}
    
    echo -e "${GREEN}🎉 安装完毕！端口已在数据库层面强制锁定为 ${DEFAULT_PORT}。${PLAIN}"
    show_info
}

diagnose_panel() {
    echo -e "${YELLOW}>>> 开始收集 3m-ui 运行诊断信息...${PLAIN}"
    echo -e "${GREEN}--- 1. 容器运行状态 ---${PLAIN}"
    docker ps -a | grep 3m-ui || echo "未找到 3m-ui 容器"
    
    echo -e "${GREEN}--- 2. 网络端口监听状态 (宿主机) ---${PLAIN}"
    ss -tulpn | grep "12053\|2053" || echo "当前宿主机没有监听 12053 或 2053 端口"
    
    echo -e "${GREEN}--- 3. 容器最近 20 行日志 ---${PLAIN}"
    docker logs --tail 20 3m-ui
    echo -e "${GREEN}-----------------------------------${PLAIN}"
    echo -e "${YELLOW}诊断提示:${PLAIN} 如果日志中显示 'Listening on :12053'，说明面板完全正常。此时若打不开，100%是云服务器厂商的安全组/防火墙没放行。如果日志报错，请根据日志内容排查。"
}

uninstall_panel() {
    echo -e "${RED}>>> 警告: 此操作将卸载 3m-ui 容器！${PLAIN}"
    docker stop 3m-ui >/dev/null 2>&1
    docker rm 3m-ui >/dev/null 2>&1
    echo -e "${GREEN}✅ 容器已删除。${PLAIN}"
    
    read -p "是否要【彻底删除】数据挂载目录？ [y/N]: " delete_data
    if [[ "${delete_data}" == "y" || "${delete_data}" == "Y" ]]; then
        rm -rf "${BASE_DIR}"
        echo -e "${RED}✅ 挂载目录已清理！${PLAIN}"
    else
        echo -e "${GREEN}✅ 数据安全保留在 ${DATA_DIR}。${PLAIN}"
    fi
}

show_menu() {
    while true; do
        clear
        echo -e "${GREEN}================================================${PLAIN}"
        echo -e "${GREEN}      3m-ui 一键脚本 (数据库直写安全版)${PLAIN}"
        echo -e "${GREEN}================================================${PLAIN}"
        echo -e "${YELLOW}1.${PLAIN} 安装 3m-ui 容器"
        echo -e "${YELLOW}2.${PLAIN} 更新 3m-ui 容器 (保留数据)"
        echo -e "${YELLOW}3.${PLAIN} 查看 3m-ui 面板信息"
        echo -e "${YELLOW}4.${PLAIN} 卸载 3m-ui 容器"
        echo -e "${YELLOW}5.${PLAIN} 运行诊断并查看运行日志"
        echo -e "${YELLOW}0.${PLAIN} 退出脚本"
        echo -e "${GREEN}================================================${PLAIN}"
        read -p "请输入选项 [0-5]: " choice
        
        case "${choice}" in
            1) install_panel; read -p "按回车键返回主菜单..." ;;
            2) docker pull ${IMAGE_NAME}; docker stop 3m-ui; docker rm 3m-ui; docker run -d --name 3m-ui --restart unless-stopped --network host -v ${DATA_DIR}:${CONTAINER_DATA_DIR} ${IMAGE_NAME}; echo "更新完成"; read -p "按回车..." ;;
            3) show_info; read -p "按回车键返回主菜单..." ;;
            4) uninstall_panel; read -p "按回车键返回主菜单..." ;;
            5) diagnose_panel; read -p "按回车键返回主菜单..." ;;
            0) exit 0 ;;
            *) sleep 1 ;;
        esac
    done
}

check_root
show_menu
