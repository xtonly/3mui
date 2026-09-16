#!/bin/bash

# ================= 颜色定义 =================
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

# ================= 基础配置 =================
# 改为使用 Docker 原生命名卷，完美解决非 root 用户的权限问题
VOL_CONFIG="3m-ui-config"
VOL_DATA="3m-ui-data"
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
    echo -e " 👤 ${YELLOW}默认用户名   :${PLAIN} admin"
    echo -e " 🔑 ${YELLOW}随机初始密码 :${PLAIN} (请查看下方日志提取)"
    echo -e "${GREEN}==================================================================${PLAIN}"
    echo -e "${YELLOW}面板运行日志 (请寻找 'password' 等字眼获取初始密码):${PLAIN}"
    # 扩大日志抓取范围，确保能看到密码
    docker logs --tail 25 3m-ui
    echo -e "${GREEN}==================================================================${PLAIN}"
    echo -e "${RED}注意: 登录后请立刻在面板内修改密码！${PLAIN}"
}

install_panel() {
    check_env
    if docker ps -a --format '{{.Names}}' | grep -Eq "^3m-ui$"; then
        echo -e "${YELLOW}检测到 3m-ui 已存在，请先卸载！${PLAIN}"
        return
    fi
    
    echo -e "${GREEN}>>> 正在创建 Docker 命名卷 (解决非 root 权限问题)...${PLAIN}"
    docker volume create ${VOL_CONFIG} >/dev/null 2>&1
    docker volume create ${VOL_DATA} >/dev/null 2>&1
    
    echo -e "${YELLOW}>>> 正在从 GHCR 拉取官方镜像...${PLAIN}"
    docker pull ${IMAGE_NAME}
    
    echo -e "${YELLOW}>>> 正在启动 3m-ui 容器...${PLAIN}"
    docker run -d \
        --name 3m-ui \
        --restart unless-stopped \
        --network host \
        -v ${VOL_CONFIG}:/etc/3m-ui \
        -v ${VOL_DATA}:/var/lib/3m-ui \
        ${IMAGE_NAME}
        
    if [ $? -ne 0 ]; then
        echo -e "${RED}容器启动失败！请执行 docker logs 3m-ui 查看报错。${PLAIN}"
        return
    fi
    
    echo -e "${YELLOW}>>> 等待面板初始化并生成密码 (约 5 秒)...${PLAIN}"
    sleep 5
    
    echo -e "${YELLOW}>>> 尝试通过官方命令行修改端口为 ${DEFAULT_PORT}...${PLAIN}"
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
    
    docker run -d \
        --name 3m-ui \
        --restart unless-stopped \
        --network host \
        -v ${VOL_CONFIG}:/etc/3m-ui \
        -v ${VOL_DATA}:/var/lib/3m-ui \
        ${IMAGE_NAME}
        
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}🎉 更新完成！底层数据已通过 Docker 卷保留。${PLAIN}"
        docker ps | grep 3m-ui
    else
        echo -e "${RED}启动容器失败，请检查诊断日志。${PLAIN}"
    fi
}

uninstall_panel() {
    echo -e "${RED}>>> 警告: 此操作将卸载 3m-ui 容器！${PLAIN}"
    docker stop 3m-ui >/dev/null 2>&1
    docker rm 3m-ui >/dev/null 2>&1
    echo -e "${GREEN}✅ 容器已删除。${PLAIN}"
    
    read -p "是否要【彻底删除】数据持久化卷（包含所有节点配置）？ [y/N]: " delete_data
    if [[ "${delete_data}" == "y" || "${delete_data}" == "Y" ]]; then
        docker volume rm ${VOL_CONFIG} >/dev/null 2>&1
        docker volume rm ${VOL_DATA} >/dev/null 2>&1
        # 清理可能残留的旧版宿主机目录
        rm -rf /opt/3m-ui >/dev/null 2>&1
        echo -e "${RED}✅ 数据持久化卷已彻底清理！${PLAIN}"
    else
        echo -e "${GREEN}✅ 数据已安全保留在 Docker Volume 中。${PLAIN}"
        echo -e "${GREEN}   (下次重新安装会自动读取旧卷并恢复数据)${PLAIN}"
    fi
}

show_menu() {
    while true; do
        clear
        echo -e "${GREEN}================================================${PLAIN}"
        echo -e "${GREEN}  3m-ui 官方规范一键脚本 (Docker Volume 版)${PLAIN}"
        echo -e "${GREEN}================================================${PLAIN}"
        echo -e "${YELLOW}1.${PLAIN} 安装 3m-ui 容器"
        echo -e "${YELLOW}2.${PLAIN} 更新 3m-ui 容器 (保留数据)"
        echo -e "${YELLOW}3.${PLAIN} 查看 3m-ui 面板信息与初始密码"
        echo -e "${YELLOW}4.${PLAIN} 卸载 3m-ui 容器"
        echo -e "${YELLOW}5.${PLAIN} 忘记密码？一键重置管理员账号"
        echo -e "${YELLOW}0.${PLAIN} 退出脚本"
        echo -e "${GREEN}================================================${PLAIN}"
        read -p "请输入选项 [0-5]: " choice
        
        case "${choice}" in
            1) install_panel; read -p "按回车键返回主菜单..." ;;
            2) update_panel; read -p "按回车键返回主菜单..." ;;
            3) show_info; read -p "按回车键返回主菜单..." ;;
            4) uninstall_panel; read -p "按回车键返回主菜单..." ;;
            5) docker exec 3m-ui /usr/local/bin/3m-ui reset-admin; read -p "按回车键返回主菜单..." ;;
            0) exit 0 ;;
            *) sleep 1 ;;
        esac
    done
}

check_root
show_menu
