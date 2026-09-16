#!/bin/bash

# ================= 颜色定义 =================
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

# ================= 基础配置 =================
BASE_DIR="/opt/3m-ui"
DATA_DIR="${BASE_DIR}/data"
# 根据该仓库的习惯，镜像名通常与其 GitHub 账户名一致。如果后续他使用了 GHCR，可在此修改为 ghcr.io/kazeyukiro/3m-ui
IMAGE_NAME="kazeyukiro/3m-ui:latest"
# 大多数 X-ui 的 Fork 版本面板内部数据默认在 /etc/x-ui（若此面板改为了 /etc/3m-ui，请修改下方挂载路径）
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

install_or_update() {
    check_docker
    
    echo -e "${GREEN}>>> 开始安装 / 更新 3m-ui...${PLAIN}"
    
    # 创建数据持久化目录
    mkdir -p "${DATA_DIR}"
    echo -e "${GREEN}已确保数据目录存在: ${DATA_DIR}${PLAIN}"
    
    # 拉取最新镜像 (更新的核心操作)
    echo -e "${YELLOW}正在从 Docker Hub 拉取最新镜像...${PLAIN}"
    docker pull ${IMAGE_NAME}
    
    # 停止并删除旧容器（如果存在）
    if docker ps -a --format '{{.Names}}' | grep -Eq "^3m-ui$"; then
        echo -e "${YELLOW}检测到旧版本容器，正在停止并清理以应用更新...${PLAIN}"
        docker stop 3m-ui >/dev/null 2>&1
        docker rm 3m-ui >/dev/null 2>&1
    fi
    
    # 启动新容器
    echo -e "${YELLOW}正在启动 3m-ui 容器...${PLAIN}"
    docker run -d \
        --name 3m-ui \
        --restart unless-stopped \
        --network host \
        -v ${DATA_DIR}:${CONTAINER_DATA_DIR} \
        ${IMAGE_NAME}
        
    if [ $? -eq 0 ]; then
        echo -e ""
        echo -e "${GREEN}==================================================================${PLAIN}"
        echo -e "${GREEN} 🎉 3m-ui 容器安装/更新成功！${PLAIN}"
        echo -e "${GREEN}==================================================================${PLAIN}"
        echo -e " 📂 ${YELLOW}数据挂载路径 :${PLAIN} ${DATA_DIR}"
        echo -e "    ${GREEN}(注: 此目录包含面板数据库配置，下次执行更新或重装时数据不会丢失)${PLAIN}"
        echo -e " 🌐 ${YELLOW}容器网络模式 :${PLAIN} host (与宿主机共享网络，节点端口直通)"
        echo -e " ⚙️  ${YELLOW}开机自启动   :${PLAIN} 已开启"
        echo -e "${GREEN}==================================================================${PLAIN}"
        echo -e "${YELLOW}提示 1 :${PLAIN} 请在浏览器中通过面板默认端口访问 (通常为 http://你的IP:2053 或相关默认端口)"
        echo -e "${YELLOW}提示 2 :${PLAIN} 若需查看运行日志，请执行命令: ${GREEN}docker logs -f 3m-ui${PLAIN}"
        echo -e ""
    else
        echo -e "${RED}启动容器失败，请执行 docker logs 3m-ui 检查具体报错。${PLAIN}"
    fi
}

uninstall() {
    echo -e "${RED}>>> 警告: 此操作将卸载 3m-ui 容器！${PLAIN}"
    read -p "是否保留挂载的配置与节点数据？(y/n, 默认保留 y): " keep_data
    keep_data=${keep_data:-y}
    
    if docker ps -a --format '{{.Names}}' | grep -Eq "^3m-ui$"; then
        docker stop 3m-ui >/dev/null 2>&1
        docker rm 3m-ui >/dev/null 2>&1
        echo -e "${GREEN}容器已停止并删除。${PLAIN}"
    else
        echo -e "${YELLOW}未检测到运行中的 3m-ui 容器。${PLAIN}"
    fi
    
    if [[ "${keep_data}" == "n" || "${keep_data}" == "N" ]]; then
        rm -rf "${BASE_DIR}"
        echo -e "${GREEN}数据目录 ${BASE_DIR} 已被彻底清理。${PLAIN}"
    else
        echo -e "${GREEN}卸载完成！你的数据仍安全保留在 ${DATA_DIR}。${PLAIN}"
    fi
}

show_menu() {
    clear
    echo -e "${GREEN}================================================${PLAIN}"
    echo -e "${GREEN}      3m-ui Docker 一键管理脚本 (带数据持久化)${PLAIN}"
    echo -e "${GREEN}================================================${PLAIN}"
    echo -e "${YELLOW}1.${PLAIN} 安装 / 更新 3m-ui"
    echo -e "${YELLOW}2.${PLAIN} 卸载 3m-ui 容器"
    echo -e "${YELLOW}0.${PLAIN} 退出脚本"
    echo -e "${GREEN}================================================${PLAIN}"
    read -p "请输入选项 [0-2]: " choice
    
    case "${choice}" in
        1)
            install_or_update
            ;;
        2)
            uninstall
            ;;
        0)
            echo -e "${GREEN}已退出。${PLAIN}"
            exit 0
            ;;
        *)
            echo -e "${RED}输入无效，请重新输入！${PLAIN}"
            sleep 2
            show_menu
            ;;
    esac
}

check_root
show_menu
