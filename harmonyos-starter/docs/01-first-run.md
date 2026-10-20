# 在 Pura 80 上首次运行

2026 年 10 月 20 日补充：目标机已升级为 HarmonyOS 7，原工程的编译 API 26、最低/目标 API 20 保持不变即可签名安装并运行。本教师测试版已按用户要求内置模型默认配置，直接发送资料问题即可；下面手动配置用于更换服务和课堂检查服务。真机结果见 [最新记录](06-harmonyos7-validation.md)。

## 1 准备条件

- Pura 80，运行 HarmonyOS 6；在设置中记录完整系统版本与补丁号。
- 安装本工程所需 SDK 的 DevEco Studio。当前工程使用 HarmonyOS SDK 26.0.0 编译，最低/目标为 HarmonyOS 6.0.0 / API 20。
- 用于申请调试签名的华为开发者账号及目标调试设备授权。
- USB 数据线，手机与电脑可通信；需要调用本地课堂服务或调试桥时，手机还需能访问电脑的局域网 IP。

不要求刷机、root 或修改手机系统。使用公开调试方式，先完成普通 App 运行；调试命令可用性另外核查。

## 2 导入与签名

1. DevEco Studio 打开 `harmonyos-starter` 本身，不打开上层 OH 工程。
2. 等待依赖同步，确认产品 `default` 的运行平台为 HarmonyOS。
3. 手机按系统设置开启开发者模式和 USB 调试，连接电脑并接受调试授权；以 IDE 中能看见目标设备为准。
4. 在 `File → Project Structure → Signing Configs` 配置调试签名。使用自动签名或手动配置与本机、包名匹配的证书和 Profile，再把签名关联到产品。
5. 选择 Pura 80，点击 Run。IDE 完成构建、签名、安装并启动。

若本机原有工程设置了 `DEVECO_SDK_HOME` 指向 OH SDK，注意本工程需要 HarmonyOS SDK。随附构建脚本显式使用 DevEco 的 HarmonyOS SDK 路径；不要把上层工程的 `local.properties` 或 OH 开发证书复制过来。

先验收空页面启动与中文输入，再配置服务。未签名 HAP 只用于检查编译和打包；不要把它当作真机安装成功证据。

## 3 没有模型服务时先跑课堂检查

随附服务不是 LLM，它检查实际 HTTP 请求里的文本和图片，并返回明确标注的测试响应，方便先验证导入、请求、保存笔记的链路。

在本工程目录生成临时令牌：

```bash
python3 - <<'PY'
from pathlib import Path
import secrets
Path('bridge/token.local').write_text(secrets.token_urlsafe(32))
PY
```

查看该文件，稍后在 App 内填写。然后启动服务。下面 `192.168.1.10` 只是示例，替换为**电脑实际的局域网地址**：

```bash
python3 bridge/classroom_model.py --bind 192.168.1.10 --port 8766 --token-file bridge/token.local
```

App 设置填写：

| 字段 | 内容 |
| --- | --- |
| 模型服务地址 | `http://192.168.1.10:8766/v1`，替换电脑 IP |
| 模型名称 | `classroom-inspector` |
| API Key | `bridge/token.local` 中的令牌 |
| 支持图片 | 打开，以验证真实图片字节进入请求 |

点“保存设置”。服务地址与模型名会持久化，手动输入的密钥和桥令牌仅本次运行有效；重启后模型密钥恢复教师默认值，桥令牌需要重新输入。服务端默认只绑定 localhost；真机访问时须显式指定电脑的可达地址，或由教师明确设置 HDC 反向端口转发。若目标系统限制局域网或明文 HTTP，请记录实际错误并使用可达的 HTTPS 服务，不改成假响应绕过问题。

把 `fixtures/hello-zh.txt` 放进手机可从文件选择器访问的位置，把 `photo-grid.png` 通过系统支持的方式导入图库。实际确认图库索引完成；只用 HDC 把文件放到某目录，不保证它会出现在相册。

在 App 中执行：文件 → 选 `hello-zh.txt` → 返回 → 确认导入 → 提问“资料口令是什么”。回复应显示本次请求包含“蓝色风车”。移除附件再问，回复应显示未包含资料口令。再试图片输入，服务仅报告收到图片字节，不理解图片内容。

## 4 换成真实模型

填写教师提供的 OpenAI 兼容地址、模型名和 API Key。普通资料问答可用文本模型；图片问答和设备任务需要真实视觉模型。当前客户端使用一次性 JSON 响应，不支持 SSE 流式输出。

先测试“你好”，再加文本资料，最后加图片。教师统一测试数据，不把私人相册当课堂素材。单次请求最长约 30 秒，用户可停止，失败后可重试；不会自动重试可能产生设备动作的请求。

## 5 公开应用启动检查

在设置页填写一个教师已经确认、允许从外部启动的目标 bundleName 和 abilityName，点“发起启动”。成功回调只表示请求被接受，仍需检查目标应用是否真的出现在前台。

不要把 OH 的 `com.ohos.*` 包名直接当成 Pura 80 的入口。也不要假定所有安装应用都能由普通 App 任意枚举或启动。具体可用入口按目标应用文档和实际设备结果确定。

## 6 完整 GUI 任务的电脑调试桥

这部分需要电脑保持连接手机。先在电脑终端确认 HDC 可识别 Pura 80，并记录唯一目标 ID：

```bash
/你的SDK路径/toolchains/hdc list targets
```

将 `bridge/apps.example.json` 复制为 `bridge/apps.local.json`，用手机上**实际核对过的**应用包名与 Ability 替换示例条目。示例的 `com.example.replace_me` 不是可运行的华为系统包名。host 默认应与本 App 的包名和 EntryAbility 一致。

示例启动命令，替换 IP、HDC 路径和设备 ID：

```bash
python3 bridge/server.py \
  --hdc /你的SDK路径/toolchains/hdc \
  --target 你的Pura80设备ID \
  --apps bridge/apps.local.json \
  --token-file bridge/token.local \
  --bind 192.168.1.10 --port 8765
```

默认尝试 `uitest screenCap -p`。仅当实际确认目标手机支持 `snapshot_display` 时，才使用 `--capture snapshot_display`。两种方式都未验证；若手机不支持这些调试命令，则需要改写 `bridge/server.py` 的设备实现，不能声称 GUI 功能已完成。

先分别检查：

```bash
/你的SDK路径/toolchains/hdc -t 你的设备ID shell uitest uiInput help
/你的SDK路径/toolchains/hdc -t 你的设备ID shell uitest screenCap -p /data/local/tmp/clawmate-probe.png
```

确认支持截图、click、swipe、text、keyEvent；图片要实际拉回并打开检查。测试输入前手动聚焦教师测试 App 的输入框，逐项检查中文与特殊字符。不能因为工具存在就推断所有操作可用。

App 设置填桥地址 `http://电脑IP:8765` 和令牌，模型改成真实视觉模型。切到“设备任务”，输入一个范围小、容易核对的任务，例如在配置好的计算器中计算 `12 × 34`。相册与文档附件只用于资料问答，不进入设备任务。

电脑调试桥只接受配置的目标应用和固定动作，不接受任意 shell 命令。会话 180 秒后停止接收动作并可被下一会话回收。一个已经送到设备的点击或输入不能撤销；取消保证后续动作停止，不表示回滚已执行操作。

## 7 后台行为与首次验收

任务打开其他 App 后，ClawMate 会进入后台。当前实现仅申请系统短时任务，并按系统返回的额度限制运行；申请失败或额度到期时明确暂停。没有为了保活声明不匹配的长时任务模式。

Pura 80 的实际额度和调试桥动作能力必须实测；若复杂任务超时，这是当前实验版本的能力边界。回到 ClawMate 后可以停止任务；最终收尾通过电脑桥尝试返回宿主，失败时显示日志并保留原结果。

首次运行按 [验收清单](04-acceptance.md) 逐项记录，未通过项保留原始错误码、发生步骤与截图。仅通过“课堂测试服务”不能证明视觉决策或实际设备操作可用。

## 8 官方资料

- [编写与调试应用](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-writing-and-debugging)
- [开发入门与签名说明](https://developer.huawei.com/consumer/cn/develop-novice-guide/)
- [文件管理官方 Codelab](https://gitee.com/harmonyos_codelabs/FilesManger)
- [UI 自动化测试服务](https://developer.huawei.com/consumer/cn/testing/get-started/)

文档核查日期：2026 年 10 月 20 日。在线文档可能切换至新版本，实际 API 以课程冻结 SDK 的声明和目标设备为准。
