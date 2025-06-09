#!/usr/bin/env bash

set -e

# 日志输出函数
info()  { echo -e "\033[1;34m[INFO]\033[0m $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*"; }

# 判断 sudo
if [ "$(id -u)" -ne 0 ]; then
  SUDO='sudo'
else
  SUDO=''
fi

# 自动识别平台架构
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH_SUFFIX="amd64" ;;
  aarch64 | arm64) ARCH_SUFFIX="arm64" ;;
  *) error "不支持的架构: $ARCH"; exit 1 ;;
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
read -p "是否现在在线编辑 config.yaml？(y=在线编辑 / n=稍后手动编辑): " edit_choice
if [[ "$edit_choice" =~ ^[Yy]$ ]]; then
  # 自动检测可用的编辑器
  if command -v "${EDITOR:-}" >/dev/null 2>&1; then
    "$EDITOR" "$CONFIG_DIR/config.yaml"
  elif command -v nano >/dev/null 2>&1; then
    nano "$CONFIG_DIR/config.yaml"
  elif command -v vim >/dev/null 2>&1; then
    vim "$CONFIG_DIR/config.yaml"
  elif command -v vi >/dev/null 2>&1; then
    vi "$CONFIG_DIR/config.yaml"
  else
    error "未找到可用的终端文本编辑器（如 nano、vim、vi）。"
    echo "请使用其他方式手动编辑：$CONFIG_DIR/config.yaml"
    exit 1
  fi
else
  warn "你选择了手动编辑。请编辑配置文件："
  echo "   $CONFIG_DIR/config.yaml"
  echo "然后再继续运行服务。"
fi

# 4. 下载 systemd 服务文件
SERVICE_PATH="/etc/systemd/system/mihomo.service"
info "配置 systemd 服务..."
curl -sSL https://raw.githubusercontent.com/Jejz168/Clash/main/mihomo/mihomo.service -o "/tmp/mihomo.service"
$SUDO mv /tmp/mihomo.service "$SERVICE_PATH"

# 询问是否已经编辑配置文件
read -p "是否已经编辑并保存了配置文件？(y/n): " edited_choice
if [[ "$edited_choice" =~ ^[Yy]$ ]]; then
  $SUDO systemctl daemon-reexec
  $SUDO systemctl daemon-reload
  $SUDO systemctl enable mihomo.service

  info "启动 mihomo 服务..."
  $SUDO systemctl start mihomo.service

  info "安装完成！你可以使用以下命令查看状态："
  echo "   systemctl status mihomo.service"
else
  warn "未启动服务，请先编辑配置文件后再手动启动 mihomo 服务。"
  echo "编辑文件路径：$CONFIG_DIR/config.yaml"
  echo "启动命令示例：sudo systemctl start mihomo.service"
  exit 0
fi