#!/usr/bin/env bash

docker_install() {
  command -v docker >/dev/null && { ok "Docker 已安装：$(docker --version)"; return; }
  confirm "将从当前发行版官方软件源安装 Docker，继续？" || return 0
  case "$PKG_FAMILY" in
    apt) pkg_install docker.io docker-compose-v2 || pkg_install docker.io docker-compose-plugin ;;
    dnf|yum) pkg_install docker docker-compose-plugin || pkg_install moby-engine docker-compose-plugin ;;
    apk) pkg_install docker docker-cli-compose ;;
  esac
  if command -v systemctl >/dev/null; then run systemctl enable --now docker; else run rc-update add docker default; run rc-service docker start; fi
  ok "Docker 安装完成"
}

docker_menu() {
  printf '\n1. 安装 Docker\n2. 查看容器\n3. 启动容器\n4. 停止容器\n5. 重启容器\n6. 查看日志\n7. 删除容器\n8. 清理未使用资源\n9. Docker 信息\n0. 返回\n'
  read -r -p "请选择: " c
  case "$c" in
    1) docker_install ;;
    2) docker_require && docker ps -a ;;
    3|4|5|6|7) docker_container_action "$c" ;;
    8) docker_require && confirm "将删除未使用的容器、网络和悬空镜像，继续？" && run docker system prune ;;
    9) docker_require && docker info ;;
  esac
}

docker_require() {
  command -v docker >/dev/null 2>&1 || { die "Docker 未安装，请先选择 1 安装 Docker"; return 1; }
}

docker_container_action() {
  docker_require || return
  docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
  local name; read -r -p "容器名（只允许现有精确名称）: " name
  docker inspect "$name" >/dev/null 2>&1 || { die "容器不存在"; return; }
  case "$1" in
    3) run docker start "$name";; 4) run docker stop "$name";; 5) run docker restart "$name";;
    6) docker logs --tail 200 -f "$name";;
    7) confirm "确认删除容器 $name？" && run docker rm "$name";;
  esac
}
