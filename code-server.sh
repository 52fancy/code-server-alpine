#!/bin/sh

# Alpine Linux 安装 code-server 脚本
# 默认 root 用户执行，支持 amd64 / arm64
# 用法: sh code-server.sh [-prefix=/usr/local]

set -e

# 检查 root 用户
if [ "$(id -u)" != "0" ]; then
    echo "该脚本必须使用 root 用户执行" >&2
    exit 1
fi

# 默认安装前缀
PREFIX="/usr/local/lib"

# 解析参数
while [ $# -gt 0 ]; do
    case "$1" in
        -prefix=*)
            PREFIX="${1#*=}"
            shift
            ;;
        -h|--help)
            echo "用法: $0 [-prefix=/usr/local/lib]"
            echo "  -prefix=<目录>  指定安装前缀，默认 /usr/local/lib"
            exit 0
            ;;
        *)
            echo "错误: 未知参数 $1"
            echo "用法: $0 [-prefix=/usr/local/lib]"
            exit 1
            ;;
    esac
done

# 安装必要依赖
echo "检查并安装依赖 (curl, tar)..."
apk update >/dev/null 2>&1
apk add --no-cache curl tar >/dev/null 2>&1 || {
    echo "无法安装 curl 或 tar，请检查网络和 apk 仓库。" >&2
    exit 1
}

# 获取系统架构
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)
        ARCH="amd64"
        ;;
    aarch64|arm64)
        ARCH="arm64"
        ;;
    *)
        echo "不支持的架构: $ARCH" >&2
        exit 1
        ;;
esac

echo "系统架构: $ARCH"

# 从 GitHub API 获取最新版本下载地址
echo "正在获取 code-server 最新版本..."
DOWNLOAD_URL=$(curl -s https://api.github.com/repos/coder/code-server/releases/latest | \
    grep -o '"browser_download_url": *"[^"]*"' | \
    grep "linux" | \
    grep "$ARCH" | \
    head -n1 | \
    cut -d '"' -f4)

if [ -z "$DOWNLOAD_URL" ]; then
    echo "错误: 未找到适用于 linux-$ARCH 的 code-server 下载地址" >&2
    exit 1
fi

echo "下载地址: $DOWNLOAD_URL"

# 安装目标路径
INSTALL_DIR="$PREFIX/code-server"
echo "目标安装目录: $INSTALL_DIR"

# 如果已存在，先删除
if [ -d "$INSTALL_DIR" ]; then
    echo "检测到已存在目录，正在删除旧版本..."
    rm -rf "$INSTALL_DIR"
fi

# 下载压缩包
echo "下载中..."
cd /tmp
curl -sL "$DOWNLOAD_URL" -o code-server.tar.gz

# 直接解压到目标目录，去除顶层版本号文件夹
echo "解压并安装到 $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"
tar -xzf code-server.tar.gz -C "$INSTALL_DIR" --strip-components=1

# 确保可执行
if [ -f "$INSTALL_DIR/bin/code-server" ]; then
    chmod +x "$INSTALL_DIR/bin/code-server"
    ln -sf "$INSTALL_DIR/bin/code-server" /usr/local/bin/code-server
fi

# 修复musl版本node
apk fetch nodejs
apk extract --allow-untrusted nodejs*.apk
cp /tmp/usr/bin/node $INSTALL_DIR/lib/node

PASSWD="Admin$RANDOM"
echo "bind-addr: [::]:8080" >>"$INSTALL_DIR"/config.yaml
echo "auth: password" >>"$INSTALL_DIR"/config.yaml
echo "password: "$PASSWD"" >>"$INSTALL_DIR"/config.yaml 
echo "user-data-dir: $INSTALL_DIR" >>"$INSTALL_DIR"/config.yaml
echo "extensions-dir: $INSTALL_DIR" >>"$INSTALL_DIR"/config.yaml
echo "session-socket: $INSTALL_DIR/code-server-ipc.sock" >>"$INSTALL_DIR"/config.yaml

echo ""
echo "========================================="
echo "code-server 安装完成！"
echo "可执行文件: $INSTALL_DIR/bin/code-server"
echo ""
echo "管理员密码: $PASSWD"
echo "========================================="
sed -i "/^exit 0/i \\code-server --config \"$INSTALL_DIR\"/config.yaml &" /etc/rc.local
code-server --config "$INSTALL_DIR"/config.yaml &
