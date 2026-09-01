#!/usr/bin/env bash

docker_install() {
  command -v docker >/dev/null && { ok "Docker 已安装：$(docker --version)"; return; }
  confirm "将从当前发行版官方软件源安装 Docker，继续？" || return 0
  case "$PKG_FAMILY" in
    apt) pkg_install docker.io docker-compose-v2 || pkg_install docker.io docker-compose-plugin ;;
    dnf|yum) pkg_install docker docker-compose-plugin || pkg_install moby-engine docker-compose-plugin ;;
    apk) pkg_install docker docker-cli-compose ;;
  esac
  command -v docker >/dev/null 2>&1 || { die "Docker 软件包安装失败，请查看日志"; return 1; }
  if command -v systemctl >/dev/null; then run systemctl enable --now docker; else run rc-update add docker default; run rc-service docker start; fi
  docker info >/dev/null 2>&1 || { die "Docker 服务未正常运行，请查看日志"; return 1; }
  ok "Docker 安装完成"
}

docker_menu() {
  ui_header "Docker 管理"
  printf '  1. 安装/更新 Docker       2. Docker 全局状态\n  3. 容器管理                4. 镜像管理\n  5. 网络管理                6. 卷管理\n  7. 清理无用资源            8. 配置日志轮转\n  9. 查看 daemon.json       10. 开启 Docker IPv6\n 11. 关闭 Docker IPv6       12. 备份 Docker 元数据/卷\n 13. 卸载 Docker 环境         0. 返回\n'
  ui_line
  read -r -p "请选择: " c
  case "$c" in
    1) docker_install ;;
    2) docker_require && docker_info_summary ;;
    3) docker_container_menu;; 4) docker_image_menu;; 5) docker_network_menu;; 6) docker_volume_menu;;
    7) docker_require && confirm "清理未使用的容器、网络、构建缓存和悬空镜像？" && run docker system prune ;;
    8) docker_daemon_logging;; 9) docker_daemon_show;; 10) docker_ipv6 on;; 11) docker_ipv6 off;;
    12) docker_backup;; 13) docker_uninstall;;
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

docker_info_summary() { docker info; printf '\n'; docker system df; printf '\n'; docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}'; }
docker_container_menu() {
  docker_require || return; docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
  printf '\n1 启动  2 停止  3 重启  4 日志  5 删除  6 查看详情  0 返回\n'; local c name; read -r -p "请选择: " c; [ "$c" != 0 ] || return
  read -r -p "容器精确名称: " name; docker inspect "$name" >/dev/null 2>&1 || { die "容器不存在"; return; }
  case "$c" in 1) run docker start "$name";;2) run docker stop "$name";;3) run docker restart "$name";;4) docker logs --tail 200 -f "$name";;5) confirm "删除 $name？" && run docker rm "$name";;6) docker inspect "$name";;esac
}
docker_image_menu() {
  docker_require || return; docker images; printf '\n1 拉取镜像  2 删除镜像  3 清理悬空镜像  0 返回\n'; local c image; read -r -p "请选择: " c
  case "$c" in 1) read -r -p "镜像（如 nginx:alpine）: " image; if [[ "$image" =~ ^[A-Za-z0-9._/:@-]+$ ]]; then run docker pull "$image"; else die "镜像名无效"; fi;;2) read -r -p "镜像 ID/名称: " image; confirm "删除镜像 $image？" && run docker image rm "$image";;3) confirm "清理悬空镜像？" && run docker image prune;;esac
}
docker_network_menu() {
  docker_require || return; docker network ls; printf '\n1 创建 bridge 网络  2 删除网络  3 查看网络  0 返回\n'; local c name; read -r -p "请选择: " c; [ "$c" != 0 ] || return; read -r -p "网络名: " name; [[ "$name" =~ ^[A-Za-z0-9_.-]+$ ]] || { die "名称无效"; return; }; case "$c" in 1) run docker network create "$name";;2) confirm "删除网络 $name？" && run docker network rm "$name";;3) docker network inspect "$name";;esac
}
docker_volume_menu() {
  docker_require || return; docker volume ls; printf '\n1 创建卷  2 删除卷  3 查看卷  4 清理未使用卷  0 返回\n'; local c name; read -r -p "请选择: " c; [ "$c" != 0 ] || return
  [ "$c" = 4 ] && { confirm "清理全部未使用卷？" && run docker volume prune; return; }; read -r -p "卷名: " name; [[ "$name" =~ ^[A-Za-z0-9_.-]+$ ]] || { die "名称无效"; return; }; case "$c" in 1) run docker volume create "$name";;2) confirm "删除卷 $name？数据不可恢复" && run docker volume rm "$name";;3) docker volume inspect "$name";;esac
}

docker_daemon_merge() {
  local filter="$1" file=/etc/docker/daemon.json tmp backup; command -v jq >/dev/null 2>&1 || pkg_install jq; mkdir -p /etc/docker
  [ -f "$file" ] || printf '{}\n' >"$file"; jq empty "$file" || { die "现有 daemon.json 不是合法 JSON"; return; }
  backup="$BACKUP_DIR/daemon.json.$(date +%s).bak"; cp -a "$file" "$backup"; tmp="$(mktemp)"; jq "$filter" "$file" >"$tmp" || { rm -f "$tmp"; die "生成配置失败"; return; }
  if command -v dockerd >/dev/null 2>&1; then dockerd --validate --config-file "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; die "新 Docker 配置校验失败"; return; }; fi
  install -m 0644 "$tmp" "$file"; rm -f "$tmp"
  if ! service_restart docker || ! docker info >/dev/null 2>&1; then cp -a "$backup" "$file"; service_restart docker || true; die "Docker 重启失败，已恢复原配置"; return 1; fi
  ok "Docker 配置已更新"
}
docker_daemon_logging() { docker_require || return; docker_daemon_merge '. + {"log-driver":"json-file","log-opts":{"max-size":"10m","max-file":"3"}}'; }
docker_daemon_show() { [ -f /etc/docker/daemon.json ] && { command -v jq >/dev/null && jq . /etc/docker/daemon.json || cat /etc/docker/daemon.json; } || echo '{}'; }
docker_ipv6() { docker_require || return; if [ "$1" = on ]; then docker_daemon_merge '. + {"ipv6":true,"fixed-cidr-v6":"fd00:dead:beef::/48"}'; else docker_daemon_merge 'del(.ipv6, ."fixed-cidr-v6")'; fi; }

docker_backup() {
  docker_require || return; local dir v; local -a ids; dir="$STATE_DIR/docker-backup-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$dir/volumes"
  docker ps -a --no-trunc >"$dir/containers.txt"; docker images --no-trunc >"$dir/images.txt"; mapfile -t ids < <(docker ps -aq)
  if [ "${#ids[@]}" -gt 0 ]; then docker inspect "${ids[@]}" >"$dir/inspect.json"; else printf '[]\n' >"$dir/inspect.json"; fi
  warn "卷备份是在线文件级快照；数据库应另外执行逻辑备份。"
  if confirm "同时备份全部命名卷？可能耗时并占用较多磁盘"; then
    docker volume ls -q | while read -r v; do [ -n "$v" ] && docker run --rm -v "$v:/data:ro" -v "$dir/volumes:/backup" alpine tar -czf "/backup/${v}.tar.gz" -C /data .; done
  fi
  ok "Docker 备份：$dir"
}

docker_uninstall() {
  docker_require || return; warn "卸载 Docker 可能中断全部容器服务。默认保留 /var/lib/docker 数据。"; confirm "确认卸载 Docker 软件包？" || return
  command -v systemctl >/dev/null && run systemctl disable --now docker || true
  case "$PKG_FAMILY" in apt) run apt-get remove -y docker.io docker-compose-v2 docker-compose-plugin || true;;dnf|yum) run "$PKG_FAMILY" remove -y docker moby-engine docker-compose-plugin || true;;apk) run apk del docker docker-cli-compose || true;;esac
  ok "Docker 软件已卸载，数据目录仍保留"
}
