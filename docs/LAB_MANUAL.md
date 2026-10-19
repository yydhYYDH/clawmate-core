# 实验手册：用 Vibe Coding 从零剥离并复现一个手机 GUI Agent（ClawMate Core）

> **一句话目标**：给你一个完整的参考仓库，你要用 AI 辅助编程（Vibe Coding）把其中“手机 GUI 智能体”这条主干剥离出来，独立实现、编译、签名，并部署到 **OpenHarmony 开发板**上，让它在真实设备上完成“打开计算器并计算 12×34”这类任务。选做：把更多 App（携程、淘宝等）通过 SDK / MCP 方式接入。

---

## 0. 实验信息

| 项目 | 内容 |
|---|---|
| 课程名称 | 手机端 GUI 智能体原理与实践 |
| 实验名称 | 从开源仓库剥离核心功能：ClawMate Core 的复现与部署 |
| 实验类型 | 设计型 / 综合型（非验证型） |
| 建议分组 | 2–3 人一组 |
| 前置课程 | 操作系统、计算机网络、移动应用开发（任意）、基础大模型 API 使用 |
| 参考仓库 | `<在此填入原始参考仓库链接>`（下称“参考仓库”，由教师提供） |
| 目标平台 | OpenHarmony 5.1 / API 18（SysLong RoboPi 或同等级开发板），ArkTS + DevEco Studio / Hvigor |
| 交付物 | 源码仓库 + 可安装 HAP + 实验报告 + 现场演示 |

> **术语约定（全文统一）**
> - **Planner**：把自然语言任务映射为“选哪个 App + 改写后的任务”的大模型。
> - **Decider**：看截图、看历史，输出“下一步动作”的多模态大模型。
> - **Self-HDC**：App 自己在设备上用 TCP 连接本机 `hdcd`，通过 HDC 协议执行 shell 命令来截图/触控，不需要电脑参与。
> - **Host**：ClawMate 自己所在的 App（任务结束后要能回到它）。
> - **HAP**：HarmonyOS / OpenHarmony 应用安装包。

---

## 1. 实验背景（读 10 分钟即可）

传统手机自动化靠“无障碍服务 + 固定脚本”或“PC 上的 adb 脚本”，前者受限于系统权限，后者离不开电脑。另一条路线是 **GUI Agent**：让多模态大模型直接“看截图、想一步、点一下”，像人一样操作任何 App，不需要目标 App 提供 API。

ClawMate Core 就是这条路线的一个最小完整实现，它只做了一件事：**在手机内部闭环**。

```
用户输入任务
    │
    ▼
[Planner]  自然语言 ──► 应用名 / 包名 + 改写后的任务
    │
    ▼
[打开 App]  aa start -b <bundle> -a <ability>
    │
    ▼
┌──────────────────────────────────────────────┐
│ [Decider] 截图 + 动作历史 ──► 下一步动作 JSON │
│     │                                        │
│     ▼                                        │
│ [执行器] click / input / swipe / keyevent    │
│     │        （通过 Self-HDC → uitest）       │
│     ▼                                        │
│ 等待页面稳定 600ms ──► 回到截图               │
│  （最多 15 步 / 10 分钟，done 则结束）         │
└──────────────────────────────────────────────┘
    │
    ▼
回到 Host + 顶部提示“任务已完成/失败/暂停/取消”
```

实验要求你复现的正是这张图，而不是整个商业产品。参考仓库里大量代码（前端、桌面端、后端、推荐系统等）属于**干扰项**，你的第一项能力就是判断“哪些是主干”。

---

## 2. 实验目标

完成后你应当能够：

1. 在一个陌生的大仓库中识别核心链路，画出模块依赖图与数据流图。
2. 用 Vibe Coding 工作流（提示词 → 生成 → 运行 → 读错误 → 修正）把一个功能从参考实现**重新实现**，而不是复制粘贴。
3. 理解并在代码里实现：大模型 JSON 输出的容错解析、归一化坐标→物理像素换算、动作原语（click/input/swipe/key）、多轮闭环与终止判定。
4. 读懂并用 ArkTS 实现一个 **HDC 二进制协议客户端**（握手、认证、shell 通道），解释为什么 App 可以“控制自己”。
5. 在开源鸿蒙设备上完成编译、签名、安装、抓日志、真机验收。
6. （选做）把 GUI 动作的“盲点”用 SDK / MCP 工具补齐，设计一个混合工具调用的 Agent。

---

## 3. 实验环境与课前准备

### 3.1 硬件

| 设备 | 要求 | 说明 |
|---|---|---|
| OpenHarmony 开发板 | API 18 及以上，可 root / `hdc shell` 为 uid=0 | 本实验以 SysLong RoboPi（OpenHarmony 5.1.0.107）为例 |
| 电脑 | Windows / macOS / Linux 均可 | 安装 DevEco Studio（含 HarmonyOS/OpenHarmony SDK） |
| 外接键盘（可选） | USB 或蓝牙 | 用于中文输入法验证 |
| 网络 | 开发板能访问模型服务 | 没有网络时见 3.5 的本地 mock |

> 设备要求里最关键的一条：**`hdc shell` 必须是 root**。若你的板子不是，Host 侧无法执行 `uitest` / `snapshot_display`，Self-HDC 路线不成立，需改用“电脑侧 HDC + App 上报”的降级方案。

### 3.2 软件与 SDK

- DevEco Studio（建议 5.0.0 以上，能编译 `compileSdkVersion 23 / compatibleSdkVersion 18`）。
- `hdc` 命令行工具（随 SDK 提供），务必加入 PATH。
- 一个 OpenAI 兼容的大模型服务：
  - Planner：纯文本模型即可；
  - Decider：**必须支持图片输入（多模态）**，且最好支持自定义 system prompt。
- Node.js ≥ 18（仅用于运行教师提供的解析回归测试，不参与 App 构建）。

### 3.3 开发板准备（一次性）

```sh
# 1) 连接
hdc list targets                      # 应看到设备 UDID
hdc shell id                          # 必须出现 uid=0(root)

# 2) 检查依赖命令
hdc shell "command -v aa bm snapshot_display uitest base64"

# 3) 打开 hdcd 的 TCP 监听（关键！默认只开 USB）
hdc shell "param set persist.hdc.mode.tcp enable"
hdc shell "param set persist.hdc.port 8710"
hdc shell "kill $(hdc shell pidof hdcd)"   # 由 init 自动拉起
hdc shell "netstat -lnt | grep 8710"       # 应看到 LISTEN
hdc shell "uitest uiInput help"            # 确认动作原语可用
```

> 为什么需要这一步：App 运行在设备内部，对它而言 `127.0.0.1` 就是设备自己。`hdcd` 默认只监听 USB，必须显式打开 TCP 模式，App 才能连上。这**不是**设置里的“无线调试”，不需要配对码。

### 3.4 获取参考仓库

教师会提供参考仓库链接。克隆后**先不要读代码**，完成第 4 节的“侦察”任务。

### 3.5 没有可用模型服务时（备用方案）

教师会在实验资源中提供一个 mock 服务（或你自己用 Python/Node 写 30 行）：

- `/v1/chat/completions` 收到含 `image_url` 的请求时，按预设脚本返回动作 JSON；
- 收到 Planner 请求时返回固定 JSON。

只要请求/响应格式与 OpenAI 兼容，你的 App 代码**一行都不用改**。这保证“网络/额度问题”不会阻塞你的工程实现。

---

## 4. 阶段一：仓库侦察与核心剥离

> 本阶段**禁止**直接复制参考仓库文件到你的工程。允许阅读，允许让 AI 帮你解释，不允许整文件搬运。

### 4.1 任务 A：绘制主干图

在参考仓库中找到“用户输入 → 最终操作设备”的完整调用链，画出：

1. **模块图**：页面/控制器、任务循环、模型客户端、动作解析、设备驱动、应用目录、后台保活、日志。
2. **数据流图**：一条具体任务（如“打开计算器算 12×34”）从输入到结束，每一跳的数据长什么样。
3. **时序图**：至少包含“取消任务”和“模型返回非法 JSON”两条异常路径。

交付要求：图中每个模块标注它在参考仓库中的**文件名**，并用 ★ 标出你认为“必须自己实现”的部分。

### 4.2 任务 B：填写“剥离清单”

| 能力 | 参考仓库中的位置 | 是否必须 | 你的实现策略（自己写 / 参考思路重写 / 不用） | 风险 |
|---|---|---|---|---|
| 聊天页面与日志展示 | | 是 | | |
| 任务状态机（成功/失败/暂停/取消） | | 是 | | |
| Planner 调用 | | 是 | | |
| Decider 调用（多模态） | | 是 | | |
| JSON 容错解析（代码块/前后缀/截断） | | 是 | | |
| 坐标换算 | | 是 | | |
| 动作执行（click/input/swipe/key） | | 是 | | |
| 截图（设备侧） | | 是 | | |
| 应用启动/停止 | | 是 | | |
| 后台保活 | | 是 | | |
| 结束回到 Host | | 是 | | |
| 中文拼音输入法 | | 否 | | |
| 推荐/画像/收藏/定时任务 | | 否 | | |
| 桌面端 / 后端服务 | | 否 | | |

> **判断标准**：删掉它之后，“输入一句话 → 设备上真的完成了操作”这条链路是否断掉？断掉就是必须的。

### 4.3 任务 C：Vibe Coding 提示词草稿

为下一阶段准备 3 条提示词（写进报告）：

1. **架构提示词**：让 AI 基于你的模块图生成 ArkTS 工程骨架（只出接口和空实现）。
2. **单模块提示词**：挑一个模块（建议 JSON 解析或坐标换算），要求“输入/输出/边界情况/错误行为”都写清楚。
3. **审查提示词**：让 AI 扮演 reviewer，指出你的实现与参考行为可能不一致的地方。

提示词模板（可直接改）：

```
你是 OpenHarmony ArkTS 工程师。目标：实现 <模块名>。
上下文：这是手机 GUI Agent 的一环，输入是 <...>，输出是 <...>。
约束：
- 只用 ArkTS / @kit.* API，不使用 Node/浏览器 API；
- 不使用 any，不使用动态属性；
- 必须处理 <边界1>、<边界2>；
- 导出纯函数，便于单元测试。
请先只输出接口与关键类型，不要写实现。
```

### 4.4 阶段验收（教师检查点 1）

- [ ] 三张图完整，能指出取消路径与解析失败路径。
- [ ] 剥离清单每行都有“是/否”和理由。
- [ ] 3 条提示词已提交。
- [ ] 口头抽查：为什么 App 能控制自己？为什么必须打开 hdcd 的 TCP？

---

## 5. 阶段二：工程搭建与最小闭环

### 5.1 建工程

1. DevEco Studio → 新建 Empty Ability 工程（ArkTS，Stage 模型）。
2. `build-profile.json5`：
   - `compatibleSdkVersion: 18`（或你的板子 API）；
   - `runtimeOS: "OpenHarmony"`；
   - 配置**与设备匹配的签名**（见 5.3）。
3. `module.json5` 申请权限：

```json5
"requestPermissions": [
  { "name": "ohos.permission.INTERNET" },
  { "name": "ohos.permission.GET_NETWORK_INFO" },
  {
    "name": "ohos.permission.KEEP_BACKGROUND_RUNNING",
    "reason": "$string:EntryAbility_desc",
    "usedScene": { "abilities": ["EntryAbility"], "when": "always" }
  }
]
```

4. 约定目录（可不同，但报告里要说明）：

```
entry/src/main/ets/
├── entryability/EntryAbility.ets
├── pages/Index.ets              // 聊天 UI
└── core/
    ├── EndpointConfig.ets       // 端点与密钥
    ├── CloudModelClient.ets     // OpenAI 兼容客户端
    ├── Prompts.ets              // Planner / Decider 提示词
    ├── AgentActionParser.ets    // JSON 容错 + 动作映射 + 坐标换算
    ├── AgentRunState.ets        // 状态与终态判定
    ├── AgentRunner.ets          // 主循环 + 取消 + 超时
    ├── PhoneBridge.ets          // 设备驱动门面 + 后台保活
    ├── AppCatalog.ets           // 应用白名单
    └── selfhdc/                 // HDC 协议客户端
```

### 5.2 里程碑 M1：能聊天，不能操作

**目标**：输入一句话，Planner 返回应用名，界面显示出来。

实现要点：

- `EndpointConfig`：`hdcIp/hdcPort/plannerBaseUrl/plannerApiKey/plannerModel/deciderBaseUrl/...`。
- `CloudModelClient.chatPlanner`：POST `<base>/v1/chat/completions`。
  - URL 归一化：去掉尾部 `/`；若已是 `/chat/completions` 直接用；若是 `/v1` 则补 `/chat/completions`；否则补 `/v1/chat/completions`。
  - 必须实现：连接超时、读超时、“取消时立刻结束等待”（见 5.6）。
- `Prompts`：Planner 提示词里要注入**本机应用清单**（名字 + 包名），并要求输出 JSON：
  `{"app_name","package_name","final_task_description"}`；无合适应用时输出空串。

**验收**：输入“打开计算器”，日志里能看到 Planner 原始响应和解析出的包名。

### 5.3 里程碑 M2：签名与首次安装

OpenHarmony 对签名校验很严格，**覆盖安装失败 90% 是签名不匹配**。

1. DevEco → File → Project Structure → Signing Configs → 自动生成 / 导入证书。
2. 构建：`hvigorw assembleHap` 或 IDE 的 Build。
3. 安装：

```sh
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
hdc shell aa start -b <你的包名> -a EntryAbility
```

4. 抓日志：

```sh
hdc hilog | grep -i clawmate
```

**排错**：

| 现象 | 原因 | 处理 |
|---|---|---|
| `install failed due to signature` | 签名与已安装包不一致 | 用同一签名覆盖；或换包名（如 `com.<学号>.clawmate`） |
| `device type not match` | `deviceTypes` 不含 `default` | 改为 `["default"]` |
| `compatibleSdkVersion` 报错 | SDK 版本高于设备 | 降到设备 API |
| 启动白屏 | `main_pages.json` 路径错 | 检查页面注册 |

### 5.4 里程碑 M3：Self-HDC 连通

这是本实验最容易卡住的一步，**先打通，再谈智能**。

最小验证顺序：

1. 用 `socket.TCPSocket` 连 `127.0.0.1:8710` → 应能连上（连不上回看 3.3）。
2. 发送 HDC 握手包（banner `OHOS HDC`，`AUTH_NONE`）→ 设备返回 `AUTH_PUBLICKEY`。
3. 生成/加载 **RSA3072** 密钥对，把公钥 PEM 发给设备 → 设备系统弹窗/或 root 设备直接 `AUTH_OK`。
4. 收到 `AUTH_OK` 后，**等待 channel-0 的 close ACK**，再发 shell（协议细节见 5.7）。
5. 执行 `printf SELF_HDC_PHONE_OK; id`，输出包含 `SELF_HDC_PHONE_OK` 与 `uid=` 即成功。

**验收**：日志出现 `SELF_HDC_PHONE_OK`，且能执行 `snapshot_display` 把截图 base64 回传到 App 并显示缩略图。

### 5.5 里程碑 M4：一步动作

实现动作原语到 `uitest uiInput` 的映射：

| 动作 | 命令 |
|---|---|
| click | `uitest uiInput click <x> <y>` |
| click_input | click → `keyEvent 2072 2017`（全选）→ `keyEvent 2071`（清空）→ `text '<内容>'` → `keyEvent 2054`（回车） |
| input（已聚焦） | 同上但跳过 click |
| swipe | `uitest uiInput swipe x1 y1 x2 y2` |
| press_back / press_home | `uitest uiInput keyEvent 2` / `1` |
| open_app | `bm dump -n <bundle>` 解析 ability → `aa force-stop` → `aa start` |

**坐标换算（必考）**：

```
x = clamp(bbox_x, 0, 1000) / 1000 * 物理宽度    // bbox 是 [x1,y1,x2,y2]，取中心
y = clamp(bbox_y, 0, 1000) / 1000 * 物理高度
```

注意：Decider 看到的是缩放后的图（如 0.5），但**换算必须用物理分辨率**，且结果要 clamp 到 `[0, width-1]`。

**验收**：手动构造一个 click 动作（不经过模型），能点开设置里的某一项。

### 5.6 里程碑 M5：完整 Agent 循环

实现 `AgentRunner`，必须包含：

1. **循环**：截图 → Decider → 解析 → 执行 → 等 600ms → 回到截图；**最多 15 步**。
2. **终止判定**：只有 `action == done` 且 `status == success/completed` 才算成功；`failed / suspended / cancelled` 分别映射；**绝不能因为点了个按钮就宣称完成**。
3. **回执**：每个成功动作后追加一条中文回执（“已点击「=」，正在检查页面变化。”）；`progress` 字段用于报告上一步的可视结果；`summary` 用于最终结果。
4. **取消**：`cancel()` 后立刻停止发新动作，即使模型响应迟到也不能执行（晚到的 Promise 结果必须被丢弃）。
5. **超时**：单次模型请求 90s；整任务 10 分钟。
6. **收尾**：`finally` 里必须 停止云端请求 → 尝试回到 Host → 释放 HDC 与后台任务。初始化失败时也要释放“半打开”的连接。
7. **第 15 步之后**再截一次图做最终确认，避免“恰好第 15 步完成”被误判失败。

**验收**：真机完成“打开计算器，计算 12×34”，正文出现分步回执与最终 `summary`。

### 5.7 里程碑 M6：后台保活与回到 Host

- 优先 `backgroundTaskManager.startBackgroundRunning(..., BackgroundMode.DATA_TRANSFER, wantAgent)` 申请**持续任务**；
- 失败则 `requestSuspendDelay` 拿临时额度，记录 `deadline`，到期后停止一切动作并给出原因；
- 任务结束用 `context.startAbility` 回到自己；被系统拒绝时，用**独立的新 HDC 连接**执行 `aa start -b <bundle> -a EntryAbility` 兜底；
- 回到 Host 失败**只记日志**，不能覆盖任务结果。

**验收**：任务结束后前台包名回到你的 App，顶部出现 2 秒自动消失的完成提示。

### 5.8 关于 HDC 协议（阅读材料，不必背）

参考实现里 `selfhdc/` 的关键点，供你在卡住时对照：

- 包格式：`[channel][command][length][data]`，握手 channel 固定 0。
- 认证流程：`AUTH_NONE → AUTH_PUBLICKEY → AUTH_SIGNATURE → AUTH_OK`。
- 新版 daemon 使用 `authtype=1`（RSA3072 + PSS/SHA512 + salt），老版用 PKCS1。
- 若 daemon 要求 `encrypttcp=1`（TLS-PSK），本实验范围内直接报“不支持”，不要硬闯。
- shell 输出没有退出码，需要在命令末尾拼接标记（如 `; echo __EXIT:$?`）自行解析。
- **审计要点**：这是本实验的“深水区”，报告里要能解释上面每一条，尤其是“为什么 AUTH_OK 之后还要等 channel-0 close”。

---

## 6. 阶段三：真机验收与评测

### 6.1 必做验收用例

| 编号 | 用例 | 通过标准 |
|---|---|---|
| T1 | 打开设置 | 8–20s 内前台为设置，正文有回执，状态成功 |
| T2 | 计算器 12×34 | 屏幕上显示 408，最终 `summary` 提及结果 |
| T3 | 多步任务（如“新建备忘录写 hello 并保存”） | 每步有回执，失败/暂停不误报成功 |
| T4 | 运行中取消 | ≤2s 停止，显示“已取消”与固定总耗时，不再有新动作 |
| T5 | 后台切换 30s 后回来 | 任务继续或按额度到期正确停止 |
| T6 | 模型返回非法 JSON | 触发一次解析重试；连续失败给出可读错误，不崩溃 |
| T7 | 结束返回 | 前台回到你的 App，顶部提示出现并 2s 后消失 |
| T8 | 划线复制 | 长按聊天正文选中 → Ctrl+C → 输入框 Ctrl+V 内容一致 |

### 6.2 证据采集

每个用例提交：

1. 屏幕截图（操作前 / 中 / 后）；
2. 完整 `hilog` 片段（包含 `SCREENSHOT`、`ACTION_BEGIN/END`、`TASK END`）；
3. 表情/动作回执的正文截图。

> 建议把每条日志加统一前缀（如 `[CM]`），抓取时 `hdc hilog | grep CM`，否则噪声会淹没你。

### 6.3 评分表（100 分）

| 维度 | 分值 | 说明 |
|---|---|---|
| 主干图与剥离清单 | 10 | 准确度、是否识别出取消与解析失败路径 |
| 工程与构建 | 10 | 能独立构建签名安装，目录清晰 |
| 模型接入与解析 | 15 | URL 归一化、响应校验、JSON 容错（代码块/包裹/截断） |
| Self-HDC | 20 | 连通、认证、shell、截图、错误处理 |
| Agent 循环与状态机 | 20 | 回执、终止判定、取消、超时、finally 释放 |
| 真机验收 T1–T8 | 15 | 每项约 2 分 |
| 实验报告 | 10 | 问题记录、Vibe Coding 过程与反思 |
| 拓展题（附加） | +20 | 见第 8 节 |

**一票否决项**：把“点击成功”当作“任务成功”；取消后仍执行动作；泄露模型密钥到公开仓库。

---

## 7. Vibe Coding 工作规范（实验纪律）

这不是“让 AI 写完就交”，评分看的是**你驾驭 AI 的过程**。

1. **小步提交**：每完成一个里程碑 commit 一次，commit message 写清楚“AI 生成 / 人工修改了什么”。
2. **先接口后实现**：让 AI 先产出类型与函数签名，你确认后再要实现。
3. **错误必须自己读**：遇到编译错误，先贴前 20 行给 AI，但要求它解释原因，而不是只给补丁。
4. **禁止黑盒**：AI 生成的每一段代码，你都要能回答“输入是什么、输出是什么、失败会怎样”。
5. **记录提示词**：报告附录保留你用过的最有价值的 5 条提示词，以及 AI 出错的地方。
6. **安全**：API Key 不进仓库（用本地配置文件 + `.gitignore`），日志里不打印完整 Key 与截图 base64。

**推荐的调试顺序**：协议层（能不能连）→ 驱动层（能不能点）→ 解析层（能不能懂）→ 循环层（能不能收尾）→ UI。**不要反过来**。

---

## 8. 拓展题：为 Agent 接入更多 App（携程 / 淘宝等）

### 8.1 问题：GUI Agent 的盲点

纯截图点击在“列表很长、需要精确筛选、需要登录态、需要跨 App 比价”时又慢又脆。工业界的做法是**混合工具**：能用 API/SDK 的就不点屏幕。

### 8.2 三个方向（任选其一或组合）

**方向 A：SDK / 半自动工具（OpenHarmony 原生）**

- 为某个 App 封装一个“原子能力”，例如“打开携程 → 搜索某日期某城市的酒店 → 返回前 5 条结果”。
- 实现方式：在 Agent 的工具表里注册 `tool_name`，由你的代码用 `Want`/`startAbility` 带参数拉起目标 App 的页面（或使用其提供的分享/跳转 scheme）。
- 挑战：多数商业 App 不开放深链，你需要设计**降级策略**：SDK 不可用时回落到 GUI 点击。

**方向 B：MCP（Model Context Protocol）工具服务**

- 在电脑（或另一台服务）上运行一个 MCP Server，暴露工具：`search_hotel(city, checkin, checkout)`、`get_price(item_id)` 等。
- App 内用 HTTP 调你的 MCP 网关（JSON-RPC），把工具列表注入 Decider 的提示词；Decider 可以选择“调用工具”而不是“点屏幕”。
- 评估点：工具结果如何在下一轮截图决策中被使用？工具失败时如何回退？

**方向 C：混合规划器**

- 在 Planner 阶段就判断任务属于“GUI 型”还是“API 型”，分别路由到两条执行链；或让 Decider 每步在 `{action, tool_call}` 之间选择。

### 8.3 交付要求

1. 设计文档：工具定义（名称、参数 JSON Schema、返回）、路由策略、失败回退。
2. 对比实验：同一任务（如“查明天北京到上海的高铁”）分别用纯 GUI 与工具增强，比较**步数、耗时、成功率**，至少 5 次。
3. 安全与合规：遵守目标平台服务条款，不绕过登录/风控；只做只读查询类演示。
4. 报告里明确说明：哪些能力是“真 API”，哪些只是“跳转 + 仍然靠 GUI”。

### 8.4 参考评分（拓展 20 分）

| 项 | 分值 |
|---|---|
| 工具抽象与代码质量 | 6 |
| 路由/回退策略的合理性 | 5 |
| 对比实验数据完整 | 5 |
| 合规说明 | 4 |

---

## 9. 常见问题（FAQ）

**Q1：`hdc install` 报签名错误？**
A：签名与已安装包不一致。用同一签名覆盖，或换一个全新包名。开发板可用公开 SDK 开发证书。

**Q2：App 连不上 `127.0.0.1:8710`？**
A：回看 3.3。检查 `persist.hdc.mode.tcp`、端口是否被重启改掉、`netstat -lnt` 是否有 LISTEN。

**Q3：截图是黑的 / 尺寸不对？**
A：`snapshot_display` 在部分设备会打印良性 I/O warning，**只看退出码和 JPEG 魔数**（头 `FFD8`、尾 `FFD9`），不要用输出文本判失败。

**Q4：`uitest uiInput text` 输入中文乱码？**
A：确认 shell 引号与编码；必要时用 `base64` 传文本。外接键盘场景需安装适配的中文输入法（见参考仓库的独立输入法工程），系统自带英文键盘不会因“切换输入法”而支持拼音。

**Q5：模型总返回带 ```json 的文本？**
A：解析前先剥离代码块，再尝试修复（补全截断的括号/引号），仍失败则重试一轮并把错误回给模型。

**Q6：切后台一会儿任务就停了？**
A：临时额度和持续任务是两回事。查看日志里的 `BACKGROUND ...` 行，确认拿到的是 continuous 还是 requestSuspendDelay，以及 `budgetMs`。

**Q7：任务结束回不到自己的 App？**
A：后台 `startAbility` 可能被拒，必须有 self-HDC 兜底；注意此时原连接可能已因取消关闭，要新建连接。

---

## 10. 提交清单

```
提交/
├── src/                      # 你的工程（不含密钥、不含 build/）
├── docs/
│   ├── architecture.md       # 三张图
│   ├── stripping.md          # 剥离清单
│   ├── test-evidence/        # T1–T8 截图与日志
│   └── report.md             # 过程、问题、反思
├── prompts.md                # 最有价值的 5 条提示词 + AI 出错记录
└── extension/                # 选做：工具接入设计与对比实验
```

报告建议 8–15 页，重点写**你在哪一步卡住、怎么定位、AI 帮了什么、哪些是它帮不了的**。

---

## 附录 A：最小接口清单（供自检）

```ts
// 端点
interface EndpointConfig {
  hdcIp: string; hdcPort: number;
  plannerBaseUrl: string; plannerApiKey: string; plannerModel: string;
  deciderBaseUrl: string; deciderApiKey: string; deciderModel: string;
}

// 模型
chatPlanner(prompt: string): Promise<string>;
chatQwenDecider(task: string, history: string[], imageBase64: string): Promise<string>;

// 解析
parse(raw: string): { action: string; parameters: Record<string, unknown>; data: Record<string, unknown> };
buildDevicePayload(parsed, width: number, height: number): Record<string, unknown>;

// 驱动
open(): Promise<void>;
startApp(name: string, bundle: string, resetFirst: boolean): Promise<void>;
screenshot(factor: number): Promise<{ image_b64: string; screen_width: number; screen_height: number }>;
guiAction(payload: Record<string, unknown>): Promise<void>;
returnHost(): Promise<void>;
close(): Promise<void>;

// 循环
run(task: string, cb: {
  onLog(l: string): void; onPhase(p: string): void;
  onStep(i: number, max: number, action: string): void; onContent(t: string): void;
}): Promise<{ status: 'success' | 'failed' | 'suspended' | 'cancelled'; message: string }>;
cancel(): void;
```

## 附录 B：关键日志前缀约定

| 前缀 | 含义 |
|---|---|
| `SELF_HDC_PHONE_OK` | Self-HDC 连通探针 |
| `SCREENSHOT physical=WxH model=WxH` | 截图成功 |
| `ACTION_BEGIN/END/FAILED seq=` | 动作生命周期 |
| `DEVICE_COMMAND ... exit=` | 设备命令与退出码 |
| `BACKGROUND ...` | 保活申请与额度 |
| `RETURN_APP_OK/FAILED` | 回到 Host |
| `TASK END:` | 任务终态与原因 |

## 附录 C：与参考实现的行为对照（只核对行为，不抄代码）

- Planner 无合适应用必须报错，而不是随便选一个。
- Decider 的 `progress` 只在“有动作历史”时展示，避免第一屏就宣称结果。
- 第 15 步后仍要做一次最终确认。
- 取消时 `destroy()` 不保证回调，必须自己 reject 等待中的 Promise。
- 初始化失败也要走 `finally` 释放连接。
- `snapshot_display` 的警告文本不影响成功判定。
- 结束返回 Host 失败不改变任务结果。

---

*本手册与具体实现解耦：任何符合第 1 节数据流的实现都算通过；评分看行为与证据，不看与参考仓库的相似度。*
