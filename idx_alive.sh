#!/usr/bin/env bash

# 定义颜色
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
RESET="\033[0m"

# 检查 root 权限
[[ $EUID -ne 0 ]] && echo -e "${RED}错误: 请先运行 sudo -i 获取 root 权限后再执行此脚本${RESET}" && exit 1

# 检查依赖
for cmd in docker wget curl nc; do
  if ! command -v $cmd &>/dev/null; then
    echo -e "${RED}错误: 未检测到 $cmd，请先安装。${RESET}"
    case $cmd in
      docker)
        echo -e "${YELLOW}安装命令（Debian/Ubuntu）：${RESET} apt update && apt install -y docker.io"
        ;;
      wget|curl|nc)
        echo -e "${YELLOW}安装命令（Debian/Ubuntu）：${RESET} apt update && apt install -y $cmd"
        ;;
    esac
    exit 1
  fi
done

# 检查 Docker 服务
if ! systemctl is-active --quiet docker; then
  echo -e "${YELLOW}Docker 服务未运行，正在尝试启动...${RESET}"
  systemctl unmask docker docker.socket containerd 2>/dev/null || true
  systemctl start docker 2>/dev/null || true
  sleep 2
  if ! systemctl is-active --quiet docker; then
    echo -e "${RED}错误: Docker 服务无法启动，请检查安装和配置。${RESET}"
    exit 1
  fi
fi

echo -e "${GREEN}===== 开始设置 Ngrok 隧道和 Docker Firefox =====${RESET}"
echo -e "${RED}重要提示: ${BLUE}此保活方法最长持续时间为24小时${RESET}"
echo ""

# 获取 ngrok token（支持参数传入）
if [[ -n "$1" ]]; then
  NGROK_TOKEN="$1"
  echo -e "${YELLOW}[1/4] 已通过参数获取 ngrok token${RESET}"
else
  echo -e "${YELLOW}[1/4] 获取必要信息...${RESET}"
  echo -e "${YELLOW}注意: Ngrok 免费账户限制了同时只能有一个代理会话，请确保此 token 与用于 SSH 的 token 不同${RESET}"
  while true; do
    read -p "请输入ngrok token (可以从 https://dashboard.ngrok.com 获取): " NGROK_TOKEN
    if [[ -z "$NGROK_TOKEN" ]]; then
      echo -e "${RED}错误: ngrok token不能为空，请重新输入${RESET}"
      continue
    fi
    if ps -ef | grep -v grep | grep -q "ngrok.*--authtoken=${NGROK_TOKEN}"; then
      echo -e "${RED}错误: 系统中已存在使用此token的ngrok进程，请使用其他token${RESET}"
      continue
    fi
    break
  done
fi

# 支持自定义 Firefox 容器端口
DEFAULT_PORT=5800
read -p "请输入 Firefox 容器端口 [默认:5800]，直接回车使用默认端口: " FIREFOX_PORT
FIREFOX_PORT=${FIREFOX_PORT:-$DEFAULT_PORT}

echo -e "${YELLOW}[2/4] 正在设置 Docker 和 Firefox 容器...${RESET}"

# 创建 Firefox 数据目录
mkdir -p ~/firefox-data

# 运行 Firefox 容器
echo -e "${YELLOW}正在启动 Firefox 容器...${RESET}"
docker rm -f firefox 2>/dev/null || true
docker run -d \
  --name firefox \
  -p ${FIREFOX_PORT}:5800 \
  -v ~/firefox-data:/config:rw \
  -e FF_OPEN_URL=https://idx.google.com/ \
  -e TZ=Asia/Shanghai \
  -e LANG=zh_CN.UTF-8 \
  -e ENABLE_CJK_FONT=1 \
  --restart unless-stopped \
  jlesage/firefox

if ! docker ps | grep -q firefox; then
  echo -e "${RED}错误: Firefox 容器启动失败，请检查 Docker 是否正常运行${RESET}"
  exit 1
fi

echo -e "${YELLOW}[3/4] 正在设置 Ngrok 隧道...${RESET}"

# 下载并设置 ngrok（如果尚未安装）
if [ ! -f /usr/local/bin/ngrok ]; then
  wget https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz -qO- | tar -xz -C /usr/local/bin
fi

# 查找可用的 API 端口
NGROK_API_PORT=4041
while nc -z localhost $NGROK_API_PORT 2>/dev/null; do
  NGROK_API_PORT=$((NGROK_API_PORT + 1))
  echo -e "${YELLOW}检测到端口 $((NGROK_API_PORT - 1)) 已被占用，尝试使用端口 ${NGROK_API_PORT}...${RESET}"
done

# 使用 nohup 在后台运行 ngrok
pkill -f "ngrok http ${FIREFOX_PORT} --name firefox" >/dev/null 2>&1 || true
nohup /usr/local/bin/ngrok http ${FIREFOX_PORT} --name firefox --authtoken=${NGROK_TOKEN} >/dev/null 2>&1 &

echo -e "${YELLOW}[4/4] 等待 Ngrok 服务启动...${RESET}"
sleep 5

echo -e "${YELLOW}获取 Ngrok 隧道信息...${RESET}"
NGROK_INFO=$(curl -s http://localhost:${NGROK_API_PORT}/api/tunnels)
grep -q "Your account is limited to 1 simultaneous ngrok agent sessions." <<< $NGROK_INFO && echo -e "${RED}错误: 您的 ngrok 账户限制了同时只能有一个 ngrok 代理会话，请检查您的 ngrok 设置或使用不同的 token。${RESET}" && exit 1
! grep -q "public_url" <<< $NGROK_INFO && echo -e "${RED}错误: 无法获取 ngrok 隧道信息，请检查 ngrok 是否正常运行。尝试访问 http://localhost:${NGROK_API_PORT}/api/tunnels 查看详情。${RESET}" && exit 1
NGROK_URL=$(echo $NGROK_INFO | grep -o '"public_url":"[^"]*"' | grep -o 'https://[^"]*')

echo -e "${GREEN}===== 设置完成 =====${RESET}"
echo ""
echo -e "${GREEN}Firefox 本地访问地址: ${RESET}http://localhost:${FIREFOX_PORT}"
echo -e "${GREEN}Firefox Ngrok 访问地址: ${RESET}$NGROK_URL"
echo ""
echo -e "${YELLOW}注意: Docker 容器设置为自动重启，除非手动停止${RESET}"
echo -e "${YELLOW}注意: Ngrok 进程在后台运行，如需停止请使用 'pkill -f \"ngrok http ${FIREFOX_PORT} --name firefox\"' 命令${RESET}"
echo -e "${YELLOW}注意: 这是一个 IDX 保活方案，请确保定期访问以保持活跃状态${RESET}"
echo ""
