# 功能审计（2026-10-26）

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
- [OpenAI-Checker 上游说明](https://github.com/missuo/OpenAI-Checker#readme) 提醒策略变化可能影响准确性；脚本仍可下载。保留，但其基于 Cloudflare 地区的判断不能当作实际 ChatGPT 登录/使用验证。没有把“可能不准确”或维护时间当作永久失效。
- `git.io/besttrace` 现指向 [autoBestTrace.sh](https://github.com/zq/shell/blob/master/autoBestTrace.sh)，内容实际调用 NextTrace 进行多目标追踪。功能仍有实现，保留；现有 BestTrace 名称与实现不一致，需后续单独确认命名。
- Docker/Compose、内核能力、OCI 元数据、DNS/网络、上游镜像及应用运行状况依赖目标环境；本次未在真实 VPS 验证，不据本地 Windows 环境缺少服务而删除。

## 回归检查

- 对全部 Shell 文件逐个执行 `bash -n`，避免 `bash -n file1 file2` 只解析首个文件的问题。
- `tests/menu_contract.sh` 增加 mock 分发测试：移除的编号只返回无效选择，保留的 14 个建站入口和 9 个甲骨文入口保持原编号；不执行动作本体。
- 菜单契约还比较调用方的来源 ID 集合与登记表，防止删除后留下悬空引用或无调用来源。
- 使用项目原有 smoke、安全、发行契约及可用 CI 检查；Linux 发行版矩阵和旧版 OpenSSL 兼容性以 GitHub Actions 结果为准。真实 VPS 集成测试不属于本次本机验证范围。
