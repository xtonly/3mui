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

check_env() {
    # 检查并安装 Docker
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}未检测到 Docker，正在自动安装...${PLAIN}"
        curl -fsSL https://get.docker.com | bash -s docker
        systemctl enable --now docker
    fi
    # 检查并安装 Git (编译源码必须)
    if ! command -v git &> /dev/null; then
        echo -e "${YELLOW}未检测到 Git，正在自动安装...${PLAIN}"
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y git
        elif command -v yum &> /dev/null; then
            yum install -y git
        fi
    fi
}

open_ports() {
    local port=$1
    echo -e "${YELLOW}>>> 正在防火墙中严格放行 ${port} 端口...${PLAIN}"
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

build_image() {
    # 如果本地没有镜像，则克隆源码并构建
    if ! docker image inspect ${IMAGE_NAME} &> /dev/null; then
        echo -e "${YELLOW}>>> 官方未提供镜像，正在从 GitHub 拉取源码并自动本机编译...${PLAIN}"
        echo -e "${YELLOW}>>> (这可能需要 1~3 分钟，视服务器性能而定，请耐心等待)${PLAIN}"
        
        rm -rf /tmp/3m-ui-source
        git clone https://github.com/kazeyukiro/3m-ui.git /tmp/3m-ui-source
        if [ $? -ne 0 ]; then
            echo -e "${RED}克隆源码失败！请检查服务器与 GitHub 的网络连接。${PLAIN}"
            exit 1
        fi
        
        echo -e "${YELLOW}>>> 开始执行 docker build...${PLAIN}"
        docker build -t ${IMAGE_NAME} /tmp/3m-ui-source
        if [ $? -ne 0 ]; then
            echo -e "${RED}镜像编译失败！请检查报错信息。${PLAIN}"
            exit 1
        fi
        
        echo -e "${GREEN}>>> 镜像编译成功！清理源码临时文件...${PLAIN}"
        rm -rf /tmp/3m-ui-source
    else
        echo -e "${GREEN}>>> 检测到本地已存在 3m-ui 镜像，跳过编译步骤。${PLAIN}"
    fi
}

install_panel() {
    check_env
    if docker ps -a --format '{{.Names}}' | grep -Eq "^3m-ui$"; then
        echo -e "${YELLOW}检测到 3m-ui 已存在，请先卸载！${PLAIN}"
        return
    fi
    
    # 核心：自动编译镜像
    build_image
    
    echo -e "${GREEN}>>> 第一步: 创建目录并启动容器初始化数据库...${PLAIN}"
    mkdir -p "${DATA_DIR}"
    
    docker run -d --name 3m-ui --restart unless-stopped --network host -v ${DATA_DIR}:${CONTAINER_DATA_DIR} ${IMAGE_NAME}
    if [ $? -ne 0 ]; then
        echo -e "${RED}容器启动失败！${PLAIN}"
        return
    fi
    
    # 等待数据库文件生成
    sleep 3
    echo -e "${YELLOW}>>> 第二步: 停止容器，准备通过数据库底层修改端口...${PLAIN}"
    docker stop 3m-ui >/dev/null 2>&1
    
    echo -e "${YELLOW}>>> 第三步: 运行 SQLite 微型容器注入 12053 端口...${PLAIN}"
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
    ss -tulpn | grep -E "12053|2053" || echo "当前宿主机没有监听 12053 或 2053 端口"
    
    echo -e "${GREEN}--- 3. 容器最近 20 行日志 ---${PLAIN}"
    docker logs --tail 20 3m-ui
    echo -e "${GREEN}-----------------------------------${PLAIN}"
}

update_panel() {
    echo -e "${YELLOW}>>> 准备更新 3m-ui...${PLAIN}"
    check_env
    
    # 删除旧镜像，强制重新拉取代码编译
    echo -e "${YELLOW}>>> 正在清理旧容器和旧镜像...${PLAIN}"
    docker stop 3m-ui >/dev/null 2>&1
    docker rm 3m-ui >/dev/null 2>&1
    docker rmi ${IMAGE_NAME} >/dev/null 2>&1
    
    # 重新构建并启动
    build_image
    docker run -d --name 3m-ui --restart unless-stopped --network host -v ${DATA_DIR}:${CONTAINER_DATA_DIR} ${IMAGE_NAME}
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}🎉 更新完成！底层数据已保留，依然运行在 ${DEFAULT_PORT} 端口。${PLAIN}"
        show_info
    else
        echo -e "${RED}启动容器失败，请检查诊断日志。${PLAIN}"
    fi
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
        echo -e "${GREEN}   3m-ui 一键脚本 (带全自动本地编译 & 端口锁定)${PLAIN}"
        echo -e "${GREEN}================================================${PLAIN}"
        echo -e "${YELLOW}1.${PLAIN} 安装 3m-ui 容器 (首次会自动拉源码编译)"
        echo -e "${YELLOW}2.${PLAIN} 更新 3m-ui 容器 (保留数据，重新拉源码编译)"
        echo -e "${YELLOW}3.${PLAIN} 查看 3m-ui 面板信息"
        echo -e "${YELLOW}4.${PLAIN} 卸载 3m-ui 容器"
        echo -e "${YELLOW}5.${PLAIN} 运行诊断并查看运行日志"
        echo -e "${YELLOW}0.${PLAIN} 退出脚本"
        echo -e "${GREEN}================================================${PLAIN}"
        read -p "请输入选项 [0-5]: " choice
        
        case "${choice}" in
            1) install_panel; read -p "按回车键返回主菜单..." ;;
            2) update_panel; read -p "按回车键返回主菜单..." ;;
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
