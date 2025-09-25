#!/bin/bash
# ===============================
# Nikki 内核更新脚本
# File name: update_nikki.sh
# Lisence: MIT
# By: Jejz
# ===============================

set -e -o pipefail  # 遇到错误立即退出

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

# -------------------------
# 配置代理前缀（可选）
# -------------------------
# 默认不使用代理，如需代理请GIT_PROXY="http://xxxx/"
GIT_PROXY=""

if [ -n "$GIT_PROXY" ]; then
  info "使用代理前缀: $GIT_PROXY"
else
  info "未启用代理前缀"
fi

# -------------------------
# 自动识别平台架构
# -------------------------
ARCH=$(uname -m)
case "${ARCH}" in
    'x86_64')    ARCH_SUFFIX='amd64' ;;
    'x86' | 'i686' | 'i386') ARCH_SUFFIX='386' ;;
    'aarch64' | 'arm64') ARCH_SUFFIX='arm64' ;;
    'armv7l')   ARCH_SUFFIX='armv7' ;;
    's390x')    ARCH_SUFFIX='s390x' ;;
    *)  error "不支持的架构: $ARCH" ;;
esac
info "检测到平台架构：$ARCH -> $ARCH_SUFFIX"

# -------------------------
# 获取 Mihomo 最新版本号
# -------------------------
echo "请选择 Mihomo 更新通道："
echo "1) Latest 稳定版 (推荐，长期使用)"
echo "2) Prerelease-Alpha 测试版 (新功能，可能不稳定)"
read -rp "请输入序号 [1-2]: " CHOICE

case "$CHOICE" in
  1)
    CHANNEL="Latest"
    VERSION=$(curl -sSL "https://api.github.com/repos/MetaCubeX/mihomo/releases/latest" \
  | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p')
    ;;
  2)
    CHANNEL="Prerelease-Alpha"
    VERSION_URL="${GIT_PROXY}https://github.com/MetaCubeX/mihomo/releases/download/${CHANNEL}/version.txt"
    VERSION=$(curl -sSL "$VERSION_URL" | grep -o 'alpha-[a-z0-9]\+')
    ;;
  *)
    echo "输入错误，退出。"
    exit 1
    ;;
esac
info "获取 Mihomo 最新版本..."

[ -z "$VERSION" ] && { error "❌ 无法获取版本号"; exit 1; }
info "✅ Mihomo选择通道为: $CHANNEL"
info "✅ Mihomo最新版本为: $VERSION"

# -------------------------
# 下载核心文件
# -------------------------
if [ "$CHANNEL" = "Latest" ]; then
    if [ "$ARCH_SUFFIX" = "amd64" ]; then
        CORE_URL="${GIT_PROXY}https://github.com/MetaCubeX/mihomo/releases/download/${VERSION}/mihomo-linux-${ARCH_SUFFIX}-compatible-${VERSION}.gz"
    else
        CORE_URL="${GIT_PROXY}https://github.com/MetaCubeX/mihomo/releases/download/${VERSION}/mihomo-linux-${ARCH_SUFFIX}-${VERSION}.gz"
    fi
else
    if [ "$ARCH_SUFFIX" = "amd64" ]; then
        CORE_URL="${GIT_PROXY}https://github.com/MetaCubeX/mihomo/releases/download/${CHANNEL}/mihomo-linux-${ARCH_SUFFIX}-compatible-${VERSION}.gz"
    else
        CORE_URL="${GIT_PROXY}https://github.com/MetaCubeX/mihomo/releases/download/${CHANNEL}/mihomo-linux-${ARCH_SUFFIX}-${VERSION}.gz"
    fi
fi

CORE_GZ="mihomo.gz"
CORE_BIN="mihomo"

info "下载核心文件: $CORE_URL"
curl -sSL "$CORE_URL" -o "$CORE_GZ" || error "下载失败"
[ ! -s "$CORE_GZ" ] && error "下载的文件为空"

# -------------------------
# 解压
# -------------------------
gzip -df "$CORE_GZ" || error "解压失败"

# -------------------------
# 替换系统内核文件
# -------------------------
TARGET="/usr/bin/mihomo"
$SUDO mv "$CORE_BIN" "$TARGET"
$SUDO chmod 755 "$TARGET"

info "✅ Mihomo $VERSION (${ARCH_SUFFIX}) 已更新到 $TARGET"

# 重启服务
info "重启 nikki 服务..."
service nikki restart
if [ $? -eq 0 ]; then
    info "✅ Nikki 服务重启成功"
else
    error "⚠️ Nikki 服务重启失败，请手动检查"
fi
