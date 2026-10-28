# 功能审计（2026-10-26）

> 后续变更：菜单 33 已改接 NB NodeQuality 固定入口，见 [集成说明](NODEQUALITY_INTEGRATION.md)。下文 NodeQuality 的原站上传、退出码和架构问题是当时上游版本的历史审计，不是新版功能声明。

基线：`main` 提交 `9fc6ca21327282b6e77e8fb907873c2338895dde`。检查范围包括菜单、函数调用、第三方来源登记表及现有测试。没有运行第三方安装器、真实服务安装、SSH/防火墙变更或重装操作。下载只用于读取内容与计算摘要，不代表已验证第三方功能端到端正常。

## 已移除

| 入口 | 可复核证据 | 处理 |
| --- | --- | --- |
| 建站菜单 3：安装 Discuz | [基线 web.sh](https://github.com/nbbk/vps-toolkit/blob/9fc6ca21327282b6e77e8fb907873c2338895dde/lib/web.sh#L80) 的 `web_install_discuz` 仅调用 `web_prepare` 和 `warn`，没有下载、生成配置或部署 Discuz。`web_prepare` 却会安装/准备 Docker、创建目录。 | 删除菜单、分发、占位函数及现行功能说明。 |
| 建站菜单 5：安装 Typecho | [基线 web.sh](https://github.com/nbbk/vps-toolkit/blob/9fc6ca21327282b6e77e8fb907873c2338895dde/lib/web.sh#L84) 的 `web_install_typecho` 同样只有准备 Docker 和提示，没有应用安装实现。 | 同上；保留正常的 LDNMP、静态网站及其他应用入口。 |
| 甲骨文菜单 10：OCI Helper 旧安装器 | [v3.5.1 Release API](https://api.github.com/repos/Yohann0617/oci-helper/releases/tags/v3.5.1) 显示安装资产 ID `598065083`、大小 1090 字节，2026-09-29 被更新；API 摘要与实际下载摘要均为 `6d3027810051b7c34f69dc39d452778469909ea46bcb69a637a2c4792bc8f332`。仓库登记值为 `a8ab84ba39fa85de896bc5434cceea1a868431c00981878469aca2bb8f3226b0`，必然触发 `external_fetch_id` 校验失败。资产内容明确宣布迁往 OCIworker，并执行该项目 `installer-latest/install.sh`，已不是原固定安装器。 | 删除菜单、函数、来源条目和现行文档，更新菜单契约。没有替换摘要、降低校验或自动接入 OCIworker。 |

这里删除的是未实现或已失效的工具箱入口，不表示 Discuz、Typecho 或 OCIworker 项目本身不可用。保留其他选项编号，避免旧编号意外指向另一项高风险操作。

## 保留项与疑点

- 21 个原始第三方来源均进行了只读 HTTP 获取。重装脚本及 R 探长的固定 SHA-256 与清单完全一致。其余动态脚本可获取不等于其内部接口、系统兼容性或测试结果已全部验证。
- JHB IPv6、NextTrace、Bench、NodeQuality 最初以 Python 默认 User-Agent 获取时返回 403；使用 `curl/8.10.1` 标识后全部返回 200 和脚本内容。YABS 也按 User-Agent 分流：默认标识返回 GitHub 网页，curl 标识返回实际脚本。工具箱使用 curl，故不据此删除。
- 独立 OpenAI-Checker 经下述 mock 进一步确认存在误报，已移除；不是仅因上游维护时间或“可能不准确”警告而删除。
- `git.io/besttrace` 现指向 [autoBestTrace.sh](https://github.com/zq/shell/blob/master/autoBestTrace.sh)，内容实际调用 NextTrace 进行多目标追踪。功能仍有实现，保留；菜单已改为“多目标路由(NextTrace)”，保留原 11 号和来源 ID。
- Docker/Compose、内核能力、OCI 元数据、DNS/网络、上游镜像及应用运行状况依赖目标环境；本次未在真实 VPS 验证，不据本地 Windows 环境缺少服务而删除。

## 回归检查

- 对全部 Shell 文件逐个执行 `bash -n`，避免 `bash -n file1 file2` 只解析首个文件的问题。
- `tests/menu_contract.sh` 增加 mock 分发测试：移除的编号只返回无效选择，保留的 14 个建站入口和 9 个甲骨文入口保持原编号；不执行动作本体。
- 菜单契约还比较调用方的来源 ID 集合与登记表，防止删除后留下悬空引用或无调用来源。
- 使用项目原有 smoke、安全、发行契约及可用 CI 检查；Linux 发行版矩阵和旧版 OpenSSL 兼容性以 GitHub Actions 结果为准。真实 VPS 集成测试不属于本次本机验证范围。

## 测试脚本专项核查

用户补充部分测试不可用后，进一步检查全部 15 个原测试入口的实际脚本、参数、下载链、依赖/架构、结果判断和退出状态。以下“保留”只表示没有足够证据删除整个入口，**不表示端到端测试正常**。未执行基准负载、扫描、大流量测速、依赖安装或 chroot/mount。

### 新增移除与修复

- **移除测试菜单 1（独立 ChatGPT 检测）**：下载内容 SHA-256 为 `951c69b0fb1238a59dfe034a2db2a952fb24960768e130d39c29b9f4d65e5ce4`。原脚本仅按首页是否包含 `text/plain` 判断封锁，再按 `/cdn-cgi/trace` 的国家码推断访问。安全 mock 将所有 curl/ping 替换为本地函数：首页响应 `HTTP/2 403\ncontent-type: text/html`、trace 响应 `ip=192.0.2.1\nloc=US`、ping 显示一个包已收发。未经任何真实请求，原脚本输出两次 `Your IP supports access`，退出 0。也就是说，明确被拒绝的首页仍被报告为支持访问。清理菜单、调用和来源登记；不以 Cloudflare 地区判断代替服务访问验证。
- **修复下载失败后继续处理旧缓存**：基线 `external_fetch` 在 `run curl` 非零退出后仍 chmod、计算摘要并输出缓存路径，最终返回 0。改为立即传播失败，拒绝空文件；已有缓存也不能在本次下载失败后被执行。所有使用该下载器的第三方入口受益。
- **修复测试执行失败不明确**：执行前检查非空及 Bash 语法；非零退出时显示来源名称和原退出码，仍返回该码。成功退出只代表脚本进程成功，不证明第三方输出可信。
- **纠正入口描述**：11 号实际是多目标 NextTrace 路由；14 号上游 `main` 只调用下载/安装和安装后提示，不接受目标地址或自动测速，最初改标为仅安装；后经菜单职责复核移除该测试入口，不将 NextTrace 项目本身视为失效。

### 逐项结论

| 原编号 / 脚本 | 静态或隔离证据 | 处理与剩余限制 |
| --- | --- | --- |
| 1 OpenAI-Checker | 上述 HTTP 403 mock 产生两次支持访问误报，退出 0；上游也注明检测策略准确性下降。 | 移除独立入口。 |
| 2 RegionRestrictionCheck | 使用各服务专有 HTTP/JSON 判据，有 curl、jq 等依赖检查及接口变更；工具箱未额外传参。 | 保留。没有逐个验证数十个服务接口、地区判据和 Cookie 的有效性，不能保证每个子测试准确。 |
| 3 yeahwu | Netflix 函数把 `curl -f ... -w %{http_code}` 的 stderr 合并到结果后与纯 `403` 比较。只加载函数定义、mock curl 返回错误文本加 403（退出 22），函数输出为空、退出 0。安装依赖仅区分 apt 与 yum，缺少 Alpine 路径；ChatGPT 子测试仍使用地区推断。 | 保留其他流媒体功能，明确存在局部漏报；没有因一个子测试失真删除整个合集。需要上游分别修正输出解析及平台支持。 |
| 11 多目标 NextTrace | `autoBestTrace.sh` 安装 NextTrace 后对 10 个固定 IP 调用 `nexttrace -M`；不再运行 BestTrace。 | 保留并纠正名称。未验证固定目标、路由 API 或真实网络探测；内部安装链仍由上游管理。 |
| 12 MTR | 无参数，依次调用 apt/yum 后执行 `mtr -r --n --tcp`，用固定 IP 前缀分类。缺少 apk/dnf 专用分支及命令失败检查，最后 echo 可掩盖中途失败。 | 保留。部分系统可能已有 mtr；不能将所有发行版判为不可用。无 mtr 的 Alpine、IP 段分类准确性和错误退出状态仍未解决。 |
| 13 SuperSpeed | 固定 Ookla 1.0.0 包 URL，按 `uname -m` 拼包名；固定旧节点 ID，按英文 Upload/Download 文本解析；下载失败未可靠停止。菜单显示 0 取消但输入校验仅允许 1–5。 | 保留疑点。x86_64/aarch64 包端点只获得 TLS 超时，不能据此认定永久失效；未测速核实节点。取消、架构别名和依赖处理存在上游缺陷。 |
| 14 NextTrace | `nxtrace.org/nt` 是安装器，有架构映射、下载和安装后提示；未调用指定目标测试。 | 从测试菜单移除；不新增独立安装入口。 |
| 16 BackTrace | latest Release v1.0.8 包含 amd64/arm64 两种资产；安装脚本将所有非 x86_64 架构都选 arm64，忽略中间命令失败。 | 保留，不能在 32 位 ARM、RISC-V 等平台假定可用；未执行二进制或修改 /usr/bin。 |
| 18 NetQuality | 有 apt/dnf/apk 等平台依赖分支，依赖 NextTrace、Speedtest、bgp.tools 及动态下载源；部分结果可能上传。 | 保留。未实测线路、吞吐和报告服务；外部页面变化仍可能影响解析。 |
| 19 TCPQuality | 默认入口下载 rootfs/core；两者均已读取，rootfs 对 x86_64/aarch64/armv7/armv6 有映射，要求 mount/umount/chroot 等权限，core 含多平台依赖安装。 | 保留。嵌套容器/受限 VPS 权限不满足时可能失败，不能归为项目永久失效；未创建 rootfs 或运行负载。 |
| 21 YABS | 当前 getopts 明确接受工具箱的 `-i -5`，分别跳过 iperf、选 Geekbench 5；按架构选 fio/Geekbench 下载，检查空间/依赖。 | 保留。参数透传用本地 fixture 验证，未运行 fio 或 Geekbench；不证明二级二进制和上传接口可用。 |
| 22 Geekbench5 | 固定 5.5.1、三种架构包及摘要；可能自动创建 Swap，解析结果网页；部分失败路径使用无状态 exit。 | 保留。未下载大型二进制、改 Swap 或运行性能测试；无 systemd、musl/Alpine、结果网页变化仍需目标环境验证。 |
| 31 Bench | 读取到 2026 版脚本，映射多种架构、优先 Ookla 1.2.0 并有备用源，检查工具/目录后做磁盘和网络测试。 | 保留。未执行 I/O、测速或验证所有节点。 |
| 32 ECS | 脚本含多平台依赖和独立组件版本/下载链，默认可调用多类测试；部分嵌套菜单仍引用旧外部检测器。 | 保留整个合集，不把入口可下载等同全部子菜单正常；未展开执行所有嵌套工具或改变网络/时间服务。 |
| 33 NodeQuality | v0.0.2 的 amd64/ARM rootfs 均存在，但 `load_3rd_program` 无条件下载 `nexttrace_linux_amd64`，与 ARM rootfs 路径不符；需 mount/chroot，并调用多个远程子脚本和上传 API。 | 保留 x86_64 等场景；ARM 路由子功能存在明确架构风险，未验证其他子测试是否能独立工作，不宣称全功能可用。 |

上游内容是动态的。复核用快照摘要：yeahwu `e27c388c60b2f1e4cd57a8fefc183a62997d0afb798702382a66c716ee984598`；SuperSpeed `f78a0eaa026eb3be25b825d447876f87729732a09f02d6069b771d55059dce98`；NodeQuality `4e1b25894cadf908ef61fb0d9ce874a75524c6dafc2ea26f0477107288e0c018`。

### 专项回归

菜单契约 mock 覆盖剩余 13 个测试入口及 YABS 参数，新增契约确认移除的 1、14 号不执行动作。安全契约使用本地 curl fixture 验证下载退出 28 时不执行缓存、空内容和语法错误不询问执行、摘要不符不执行、退出 42 原样报告，以及合法脚本的 `-i -5` 与含空格参数完整透传。没有用真实失败网络替代确定性回归。

## 云端补充回归与下载保护

推送前发现并发提交 `2fccf6bbbc5e0a2d4377e889175eed99bb67194f`，已以该提交为基线保留其审计、移除、命名与原测试，不覆盖已有改动。复核后删除测试菜单 14 及其来源行：它只安装、不执行测试，不符合该菜单功能；保留原 11 的 NextTrace 多目标测试。不新增安装功能，也不认为 NextTrace 项目失效。其余既有修复和证据保留。

- 下载改为随机临时文件，完整且非空才原子替换缓存；失败/部分下载不返回路径，不执行旧缓存，不留下临时文件。重定向限制为 HTTPS。预览模式在共用下载器和测试启动器均拒绝实际下载/执行，避免自动确认后执行旧缓存。
- 测试确认前显示脚本前 80 行；无需给下载文件执行权限（使用 Bash 读取）。保留语法/摘要检查及参数和退出码；文案不再把每个非零状态断言为测试失败。
- NodeQuality 当前 `post_cleanup` 无条件 `exit 1`，正常运行也可能非零；相反 MTR、GB5、多目标 NextTrace 的部分失败可能被最后成功命令掩盖。因此不根据退出码认证测试结果。
- 多目标 NextTrace 上游缺少二进制时使用 HTTP 管道安装；GB5 使用 sudo 即使已经 root；yeahwu 不含 Alpine 依赖分支。顶层 SHA-256 不能保护二级下载，也不担保结果准确性。
- 新增 `tests/testsuite_contract.sh`：本地 curl stub 覆盖失败、部分下载、空文件、缓存、临时文件清理、摘要不符、语法错误、取消、dry-run、原样参数和退出码；额外检查13 个保留编号及删除编号1、14。所有测试不接触真实网络或系统安装。
- 新测试接入 Shell CI；原 `bash -n 多个文件` 只解析第一个文件，已修正为逐文件检查。

### 其余 12 个来源：条件性问题与未验证边界

全部顶层下载为 HTTP 200 且逐个 `bash -n` 通过，不代表功能正常。下表保留可复核指纹；没有因为缺少本机依赖或一次网络失败删除整个项目。所有二级下载仍未获完整性担保。

| 来源 ID | 语义检查 / 限制 | 下载 SHA-256 |
| --- | --- | --- |
| test-region | 无参数进入交互区域选择；有依赖检查；未验证具体服务准确性。 | `9c0ec7f81a39743c91df9636924f7b308b96fbc038b84b95040d6eb48f8da8cd` |
| test-media | 无参数支持；安装依赖仅 apt/yum，未覆盖 Alpine；内置 ChatGPT 地区推断不代表真实可用。 | `e27c388c60b2f1e4cd57a8fefc183a62997d0afb798702382a66c716ee984598` |
| test-mtr | 无条件调用 apt 和 yum，没有 apk；mtr 缺失/失败后空日志可能被标为“其他”且最终退出成功。 | `5521976f5143127bf0bcbf7b390055b61bcbd4e3f2ae977c5ec9f783b936fbaf` |
| test-superspeed | 使用旧 Ookla 1.0.0 下载源；下载/解压失败可能仍显示完成，还会安装 python 并清理工作目录 speedtest*。二级资产 HEAD 503，暂不能判断永久失效。 | `f78a0eaa026eb3be25b825d447876f87729732a09f02d6069b771d55059dce98` |
| test-backtrace | 要求 wget、tar、root 写入 /usr/bin；非 x86_64 一律当 arm64，未检查安装失败。两个 release 资产可获取，不是整体死亡。 | `34e1e0dc1a7f0f332cadbd799a4c8138f4e1989bdc55b0f0cc306cb113777ef3` |
| test-netquality | 无参数入口存在，包含 apt/dnf/yum/apk 分支；仍需真实 VPS 验证。 | `6c40fe1ae40d969255cb63075c94882733b82ba43831341eb1aadeea7b1fbfcd` |
| test-tcpquality | 无参数入口存在，但会下载 Debian rootfs/core 并 chroot；需要 root/mount 能力，不是纯只读测试。 | `b5fbc67029e6c9371a3fc4cc0c191661c419b5e5c06fe475831ca748f94e675f` |
| test-yabs | 现有 -i -5 参数正确：跳过 iperf，选用 GB5；并非启动参数失效。 | `f783214d0dcaba52779bed60a8652dad3101189cf7aff5120114aaa19795773a` |
| test-gb5 | 依赖/Swap 操作使用 sudo（即使已经 root），仅 apt/yum/dnf；摘要失败路径裸 exit 和缺少 pipefail 可误报成功。官方 93 MB 包仅 HEAD 200，未下载；镜像 HEAD 503 不判永久失效。 | `5f1393ef51c423b12f4800f81a1520c1246205067e03de2a8c1851ffdc554e75` |
| test-bench | 无参数接口、架构映射及下载回退仍实现；未跑磁盘/测速。 | `fbc7d7ec27f59939ba798f456ed3d31931c6d3d4604a63e6d563b19a4974ae04` |
| test-ecs | 无参数交互菜单仍实现；含安装依赖、调整时间等系统操作，未执行。 | `8eb42a0c124885995bbe996d85a9710faef00adb23bf5d53b8f15915257015bb` |
| test-nodequality | post_cleanup 无条件 exit 1，因此完整运行也可能非零；ARM 路径仍下载 amd64 NextTrace。不能只凭退出码判定测试失败。 | `4e1b25894cadf908ef61fb0d9ce874a75524c6dafc2ea26f0477107288e0c018` |
