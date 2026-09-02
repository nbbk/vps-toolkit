# VPS 私人管理工具完整功能说明

本文对应 `vps-toolkit 2.3.0`。按私人 VPS 的使用要求，工具继续整体以 root 运行；推荐使用 `sudo nb` 进入。确认提示统一为 `[y/N]`：输入 `y` 或 `Y` 执行，输入 `n` 或直接回车取消。所有二级菜单执行功能后会留在当前菜单，只有选择 `0` 才返回主菜单。

## 2.3.0 管理架构

核心管理保留系统、网络、防火墙、BBR、Swap、Docker、SSH、基础工具、后台工作区、备份、诊断和安全体检。会下载外部可执行内容的甲骨文云、测试、建站面板与重装系统统一放入“扩展中心”，避免把第三方行为与核心功能混在一起。

高风险配置修改统一显示修改对象和回滚方式；支持的配置会进入 `/var/lib/vps-toolkit/managed-backups`，事务记录位于 `/var/lib/vps-toolkit/transactions`。备份元数据包含原路径、模块、时间和工具版本，恢复前校验 SHA-256，并再次备份当前文件。

### 非交互命令

`nb --help` 显示完整命令。常用入口包括 `nb info`、`nb doctor`、`nb security`、`nb report`、`nb firewall status/open/close`、`nb ssh status/port`、`nb swap set`、`nb bbr status/enable`、`nb docker status`、`nb backup list/diff/restore/export/import`、`nb history`、`nb undo`、`nb baseline create/check` 和 `nb update stable/testing/rollback`。修改类命令不会绕过安全确认。

在命令前加入 `--dry-run` 可预演受支持的修改，例如 `sudo nb --dry-run ssh port 2222`。预演会显示计划、自动跳过确认并明确报告“未修改系统”。

### 兼容性诊断与安全体检

兼容性诊断识别操作系统、架构、内核、包管理器、systemd/OpenRC、虚拟化、云平台、防火墙后端、SSH service/socket、网络连通性、Docker、拥塞控制及队列算法，并对主要功能显示可用/不可用。安全体检只读检查防火墙、SSH Root/密码登录、空密码账户、Fail2Ban、数据库公网监听、待更新软件、磁盘、inode、NTP 和失败登录。

诊断报告保存到 `/var/lib/vps-toolkit/reports`，权限为 `0600`，包含系统资源、监听端口、失败服务和工具错误摘要，不包含密码、Token、SSH 私钥内容。

### 第三方来源与更新通道

`config/sources.tsv` 是唯一的第三方可执行来源登记表，`config/extensions.tsv` 管理扩展入口、风险等级和启停状态。重装脚本、R 探长和 OCI Helper 使用固定提交/Release 与 SHA-256；动态脚本标记为每次审阅。稳定更新通道只接受 GitHub 最新正式 Release 资产，先用 `config/release-signing-public.pem` 验证 SHA-256 清单的 Ed25519 签名，再验证源码包摘要；测试通道读取 `main`。正式版本变化记录在 `CHANGELOG.md`。

## 一、安装、启动与文件位置

| 项目 | 命令或位置 | 说明 |
|---|---|---|
| 一键安装 | `curl -fsSL https://raw.githubusercontent.com/nbbk/vps-toolkit/main/bootstrap.sh \| sudo bash` | 从本仓库下载源码包并安装 |
| 日常启动 | `sudo nb` | 推荐的短命令 |
| 备用启动 | `sudo n` | 仅当系统原本没有 `n` 命令时安装 |
| 完整命令 | `sudo vps-tool` | 始终可用 |
| 在线更新 | `sudo nb --update` | 检查、备份并安装最新版 |
| 卸载 | `sudo nb --uninstall` | 删除程序，可选择是否删除数据和日志 |
| 程序目录 | `/opt/vps-toolkit` | 主程序及模块 |
| 状态与备份 | `/var/lib/vps-toolkit` | 配置备份、外部脚本、升级备份 |
| 操作日志 | `/var/log/vps-toolkit.log` | 权限为 `0600`，不记录密码 |

脚本支持 Debian、Ubuntu、CentOS Stream、Rocky Linux、AlmaLinux、Fedora 和 Alpine。不同发行版的软件包名称、防火墙和服务管理器不同，工具会自动识别。
一键安装器依赖 OpenSSL 验证正式发布签名；缺失时会从发行版软件源安装。手动复制目录安装的用户应确保系统已有 `openssl`，否则后续稳定版更新会安全停止并提示安装。

## 二、主菜单说明

### 1. 系统信息

只读功能，不会修改系统。显示：

- 发行版、内核、架构、主机名和运行时间；
- CPU 型号、核心数和架构；
- 内存与 Swap 使用量；
- 磁盘文件系统、容量和使用率；
- IPv4/IPv6 地址；
- 当前 TCP/UDP 监听端口及对应进程。

适合在维护前确认系统环境、磁盘是否充足，以及端口是否已被占用。

### 2. 系统更新

使用发行版自带的软件源更新全部已安装软件包：

- Debian/Ubuntu：`apt-get update` 和 `apt-get upgrade`；
- RHEL 系：`dnf/yum upgrade`；
- Alpine：`apk update` 和 `apk upgrade`。

不会自动重启。若出现 `/var/run/reboot-required`，工具会提示需要重启。生产节点更新前应先制作快照，避免内核或基础库升级影响业务。

### 3. 系统清理

清理软件包缓存、无用依赖和 14 天以前的 systemd 日志：

- Debian/Ubuntu 会执行 `autoremove --purge`；
- RHEL 系会执行 `autoremove` 和缓存清理；
- Alpine 会清理 APK 缓存；
- 使用 systemd 的系统会压缩旧日志占用。

不会删除用户文件、Docker 卷或项目目录，但可能删除系统判断为不再依赖的软件包。

### 4. 开放端口

支持单端口和端口范围，例如：

```text
443/tcp
53/udp
8000:8100/tcp
```

优先管理 UFW，其次 firewalld。若系统没有防火墙，会询问并安装发行版默认防火墙。检测到原生 nftables 规则时只读展示，不自动插入规则，避免破坏已有复杂规则。

注意：云厂商安全列表、NSG 和安全组位于 VPS 外部，本功能不能修改。机内开放后，仍需在 OCI、AWS、Azure 等控制台同步放行。

### 5. 关闭端口

从 UFW 或 firewalld 删除指定的允许规则。关闭前应先确认服务并不依赖该端口。不要关闭当前 SSH 连接使用的端口，除非已经验证另一个 SSH 端口可以登录。

### 6. 查看端口/防火墙

只读显示当前防火墙后端、规则、状态以及系统监听端口。适合检查“端口已放行但仍无法连接”的问题：

1. 服务是否实际监听；
2. 机内防火墙是否允许；
3. 云安全组是否允许；
4. 服务是否只监听 `127.0.0.1`。

## 三、BBR 管理

BBR 是 TCP 拥塞控制算法，主要改善高延迟、跨地区和存在轻度丢包线路的吞吐与延迟。它不能突破套餐带宽，也不能改变运营商路由。

### 1. 启用当前内核原生 BBR

加载 `tcp_bbr`，确认当前内核支持 BBR，然后写入：

```text
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
```

配置文件为 `/etc/sysctl.d/99-vps-toolkit-bbr.conf`。不更换内核，风险最低，适合绝大多数代理节点、网站和 Docker 服务。

### 2. 撤销 BBR 配置

删除本工具创建的原生 BBR 配置并尝试恢复 `cubic`。如果第 6 项网络优化仍然存在，它还会继续指定 BBR；要完全撤销，应同时执行第 7 项。

### 3. 安装 XanMod BBRv3 内核

为符合条件的 x86_64 Debian/Ubuntu 添加 XanMod 官方 APT 源，识别 CPU 的 x86-64 PSABI 等级，然后安装匹配的 XanMod 或 XanMod LTS 内核。

支持范围以 XanMod 官方仓库为准，当前工具仅开放给 Debian 12+、Ubuntu 24.04+ 等受支持代号。安装后不会自动重启。

风险：这是第三方内核。少数虚拟化平台可能无法启动新内核。执行前必须制作启动卷快照，并确认云控制台或串口救援可用。

### 4. 更新 XanMod BBRv3 内核

仅适用于已经安装 XanMod 的系统。通过官方软件源升级当前 XanMod 软件包，不会自动重启。需要在合适的维护窗口手动重启才会运行新内核。

### 5. 卸载 XanMod BBRv3 内核

卸载所有 XanMod 内核包、清理依赖和软件源，然后更新 GRUB。工具会先确认系统中仍有非 XanMod 原生内核，否则拒绝卸载。卸载后需要手动重启。

### 6. 网络参数优化

写入 `/etc/sysctl.d/99-vps-toolkit-network.conf`，设置 BBR、`fq`、TCP Fast Open、MTU 探测、Keepalive、连接队列和连接结束等待时间。采用相对保守的 VPS 通用值。

推荐用途：代理节点、跨国连接、转发服务和中等并发应用。数据库专机或已经由其他调优工具管理的服务器，应避免叠加多套 sysctl 配置。

### 7. 撤销网络参数优化

删除上述网络优化文件并重新加载系统全部 sysctl。不会删除第 1 项单独创建的 BBR 配置。

### 8. 查看详细状态

只读显示当前内核、可用拥塞算法、实际算法、队列算法、XanMod 软件包、关键 sysctl 和是否需要重启。

### 节点推荐组合

- 普通 x86_64/ARM 节点：`1 + 6`；
- 甲骨文 ARM 实例：`1 + 6`，不要安装 XanMod；
- x86_64 Debian/Ubuntu 高延迟跨国线路：优先 `1 + 6`，效果仍不理想且可接受换内核风险时再考虑 `3 + 6`；
- 当前已显示 `bbr + fq`：通常只需考虑第 6 项，或者保持现状。

## 四、修改虚拟内存

显示当前内存与 Swap，允许把 `/swapfile` 设置为 128–262144 MB，或输入 `0` 删除本工具管理的 Swap。

创建流程包括停用旧 `/swapfile`、备份、分配空间、设置 `0600` 权限、格式化、启用并写入 `/etc/fstab`。如果检测到其他 Swap 分区或文件，会拒绝自动处理，防止误删。

常见建议：

- 512 MB 内存 VPS：Swap 512–1024 MB；
- 1–2 GB 内存 VPS：Swap 1024–2048 MB；
- 内存充足且应用不易突发：可保持较小 Swap；
- Swap 不能代替物理内存，频繁使用会明显降低性能。

## 五、Docker 管理

### 1. 安装 Docker

从发行版官方软件源安装 Docker 和 Compose 插件，启用服务，并通过 `docker info` 验证服务。不会使用不透明的 `curl | sh` 安装脚本。

### 2. Docker 全局状态

显示 Docker Server 信息、磁盘占用以及全部容器。Docker 未安装时只提示并返回主菜单，不会导致整个工具退出。

### 3. 容器管理

支持查看、启动、停止、重启、跟踪日志、删除和检查容器。要求输入现有精确容器名，不修改 Compose 文件。

### 4. 镜像管理

支持拉取、删除和清理悬空镜像。镜像名输入经过字符格式校验。

### 5. 网络管理

列出、创建、删除和检查 Docker 网络。自动创建类型为 bridge；默认的 bridge、host、none 网络不应删除。

### 6. 卷管理

列出、创建、删除、检查和清理未使用卷。卷通常包含数据库和应用数据，删除后难以恢复。

### 7. 清理无用资源

执行常规 `docker system prune`，不主动删除命名卷。

### 8–9. daemon.json 与日志轮转

日志轮转设置 `json-file`、单文件 10 MB、最多 3 个文件。修改前备份现有 `/etc/docker/daemon.json`，使用 jq 合并而不是覆盖；若 dockerd 支持则先验证配置，重启失败会恢复备份。第 9 项只读显示当前 JSON。

### 10–11. Docker IPv6

开启时设置 Docker IPv6 和私有 ULA 网段 `fd00:dead:beef::/48`，关闭时只删除这两个字段。配置变更会重启 Docker；不会替代宿主机和云网络的 IPv6 配置。

### 12. Docker 备份

保存容器、镜像列表和容器 inspect 元数据；可选使用临时 Alpine 容器打包全部命名卷。在线卷备份不是数据库一致性备份，MySQL/PostgreSQL 等仍应执行逻辑导出。

### 13. 卸载 Docker

停止并卸载 Docker 软件包，默认保留 `/var/lib/docker` 数据，避免误删卷和镜像。所有容器服务会中断。

## 六、账户与 SSH

### 10. 修改登录密码

选择用户后直接调用系统 `passwd`。密码由 `passwd` 从终端读取，工具不会获得、保存或写入日志。建议使用强密码；如果已经安全配置密钥登录，可关闭密码认证。

### 11. 修改 SSH 端口

安全流程如下：

1. 验证新端口范围并检查是否已占用；
2. 使用 `sshd -t` 确认当前配置正常；
3. 先在防火墙开放新端口；
4. 备份 SSH 配置；
5. 写入独立端口配置；
6. 再次运行 `sshd -t`；
7. 重启 SSH 并确认新端口实际监听；
8. 失败时撤销新配置并恢复服务。

Ubuntu 22.10 及更新版本可能由 systemd 的 `ssh.socket` 而不是 `sshd_config` 决定监听端口。工具会自动识别这种模式，创建独立的 Socket 覆盖配置，同时保留旧端口和开放新端口，然后执行 `daemon-reload`、重启 Socket 并检查实际监听状态。修改成功后仍应保持当前连接，新开一个终端验证新端口；OCI 等云平台还必须在云安全列表中单独放行新端口。

工具不会自动关闭旧端口。请保持当前会话，另开终端验证新端口登录成功，然后再使用“关闭端口”删除旧端口规则。

### 12. SSH 安全检查

只读检查 SSH 配置语法、实际端口、Root 登录、密码认证、公钥认证、空密码和 X11 转发状态。它只提供现状，不会自动关闭登录方式。

## 七、甲骨文云脚本合集

### 代码来源说明

甲骨文云菜单不是一个单独的第三方整包。以下功能由本仓库直接实现并随安装包部署：保活容器生命周期管理、Root 密码登录开关、IPv6 内置诊断/恢复、OCI 元数据查询。

以下三个入口是明确标注来源的第三方上游工具，不复制或伪装成本仓库代码：

| 功能 | 上游来源 | 本工具的处理方式 |
|---|---|---|
| DD 重装 | `github.com/bin456789/reinstall` | 执行时下载、计算 SHA-256、显示前 100 行、确认后运行 |
| R 探长 | `github.com/semicons/java_oci_manage` | 执行时下载官方 Release 的 `sh_client_bot.sh`、计算 SHA-256、显示前 120 行、确认后运行 |
| OCI Helper | `github.com/Yohann0617/oci-helper` | 执行时下载最新 Release、计算 SHA-256、显示前 120 行、确认后运行 |
| JHB IPv6 | `https://jhb.ovh/jb/v6.sh` | 执行时下载、计算 SHA-256、显示前 120 行、确认后运行 |

采用这种方式是为了保留作者归属、避免未经许可证允许复制代码，并让用户明确知道实际执行内容来自哪里。SHA-256 只用于标识本次下载文件，不能证明第三方代码安全。如果不信任上游，请不要输入 `y`，并优先使用本仓库内置功能。

### 1. 安装闲置实例保活容器

运行 `fogforest/lookbusy` 容器，可设置 CPU 范围、内存占用比例和测速间隔。容器使用只读根文件系统、移除 Linux capabilities、禁止提权并限制进程数。

该功能可能违反云服务商关于人为制造负载的政策。使用前应自行阅读最新 OCI 服务条款；本工具不保证它能避免实例回收。

### 2. 卸载闲置实例保活容器

删除名称为 `vps-toolkit-lookbusy` 的容器，不删除其他 Docker 容器。

### 3. DD 重装系统

支持 Debian 11/12/13 和 Ubuntu 20.04/22.04/24.04，使用 `bin456789/reinstall` 项目。执行前会：

- 下载到 `/var/lib/vps-toolkit/external/reinstall.sh`；
- 展示下载来源和 SHA-256；
- 显示脚本前 100 行；
- 再通过 `[y/N]` 确认。

确认执行后会清空系统盘并中断 SSH，通常不可撤销。必须提前备份启动卷和业务数据，确认目标系统、网络、登录方式及 OCI 串口控制台。

### 4. R 探长

下载并运行 `semicons/java_oci_manage` 官方 Release 中的 `sh_client_bot.sh`。执行前显示来源、SHA-256 和脚本前 120 行。R 探长具备 OCI 等多云账号、实例和 SSH 管理能力，API 私钥与配置只应放在可信服务器上。

### 5. 开启 Root 密码登录

适用于确实需要 Root 密码 SSH 登录的场景：

1. 验证当前 SSH 配置；
2. 提示风险并确认；
3. 调用 `passwd root` 设置密码；
4. 写入独立配置 `00-vps-toolkit-root-login.conf`；
5. 开启 Root、密码和公钥认证；
6. 使用 `sshd -t` 校验并重启；
7. 读取实际生效配置确认；
8. 失败时删除新增配置并重启恢复。

建议同时在 OCI 安全列表中把 SSH 来源限制为自己的固定 IP，并配置 Fail2Ban。开放 Root 密码登录的安全性低于普通 sudo 用户配合 Ed25519 密钥。

### 6. 关闭 Root 密码登录

设置 `PermitRootLogin prohibit-password`、`PasswordAuthentication no`、`PubkeyAuthentication yes`。关闭前必须检测到 `/root/.ssh/authorized_keys` 非空，否则拒绝执行，避免直接失联。

### 7. IPv6 内置诊断/恢复

显示全局 IPv6 地址、路由、内核开关和连通性。确认后启用 Linux IPv6 内核开关，并根据系统重新应用 Netplan 或 NetworkManager。

它不能代替 OCI 控制台设置。如果仍不通，需要检查 VCN、子网 IPv6 CIDR、安全列表、路由表及实例 VNIC 是否分配 IPv6 地址。

### 8. JHB IPv6 恢复脚本

下载参考项目使用的 `jhb.ovh/jb/v6.sh`，显示来源、SHA-256 和前 120 行，再确认执行。由于是第三方动态脚本，每次执行前都应检查显示内容。

### 9. 查看 OCI 元数据与网络

显示 IPv6 状态并查询 OCI 实例元数据服务。输出会尝试隐藏 SSH 公钥和用户数据等敏感字段。该功能只在 OCI 实例内有效。

### 10. OCI Helper

下载并运行 `Yohann0617/oci-helper` 的官方 Release 安装器。该项目此前被错误标记为“R 探长”，从 2.1.1 起已纠正名称并作为独立入口保留。

## 八、日志、更新与卸载

### 14. 查看操作日志

使用 `less` 查看 `/var/log/vps-toolkit.log`。日志记录时间、执行命令和错误，不记录 `passwd` 输入的密码。按 `q` 退出。

### 15. 检查并更新本工具

稳定更新器读取最新 `vX.Y.Z` GitHub Release，下载本项目构建的版本资产、SHA-256 清单和 `.sha256.sig`，先验证 Ed25519 签名再核对源码包摘要；缺失验签工具、文件、公钥或任何校验不通过时安全停止，不回退到 `main`。`testing` 通道才读取 `main`，用于提前测试开发版本。

确认升级后：

1. 备份当前 `/opt/vps-toolkit`；
2. 安装新版本；
3. 验证安装后的版本号和主脚本语法；
4. 验证失败则恢复旧版本；验证成功则结束内存中的旧菜单进程，并立即启动刚安装的新版本。

从主菜单选择更新或执行 `sudo nb --update` 都会进入上述流程。交互式运行时，结果页会保留旧版本、新版本和备份位置，按回车后才进入新版，避免新菜单清屏覆盖升级结果。非交互式运行不会等待输入。升级完成后不需要退出并重新输入 `nb`；屏幕上重新出现的主菜单已经来自新版本。

备份位置为 `/var/lib/vps-toolkit/update-backups/`。命令行入口为 `sudo nb --update`。`sudo nb update rollback` 会显示最近一次升级备份的版本，确认后先保存当前版本，再恢复旧目录并校验版本号。更新器默认拒绝把正式安装降级到更低版本，回滚命令是明确的例外。

### 16. 卸载本工具

删除 `/opt/vps-toolkit` 及由安装器创建的 `vps-tool`、`nb`、`n` 快捷链接。第二次确认可选择删除状态目录和日志。

卸载不会撤销防火墙、SSH、Swap、BBR、Docker、内核或软件包改动，因为自动反向修改这些系统状态可能导致失联或业务中断。应在卸载前按各模块说明人工撤销。

## 九、安全与使用原则

- 在修改 SSH、防火墙、内核或执行 DD 前制作云盘快照；
- 保持至少一个已登录 SSH 会话，直到新配置验证完成；
- 不要同时使用多套 BBR/sysctl/防火墙管理脚本；
- 第三方脚本的 SHA-256 只能标识本次下载内容，不能证明代码安全；
- 不要把 VPS 密码、私钥、Token 或完整日志发布到 Issue；
- 云安全组与机内防火墙是两层独立控制，必须同时检查；
- 重要业务应先在测试 VPS 验证，再应用到生产实例。

## 十、开放全部端口

主菜单第 19 项会把机内 UFW 入站默认策略改为允许，为 firewalld 添加 `1-65535/tcp` 和 `1-65535/udp`，或在备份完整 nftables 规则后清空规则集。这会暴露所有正在监听的数据库、缓存、面板和内部 API，强烈建议仅用于另有上游硬件防火墙或临时排障的环境。

第 20 项依据 `/var/lib/vps-toolkit/firewall-open-all.state` 恢复执行前状态：UFW 恢复原入站默认策略和启用状态，firewalld 只删除第 19 项新增加的整段规则，nftables 载入该次操作前的完整规则备份。缺少状态记录或防火墙后端已经变化时会拒绝盲目恢复。撤销前仍应确认当前 SSH 端口的放行情况。两项功能都不能修改 OCI/AWS/Azure 的安全组。

## 十一、系统工具箱

系统工具箱集中提供主机名、密码、端口、SSH 端口、DNS、用户、Swap、时区、BBR、更新清理、运行服务、Cron、系统日志、Fail2Ban 和 SSH 安全检查。

- 新建用户会创建家目录、设置密码，并加入 `sudo` 或 `wheel` 管理组；
- 删除用户默认保留家目录，禁止删除 root；
- DNS 修改会备份 `/etc/resolv.conf`，但可能被 Netplan、systemd-resolved 或云初始化再次覆盖；
- 时区提供上海、香港、新加坡、东京、UTC、伦敦、纽约、洛杉矶等数字选项，也支持输入标准时区名称；
- Fail2Ban 从发行版软件源安装，仍需根据真实 SSH 日志路径检查 jail；
- 服务、Cron 和日志入口默认只读。

## 十二、重装系统

扩展中心的“重装系统”使用登记并固定版本的 `bin456789/reinstall`，覆盖 Debian、Ubuntu、Rocky、AlmaLinux、Oracle Linux、Fedora、CentOS、Alpine、Arch、Kali、openEuler、openSUSE 和 fnOS，并支持自定义 HTTPS DD 镜像。

执行前显示上游来源、SHA-256 和脚本内容预览。重装会清空系统盘并断开 SSH，必须先备份启动卷和业务数据。Windows 镜像版本、驱动和授权差异较大，本工具不硬编码未知镜像；需要 Windows 时可在自定义 DD 中使用自己核验过的合法镜像。

### IPv4 / IPv6 模式

位于“系统工具箱 → 24”：

- IPv4 优先：保留双栈，在 `/etc/gai.conf` 的独立标记区块提高 IPv4-mapped 地址优先级；
- IPv6 优先：保留双栈，提高原生 IPv6 地址优先级；
- 仅 IPv4：通过 `/etc/sysctl.d/99-vps-toolkit-ipv4-only.conf` 持久关闭 IPv6；
- 仅 IPv6：使用独立 nftables 表阻断非 loopback IPv4 入站和出站，并在 systemd 系统创建开机服务；
- 恢复双栈：删除本工具的 sysctl、nftables、systemd 和 gai.conf 配置，然后重新加载系统参数。

仅 IPv6 是高风险模式。工具会确认存在全局 IPv6 地址、IPv6 默认路由、真实 IPv6 连通性，并检查当前 SSH 客户端地址；当前会话通过 IPv4 建立时会拒绝切换。建议仍通过云串口执行，并确保 DNS、软件源和业务上游均支持 IPv6。

## 十三、测试脚本合集

测试菜单包括 ChatGPT/流媒体解锁、BestTrace、MTR、SuperSpeed、NextTrace、BackTrace、NetQuality、TCPQuality、YABS、Geekbench 5、Bench、ECS 融合怪和 NodeQuality。

所有测试均为第三方动态脚本：运行时下载、显示来源与 SHA-256，再经确认执行。性能测试会消耗 CPU、磁盘和大量流量，可能触发云厂商限速；生产业务高峰期不要运行。测试结果受时间、线路和上游服务策略影响。

## 十四、LDNMP 建站

建站模块以 Docker Compose 和官方/项目官方镜像为主，数据根目录为 `/opt/vps-web`。

- LDNMP：Nginx、PHP 8.3 FPM、MySQL 8.4、Redis 7；
- WordPress：WordPress 官方镜像与 MariaDB；
- Halo：Halo 官方镜像；
- Vaultwarden：项目镜像，正式使用前必须配置 HTTPS 和管理令牌；
- 静态站点：独立 Nginx 容器和可编辑 HTML 目录；
- 反向代理：host 网络模式，适合代理本机服务；
- Discuz/Typecho：因缺少统一维护的官方容器镜像，工具提示使用 LDNMP 后上传官方源码，不自动采用未知镜像；
- 备份：打包 `/opt/vps-web` 文件；数据库仍应单独做逻辑导出；
- 更新：遍历 Compose 项目拉取镜像并重建；
- 卸载：停止 Compose 项目并删除站点目录，命名卷可能保留。

宝塔国内版使用 `https://download.bt.cn/install/install_panel.sh`，aaPanel 国际版使用 `https://www.aapanel.com/script/install_7.0_en.sh`。两者都是具有服务器高级权限的第三方面板，不建议与本工具 LDNMP 环境混装；执行前同样展示来源、SHA-256 和脚本预览。

## 十五、基础工具与后台工作区

基础工具菜单显示 curl、wget、sudo、socat、htop、iftop、unzip、tar、tmux、ffmpeg、btop、ranger、ncdu、fzf、vim、nano、git 以及可选终端小游戏的安装状态。支持单项、常用批量、全部和指定包操作；指定包名会经过格式校验。

后台工作区使用 tmux：

- 1–10 对应固定的 `workspace-1` 到 `workspace-10`；
- 可创建、进入和删除自定义工作区；
- 按 `Ctrl+b` 后按 `d` 可退出但保持任务运行；
- SSH 自动驻留会在指定用户 `.profile` 写入带边界标记的配置；关闭时只删除该标记区块；
- 工作区中的进程在 SSH 断开后继续运行，但服务器重启后不会自动恢复进程状态。

## 十六、主菜单仪表盘与功能搜索

每次显示主菜单时，顶部会汇总内存、根分区、SSH 监听端口、当前 TCP 拥塞算法、Docker 安装状态和基础告警数量。它用于快速发现磁盘接近满载等明显问题，不代替完整监控系统。

主菜单第 26 项支持中文或英文关键词搜索，例如“SSH”“备份”“Docker”“基线”，返回对应的主菜单编号和命令提示。搜索只读取内置功能索引，不联网。

## 十七、安全预演、操作锁与事务撤销

`sudo nb --dry-run <命令>` 用于预演支持的修改操作。当前覆盖端口开关、SSH 端口、原生 BBR、Swap、备份恢复/导入/导出、状态基线和工具更新。预演不会安装依赖、写配置、重启服务或创建目标文件。

会修改核心配置的操作使用全局锁。同一时间只允许一个工具会话执行修改，避免两个终端同时写 SSH、sysctl、Swap 或防火墙。系统有 `flock` 时使用文件描述符锁；没有时使用带进程检查的目录锁，异常退出留下的无效锁会在下次操作时清理。

事务文件位于 `/var/lib/vps-toolkit/transactions`，记录事务 ID、模块、起止时间、工具版本、配置备份 ID、反向防火墙动作、命令失败状态和最终状态。主菜单“配置备份中心 → 操作历史”或 `sudo nb history` 可查看。

`sudo nb undo latest` 撤销最近一次成功且尚未撤销的事务，也可指定事务 ID。撤销会：

1. 先为当前配置再做一份备份；
2. 按相反顺序恢复原配置和防火墙规则；
3. 重新校验并加载 SSH、sysctl 或 Swap；
4. 全部成功后把原事务标记为 `undone`，防止重复撤销。

自动撤销目前覆盖本工具接入事务层的 SSH 端口、防火墙单条规则、BBR、网络参数和 `/swapfile`。系统升级、内核、Docker 数据、DD 重装和第三方脚本不属于通用一键撤销范围。

## 十八、配置备份中心与状态基线

托管备份支持列表、当前差异、校验恢复、普通导出、加密导出、安全导入和按数量清理。加密导出使用 OpenSSL AES-256-CBC 与 PBKDF2，密码由 OpenSSL 直接从终端读取。导入时会拒绝路径穿越、链接、非法 ID、不安全恢复路径、结构不完整和 SHA-256 不匹配的记录，也不会覆盖同名备份。

主菜单第 25 项“系统状态基线”采集以下内容：系统身份和内核、SSH 配置哈希、本工具 sysctl 配置哈希、UID 0 与 sudo/wheel 管理员、TCP 监听地址、Cron 文件哈希、软件源哈希、Docker 容器/镜像/端口摘要，以及 UFW、firewalld 或去除计数器后的 nftables 规则。基线和漂移报告权限为 `0600`，位于 `/var/lib/vps-toolkit/baseline`。

首次运行选择“创建基线”；以后选择“检查当前变化”会生成统一 diff。软件更新、容器变化或计划内配置修改也会触发变化，因此应在确认变更合法后更新基线。基线只能提示状态不同，不能判断变化一定恶意。

## 十九、扩展注册表与测试层级

`config/extensions.tsv` 登记扩展 ID、显示名称、入口函数、风险级别和默认状态。扩展中心可查看、启用或禁用 `oracle`、`tests`、`web`、`reinstall`；禁用后入口会拒绝启动，状态保存在 `/var/lib/vps-toolkit/extensions.disabled`。这不会删除扩展代码或已经安装的软件。

自动测试分四层：Shell 语法与 ShellCheck、菜单/安全契约、Debian/Ubuntu/Rocky/Alpine 容器矩阵、一次性 VPS 集成测试。真实 SSH 和防火墙变更测试只有在仓库变量开启、运行器带 `vps-toolkit-disposable` 标签、手动输入 `DISPOSABLE` 且主动打开变更测试时才执行；操作完成后会调用事务撤销。正式运行前仍必须由操作者制作 VPS 快照。
