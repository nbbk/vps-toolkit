# VPS 私人管理工具

一个面向自用 VPS 的交互式 Bash 工具，参考了 `kejilion/sh` 的功能分类，但重新实现为小型模块化代码。脚本不含遥测、不保存密码，也不默认执行网上下载的脚本。

当前版本：`2.0.1`

> 📖 **完整功能说明：** [查看各模块、每个菜单功能、适用场景、风险与回滚方式](docs/FUNCTIONS.md)

主菜单快速索引：系统信息、系统更新、系统清理、端口与防火墙、BBR、Swap、Docker、用户密码、SSH 端口、SSH 安全检查、甲骨文云工具、日志、在线更新和卸载。首次使用或执行 SSH、内核、DD 重装等高风险功能前，请先阅读完整说明。

## 支持范围

- 系统：Debian / Ubuntu、RHEL 系（CentOS Stream、Rocky、Alma、Fedora）、Alpine
- 功能：系统查询、更新、清理；端口与防火墙；BBR；Swap；完整 Docker 管理；账户与 SSH；甲骨文云；系统工具；多系统重装；线路/性能测试；LDNMP 建站；基础工具；tmux 后台工作区
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

## 更新升级

在主菜单选择“检查并更新本工具”，或执行：

```bash
sudo nb --update
```

升级器会从 `nbbk/vps-toolkit` 下载最新源码，显示下载包 SHA-256，检查必需文件并对全部 Shell 脚本运行语法检查。输入 `y` 确认后会备份当前安装再覆盖升级；安装或验证失败时自动恢复旧版本。旧版本备份保存在 `/var/lib/vps-toolkit/update-backups/`。

默认保留备份及日志；可在卸载过程中选择一并删除。卸载程序不会擅自撤销防火墙、SSH、Swap、BBR、Docker 或系统软件包修改，避免造成失联或业务中断。

也可不安装直接运行：

```bash
sudo bash vps-tool.sh
```

## 重要安全设计

- SSH 换端口会先开放新端口、备份配置、运行 `sshd -t`、重启并确认监听；不会自动关闭旧端口。请保持当前会话，另开终端验证后再关闭旧端口。
- 修改密码直接调用系统 `passwd`，脚本不接触明文密码。
- 原生 BBR 不替换内核；XanMod BBRv3 仅在官方支持的 x86_64 Debian/Ubuntu 版本开放，安装、更新和卸载均要求 `y/N` 确认，不会自动重启。
- DD 重装、R 探长和 JHB IPv6 脚本会先下载到 `/var/lib/vps-toolkit/external`，显示来源、SHA-256 与脚本开头，再要求 `y/N` 确认才执行。
- 甲骨文云 Root 密码登录会设置 root 密码、写入独立 SSH 配置，并通过 `sshd -t` 和有效配置回读验证；关闭密码登录前必须存在 root 公钥。
- 日志保存在 `/var/log/vps-toolkit.log`，权限为 `0600`，不记录密码。
- 操作前仍应制作云盘快照，并确保云厂商控制台/串口救援可用。

## 测试

```bash
bash tests/smoke.sh
bash tests/menu_contract.sh
shellcheck -x -e SC1090,SC1091 ./*.sh lib/*.sh tests/*.sh
```

仓库包含 GitHub Actions；每次推送和 Pull Request 都会自动运行语法、冒烟、菜单契约与 ShellCheck 检查。

## 设计边界

云厂商的安全列表/NSG 位于 VPS 外部，脚本只能修改机内防火墙。开放端口后仍需在 OCI 控制台同步放行。Docker 的“备份/迁移”高度依赖卷与 Compose 项目结构，本版本不做可能产生虚假安全感的自动恢复；建议直接备份 Compose 文件和命名卷数据。

第三方链接会随上游变化。执行下载的脚本前，应重新核对仓库所有者、提交记录、下载文件内容和 SHA-256。
