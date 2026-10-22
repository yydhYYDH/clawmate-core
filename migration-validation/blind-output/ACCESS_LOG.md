# 盲测资源访问日志

- 初始命令仅在独立工作目录读取 MIGRATION_PROMPT.md、列出文件；未读取 reports 的历史验收内容。
- 输入冻结 INPUT_SHA256.json 对 starter 源码、配置、文档、测试逐文件 SHA-256（排除 Git、reports、依赖）。
- 授权外部资源：/Users/bingyubai/Library/OpenHarmony/Sdk API 23；/Applications/DevEco-Studio.app/Contents 工具链；公开 OpenHarmony 官方 HDC 协议；目标设备只读元数据。具体命令随实施追加。

- 官方协议读取：https://raw.githubusercontent.com/openharmony/developtools_hdc/OpenHarmony-5.1.0-Release/src/common/define.h（urllib，保存 official-hdc）

- 官方协议读取：https://raw.githubusercontent.com/openharmony/developtools_hdc/OpenHarmony-5.1.0-Release/src/common/define_plus.h（urllib，保存 official-hdc）

- 官方协议读取：https://raw.githubusercontent.com/openharmony/developtools_hdc/OpenHarmony-5.1.0-Release/src/common/session.h（urllib，保存 official-hdc）

- 官方协议读取：https://raw.githubusercontent.com/openharmony/developtools_hdc/OpenHarmony-5.1.0-Release/src/common/session.cpp（urllib，保存 official-hdc）

- 官方协议读取：https://raw.githubusercontent.com/openharmony/developtools_hdc/OpenHarmony-5.1.0-Release/src/common/serial_struct.h（urllib，保存 official-hdc）

- 官方协议读取：https://raw.githubusercontent.com/openharmony/developtools_hdc/OpenHarmony-5.1.0-Release/src/daemon/daemon.cpp（urllib，保存 official-hdc）

- 官方协议读取：https://raw.githubusercontent.com/openharmony/developtools_hdc/OpenHarmony-5.1.0-Release/src/host/server.cpp（urllib，保存 official-hdc）

- 官方协议读取：https://raw.githubusercontent.com/openharmony/developtools_hdc/OpenHarmony-5.1.0-Release/src/common/common.h

- 官方协议读取：https://raw.githubusercontent.com/openharmony/developtools_hdc/OpenHarmony-5.1.0-Release/src/common/serial_struct_define.h

- 官方目录 API：https://api.github.com/repos/openharmony/developtools_hdc/contents/src/common?ref=OpenHarmony-5.1.0-Release

- 官方源文件：https://raw.githubusercontent.com/openharmony/developtools_hdc/OpenHarmony-5.1.0-Release/src/common/define_enum.h

- 官方源文件：https://raw.githubusercontent.com/openharmony/developtools_hdc/OpenHarmony-5.1.0-Release/src/daemon/shell.cpp

## 实际 SDK/工具链读取

- 命令工作目录始终显式 `/private/tmp/clawmate-oh-blind-20261022`；未读取默认课程目录、其他课程/助手仓库、父会话、Git 历史或参考实现；未派生子代理。
- `ls /Users/bingyubai/Library/OpenHarmony/Sdk`、`ls .../23`、`rg --files .../23`：确定本机 API23 的 ets/js/native/toolchains 路径。
- SDK ETS 实际读取文件：`ets/oh-uni-package.json`；`ets/api/@ohos.net.socket.d.ts`；`ets/api/@ohos.inputMethod.d.ts`；`ets/api/@ohos.resourceschedule.backgroundTaskManager.d.ts`；`ets/api/@ohos.multimodalInput.keyCode.d.ts`；`ets/api/@ohos.app.ability.wantAgent.d.ts`；`ets/kits/@kit.NetworkKit.d.ts`；`ets/kits/@kit.AbilityKit.d.ts`。使用 cat/sed/rg 检查接口签名、since和组合键值。
- DevEco 工具读取与执行：`tools/ohpm/bin/ohpm install`；`tools/hvigor/bin/hvigorw --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap --no-daemon`；`tools/node/bin/node --test tests/*.test.cjs`；测试 loader 读取工具链自带 TypeScript 转译器；`jbr/Contents/Home/bin/java -version`；Python plistlib 读取 DevEco `Info.plist`。工具写标准依赖/Hvigor缓存经环境自动审批允许；没有读取其他项目缓存源码。版本记录见 blind-logs/toolchain.json。
- SDK HDC：最初沙箱 `hdc list targets` 返回 Connect server failed，获准执行只读设备枚举后返回 `[Empty]`。随后两次只读探测均无目标；`hdc -v` 的结果记录在 toolchain.json；最终 device-preflight.log 退出77，未执行设备配置、安装、卸载或清数据。
- Python/系统 shell/sha256/zip等只用于独立目录文件和构建检查；shell 引用测试通过 `/bin/sh -c printf` 检验特殊字符，没有执行用户文字内容。

## 公开官方资料查询

- 先以 web 搜索官方 developtools_hdc 仓库及 HDC handshake/SessionHandShake。仅使用 OpenHarmony 官方源文件实现协议；搜索返回的非官方概览未作为实现依据。
- 查询官方 `openharmony/testfwk_arkxtest/README_zh.md` 的 uiInput 文档，核实 `inputText x y text` 与当前焦点 `text` 的区别；来源 https://github.com/openharmony/testfwk_arkxtest/blob/master/README_zh.md 。因此将无坐标注入修正为 `uitest uiInput text`；具体目标设备能力仍未验证。
- 公开源文件 urllib 首次受沙箱 DNS 限制，后获准网络读取。404 的 `src/common/serial_struct.cpp`、`src/common/unity.cpp`、`src/common/shell.cpp`、`src/daemon/unity.cpp` 未提供内容；成功文件均在 official-hdc 内并保留原版权头。
- 官方目录 API：https://api.github.com/repos/openharmony/developtools_hdc/contents/src/common?ref=OpenHarmony-5.1.0-Release 。源链接逐条记录于上文。没有克隆或查看 Git 历史。

## 检查和冻结

- 所有新增 build/check/device 日志存于 blind-logs；保留失败编译和首次测试失败日志，没有用历史 reports 内容替代本次结果。
- 移除起始源码中 DEFAULT_MODEL_KEY 常量的值，未打印、记录或复制原密钥。资料问答设置与模型名保留；模型密钥由运行时界面输入。
- 最终使用 scripts/freeze-outputs.py 校验 MIGRATION_PROMPT 未变并生成输出清单、源码包和 SHA-256。原 reports、.git、构建缓存和依赖不进入交付源码包。
