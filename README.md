# VPS 私人管理工具

一个面向自用 VPS 的交互式 Bash 工具，参考了 `kejilion/sh` 的功能分类，但重新实现为小型模块化代码。脚本不含遥测、不保存密码，也不默认执行网上下载的脚本。

当前版本：`2.2.0`

> 📖 **完整功能说明：** [查看各模块、每个菜单功能、适用场景、风险与回滚方式](docs/FUNCTIONS.md)

主菜单分为核心管理与扩展中心。核心包括系统、网络、防火墙、BBR、Swap、Docker、SSH、备份、兼容性诊断和安全体检；甲骨文云、测试、建站、面板和重装系统统一放在第三方扩展中心。

## 2.2.0 重点能力

- `nb doctor`：识别发行版、架构、包管理器、init、虚拟化、云平台、防火墙、SSH Socket、IPv4/IPv6、Docker 和 BBR，并标记功能可用性。
- `nb security`：只读检查防火墙、SSH、空密码账户、Fail2Ban、数据库公网监听、更新、磁盘、inode、时间同步和失败登录。
- `nb report`：生成权限为 `0600` 的诊断报告，不收集密码和 SSH 私钥。
- 配置备份中心：备份带来源路径、模块、工具版本、时间和 SHA-256，可校验恢复、导出和清理。
- 第三方扩展清单：高风险脚本固定版本与 SHA-256；动态测试脚本每次显示来源、摘要并人工确认。
- 稳定/测试更新通道：稳定通道读取 GitHub Release，测试通道读取 `main`。

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

常用非交互命令：

```bash
sudo nb doctor
sudo nb security
sudo nb report
sudo nb firewall open 443 tcp
sudo nb ssh status
sudo nb backup list
sudo nb update stable
```

完整命令可运行 `nb --help` 查看。会修改系统的命令仍然执行参数校验、风险确认、备份和结果验证。

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

稳定通道从 GitHub 最新 Release 更新：

```bash
sudo nb update stable
```

测试通道从 `main` 分支更新，可能包含尚未正式发布的修改：

```bash
sudo nb update testing
```

升级器显示下载包 SHA-256，检查必需文件并对全部 Shell 脚本运行语法检查。确认后先备份当前安装；安装或验证失败时恢复旧版本。旧版本保存在 `/var/lib/vps-toolkit/update-backups/`。

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
bash tests/distro_contract.sh
shellcheck -x -e SC1090,SC1091 ./*.sh lib/*.sh tests/*.sh
```

GitHub Actions 会在 Debian 12、Ubuntu 24.04、Rocky Linux 9、Alpine 3.20 容器中检查系统识别和命令契约。`tests/vps_integration.sh` 用于带快照的专用一次性 VPS；仓库提供手动触发的 self-hosted runner 工作流，默认关闭，防止误伤生产机。

## 设计边界

云厂商的安全列表/NSG 位于 VPS 外部，脚本只能修改机内防火墙。开放端口后仍需在 OCI 控制台同步放行。Docker 的“备份/迁移”高度依赖卷与 Compose 项目结构，本版本不做可能产生虚假安全感的自动恢复；建议直接备份 Compose 文件和命名卷数据。

第三方来源记录在 `config/sources.tsv`。高风险重装、R 探长和 OCI Helper 固定到明确提交或 Release 并校验 SHA-256；无法稳定固定的测试、面板脚本标记为 `review-each-download`，每次都必须重新审阅和确认。
