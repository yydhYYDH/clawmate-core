# 接入华为浏览器和夸克并验收

本指南针对 Pura 80 / HarmonyOS 7 上的 ClawMate 电脑调试桥方案。浏览器接入点是调试桥的应用目录；App 每次设备任务开始时读取该目录，模型从中选择应用。它不会直接读取浏览器私有数据库。

**本轮已接入两个浏览器，并在真实手机上通过电脑桥的查询和结果读取验收。手机 App 发起的完整流程仍受系统短时后台额度限制，不能写成已经全部通过。** 复测结果见第 8 节。

## 1 核对实际入口

本机已通过 `bm dump -n` 核对：

| 应用 | bundle | ability |
| --- | --- | --- |
| 华为浏览器 | com.huawei.hmos.browser | MainAbility |
| 夸克浏览器 | com.quark.ohosbrowser | EntryAbility |

其他手机或应用版本可能不同，不能仅因 App 显示名称相同就沿用入口。核对命令：

```bash
hdc -t <手机ID> shell bm dump -n com.huawei.hmos.browser
hdc -t <手机ID> shell bm dump -n com.quark.ohosbrowser
```

检查 Ability 列表中的实际 `name`，不要把模块的 `mainAbility` 显示字符串机械当成唯一可启动入口。

## 2 配置应用目录

本工程提供 [Pura 80 目录示例](../bridge/apps.pura80.example.json)。把它复制为本机配置，或将两个浏览器条目合并到原有目录：

```json
{
  "host": {
    "name": "ClawMate Lab",
    "bundle": "com.clawmate.harmonystarter",
    "ability": "EntryAbility"
  },
  "apps": [
    {
      "name": "华为浏览器",
      "bundle": "com.huawei.hmos.browser",
      "ability": "MainAbility",
      "startUri": "https://www.baidu.com/",
      "searchUriTemplate": "https://www.baidu.com/s?wd={query}"
    },
    {
      "name": "夸克浏览器",
      "bundle": "com.quark.ohosbrowser",
      "ability": "EntryAbility",
      "startUri": "https://www.baidu.com/",
      "searchUriTemplate": "https://www.baidu.com/s?wd={query}"
    }
  ]
}
```

`startUri` 是教师配置的公开起始页，不由模型随意传入。调试桥启动浏览器时使用 `aa start -A ohos.want.action.viewData -U <startUri>`。真机检查发现夸克需要 `viewData` 才按 URI 打开网页；只给包名和 URI 可能停留在首页。

`searchUriTemplate` 是已配置的查询入口，只有查询参数中允许一个 `{query}`。Planner 为浏览器任务返回 `query` 后，调试桥对关键词做 URL 编码，再交给指定浏览器。它是 URI 跳转查询，不是通过模拟按键向搜索框逐字输入；这两条方式在报告中分开记录。

修改 JSON 后必须重启调试桥；它目前在启动时加载配置，不会自动重新读取文件。App 的 Planner 无需再硬编码这两个包名。

## 3 运行调试桥与 App

示例使用独立端口 18765，替换工具路径、手机 ID、令牌文件和本机配置路径：

```bash
python3 -u bridge/server.py \
  --hdc /path/to/hdc --target <手机ID> \
  --apps bridge/apps.local.json --token-file bridge/token.local \
  --bind 127.0.0.1 --port 18765
```

如果通过 USB 将手机端口反向转发到电脑：

```bash
hdc -t <手机ID> rport tcp:18765 tcp:18765
```

App 桥地址填写 `http://127.0.0.1:18765`，并填写相同令牌。这里 localhost 可用是因为明确配置了反向转发；没有转发时它只指手机自身。也可以用手机可访问的电脑局域网地址，并让桥绑定对应接口。

手机选择“设备任务”，启用支持图片的真实模型。重启 App 后桥令牌需要重新输入。首次接入包含搜索动作的版本，需要重新构建、签名并覆盖安装 App，保留数据即可。

## 4 查询与搜索动作如何执行

推荐的查询路径是 Planner 返回：

```json
{"bundle":"com.huawei.hmos.browser","task":"读取搜索结果","query":"OpenHarmony 官网"}
```

App 把 query 交给 `startApp`，桥仅使用该应用目录中的 `searchUriTemplate`，不允许模型把搜索词变成任意命令或替换 URL 的主机名。带有 `&`、中文或引号的关键词也会被编码为查询内容。浏览器真实加载结果后，再由模型读取截图及可见文字。

需要操作网页自身的输入框时，仍保留 GUI 输入路径：

模型先点击搜索框，再发送：

```json
{"action":"input","text":"OpenHarmony 官网","replace":true,"submit":true}
```

- `replace: true`：对当前焦点输入框全选、清除，再输入本次文本。
- `submit: true`：输入后按 Enter 提交。
- 未指定时仍沿用原来的普通输入行为，避免影响已有任务。

每个底层命令前都检查取消；一旦取消，不再输入或提交。模型不能用这些参数执行任意 shell。当前屏幕的可见文字与实测控件会连同截图交给模型，帮助它区分输入页、结果页、加载状态和遮挡弹窗。

## 5 分层验收

| 用例 | 指令或操作 | 通过依据 |
| --- | --- | --- |
| B01 入口 | 分别启动两个浏览器的固定公开网址 | 前台包名正确，并看到指定页面；仅 aa 返回成功不够 |
| B02 华为搜索 | 使用华为浏览器搜索“OpenHarmony 官网”，告诉我最相关结果标题和摘要 | 搜索由 App 发起，页面真实出现关键词，回答与当前结果一致 |
| B03 夸克搜索 | 使用夸克浏览器搜索“OpenHarmony 官网”，告诉我最相关结果标题和摘要 | 同上，并核对前台确为夸克 |
| B04 改关键词 | 将其中一次改为“OpenHarmony 文档” | 新请求实际替换关键词，回答来自新结果 |
| B05 打开结果 | 搜索后打开官网，返回实际看到的页面名称和地址 | 结果页跳转成功，来源能在页面或地址栏核对；不能编造网址 |
| B06 返回 | 任务结束后回到 ClawMate | 当前宿主包正确、显示准确终态与正文 |
| B07 取消与失败 | 任务过程中返回 ClawMate 点击停止；另测无效模型地址后恢复 | 不再执行新动作，取消/失败不显示成功，恢复配置后可重试 |

先通过 B01–B03，再把 B05 作为进阶用例；“浏览器打开了”“搜索结果出现了”“打开官网了”是三个不同的通过条件。搜索摘要未显示完整来源链接时，允许明确写“链接未确认”，不能拿模型猜出的域名充当证据。

## 6 常见故障

- **App 不选择浏览器**：检查 `/capabilities` 中的实际目录；文件已改但桥没重启时仍是旧目录。
- **夸克只开首页**：检查是否带 `ohos.want.action.viewData` 和合法的 `startUri`。
- **文字粘到旧查询后面**：使用 `replace: true`，先确认搜索框确实获得焦点。
- **输入后不查询**：用 `submit: true`，并实际核对结果页，不以输入回执判断成功。
- **连续点击搜索**：检查页面是否已经有结果、是否被权限弹窗遮挡、是否仍在加载。新版本向模型提供当前可见文字，并要求不要重复同一无效点击。
- **网站要求额外权限、登录或验证码**：能拒绝或关闭时先关闭；必须完成才能继续时暂停并交给用户，不自动授予权限或绕过验证。
- **到 12 步仍未完成**：记录暂停和最后页面，缩小任务范围；不能通过提高步数掩盖重复点击。

## 7 本轮验收结果

### 7.1 电脑端可复现命令

本工程提供 `scripts/check-browser.py`，用于在同一调试桥上独立验收浏览器能力，不依赖手机 App 保持后台执行。先在本地创建模型配置，内容如下，使用实际值替换占位符，不提交真实密钥：

```json
{"base":"http://你的模型服务","model":"你的模型名","key":"你的密钥"}
```

然后运行：

```bash
python3 scripts/check-browser.py \
  --bridge http://127.0.0.1:18765 \
  --bridge-token-file bridge/token.local \
  --model-config model.local.json \
  --browser 华为浏览器 --query 'OpenHarmony 官网' \
  --output reports/huawei-browser
```

将 `--browser` 换为 `夸克浏览器`，输出目录也换一个，即可分别验收。默认模式为：URI 提交查询 → 等真实结果出现 → 模型只读摘要 → 返回 ClawMate。`--mode agent` 用于另行尝试 GUI 多步控制，不是默认读取验收的通过依据。

输出包含实际可见文字、模型摘要、最终公开页面截图与清理结果；不记录请求密钥。该命令明确属于**电脑编排验收**，不能替代手机 App 后台流程的验收。

### 7.2 手机 App 的验收方式

在手机选择“设备任务”，分别输入 B02/B03 指令。查看日志中实际打开的应用、每步操作、最终状态和结果，再核对页面。若显示短时后台申请失败，保留真实错误码和额度，不以电脑端通过覆盖这个失败。

## 8 本轮实际结果

验收环境：Pura 80，HarmonyOS 7.0.0.109，API 26。两个浏览器入口均通过设备实际查询核对。

| 项目 | 实际结果 |
| --- | --- |
| 目录与公开网页启动 | 两个浏览器均通过；夸克使用 viewData 后按 URI 打开 |
| 华为浏览器 URI 查询与读取 | 通过；约 9.4 秒，读取 OpenAtom OpenHarmony 项目介绍，实际可见来源 gitee.com |
| 夸克浏览器 URI 查询与读取 | 通过；约 8.8 秒，读取 OpenHarmony 项目介绍，实际可见来源 gitee.com |
| 夸克更换关键词 | 通过；改为“OpenHarmony 文档”后约 9.1 秒，页面与回答更新为文档相关结果 |
| 华为浏览器电脑 GUI 代理 | 一次通过；约 54.7 秒、7 个动作后读到结果并返回，不代表所有多步任务稳定 |
| 搜索后继续打开官网 | 首次在 12 步上限暂停，未作为已通过项 |
| 手机 App 发起华为浏览器查询 | 最终复测暂停，短时后台申请失败 |
| 手机 App 发起夸克查询 | 最终复测暂停，短时后台申请失败 |
| 构建与回归 | HarmonyOS 签名构建通过；40 项 App 行为测试和 20 项 Python 测试通过 |

系统诊断实测：短时后台剩余额度为 `14925 ms`，申请返回 `9900002`，消息为 remaining time insufficient。这是剩余运行时间不足，不是“浏览器未接入”或“缺少浏览器权限”。未通过改用不匹配的长时任务类型、改系统权限或清除数据来绕过系统约束。

额度查询 `getTransientTaskInfo` 是 API 20 起的接口；迁移到课程 OH API 18 时，要保留失败回退或替换诊断实现，不能把额度查询失败当作整个应用无法运行。

因此，课堂可以先用电脑编排命令验收真实浏览器能力；如果要求所有任务都由手机 App 在后台持续编排，需要另行设计符合系统约束的执行方式，例如把耗时编排交给已经存在的电脑桥。该架构调整不属于本轮已完成内容。

详细证据保存在本机 `reports/browser-acceptance/`，该目录不进入源码分发包。所有通过结论区分 GUI 输入、URI 查询、电脑编排与手机 App 编排，不把它们混为一个“已完成”。
