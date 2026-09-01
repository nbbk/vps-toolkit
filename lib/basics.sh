#!/usr/bin/env bash

basic_packages=(curl wget sudo socat htop iftop unzip tar tmux ffmpeg btop ranger ncdu fzf vim nano git)
fun_packages=(cmatrix sl bastet nsnake ninvaders)

basics_status() {
  local p state
  printf '软件包管理器：%s\n' "$PKG_FAMILY"
  for p in "${basic_packages[@]}" "${fun_packages[@]}"; do command -v "$p" >/dev/null 2>&1 && state=已安装 || state=未安装; printf '%-12s %s\n' "$p" "$state"; done
}

basics_menu() {
  basics_status
  cat <<'EOF'
--------------------------------------------------------
1 curl   2 wget   3 sudo   4 socat  5 htop   6 iftop
7 unzip  8 tar    9 tmux  10 ffmpeg 11 btop 12 ranger
13 ncdu 14 fzf   15 vim   16 nano   17 git
21 cmatrix 22 sl 26 bastet 27 nsnake 28 ninvaders
31 全部安装  32 安装常用工具（不含游戏）  33 全部卸载
41 安装指定软件包  42 卸载指定软件包       0 返回
--------------------------------------------------------
EOF
  local c p; read -r -p "请选择: " c
  case "$c" in
    1) p=curl;;2) p=wget;;3) p=sudo;;4) p=socat;;5) p=htop;;6) p=iftop;;7) p=unzip;;8) p=tar;;9) p=tmux;;10) p=ffmpeg;;11) p=btop;;12) p=ranger;;13) p=ncdu;;14) p=fzf;;15) p=vim;;16) p=nano;;17) p=git;;
    21) p=cmatrix;;22) p=sl;;26) p=bastet;;27) p=nsnake;;28) p=ninvaders;;
    31) pkg_install "${basic_packages[@]}" "${fun_packages[@]}"; return;;
    32) pkg_install "${basic_packages[@]}"; return;;
    33) confirm "卸载本菜单列出的全部工具？" && basics_remove "${basic_packages[@]}" "${fun_packages[@]}"; return;;
    41) read -r -p "软件包名: " p; basics_valid_package "$p" || { die "包名格式无效"; return; };;
    42) read -r -p "软件包名: " p; basics_valid_package "$p" || { die "包名格式无效"; return; }; confirm "卸载 $p？" && basics_remove "$p"; return;;
    *) return;;
  esac
  pkg_install "$p"
}

basics_valid_package() { [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9+._-]{0,63}$ ]]; }
basics_remove() { case "$PKG_FAMILY" in apt) run apt-get remove -y "$@";; dnf|yum) run "$PKG_FAMILY" remove -y "$@";; apk) run apk del "$@";; esac; }
