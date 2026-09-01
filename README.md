# VPS 私人管理工具

一个面向自用 VPS 的交互式 Bash 工具，参考了 `kejilion/sh` 的功能分类，但重新实现为小型模块化代码。脚本不含遥测、不保存密码，也不默认执行网上下载的脚本。

当前版本：`1.1.1`

## 支持范围

- 系统：Debian / Ubuntu、RHEL 系（CentOS Stream、Rocky、Alma、Fedora）、Alpine
- 功能：系统查询、更新、清理；开放/关闭端口；BBR；Swap；Docker；用户密码；SSH 端口；SSH 安全检查；甲骨文云辅助工具
- 防火墙：优先管理 UFW 或 firewalld。遇到已有原生 nftables 规则时只读展示，避免覆盖复杂规则。

## 安装与运行

GitHub 一行安装并启动：

```bash
curl -fsSL https://raw.githubusercontent.com/nbbk/vps-toolkit/main/bootstrap.sh | sudo bash && sudo vps-tool
```

安装后日常进入工具只需输入：

```bash
sudo nb
```

如果系统原本没有名为 `n` 的命令，也可以使用 `sudo n`。安装器绝不会覆盖已有的 `n` 命令；`sudo vps-tool` 始终可用。

下载脚本和安装源码均来自同一个公开仓库。如果希望先审计，可先下载 `bootstrap.sh` 查看内容再运行。

把整个目录上传到 VPS，然后执行：

```bash
cd vps-toolkit
sudo bash install.sh
sudo vps-tool
```

## 卸载

在主菜单选择“卸载本工具”，或执行：

```bash
sudo vps-tool --uninstall
```

也可以使用：`sudo nb --uninstall`。

默认保留备份及日志；可在卸载过程中选择一并删除。卸载程序不会擅自撤销防火墙、SSH、Swap、BBR、Docker 或系统软件包修改，避免造成失联或业务中断。

也可不安装直接运行：

```bash
sudo bash vps-tool.sh
```

## 重要安全设计

- SSH 换端口会先开放新端口、备份配置、运行 `sshd -t`、重启并确认监听；不会自动关闭旧端口。请保持当前会话，另开终端验证后再关闭旧端口。
- 修改密码直接调用系统 `passwd`，脚本不接触明文密码。
- BBR 只启用当前内核自带的 `tcp_bbr`，不会替换第三方内核。
- DD 重装和第三方开机脚本只下载到 `/var/lib/vps-toolkit/external`，显示 SHA-256，不自动执行。
- 日志保存在 `/var/log/vps-toolkit.log`，权限为 `0600`，不记录密码。
- 操作前仍应制作云盘快照，并确保云厂商控制台/串口救援可用。

## 测试

```bash
bash tests/smoke.sh
shellcheck vps-tool.sh install.sh lib/*.sh
```

## 设计边界

云厂商的安全列表/NSG 位于 VPS 外部，脚本只能修改机内防火墙。开放端口后仍需在 OCI 控制台同步放行。Docker 的“备份/迁移”高度依赖卷与 Compose 项目结构，本版本不做可能产生虚假安全感的自动恢复；建议直接备份 Compose 文件和命名卷数据。

第三方链接会随上游变化。执行下载的脚本前，应重新核对仓库所有者、提交记录、下载文件内容和 SHA-256。
