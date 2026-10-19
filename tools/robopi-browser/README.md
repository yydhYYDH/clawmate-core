# RoboPi 浏览器

为 SysLong RoboPi / OpenHarmony 5.1（API 18）提供独立的 ArkWeb 浏览器应用，包名 `com.clawmate.browser`，桌面名称「RoboPi 浏览器」。设备已预装 `com.ohos.arkwebcore` 5.1.0.105，无需替换系统引擎。

支持输入 HTTP(S) 网址或关键词（百度搜索）、清空地址、前进、后退、刷新。网页下载通过 ArkWeb 下载委托保存到应用私有 files 目录，界面显示保存路径。下载后自动安装应用、公共下载目录和文件导出界面暂未实现。证书校验失败时中止访问。

构建：

```bash
bash tools/robopi-browser/build-signed.sh
```

脚本沿用本仓库开发板输入法的本地 SDK 构建和公共 OpenHarmony 开发证书签名方式；可设置 `BROWSER_DEVECO`、`BROWSER_SDK`、`BROWSER_SDK_API` 覆盖工具链路径。公共 SDK 证书仅用于开发板验证。

安装和启动：

```bash
hdc install -r tools/robopi-browser/entry/build/default/outputs/default/robopi-browser-signed.hap
hdc shell param set web.oop.gpu true
hdc shell aa start -a EntryAbility -b com.clawmate.browser
```

地址栏已有内容时先点击「清空」，再输入关键词并点击「打开」。

## 实机验证（2026-10-15）

已在连接的 SysLong RoboPi 上完成编译、公共 SDK 证书签名验证、安装、百度首页访问及关键词 `OpenHarmony` 的搜索。搜索结果包含 OpenAtom OpenHarmony 官网，原生控件和网页实际画面均已用设备截图验证。

该固件的默认 GPU 配置（`web.oop.gpu=None`）下，Web 的 DOM 与网络请求正常，但网页画面为空白，首次启动还可能停留在启动图。将 `web.oop.gpu` 设为 `true` 后会启动独立的 `:gpu` 进程，网页恢复绘制。应用先显示原生控件，再延迟初始化 Web，以保证启动首帧呈现。

`web.oop.gpu` 是设备全局、非持久参数，重启设备后可能需要重新执行上面的设置命令。若浏览器已运行，设置后需先执行 `hdc shell aa force-stop com.clawmate.browser` 再启动。恢复固件原配置可执行 `hdc shell param set web.oop.gpu None`。排查时修改的 `web.optimization`、`web.ohos.vulkan` 已分别恢复为原值 `true`、`None`。

网页下载处理已接入，但文件下载与导出本次未做实机验收。当前验证范围为浏览和搜索。
