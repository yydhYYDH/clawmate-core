# ClawMate HarmonyOS 起始工程

面向 **Pura 80 / HarmonyOS 6 及以上** 的独立 ArkTS 起始工程，供学生阅读、运行，再探索迁移到 OpenHarmony。本次已在 Pura 80 / HarmonyOS 7 运行。它有真实的资料问答请求、系统相册与文件选择、本地笔记，以及可选的电脑调试桥 GUI Agent。打开本目录即可作为一个独立 DevEco Studio 工程使用，不依赖上层 OH 工程源码。

**已通过签名安装、HarmonyOS 7 冷启动、真实模型中文问答、文档导入与资料问答、笔记重启恢复和请求取消测试。** 尚未全部通过的项目和详细结果见 [HarmonyOS 7 真机记录](docs/06-harmonyos7-validation.md)。跨 App 控制通过“App → 电脑调试桥 → HDC → 手机”实现，需要电脑始终连接手机；不是手机内部 self-HDC，也不保证普通 App 获得跨应用控制权限。

按用户要求，`core/TeacherDefaults.ets` 已内置教师模型地址、模型名和课堂密钥，可直接发起资料问答。手动填写的其他密钥仍不写入首选项。**对外发布学生材料前，应替换或移除内置凭据；不能把本教师测试版直接当作不含凭据的公开模板。**

## 从这里开始

1. 教师先按 [首次运行指南](docs/01-first-run.md) 在 Pura 80 配置签名并运行。
2. 学生阅读 [代码地图与调用链](docs/02-code-map.md)，先跑资料问答、文件和笔记。
3. 教师完成真实设备控制检查后，再开放设备任务实验。
4. 学生按 [4 小时探索迁移任务](docs/03-student-lab.md) 将工程改到课程 OH 开发板。
5. 使用 [验收清单](docs/04-acceptance.md) 记录真实结果，不把测试替身等同于真机通过。
6. 需要跨 App 查询网页时，按 [浏览器接入与验收](docs/07-browser-integration.md) 配置华为浏览器和夸克。

## 已实现功能

| 功能 | 实现方式 |
| --- | --- |
| 中文输入、对话、正文复制、日志 | 原生 ArkUI 页面，消息与任务状态分开 |
| 资料问答 | 可配置 OpenAI 兼容 `/v1/chat/completions`，支持文本和视觉模型输入 |
| 相册图片 | 系统 PhotoViewPicker；返回 App 后确认导入，生成缩略预览和沙箱副本 |
| 文本文件 | DocumentViewPicker，UTF-8 `.txt/.md`；限 256 KiB，按实际读取长度解码 |
| 附件移除 | 未发送前可移除；提交的是文本与图片字节，不是设备 URI |
| 笔记 | 保存回复与资料引用；原子替换索引，正常退出后可恢复；最多 50 条 |
| 请求停止、失败恢复 | 取消主动结束等待；不执行迟到模型返回的动作；超时后恢复输入 |
| 公开应用启动检查 | 设置页填写已确认的 bundleName 和 Ability，调用 startAbility |
| GUI 设备任务 | 目录规划 → 截图 → 视觉模型 → 校验动作 → 桥接执行 → 新截图核对 |
| 浏览器查询 | 已提供华为/夸克目录、公开 URI 查询模板和搜索框替换/提交动作；手机后台与电脑编排分开验收 |
| 后台约束 | 按系统实际短时额度限时执行；额度不足或到期明确暂停 |
| 课堂测试服务 | 真实 HTTP 请求检查，明确标注“非大模型”；不伪造 GUI 执行成功 |

资料问答每次发送当前问题和当前附件，**未实现完整多轮会话上下文**。聊天记录仅本次运行有效，保存的笔记才会持久化。每种附件最多一个；图片原文件限 10 MiB，发给模型的是长边不超过 1024 像素的 JPEG 预览。

## 构建与检查

已验证工具组合：DevEco Studio 26.0.0.851、HarmonyOS SDK 26.0.0.105、Hvigor 模型 6.0.2。编译 SDK 为 `26.0.0`，最低和目标版本均为 `6.0.0(20)`；这三个值含义不同，不代表手机必须升级到 API 26。旧手机的实际运行兼容性仍以真机为准。

macOS 当前环境：

```bash
bash scripts/build.sh
bash scripts/check.sh
```

其他安装位置可设置 `STARTER_DEVECO` 为 DevEco Studio 的工具根目录；Windows 建议使用 IDE 导入运行，并使用配套 Node/Python 执行检查。电脑端测试不会调用真实手机 SDK 服务。

配置签名后产物为 `entry/build/default/outputs/default/entry-default-signed.hap`，本次已使用它安装到 Pura 80。未配置签名时仅生成 `entry-default-unsigned.hap`，不能直接用于手机安装。每位开发者需要自己的调试签名与设备授权；源码分发包移除个人签名路径和签名配置。

## 工程目录

```text
AppScope/                          应用标识与资源
entry/src/main/ets/
  pages/Index.ets                  对话、笔记、设置
  entryability/EntryAbility.ets    上下文和前后台生命周期
  core/                           模型请求、任务循环、数据校验、取消
  platform/                       文件、存储、HTTP 和设备执行接口
bridge/server.py                  真实 HDC 电脑调试桥
bridge/classroom_model.py         明确标注的课堂请求检查服务
fixtures/                         正常与异常测试资料
tests/                            电脑端行为测试
docs/                             教师与学生资料
scripts/                          构建、检查与资料生成
```

本源码保留可阅读的平台接口，未附带 OH 完整迁移答案。学生需要自己分析 SDK、设备类型、系统服务、URI 生命周期和执行器差异，不能只修改 runtimeOS 就声称完成迁移。
