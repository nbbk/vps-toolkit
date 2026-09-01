#!/usr/bin/env bash

WEB_ROOT="${VMT_WEB_ROOT:-/opt/vps-web}"

web_menu() {
  while true; do
  ui_header "LDNMP 建站"
  cat <<'EOF'
  1. 安装 LDNMP 环境        2. 安装 WordPress
  3. 安装 Discuz            4. 安装 Halo
  5. 安装 Typecho           6. 安装 Bitwarden/Vaultwarden
  7. 安装静态网站           8. 新增反向代理
 9. 查看站点与容器        10. 备份全部站点
 11. 恢复站点备份          12. 更新 LDNMP 镜像
 13. 优化 LDNMP 环境       14. 卸载 LDNMP 环境
 15. 安装宝塔国内版         16. 安装 aaPanel 国际版
  0. 返回
EOF
  ui_line
  local c; read -r -p "请选择: " c
  case "$c" in
    1) web_install_ldnmp;; 2) web_install_wordpress;; 3) web_install_discuz;; 4) web_install_halo;;
    5) web_install_typecho;; 6) web_install_vaultwarden;; 7) web_static;; 8) web_proxy;;
    9) web_status;; 10) web_backup;; 11) web_restore;; 12) web_update;; 13) web_optimize;; 14) web_uninstall;;
    15) web_install_panel bt;; 16) web_install_panel aapanel;; 0) break;; *) warn "无效选择";;
  esac
  submenu_pause
  done
}

web_safe_root() { case "$WEB_ROOT" in /|/opt|/var|/usr|"") die "不安全的建站根目录：$WEB_ROOT"; return 1;; /*) return 0;; *) die "建站根目录必须是绝对路径"; return 1;; esac; }
web_prepare() { web_safe_root || return; docker_install; docker_require || return; mkdir -p "$WEB_ROOT"; chmod 750 "$WEB_ROOT"; }
web_valid_name() { [[ "${1:-}" =~ ^[a-z0-9][a-z0-9_-]{0,31}$ ]]; }
web_random_password() { od -An -N12 -tx1 /dev/urandom | tr -d ' \n'; }

web_install_ldnmp() {
  web_prepare || return; local dir="$WEB_ROOT/ldnmp" pass; mkdir -p "$dir/www" "$dir/nginx"
  [ ! -f "$dir/compose.yml" ] || { warn "LDNMP 已存在：$dir"; return; }; pass="$(web_random_password)"
  cat >"$dir/compose.yml" <<EOF
services:
  nginx:
    image: nginx:alpine
    restart: unless-stopped
    ports: ["80:80", "443:443"]
    volumes: ["./www:/var/www/html:ro", "./nginx:/etc/nginx/conf.d:ro"]
    depends_on: [php]
  php:
    image: php:8.3-fpm-alpine
    restart: unless-stopped
    volumes: ["./www:/var/www/html"]
  mysql:
    image: mysql:8.4
    restart: unless-stopped
    environment: {MYSQL_ROOT_PASSWORD: "$pass"}
    volumes: ["mysql-data:/var/lib/mysql"]
  redis:
    image: redis:7-alpine
    restart: unless-stopped
    volumes: ["redis-data:/data"]
volumes: {mysql-data: {}, redis-data: {}}
EOF
  cat >"$dir/nginx/default.conf" <<'EOF'
server { listen 80 default_server; root /var/www/html; index index.php index.html;
  location / { try_files $uri $uri/ /index.php?$args; }
  location ~ \.php$ { include fastcgi_params; fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name; fastcgi_pass php:9000; }
}
EOF
  printf '<h1>VPS Toolkit LDNMP</h1>\n' >"$dir/www/index.html"; chmod 600 "$dir/compose.yml"
  (cd "$dir" && run docker compose up -d); ok "LDNMP 已安装：$dir；MySQL root 密码保存在权限 600 的 compose.yml"
}

web_app_compose() {
  local name="$1" content="$2" dir; dir="$WEB_ROOT/apps/$name"; mkdir -p "$dir"; [ ! -f "$dir/compose.yml" ] || { die "应用已存在：$name"; return; }; printf '%s\n' "$content" >"$dir/compose.yml"; chmod 600 "$dir/compose.yml"; (cd "$dir" && run docker compose up -d)
}

web_install_wordpress() { web_prepare || return; local name pass root; read -r -p "站点标识 [wordpress]: " name; name="${name:-wordpress}"; web_valid_name "$name" || { die "标识无效"; return; }; pass="$(web_random_password)"; root="$(web_random_password)"; web_app_compose "$name" "services:
  db: {image: mariadb:11, restart: unless-stopped, environment: {MARIADB_DATABASE: wordpress, MARIADB_USER: wordpress, MARIADB_PASSWORD: '$pass', MARIADB_ROOT_PASSWORD: '$root'}, volumes: [db:/var/lib/mysql]}
  app: {image: wordpress:php8.3-apache, restart: unless-stopped, ports: ['8080:80'], environment: {WORDPRESS_DB_HOST: db, WORDPRESS_DB_USER: wordpress, WORDPRESS_DB_PASSWORD: '$pass', WORDPRESS_DB_NAME: wordpress}, volumes: [wp:/var/www/html], depends_on: [db]}
volumes: {db: {}, wp: {}}"; ok "WordPress 已启动：http://服务器IP:8080"; }
web_install_discuz() { web_prepare || return; warn "Discuz 官方没有统一维护的 Compose 镜像；为避免使用未知镜像，本版本暂不自动部署。可先安装 LDNMP 后上传官方源码。"; }
web_install_halo() { web_prepare || return; web_app_compose halo "services:
  halo: {image: halohub/halo:2, restart: unless-stopped, ports: ['8090:8090'], command: ['--spring.r2dbc.url=r2dbc:pool:h2:file:///root/.halo2/db/halo-next?MODE=MYSQL&DB_CLOSE_ON_EXIT=FALSE'], volumes: [halo:/root/.halo2]}
volumes: {halo: {}}"; ok "Halo：http://服务器IP:8090"; }
web_install_typecho() { web_prepare || return; warn "Typecho 建议使用 LDNMP 环境并从官网上传源码；本工具不采用来源不明的第三方镜像。"; }
web_install_vaultwarden() { web_prepare || return; web_app_compose vaultwarden "services:
  app: {image: vaultwarden/server:latest, restart: unless-stopped, ports: ['8088:80'], volumes: [data:/data]}
volumes: {data: {}}"; warn "Vaultwarden 已启动在 8088；投入使用前必须配置 HTTPS 和管理员令牌。"; }

web_static() { web_prepare || return; local name port dir; read -r -p "站点标识: " name; web_valid_name "$name" || { die "标识无效"; return; }; read -r -p "本机端口 [8081]: " port; port="${port:-8081}"; valid_port "$port" || { die "端口无效"; return; }; dir="$WEB_ROOT/static/$name"; mkdir -p "$dir/html"; printf '<h1>%s</h1>\n' "$name" >"$dir/html/index.html"; cat >"$dir/compose.yml" <<EOF
services:
  web: {image: nginx:alpine, restart: unless-stopped, ports: ['$port:80'], volumes: ['./html:/usr/share/nginx/html:ro']}
EOF
  (cd "$dir" && run docker compose up -d); ok "静态站点目录：$dir/html，访问端口：$port"; }
web_proxy() { web_prepare || return; local name port target dir; read -r -p "代理标识: " name; web_valid_name "$name" || { die "标识无效"; return; }; read -r -p "监听端口: " port; valid_port "$port" || { die "端口无效"; return; }; read -r -p "上游地址（如 http://127.0.0.1:3000）: " target; [[ "$target" =~ ^https?://[A-Za-z0-9._:-]+/?$ ]] || { die "上游格式无效"; return; }; dir="$WEB_ROOT/proxy/$name"; mkdir -p "$dir"; cat >"$dir/default.conf" <<EOF
server { listen $port; location / { proxy_pass $target; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; } }
EOF
  cat >"$dir/compose.yml" <<EOF
services:
  proxy: {image: nginx:alpine, restart: unless-stopped, volumes: ['./default.conf:/etc/nginx/conf.d/default.conf:ro'], network_mode: host}
EOF
  (cd "$dir" && run docker compose up -d); ok "反向代理已启动，监听端口：$port"; }
web_status() { docker_require || return; docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}'; printf '\n站点目录：\n'; find "$WEB_ROOT" -mindepth 1 -maxdepth 3 -name compose.yml -print 2>/dev/null || true; }
web_backup() { [ -d "$WEB_ROOT" ] || { die "没有站点数据"; return; }; local out; out="$STATE_DIR/web-backup-$(date +%Y%m%d-%H%M%S).tar.gz"; run tar -czf "$out" -C "$(dirname "$WEB_ROOT")" "$(basename "$WEB_ROOT")"; ok "文件备份完成：$out。数据库仍建议另做逻辑导出。"; }
web_restore() { local file; read -r -p "备份文件绝对路径: " file; [ -f "$file" ] || { die "文件不存在"; return; }; confirm "恢复文件到 $(dirname "$WEB_ROOT")？" && run tar -xzf "$file" -C "$(dirname "$WEB_ROOT")"; }
web_update() { docker_require || return; find "$WEB_ROOT" -name compose.yml -print0 2>/dev/null | while IFS= read -r -d '' f; do (cd "$(dirname "$f")" && docker compose pull && docker compose up -d); done; }
web_optimize() { warn "通用优化会启用 Docker 日志轮转；数据库参数应按内存单独规划。"; docker_daemon_logging; }
web_uninstall() { web_safe_root || return; [ -d "$WEB_ROOT" ] || { warn "环境不存在"; return; }; warn "这会停止站点并删除 $WEB_ROOT，命名卷仍可能保留。"; confirm "确认卸载全部建站环境？" || return; find "$WEB_ROOT" -name compose.yml -print0 | while IFS= read -r -d '' f; do (cd "$(dirname "$f")" && docker compose down); done; rm -rf -- "$WEB_ROOT"; }

web_install_panel() {
  local type="$1" url name file
  if [ "$type" = bt ]; then url=https://download.bt.cn/install/install_panel.sh; name=宝塔国内版; else url=https://www.aapanel.com/script/install_7.0_en.sh; name=aaPanel国际版; fi
  warn "$name 会取得服务器高级管理权限，并自行管理 Web、数据库和防火墙配置。不建议与现有 LDNMP 环境混装。"
  file="$(external_fetch "$url" "panel-${type}-install.sh")" || return; sed -n '1,120p' "$file"
  confirm "确认执行 $name 官方安装器？" || return 0; chmod 700 "$file"
  if [ "$type" = bt ]; then bash "$file" ed8484bec; else bash "$file" aapanel; fi
}
