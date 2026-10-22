# 提示词盲测与参考行为核对

日期：2026-10-22。任务：从当前 `harmonyos-starter` 独立迁移到 OH，覆盖浏览器搜索、备忘录写入、跨 App 搜索结果保存、文件下载，并保留 starter 的资料与笔记功能。

## 验证方法

教师会话先阅读参考 OH 与 starter，拟定完整需求，然后冻结提示词。实际实现使用 `fork_turns=none` 的新会话，未继承教师对话或参考源码，只收到独立 starter 副本、冻结提示词与 SDK/工具链路径。实现会话按约束不读取其他课程仓库、Git 历史和 starter 的旧 `reports/` 内容，另存 `ACCESS_LOG.md`。

这是独立上下文及访问约束下的盲测，不是通过容器挂载实现的操作系统级读取隔离。教师持有参考代码，仅对照检查；未向实现会话传递参考代码、独立验收用例或具体修复方案。参考答案没有用于生成或修补盲测产物。

初始副本移除个人 HarmonyOS 签名配置，测试包名为 `com.clawmate.ohblind`。原 starter 与参考 OH 源码未修改。输入、提示词和输出分别用 SHA-256 固定，具体见同目录 manifest。

## 初始基线

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| starter 自动化检查 | 40 项 Node + 20 项 Python 通过 | `starter-check.log` |
| 参考 OH 自动化检查 | 15 项 Node 通过 | `oh-reference-check.log` |
| 独立行为验收在原 starter 上运行 | 4/5；跨 App 后丢失新观察的标题/URL | `held-out-starter.log` |
| 已连接设备 | HDC 输出 `[Empty]` | `device-check.json` |

参考 OH 已有 GUI 任务循环、Self-HDC、取消/超时和返回宿主。它的主规划目录没有课程 RoboPi 浏览器；独立浏览器已记录浏览/搜索验收，但下载明确未做实机验收。现有材料也没有提供“搜索→备忘录”完整链路的通过记录。因此四项教学目标应单独验收，不能以“与参考相似”推断它们已完成。

## 首轮盲测结果

**结论：未完全一致，不能据本轮结果保证学生仅用这份提示词即可完成目标板上的全部功能。** 已证明可以独立生成 OH 工程、通过构建并补齐多项业务行为；Self-HDC 握手存在可复现缺陷，四项业务均无真机通过证据。

| 检查层级 | 结果 | 证据 |
| --- | --- | --- |
| 实现者最终自测 | 60 项 Node + 20 项 Python 通过 | `blind-output/blind-logs/check-final.log` |
| 最终 OH 构建 | 通过，未签名 HAP | `blind-output/blind-logs/build-final.log` |
| HAP 元数据 | OpenHarmony，min/target API18，default，com.clawmate.ohblind | `blind-output/blind-logs/hap-metadata.json` |
| 事先准备、未提供给实现者的业务验收 | **5/5 通过** | `held-out-blind.log` |
| 输出冻结后的协议审查与针对性回放 | **0/2，两项失败** | `hdc-handshake-blind.log` |
| 输出完整性 | 105 个冻结文件哈希全部一致；提示词未改 | `blind-output/OUTPUT_SHA256.json` |
| 原项目完整性 | 280 个基线文件哈希未变 | `integrity-check.json` |
| 签名/安装/冷启动/真实模型/设备任务 | 未验证 | 无设备，未生成匹配签名 HAP |

5 项业务验收覆盖：新观察的标题/URL 在跨 App 后保留；取消后的迟到模型响应不执行动作；初始化失败关闭资源且不启动其他 App；返回宿主失败不覆盖失败结果；动作达上限后仍多观察一次。

2 项协议回放是在发现问题后新增的定向检查，不是事先隐藏的用例。回放使用官方 `developtools_hdc` 的 `SendAuthOkMsg` 序列：先发送 AUTH_OK 握手，再发送 channel=0、count=1 的 CHANNEL_CLOSE。它不连接实际设备，不涉及认证绕过。

## 关键不一致

### 1. RSA 授权流程未实现

冻结产物 `platform/SelfHdcClient.ets` 在握手 authType 不等于 4 时直接失败；未实现公钥注册、签名 challenge、设备授权等待和身份持久化。原 OH 的 HdcClient/HdcIdentity 有对应流程。拒绝不支持的认证是合理的失败处理，但它不等于完成了目标环境所需的 Self-HDC 能力。

### 2. AUTH_OK 后遗漏通道 0 的收尾确认

冻结产物收到 AUTH_OK 后立即 ready=true，open 返回，没有消费并确认随后发来的通道 0 关闭消息。官方 daemon 会发送这条关闭消息，参考 OH 也显式等待 ACK 后才允许 shell。独立回放断言失败：`open resolved without ACK of the daemon authentication channel close`。按当前客户端队列逻辑，后续 shell 可能读到残留的通道 0 消息并报“未预期的命令通道”，因此即使无需 RSA challenge，也不能将建链判作已经可用。

### 3. 未解析 AUTH_OK 内的实际授权状态

冻结产物只检查 authType=4，不检查握手数据中的 `daemonauthstatus`。回放 AUTH_OK + DAEMON_UNAUTH，open 仍成功，独立检查失败：`Missing expected rejection`。这只是 App 错误标记已授权，不表示设备端真的放行命令。参考 OH 会检查 TLV 状态，SUCCESS 才进入可执行阶段，等待用户授权和拒绝分别处理。

### 4. 应用入口解析比参考版窄

冻结产物只接受恰好一个公开 page Ability；参考版还根据 launcher skill、mainElementName 和主模块选择入口。多 Ability App 可能被新实现排除。此项为源码差异，未拿目标设备元数据复现，不记作真机失败。

## 四类教学任务的实际证据

| 目标 | 本轮代码/电脑检查 | 仍缺的证据 |
| --- | --- | --- |
| 浏览器搜索 | 浏览器候选目录、视觉任务闭环、来源约束 | 握手修复、真实浏览器搜索与结果/URL核对 |
| 备忘录写入 | 目录、中文输入与保存决策路径 | 真实中文输入、保存后关闭重开 |
| 搜索结果跨 App 保存 | 独立用例确认标题/链接跨 App 传递 | 本次网页结果实际写入独立备忘录 |
| 文件下载 | 浏览器下载触发路径；落盘、大小、时间和 SHA-256 核对器；失败不提升成功 | 有效下载/404/中断，测试文件预期大小/内容核对 |

原资料问答、附件和本地笔记回归通过的是电脑 SDK 替身与文件行为检查；OH 真实 Picker、模型和重启恢复仍待上板验证。构建使用 API23 不证明所有系统服务在 API18 都可用。

## 提示词使用结论与后续复测条件

完整提示词仍按原冻结版本交付，未在看到参考实现后修改盲测产物或回灌修复。`student-prompt.md` 仅删除盲测约束段，与被测试的功能需求相同。

本提示词覆盖了用户要求的功能、异常行为、平台适配和验收边界；本次实验显示，详细需求本身不能保证 AI 自动补齐 HDC 的协议细节。若要把它标作“验证可达成”，需要先补齐实际认证协商、AUTH_OK 的 TLV 状态判断与通道 0 ACK 屏障，再用新独立会话/新输入记录复测，最后连接目标板验证四项业务。可在下一版提示词中明确写出这些行为与协议回放要求，但下一版不能借用本轮结果声称已通过。

教师也可课前提供一个独立、通用且已在目标板验证的 Self-HDC 支持包，将学生任务限定为接口接入和业务迁移；该支持包应明确列入学生输入，不能隐含依赖现有完整 OH 助手。

## 可审查交付

- 完整提示词：`../harmonyos-starter/docs/08-oh-migration-prompt.md`。
- 学生版提示词：`student-prompt.md`。
- 首轮源码包：`blind-output/artifacts/clawmate-ohblind-source.zip`。
- 首轮未签名 HAP：`blind-output/artifacts/com.clawmate.ohblind-unsigned.hap`；**含上述已知缺陷，不作为可运行完成版**。
- 实现者原始报告与访问日志：`blind-output/BLIND_REPORT.md`、`blind-output/ACCESS_LOG.md`。
- 最终冻结清单：`blind-output/OUTPUT_SHA256.json`、`blind-output/FREEZE_SHA256.txt`。

HAP SHA-256：`e1f8ee6e823db88c12f34587aeedebbdf8eaf59cf6cfb9129da0d0da5c95ffe0`。

原始独立工作目录仍在 `/private/tmp/clawmate-oh-blind-20261022`；源码包和主要证据已另存本仓库，避免只依赖临时目录。
