#!/bin/bash

# ================= 颜色定义 =================
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

# ================= 基础配置 =================
BASE_DIR="/opt/3m-ui"
CONFIG_DIR="${BASE_DIR}/config"
DATA_DIR="${BASE_DIR}/data"
IMAGE_NAME="ghcr.io/kazeyukiro/3m-ui:latest"
DEFAULT_PORT="12053"

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误：本脚本需要 root 权限执行！${PLAIN}"
        exit 1
    fi
}

check_env() {
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}未检测到 Docker，正在自动安装...${PLAIN}"
        curl -fsSL https://get.docker.com | bash -s docker
        systemctl enable --now docker
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
    
    # 尝试从日志中抓取初始密码 (如果是首次安装)
    echo -e " 👤 ${YELLOW}默认用户名   :${PLAIN} admin"
    echo -e " 🔑 ${YELLOW}随机初始密码 :${PLAIN} (请查看下方日志提取，或在终端执行 docker logs 3m-ui 查看)"
    echo -e "${GREEN}==================================================================${PLAIN}"
    echo -e "${YELLOW}面板运行日志最后 15 行 (请在其中寻找 password 等字眼):${PLAIN}"
    docker logs --tail 15 3m-ui
    echo -e "${GREEN}==================================================================${PLAIN}"
    echo -e "${RED}注意: 登录后请立刻在面板内修改密码，日志轮转后将无法再次找回！${PLAIN}"
}

install_panel() {
    check_env
    if docker ps -a --format '{{.Names}}' | grep -Eq "^3m-ui$"; then
        echo -e "${YELLOW}检测到 3m-ui 已存在，请先卸载！${PLAIN}"
        return
    fi
    
    echo -e "${GREEN}>>> 正在按照官方规范创建目录...${PLAIN}"
    mkdir -p "${CONFIG_DIR}"
    mkdir -p "${DATA_DIR}"
    
    echo -e "${YELLOW}>>> 正在从 GHCR 拉取官方镜像...${PLAIN}"
    docker pull ${IMAGE_NAME}
    if [ $? -ne 0 ]; then
        echo -e "${RED}拉取镜像失败！可能是网络无法连接到 ghcr.io。${PLAIN}"
        return
    fi
    
    echo -e "${YELLOW}>>> 正在启动 3m-ui 容器...${PLAIN}"
    docker run -d \
        --name 3m-ui \
        --restart unless-stopped \
        --network host \
        -v ${CONFIG_DIR}:/etc/3m-ui \
        -v ${DATA_DIR}:/var/lib/3m-ui \
        ${IMAGE_NAME}
        
    if [ $? -ne 0 ]; then
        echo -e "${RED}容器启动失败！请执行 docker logs 3m-ui 查看报错。${PLAIN}"
        return
    fi
    
    # 等待面板初始化完成并生成密码
    echo -e "${YELLOW}>>> 等待面板初始化并生成随机密码 (约 5 秒)...${PLAIN}"
    sleep 5
    
    echo -e "${YELLOW}>>> 尝试通过官方命令行工具修改端口为 ${DEFAULT_PORT}...${PLAIN}"
    # 使用官方文档提供的正确二进制路径修改端口
    docker exec 3m-ui /usr/local/bin/3m-ui setting -port ${DEFAULT_PORT}
    
    echo -e "${YELLOW}>>> 重启容器以应用端口修改...${PLAIN}"
    docker restart 3m-ui >/dev/null 2>&1
    open_ports ${DEFAULT_PORT}
    
    echo -e "${GREEN}🎉 安装完毕！${PLAIN}"
    show_info
}

update_panel() {
    echo -e "${YELLOW}>>> 准备更新 3m-ui...${PLAIN}"
    check_env
    
    docker pull ${IMAGE_NAME}
    
    echo -e "${YELLOW}>>> 正在清理旧容器...${PLAIN}"
    docker stop 3m-ui >/dev/null 2>&1
    docker rm 3m-ui >/dev/null 2>&1
    
    # 使用现有的配置和数据目录启动新容器
    docker run -d \
        --name 3m-ui \
        --restart unless-stopped \
        --network host \
        -v ${CONFIG_DIR}:/etc/3m-ui \
        -v ${DATA_DIR}:/var/lib/3m-ui \
        ${IMAGE_NAME}
        
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}🎉 更新完成！底层数据已保留。${PLAIN}"
        docker ps | grep 3m-ui
    else
        echo -e "${RED}启动容器失败，请检查诊断日志。${PLAIN}"
    fi
}

reset_password() {
    if ! docker ps -a --format '{{.Names}}' | grep -Eq "^3m-ui$"; then
        echo -e "${RED}未检测到运行中的 3m-ui 容器！${PLAIN}"
        return
    fi
    echo -e "${YELLOW}>>> 正在执行官方重置密码命令...${PLAIN}"
    docker exec 3m-ui /usr/local/bin/3m-ui reset-admin
    echo -e "${GREEN}✅ 重置指令已发送！请查看上方日志或终端输出了解新密码。${PLAIN}"
}

uninstall_panel() {
    echo -e "${RED}>>> 警告: 此操作将卸载 3m-ui 容器！${PLAIN}"
    docker stop 3m-ui >/dev/null 2>&1
    docker rm 3m-ui >/dev/null 2>&1
    echo -e "${GREEN}✅ 容器已删除。${PLAIN}"
    
    read -p "是否要【彻底删除】数据挂载目录（包含所有节点配置）？ [y/N]: " delete_data
    if [[ "${delete_data}" == "y" || "${delete_data}" == "Y" ]]; then
        rm -rf "${BASE_DIR}"
        echo -e "${RED}✅ 挂载目录已彻底清理！${PLAIN}"
    else
        echo -e "${GREEN}✅ 数据安全保留在 ${BASE_DIR} 目录下。${PLAIN}"
    fi
}

show_menu() {
    while true; do
        clear
        echo -e "${GREEN}================================================${PLAIN}"
        echo -e "${GREEN}        3m-ui 官方规范一键部署脚本${PLAIN}"
        echo -e "${GREEN}================================================${PLAIN}"
        echo -e "${YELLOW}1.${PLAIN} 安装 3m-ui 容器"
        echo -e "${YELLOW}2.${PLAIN} 更新 3m-ui 容器 (保留数据)"
        echo -e "${YELLOW}3.${PLAIN} 查看 3m-ui 面板信息与初始密码"
        echo -e "${YELLOW}4.${PLAIN} 卸载 3m-ui 容器"
        echo -e "${YELLOW}5.${PLAIN} 忘记密码？一键强制重置管理员账号"
        echo -e "${YELLOW}0.${PLAIN} 退出脚本"
        echo -e "${GREEN}================================================${PLAIN}"
        read -p "请输入选项 [0-5]: " choice
        
        case "${choice}" in
            1) install_panel; read -p "按回车键返回主菜单..." ;;
            2) update_panel; read -p "按回车键返回主菜单..." ;;
            3) show_info; read -p "按回车键返回主菜单..." ;;
            4) uninstall_panel; read -p "按回车键返回主菜单..." ;;
            5) reset_password; read -p "按回车键返回主菜单..." ;;
            0) exit 0 ;;
            *) sleep 1 ;;
        esac
    done
}

check_root
show_menu
