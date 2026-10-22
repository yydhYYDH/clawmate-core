# 独立盲测交付报告

日期：2026-10-22。唯一课程工作目录：`/private/tmp/clawmate-oh-blind-20261022`。冻结提示词未修改。未读取现有 OH 助手、其他课程仓库、父会话、Git 历史或参考实现；仅读取独立 starter、SDK/工具链、公开官方协议资料，并执行只读设备枚举。未派子代理。

## 实际结论

完成独立源码实施、电脑检查和 OpenHarmony 未签名 HAP 构建。**尚未完成可运行真机助手的全部验收**：没有连接的目标设备、匹配签名或本次真实模型凭据，因而安装、冷启动、Self-HDC 真实协议兼容、中文注入、持续后台、计算器408、网页搜索、独立备忘录持久化、跨 App 与浏览器下载均未验证。没有生成或冒用真机录像/截图。

认证实现有明确能力边界：实现官方二进制握手并仅在设备返回 AUTH_OK 时发命令；对公钥/签名 challenge 或失败明确拒绝、释放 socket。尚无教师设备的实际认证机制和授权凭据，因此不声称实现了课程设备的 RSA 授权，不修改全局认证开关、不迁移电脑私钥。

## 修改和可复现结果

| 项目 | 源码状态 | 电脑检查 | OH 编译 | 签名/真机 |
| --- | --- | --- | --- | --- |
| OH runtime、API23编译/最低18、default、独立包名 | 已实现 | HAP 元数据核对 | 通过 | 未签名；无设备 |
| Self-HDC TCP帧、protobuf握手、拆包/粘包、通道输出、结束/退出码、取消/超时释放 | 已实现；认证仅AUTH_OK | 替身协议测试通过 | 通过 | 未验证真实 hdcd |
| bm目录/真实入口、aa启动、跨App | 已实现；候选限三个题目包 | 非默认Ability解析和目录外拒绝通过 | 通过 | 安装目录和入口未核实 |
| 截图MIME/解码/缩小、0–1000物理坐标 | 已实现 | 坐标边界通过；系统解码未实测 | 通过 | 未验证 |
| 点击/滑动/替换追加中文/回车/返回/Home/等待 | 已实现；依赖 uitest text | 特殊字符shell roundtrip、命令顺序通过 | 通过 | 中文注入/组合键未验证 |
| 原资料导入/问答、BOM/空文件/非法编码/大小/附件、笔记引用重载 | 保留 | 源回归通过（SDK服务用替身） | 通过 | Picker/真实模型/重启未验证 |
| 任务闭环/结构纠正/停止/终态/最后一步观察/返回清理 | 已实现 | 失败不提升成功、迟到动作阻止、15动作后观察通过 | 通过 | 跨App后台未验证 |
| 搜索→备忘录的观察与动作上下文 | 已实现 | 实际观察字段标题/链接传至下一App的替身测试通过 | 通过 | 没有实际网页或备忘录证据 |
| 浏览器下载文件核对 | 已实现核对器；依赖现有浏览器下载 | 无文件/旧路径/助手沙箱/失败不成功通过 | 通过 | 浏览器下载能力、404/中断重试未实测 |
| API18持续后台、短时回退、额度到期和终态释放 | 已实现；移除API20诊断 | 授权/拒绝/迟到释放/旧回调隔离通过 | 通过 | syscap/许可/实际额度未验证 |
| 系统输入法选择及当前名称 | 已实现；接口不可用会提示 | 未模拟系统UI | 通过（兼容API有弃用警告） | 未验证 |

默认链路已经换为 `Index → AgentRunner → OpenHarmonySelfHdcExecutor → SelfHdcClient → 板端TCP hdcd`；业务层不拼调试命令。原 HTTP 执行器、电脑桥和原检查脚本保留，但不是默认链路。将任务预算改为600秒、模型请求最长90秒、15次动作后额外观察；持续后台未批准时按真实短时额度暂停，不能据预算声称10分钟保活。

本次移除了起始源码内置密钥的值，没有在新源码、日志或报告复制原密钥。模型URL/名称/视觉支持和运行时密钥设置仍保留。没有调用真实模型；当前默认模型名仍为起始配置 `/temp/SAI-fengerhu/models/Qwen35-35B`，这不是本次通过验证的服务。电脑模型服务必须使用开发板可达地址。

## 命令与日志

| 命令/阶段 | 实际结果 | 证据 |
| --- | --- | --- |
| Python输入SHA-256冻结 | 已冻结源码/配置/文档/测试；不读取历史reports内容，排除Git/依赖 | INPUT_SHA256.json |
| `bash scripts/build.sh` 初次 | 先遇缓存权限、再缺OHOS_BASE_SDK_HOME；配置修正后成功 | blind-logs/build-initial.log |
| Self-HDC增量构建 | 曾有ArkTS显式类型错误，修复后通过；日志未删除 | build-selfhdc.log、build-selfhdc-fixed.log、build-background.log |
| 首轮/次轮 `bash scripts/check.sh` | 首轮43/51，次轮54/55；缺SDK新值导入替身、旧成功样例缺证据、原密钥预置断言，已对应迁移契约修正 | check-first.log、check-second.log |
| 后台/取消后检查 | 逐轮通过58项Node及原20项Python；补充取消边界后最终60项Node通过 | check-third.log、check-cancellation.log、check-final.log |
| `bash scripts/build.sh` 最终 | **BUILD SUCCESSFUL**；无签名配置警告；最终生成未签名HAP | blind-logs/build-final.log |
| HAP ZIP内 `module.json` 解析 | bundle=com.clawmate.ohblind；minAPI18/targetAPI18；compileSdkType=OpenHarmony；deviceTypes=[default] | blind-logs/hap-metadata.json |
| `hdc list targets` / `bash scripts/device-preflight.sh` | 获准只读执行后均 `[Empty]`；最终脚本退出77，不执行后续设备命令 | blind-logs/device-targets.txt、device-preflight.log |
| 工具版本查询 | DevEco26.0.0；Node24.14.1；JBR25.0.2；OH ETS API23/6.1.0.32；HDC3.2.0c | blind-logs/toolchain.json |

`check-final.log`：60项Node测试全部通过，0失败；Python原有20项全部通过。原Python电脑桥检查只能证明源逻辑回归，不能作为新Self-HDC或OH真机证据。所有电脑SDK替身测试也不能证明系统Picker、截图服务、输入法、后台授权或真实模型可用。

已保留全部检查脚本。新增 tests/selfhdc.test.cjs 覆盖每一字节拆分边界、粘包、错误帧、UTF-8分片、握手拒绝、初始化失败、挂起连接取消、通道退出状态、真实shell引用、坐标、目录、输入顺序、跨App上下文、下载失败和最后观察。Runtime新增持续后台授权、拒绝回退、迟到资源释放和旧回调不影响新任务。

## 交付路径与冻结

- 源码：当前独立目录；可分发源码包 `artifacts/clawmate-ohblind-source.zip`（不包含历史 reports、Git、依赖或缓存）。
- 未签名HAP：`entry/build/default/outputs/default/entry-default-unsigned.hap`，复制件 `artifacts/com.clawmate.ohblind-unsigned.hap`。
- HAP大小：1464513字节。SHA-256：`e1f8ee6e823db88c12f34587aeedebbdf8eaf59cf6cfb9129da0d0da5c95ffe0`。
- 匹配签名HAP：**未生成**。没有实际设备授权/证书；没有复制其他私钥。
- 报告：BLIND_REPORT.md；迁移/设备步骤：docs/OH_MIGRATION.md；访问日志：ACCESS_LOG.md；所有本次日志：blind-logs/。
- 输入冻结：INPUT_SHA256.json；输出逐文件冻结：OUTPUT_SHA256.json；源码包/HAP/清单的最终摘要：FREEZE_SHA256.txt。冻结脚本 scripts/freeze-outputs.py 校验提示词未变。

## 阻塞与教师设备复现

1. **设备缺失**：SDK HDC无目标。实际设备系统/API、id、aa、bm、snapshot_display、uitest、base64、TCP监听、三个App元数据均未核实。连接设备后运行只读 device-preflight，不能省略就假定 EntryAbility。
2. **Self-HDC认证待匹配**：教师设备若返回RSA challenge，本版本明确失败。需要教师已授权的实际机制后才可完成此部分；不得关认证、绕过授权或声称链路通过。
3. **签名/安装缺失**：给独立测试包配置本人的匹配签名，再安装signed HAP；不能直接把unsigned HAP当可安装成功证据，不能覆盖已有助手。
4. **模型和业务验收缺失**：界面配置可达的图片模型服务，先跑计算器408；再搜索、换关键词、独立备忘录保存并重开、跨App写入、有效下载/404/中断、停止和恢复。每项记录真实截图/录像、可见链接、实际保存文件及摘要。
5. **平台能力待核实**：当前焦点`uitest text`、中文组合键、截图权限、输入法服务、KEEP_BACKGROUND_RUNNING的许可和syscap必须以目标API18设备实测为准。API23编译不证明这些系统服务存在。

详细执行步骤见 docs/OH_MIGRATION.md。未经这些实测，不应给本次迁移填写“真机通过”或“全部完成”。
