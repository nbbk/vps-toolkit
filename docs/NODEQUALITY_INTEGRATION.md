# NB NodeQuality 集成

测试菜单 **33**、来源 ID `test-nodequality` 保持不变，使用独立维护的
[nbbk/NodeQuality](https://github.com/nbbk/NodeQuality)，不再调用原站入口。
保留原项目 [LloydAsp/NodeQuality](https://github.com/LloydAsp/NodeQuality)
的来源与 AGPL 许可证；具体修改说明和依赖验证记录见新仓库。

## 默认行为与边界

- 工具箱校验固定入口脚本的提交 URL 和 SHA-256，显示脚本并保留运行确认。
- 默认仅生成本地日志/JSON，成功或失败均尽力保留报告；终端显示报告路径。
- 不自动上传到原站或自建服务。自建服务部署及显式上传参数见 NodeQuality 仓库；
  本菜单不传入上传参数，不代表已部署 Docker/Cloudflare 服务。
- 仅支持 Linux x86_64/aarch64，需要 root；会产生测试流量、CPU 和磁盘负载。
- chroot 不是安全边界，会共享宿主内核、网络及绑定的设备/系统目录。
  不要将固定入口摘要等同于所有运行时依赖安全或固定；第三方动态测试仍需信任。

工具箱只下载单个 `NodeQuality.sh` 并缓存为 `test-nodequality.sh`，不复制仓库；
入口不得依赖未随下载提供的本地兄弟文件。许可证和对应源码可由固定来源提交追溯。

## 更新固定入口

1. 完成 NodeQuality 代码审查、许可证/原作者署名保留及测试验证。
2. 发布获授权的代码后，核实远端实际存在的 **40 位提交 SHA**。
3. 获取该提交的 `NodeQuality.sh`，审核内容并计算 **64 位小写 SHA-256**。
   必须来自远端准确内容，不使用浮动 main、短提交或示例摘要。
4. 同时更新 `config/sources.tsv` 中该行的 URL、同一提交、`pinned-sha256` 和摘要。
   URL 必须为 `https://raw.githubusercontent.com/nbbk/NodeQuality/<真实提交>/NodeQuality.sh`。
5. 复跑安全模拟测试，审核后发布工具箱。无效配置拒绝下载，不回退原站。

## 验证

`bash tests/nodequality_contract.sh` 使用临时目录和假的 curl，覆盖未配置、
动态策略、错误仓库、短提交、缺失/错误摘要、参数传递、取消和 dry-run。
测试不会执行真实基准测试、挂载、系统安装或上传。
真实 VPS、x86_64/aarch64 兼容性及测试结果准确性仍需专用测试机验证。
