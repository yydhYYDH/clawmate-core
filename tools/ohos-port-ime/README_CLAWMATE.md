# 独立中文输入法

基于 https://gitee.com/ohos_port/applications_inputmethod ，上游提交见
`UPSTREAM_COMMIT`。保留上游 Apache-2.0 LICENSE 及源文件版权声明。

本地适配：

- 独立包名 `com.clawmate.inputmethod`，不覆盖 `com.example.kikakeyboard`。
- 独立服务名 `ClawMateInputMethod`，与 Kika 的 `ServiceExtAbility` 区分。
- 升级到本机 Hvigor 6.0.2 工程格式，编译 SDK 23，最低 API 18。
- 移除上游个人签名配置，使用公开 SDK 开发证书为开发板签名。
- 修复物理键盘空格：中文有候选时选词，英文或无候选时插入空格。
- 修复中文模式数字被拼音引擎忽略的问题；补齐数字小键盘 0–9 的键码映射。
- 主键盘和小键盘均可输入数字；中文有对应候选时按 1–7 选词，无对应候选时直接输入数字。
- 保留上游单按并松开 Shift 切换中英文逻辑。

## 构建和安装

```sh
bash tools/ohos-port-ime/build-signed.sh
hdc -t <设备ID> install -r tools/ohos-port-ime/entry/build/default/outputs/default/clawmate-pinyin-signed.hap
```

可通过 `IME_DEVECO`、`IME_SDK` 调整本机路径。开发证书仅用于开发板测试。
源码中的编译 API 固定为 23；改变 SDK API 时也需调整 build-profile.json5。
原生引擎、字典及上游许可均包含在此工程中。

首次启用：桌面打开「中文输入法」→「默认输入法」→勾选「中文输入法」。
ClawMate 页面下方会显示「中文输入法」。原 Kika 仍可在列表中选回。
此次设备上的 ClawMate 内置选择框点击中文项未成功切换；输入法自身的
管理页 Radio 选择可正常启用，因此首次启用使用该管理页。

## 实机验收（2026-10-14）

SysLong RoboPi / OpenHarmony 5.1.0.107 / API 18。通过 `uitest uiInput keyEvent`
发送按键，触发输入法 KeyboardDelegate，未使用直接中文文本注入。

| 项目 | 结果 |
|---|---|
| 原 Kika 共存 | InputMethodService 同时列出新旧两项 |
| 拼音候选 | `nihao` 显示候选「你好」 |
| 空格选词 | 空格后聊天输入框为「你好」 |
| 拼音退格 | 删除 `rnihao` 六个字符后可重新输入 `nihao` |
| 已上屏退格 | 「你好」退格后变为「你」 |
| Shift 切英文 | 单按左 Shift 后 `a`、空格、`b` 上屏为 `a b` |
| Shift 切中文 | 再按左 Shift，`ni` 恢复拼音「你」候选 |
| 无系统设置按钮 | ClawMate 界面布局确认仅保留「切换输入法」 |

上述自动验收使用设备注入按键；用户随后确认外接罗技键盘手动测试也正常：
`nihao` + 空格输入「你好」，单按并松开 Shift 后可输入英文 `abc`。
验收布局文件暂存于 `/tmp/clawmate-install/ime-*.json`。

### 数字键修复验收（2026-10-14）

- 编译、开发签名校验、覆盖安装均通过。
- 通过 `uitest uiInput keyEvent` 验证中英文模式主键盘数字行及小键盘 0–9，布局回读与输入一致。
- 中文模式 `nihao` 后按主键盘 1 上屏「你好」，随后两组数字均正常输入。
- `node --test tests/ime.test.cjs` 三项回归测试通过，覆盖中英文数字输入、两组键码选词、候选翻页下标及无对应候选时的数字输入。
- 实机证据位于 `/tmp/clawmate-install/ime-digits-*.json`；本次使用系统按键注入，外接键盘手动复测待用户确认。
