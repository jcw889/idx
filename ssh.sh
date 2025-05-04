#!/usr/bin/env bash

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
RESET="\033[0m"

echo -e "${GREEN}===== 反向SSH隧道一键脚本 =====${RESET}"

read -p "请输入VPS公网IP或域名: " VPS_HOST
read -p "请输入VPS用户名: " VPS_USER
read -p "请输入VPS监听端口（如60022）: " VPS_PORT

if [[ -z "$VPS_HOST" || -z "$VPS_USER" || -z "$VPS_PORT" ]]; then
    echo -e "${RED}所有参数都不能为空！${RESET}"
    exit 1
fi

echo -e "${YELLOW}请确保你已将本机的SSH公钥添加到VPS的 ~/.ssh/authorized_keys，否则会要求输入密码。${RESET}"

# 启动反向隧道
echo -e "${YELLOW}正在建立反向SSH隧道...${RESET}"
ssh -N -R ${VPS_PORT}:localhost:22 ${VPS_USER}@${VPS_HOST}

echo -e "${GREEN}反向SSH隧道已建立！${RESET}"
echo -e "${YELLOW}现在你可以在VPS上用如下命令连接IDX：${RESET}"
echo -e "${GREEN}ssh -p ${VPS_PORT} root@localhost${RESET}"
