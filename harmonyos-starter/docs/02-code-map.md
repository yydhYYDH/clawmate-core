# ClawMate 代码地图与学习顺序

## 1 两条主流程

资料问答：

```text
Index 选图/选文件 → Files.select... 返回 URI
  → 用户返回后确认导入
  → Files.importSelected → 校验/读取/解码 → 沙箱副本与预览
  → Index.send → makeQuestion → ModelService → HttpJson
  → 显示回复 → Repository.saveNotes → 正常重启加载
```

设备任务：

```text
Index.send → AgentRunner
  → DeviceExecutor.open → 读取可用目录与能力 → 创建桥接会话
  → 模型规划目标应用 → startApp
  → 截图 → 模型决定动作 → 本地校验 → 执行 → 新截图核对
  → success / failed / suspended / cancelled
  → 取消执行器 → 尝试返回宿主 → 关闭会话
```

## 2 按什么顺序阅读

| 顺序 | 文件 | 要回答的问题 |
| --- | --- | --- |
| 1 | `core/Types.ets` | 消息请求、附件、笔记、动作和结果分别保存什么 |
| 2 | `pages/Index.ets` | 用户操作如何触发导入、请求、停止和笔记保存 |
| 3 | `core/Domain.ets` | 如何保证文件内容真的进入请求；如何拒绝非法模型动作 |
| 4 | `platform/Files.ets` | URI、文件描述符、沙箱副本、缩略图各有什么生命周期 |
| 5 | `platform/Repository.ets` | 为什么写临时索引再重命名；为什么密钥不持久化 |
| 6 | `core/RunScope.ets`、`platform/HttpJson.ets` | 如何让停止立即结束等待，避免迟到响应继续执行 |
| 7 | `core/AgentRunner.ets` | 为什么每一步后都需要新截图，而不是点击后就报告完成 |
| 8 | `platform/DeviceExecutor.ets` | 哪些是业务约定，哪些是平台实现 |
| 9 | `platform/HarmonyBridgeExecutor.ets`、`bridge/server.py` | 手机 HTTP 与电脑 HDC 是怎样连起来的 |
| 10 | `platform/Runtime.ets`、`entryability/EntryAbility.ets` | 退后台、页面销毁、额度到期分别如何停止任务 |

## 3 哪些代码通常能共用

Domain 的数据校验、请求构造、终态规则和 AgentRunner 的任务流程可作为共享逻辑。HTTP、图像、文件和 Preferences 使用两边都有的接口时也可能无需重写，但需要核查 API 起始版本及设备服务。

设备执行是最清楚的替换点。源版 `HarmonyBridgeExecutor` 依赖外部电脑；OH 开发板可以按课程提供的环境实现另一个 `DeviceExecutor`，例如接入 self-HDC。不要将电脑桥的 IP 简单替换为 `127.0.0.1`，那不会自动产生本机 HTTP 服务或 HDC 客户端。

## 4 设计取舍

- 界面一个文件承载三个页面，降低初读时的跳转成本；进一步拆组件是选做。
- 每次只发当前问题与附件，避免在首次实验中引入复杂的会话裁剪；完整上下文属于扩展。
- 文本限 256 KiB，先整文件读取再严格 UTF-8 解码；这样不会在多字节字符边界截断解码。读取本身仍处理短读和真实长度。
- 图片保存原副本，预览及发送使用缩略 JPEG，避免直接上传设备 URI。
- 笔记只引用 App 内部文件；删除一条笔记时先检查是否仍被其他笔记或当前消息引用。
- 未保存的资料副本不会自动批量清理；进程异常结束可能留下未引用文件，存储清理作为探索题。卸载会清除本机数据，不能以卸载重装测试持久化。
- 取消不会撤销已经执行的设备动作；在两个端点都检查取消，并阻止后续命令。
- 手动输入的凭据仅内存保存；教师测试默认密钥按用户要求放在 `TeacherDefaults.ets`，重启后恢复该默认值。对外分发前替换或移除；进一步的凭据存储需单独设计。

## 5 阅读后回答

1. 为什么 Picker 返回后还要“确认导入”？
2. 一个临时 URI 为什么不能直接保存为长期资料地址？
3. 为什么发给模型的是图片字节，而不是手机路径？
4. 把 `destroy()` 调用成功当作“等待已结束”有什么问题？
5. 为什么系统允许电脑做 UI 测试，不代表普通 App 内可以直接执行相同动作？
6. 学生写出 OH 执行器后，AgentRunner 中哪些内容应该保持不变？
