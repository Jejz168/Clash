#!/usr/bin/env bash
#===============================================
# Description: Mihomo裸核安装使用
# File name: mihomo-install.sh
# Lisence: MIT
# By: Jejz
#===============================================

set -e -o pipefail

# 日志输出函数
log() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
info()  { log "\033[1;34m[INFO]\033[0m $*"; }
warn()  { log "\033[1;33m[WARN]\033[0m $*"; }
error() { log "\033[1;31m[ERROR]\033[0m $*"; exit 1; }

# 判断 sudo
if [ "$(id -u)" -ne 0 ]; then
  SUDO='sudo'
else
  SUDO=''
fi

# 读取 ID 字段
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID=$ID
else
    echo "无法识别系统（缺少 /etc/os-release）"
    exit 1
fi

# 输出识别到的系统
echo "检测到系统: $OS_ID"

# 根据系统使用对应的安装命令
case "$OS_ID" in
  openwrt)
    echo "使用 opkg 安装 curl gzip nano"
    opkg update && opkg install curl gzip nano
    ;;
  alpine)
    echo "使用 apk 安装 curl gzip nano"
    apk update && apk add curl gzip nano
    ;;
  debian|ubuntu)
    echo "使用 apt 安装 curl gzip nano"
    apt update && apt install -y curl gzip nano
    ;;
  centos|rhel|fedora)
    if command -v dnf >/dev/null 2>&1; then
        echo "使用 dnf 安装 curl gzip nano"
        dnf install -y curl gzip nano
    else
        echo "使用 yum 安装 curl gzip nano"
        yum install -y curl gzip nano
    fi
    ;;
  arch)
    echo "使用 pacman 安装 curl gzip nano"
    pacman -Syu --noconfirm curl gzip nano
    ;;
  *)
    echo "不支持的系统类型: $OS_ID"
    exit 1
    ;;
esac

# 自动识别平台架构
ARCH=$(uname -m)
case "${ARCH}" in
    'x86_64')    ARCH_SUFFIX='amd64';;
    'x86' | 'i686' | 'i386')     ARCH_SUFFIX='386';;
    'aarch64' | 'arm64') ARCH_SUFFIX='arm64';;
    'armv7l')   ARCH_SUFFIX='armv7';;
    's390x')    ARCH_SUFFIX='s390x';;
    *)  error "不支持的架构: $ARCH"; exit 1 ;;
esac
info "检测到平台架构：$ARCH -> $ARCH_SUFFIX"

# 1. 获取版本号
info "获取 Mihomo 最新版本..."
VERSION_URL="https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/version.txt"
VERSION=$(
  curl -sSL "$VERSION_URL" | grep -o 'alpha-[a-z0-9]\+' || {
    error "无法获取版本号"; exit 1;
  }
)
info "最新版本为 $VERSION"

# 2. 下载核心文件
CORE_URL="https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/mihomo-linux-${ARCH_SUFFIX}-${VERSION}.gz"
CORE_GZ="mihomo.gz"
CORE_BIN="mihomo"

info "下载核心文件..."
curl -sSL "$CORE_URL" -o "$CORE_GZ"
gzip -df "$CORE_GZ"
chmod +x "$CORE_BIN"

info "安装核心到 /usr/local/bin..."
$SUDO mv "$CORE_BIN" /usr/local/bin/mihomo
$SUDO chmod 755 /usr/local/bin/mihomo

# 3. 下载 config.yaml
CONFIG_DIR="/etc/mihomo"
$SUDO mkdir -p "$CONFIG_DIR"

info "检查配置文件是否存在..."
if [ -f "$CONFIG_DIR/config.yaml" ]; then
  info "配置文件已存在，跳过下载。"
else
  info "下载 config.yaml..."
  curl -sSL https://raw.githubusercontent.com/Jejz168/Clash/main/mihomo/mihomo-config.yaml -o "$CONFIG_DIR/config.yaml"
fi

info "请修改配置文件：$CONFIG_DIR/config.yaml"
warn "当前配置文件可能尚未包含订阅地址，若不配置，Mihomo 启动将失败！"
warn "⚠️ 建议使用图形化文本编辑器（如 VS Code）手动编辑 config.yaml，避免格式错误。"
read -p "是否现在在线编辑 config.yaml？(y=在线编辑 / n=稍后手动编辑): " edit_choice
if [[ "$edit_choice" =~ ^[Yy]$ ]]; then
  nano "$CONFIG_DIR/config.yaml"
else
  warn "你选择了手动编辑。请编辑配置文件："
  echo "   $CONFIG_DIR/config.yaml"
  echo "然后再继续运行服务。"
fi

# 4.配置启动文件
read -p "是否已经编辑并保存了配置文件？(y/n): " edited_choice
if [[ "$edited_choice" =~ ^[Yy]$ ]]; then
  SERVICE_NAME="mihomo"
  case "$OS_ID" in
    openwrt)
      info "写入 OpenWrt init 脚本..."
      INIT_FILE="/etc/init.d/$SERVICE_NAME"
      $SUDO tee "$INIT_FILE" > /dev/null <<EOF
#!/bin/sh /etc/rc.common

START=99
STOP=10

start() {
    echo "启动 $SERVICE_NAME"
    /usr/local/bin/mihomo -c /etc/mihomo/config.yaml &
}

stop() {
    echo "停止 $SERVICE_NAME"
    killall mihomo || true
}
EOF
      $SUDO chmod +x "$INIT_FILE"
      $SUDO /etc/init.d/$SERVICE_NAME enable
      $SUDO /etc/init.d/$SERVICE_NAME start
      info "OpenWrt 启动配置完成，服务已启动！"
      ;;

    alpine)
      info "写入 Alpine OpenRC 脚本..."
      INIT_FILE="/etc/init.d/$SERVICE_NAME"
      $SUDO tee "$INIT_FILE" > /dev/null <<EOF
#!/sbin/openrc-run

command="/usr/local/bin/mihomo"
command_args="-c /etc/mihomo/config.yaml"
command_background=true

depend() {
    need net
}
EOF
      $SUDO chmod +x "$INIT_FILE"
      $SUDO rc-update add $SERVICE_NAME default
      $SUDO rc-service $SERVICE_NAME start
      info "Alpine 启动配置完成，服务已启动！"
      ;;

    debian|ubuntu|centos|rhel|fedora|arch)
      info "写入 systemd 服务文件..."
      SERVICE_PATH="/etc/systemd/system/$SERVICE_NAME.service"
      $SUDO tee "$SERVICE_PATH" > /dev/null <<EOF
[Unit]
Description=Mihomo Kernel by MetaCubeX
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/mihomo -c /etc/mihomo/config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
      $SUDO systemctl daemon-reexec
      $SUDO systemctl daemon-reload
      $SUDO systemctl enable $SERVICE_NAME
      $SUDO systemctl start $SERVICE_NAME
      info "$OS_ID 启动配置完成，服务已启动！"
      ;;

    *)
      error "该系统未配置自动启动脚本。"
      ;;
  esac
else
  warn "未启动服务，请先编辑配置文件后再手动启动 mihomo 服务。"
  echo "配置文件路径：$CONFIG_DIR/config.yaml"
  exit 0
fi