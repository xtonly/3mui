#!/bin/bash

# ================= 颜色定义 =================
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

# ================= 基础配置 =================
BASE_DIR="/opt/3m-ui"
DATA_DIR="${BASE_DIR}/data"
# 根据报错，源镜像可能位于 GitHub 官方源 (GHCR)
IMAGE_NAME="ghcr.io/kazeyukiro/3m-ui:latest"
# 如果该面板依然继承 x-ui 的结构，内部数据应在 /etc/x-ui
CONTAINER_DATA_DIR="/etc/x-ui" 

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误：本脚本需要 root 权限执行！${PLAIN}"
        exit 1
    fi
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}未检测到 Docker，正在尝试自动安装...${PLAIN}"
        curl -fsSL https://get.docker.com | bash -s docker
        systemctl enable --now docker
        if ! command -v docker &> /dev/null; then
            echo -e "${RED}Docker 安装失败，请手动安装后重试。${PLAIN}"
            exit 1
        fi
        echo -e "${GREEN}Docker 安装成功！${PLAIN}"
    fi
}

show_info() {
    # 自动获取本机公网 IP
    LOCAL_IP=$(curl -s4m8 ip.sb || curl -s4m8 ipinfo.io/ip)
    
    echo -e ""
    echo -e "${GREEN}==================================================================${PLAIN}"
    echo -e "${GREEN} 🚀 3m-ui 面板信息查询${PLAIN}"
    echo -e "${GREEN}==================================================================${PLAIN}"
    echo -e " 📂 ${YELLOW}数据挂载路径 :${PLAIN} ${DATA_DIR}"
    echo -e " 🌐 ${YELLOW}面板访问地址 :${PLAIN} http://${LOCAL_IP}:2053 ${GREEN}(注: 2053为默认端口，如有修改请用新端口)${PLAIN}"
    echo -e " 👤 ${YELLOW}默认用户名   :${PLAIN} admin"
    echo -e " 🔑 ${YELLOW}默认密码     :${PLAIN} admin"
    echo -e "${GREEN}==================================================================${PLAIN}"
    echo -e "${YELLOW}温馨提示 :${PLAIN} 如果无法打开网页，请前往云服务商控制台(或面板内)放行 2053 端口。"
    echo -e ""
}

install_panel() {
    check_docker
    
    if docker ps -a --format '{{.Names}}' | grep -Eq "^3m-ui$"; then
        echo -e "${YELLOW}检测到 3m-ui 容器已在运行！如需操作请选择【2】更新或先卸载。${PLAIN}"
        return
    fi
    
    echo -e "${GREEN}>>> 开始安装 3m-ui...${PLAIN}"
    mkdir -p "${DATA_DIR}"
    
    echo -e "${YELLOW}正在拉取最新镜像 ${IMAGE_NAME} ...${PLAIN}"
    docker pull ${IMAGE_NAME}
    if [ $? -ne 0 ]; then
        echo -e "${RED}镜像拉取失败！请检查网络，或与面板作者确认正确的 Docker 镜像名称。${PLAIN}"
        return
    fi
    
    echo -e "${YELLOW}正在启动 3m-ui 容器...${PLAIN}"
    docker run -d \
        --name 3m-ui \
        --restart unless-stopped \
        --network host \
        -v ${DATA_DIR}:${CONTAINER_DATA_DIR} \
        ${IMAGE_NAME}
        
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}🎉 3m-ui 容器安装成功！${PLAIN}"
        show_info
    else
        echo -e "${RED}启动容器失败，请执行 docker logs 3m-ui 检查报错。${PLAIN}"
    fi
}

update_panel() {
    check_docker
    
    if ! docker ps -a --format '{{.Names}}' | grep -Eq "^3m-ui$"; then
        echo -e "${YELLOW}未检测到 3m-ui 容器，无法进行更新，请先执行【1】安装！${PLAIN}"
        return
    fi
    
    echo -e "${GREEN}>>> 开始更新 3m-ui...${PLAIN}"
    echo -e "${YELLOW}正在拉取最新镜像...${PLAIN}"
    docker pull ${IMAGE_NAME}
    
    echo -e "${YELLOW}正在停止并删除旧容器...${PLAIN}"
    docker stop 3m-ui >/dev/null 2>&1
    docker rm 3m-ui >/dev/null 2>&1
    
    echo -e "${YELLOW}正在启动新版本容器...${PLAIN}"
    docker run -d \
        --name 3m-ui \
        --restart unless-stopped \
        --network host \
        -v ${DATA_DIR}:${CONTAINER_DATA_DIR} \
        ${IMAGE_NAME}
        
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}🎉 3m-ui 更新成功！由于采用了挂载，你的所有节点数据均已保留。${PLAIN}"
        show_info
    else
        echo -e "${RED}启动容器失败，请执行 docker logs 3m-ui 检查报错。${PLAIN}"
    fi
}

uninstall_panel() {
    echo -e "${RED}>>> 警告: 此操作将卸载 3m-ui 容器！${PLAIN}"
    
    if docker ps -a --format '{{.Names}}' | grep -Eq "^3m-ui$"; then
        docker stop 3m-ui >/dev/null 2>&1
        docker rm 3m-ui >/dev/null 2>&1
        echo -e "${GREEN}✅ 容器进程已被终止并删除。${PLAIN}"
    else
        echo -e "${YELLOW}未检测到运行中的 3m-ui 容器。${PLAIN}"
    fi
    
    echo -e ""
    echo -e "${YELLOW}当前面板的历史数据存放在: ${DATA_DIR}${PLAIN}"
    read -p "是否要【彻底删除】数据挂载目录？(不删除的话，下次重新安装数据还在) [y/N] (默认保留 N): " delete_data
    delete_data=${delete_data:-n}
    
    if [[ "${delete_data}" == "y" || "${delete_data}" == "Y" ]]; then
        rm -rf "${BASE_DIR}"
        echo -e "${RED}✅ 警告：数据挂载目录 ${BASE_DIR} 已被彻底清理！${PLAIN}"
    else
        echo -e "${GREEN}✅ 卸载完成！你的配置数据安全保留在 ${DATA_DIR}。${PLAIN}"
        echo -e "${GREEN}下次再次执行安装时，系统会自动读取此目录恢复节点。${PLAIN}"
    fi
}

show_menu() {
    while true; do
        clear
        echo -e "${GREEN}================================================${PLAIN}"
        echo -e "${GREEN}      3m-ui Docker 一键管理脚本 (分离版)${PLAIN}"
        echo -e "${GREEN}================================================${PLAIN}"
        echo -e "${YELLOW}1.${PLAIN} 安装 3m-ui 容器"
        echo -e "${YELLOW}2.${PLAIN} 更新 3m-ui 容器"
        echo -e "${YELLOW}3.${PLAIN} 查看 3m-ui 面板信息 (地址/密码/挂载目录)"
        echo -e "${YELLOW}4.${PLAIN} 卸载 3m-ui 容器"
        echo -e "${YELLOW}0.${PLAIN} 退出脚本"
        echo -e "${GREEN}================================================${PLAIN}"
        read -p "请输入选项 [0-4]: " choice
        
        case "${choice}" in
            1)
                install_panel
                read -p "按回车键返回主菜单..."
                ;;
            2)
                update_panel
                read -p "按回车键返回主菜单..."
                ;;
            3)
                show_info
                read -p "按回车键返回主菜单..."
                ;;
            4)
                uninstall_panel
                read -p "按回车键返回主菜单..."
                ;;
            0)
                echo -e "${GREEN}已退出。${PLAIN}"
                exit 0
                ;;
            *)
                echo -e "${RED}输入无效，请重新输入！${PLAIN}"
                sleep 2
                ;;
        esac
    done
}

check_root
show_menu
