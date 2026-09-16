#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  3m-ui Docker 一键管理脚本
#  支持：安装 / 更新 / 卸载
#  数据持久化：独立挂载到宿主机 /opt/3m-ui/data
# ============================================================

APP_NAME="3m-ui"
CONTAINER_NAME="3m-ui"
IMAGE_NAME="ghcr.io/kazeyukiro/3m-ui:latest"
DATA_DIR="/opt/3m-ui"
DATA_SUBDIR="${DATA_DIR}/data"
COMPOSE_FILE="${DATA_DIR}/docker-compose.yml"
PANEL_PORT="${PANEL_PORT:-8080}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ---------- 检查 root ----------
check_root() {
    [[ $EUID -eq 0 ]] || error "请使用 root 用户运行此脚本（sudo bash $0）"
}

# ---------- 检查 Docker ----------
check_docker() {
    if ! command -v docker &>/dev/null; then
        warn "未检测到 Docker，正在安装..."
        curl -fsSL https://get.docker.com | sh
        systemctl enable docker --now 2>/dev/null || true
    fi
    if ! docker compose version &>/dev/null; then
        warn "未检测到 Docker Compose 插件，请手动安装后重试"
        exit 1
    fi
    info "Docker 环境检查通过"
}

# ---------- 创建数据目录 ----------
create_dirs() {
    mkdir -p "${DATA_SUBDIR}"/{config,db,cert,logs}
    info "数据目录已创建：${DATA_SUBDIR}"
}

# ---------- 生成 docker-compose.yml ----------
generate_compose() {
    cat > "${COMPOSE_FILE}" <<EOF
services:
  ${APP_NAME}:
    image: ${IMAGE_NAME}
    container_name: ${CONTAINER_NAME}
    restart: unless-stopped
    network_mode: host
    volumes:
      # 面板配置
      - ${DATA_SUBDIR}/config:/app/config
      # SQLite 数据库
      - ${DATA_SUBDIR}/db:/app/data
      # SSL / ACME 证书
      - ${DATA_SUBDIR}/cert:/app/cert
      # 运行日志
      - ${DATA_SUBDIR}/logs:/app/logs
    environment:
      - TZ=Asia/Shanghai
      - PANEL_PORT=${PANEL_PORT}
EOF
    info "docker-compose.yml 已生成"
}

# ==================== 安装 ====================
do_install() {
    check_root; check_docker
    info "开始安装 ${APP_NAME}..."

    if [[ -f "${COMPOSE_FILE}" ]]; then
        warn "检测到已有配置，将保留现有数据并更新镜像"
    else
        create_dirs
        generate_compose
    fi

    cd "${DATA_DIR}"
    docker compose pull
    docker compose up -d

    echo ""
    echo "=============================================="
    echo -e "${GREEN}  ✅ ${APP_NAME} 安装完成！${NC}"
    echo "=============================================="
    echo -e "  面板地址 : ${YELLOW}http://$(hostname -I | awk '{print $1}'):${PANEL_PORT}/${NC}"
    echo -e "  默认用户 : ${YELLOW}admin${NC}"
    echo -e "  初始密码 : 首次启动时会打印在容器日志中"
    echo -e "             执行 ${YELLOW}docker logs ${CONTAINER_NAME} 2>&1 | grep -i password${NC}"
    echo ""
    echo -e "  数据目录 : ${YELLOW}${DATA_SUBDIR}${NC}"
    echo -e "  更新命令 : ${YELLOW}sudo bash $0 update${NC}"
    echo -e "  卸载命令 : ${YELLOW}sudo bash $0 uninstall${NC}"
    echo "=============================================="
}

# ==================== 更新 ====================
do_update() {
    check_root; check_docker
    [[ -f "${COMPOSE_FILE}" ]] || error "未找到安装配置，请先执行安装"

    info "正在更新 ${APP_NAME}..."
    cd "${DATA_DIR}"
    docker compose pull
    docker compose up -d --remove-orphans

    echo ""
    echo -e "${GREEN}  ✅ ${APP_NAME} 更新完成！${NC}"
    echo -e "  数据目录 ${YELLOW}${DATA_SUBDIR}${NC} 中的数据未受影响"
    echo -e "  面板地址 : ${YELLOW}http://$(hostname -I | awk '{print $1}'):${PANEL_PORT}/${NC}"
}

# ==================== 卸载 ====================
do_uninstall() {
    check_root
    [[ -f "${COMPOSE_FILE}" ]] || { warn "未找到安装配置，无需卸载"; exit 0; }

    echo -e "${YELLOW}⚠️  即将卸载 ${APP_NAME}${NC}"
    echo -e "  容器和镜像将被删除"
    echo -e "  数据目录 ${YELLOW}${DATA_SUBDIR}${NC} 将保留"
    echo ""
    read -rp "确认卸载？(y/N): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消卸载"; exit 0; }

    cd "${DATA_DIR}"
    docker compose down --rmi all 2>/dev/null || true

    echo ""
    echo -e "${GREEN}  ✅ ${APP_NAME} 已卸载${NC}"
    echo -e "  数据仍保留在：${YELLOW}${DATA_SUBDIR}${NC}"
    echo -e "  如需彻底删除数据，请执行："
    echo -e "  ${RED}rm -rf ${DATA_DIR}${NC}"
}

# ==================== 主入口 ====================
case "${1:-}" in
    install)   do_install ;;
    update)    do_update ;;
    uninstall) do_uninstall ;;
    *)
        echo "用法: sudo bash $0 {install|update|uninstall}"
        echo ""
        echo "  install    — 安装 3m-ui 并持久化数据"
        echo "  update     — 拉取最新镜像并更新（数据保留）"
        echo "  uninstall  — 停止并删除容器/镜像（数据保留）"
        exit 1
        ;;
esac
