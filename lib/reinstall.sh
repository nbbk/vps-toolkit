#!/usr/bin/env bash

reinstall_menu() {
  while true; do
  ui_header "重装系统"
  cat <<'EOF'
重装系统（使用 bin456789/reinstall）
--------------------------------------------------------
1. Debian 13       2. Debian 12       3. Debian 11
4. Debian 10      11. Ubuntu 26.04    12. Ubuntu 24.04
13. Ubuntu 22.04  14. Ubuntu 20.04    21. Rocky Linux 10
22. Rocky Linux 9 23. AlmaLinux 10    24. AlmaLinux 9
25. Oracle Linux 10 26. Oracle Linux 9 27. Fedora 44
28. Fedora 43     29. CentOS 10       30. CentOS 9
31. Alpine Linux  32. Arch Linux      33. Kali Linux
34. openEuler     35. openSUSE        36. fnOS
90. 自定义 DD 镜像 URL               0. 返回
--------------------------------------------------------
EOF
  local c os ver mode img file; os=""; ver=""; mode=normal; img=""; read -r -p "请选择: " c
  case "$c" in
    1) os=debian;ver=13;;2) os=debian;ver=12;;3) os=debian;ver=11;;4) os=debian;ver=10;;
    11) os=ubuntu;ver=26.04;;12) os=ubuntu;ver=24.04;;13) os=ubuntu;ver=22.04;;14) os=ubuntu;ver=20.04;;
    21) os=rocky;ver=10;;22) os=rocky;ver=9;;23) os=almalinux;ver=10;;24) os=almalinux;ver=9;;
    25) os=oracle;ver=10;;26) os=oracle;ver=9;;27) os=fedora;ver=44;;28) os=fedora;ver=43;;29) os=centos;ver=10;;30) os=centos;ver=9;;
    31) os=alpine;ver="";;32) os=arch;ver="";;33) os=kali;ver="";;34) os=openeuler;ver="";;35) os=opensuse;ver="";;36) os=fnos;ver="";;
    90) mode='dd'; read -r -p "HTTPS 镜像 URL: " img; [[ "$img" =~ ^https:// ]] || { die "只允许 HTTPS URL"; submenu_pause; continue; };; 0) break;; *) warn "无效选择"; submenu_pause; continue;;
  esac
  file="$(external_fetch_id reinstall)" || return
  sed -n '1,80p' "$file"; warn "重装将清空系统盘并断开 SSH，请先备份启动卷和业务数据。"
  confirm "确认开始重装？" || { submenu_pause; continue; }; chmod 700 "$file"
  if [ "$mode" = dd ]; then bash "$file" dd --img "$img"; elif [ -n "$ver" ]; then bash "$file" "$os" "$ver"; else bash "$file" "$os"; fi
  submenu_pause
  done
}
