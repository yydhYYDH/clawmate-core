# Self-HDC：设备用 HDC 控制自己

本文记录 ClawMate Core 在 OpenHarmony 设备上「App 通过 HDC 控制本机」的原理、
设备侧准备步骤、以及 App 实际执行的 shell 命令。所有命令都在目标设备上执行。

## 0. 原理

App 运行在手机上，因此对 App 来说 `127.0.0.1` 就是手机自己。App 不 fork 子进程，
而是用 `@kit.NetworkKit` 的 TCP socket 直接连到**本机 hdcd 的 TCP 端口**，
按 HDC 二进制协议完成握手/认证，然后发 shell 命令，从而驱动：

- 截图：`snapshot_display`
- 触控：`uitest uiInput`
- 应用管理：`aa` / `bm`

链路：

```
App(手机) --TCP 127.0.0.1:8710--> hdcd(手机) --sh--> snapshot_display / uitest uiInput / aa
```

PC 不参与运行时控制。

## 1. 目标设备信息（本次实机）

| 项 | 值 |
|---|---|
| 型号 | SysLong RoboPi |
| 系统 | OpenHarmony-5.1.0.107 |
| API | 18 |
| 主屏 | 800x1280（另有 1920x1080 外接屏 screen[1]） |
| hdc UDID | `d6290343394136313113bd1c31cb9c00` |
| 权限 | `hdc shell` 为 `uid=0(root)` |

## 2. 打开 hdcd 的 TCP 监听（设备侧，root）

设备默认只开 USB，`hdcd` 没有 TCP 监听。用系统参数打开（`persist.*`，重启后保留）：

```sh
# 1) 打开 TCP 模式
param set persist.hdc.mode.tcp enable

# 2) 固定端口（默认是随机端口，例如上一次是 37833）
param set persist.hdc.port 8710

# 3) 重启 hdcd 让参数生效（kill 后由 init 自动拉起）
kill <hdcd_pid>
```

验证监听已经起来（端口 8710 = 0x2206）：

```sh
cat /proc/net/tcp          # 应能看到 0.0.0.0:2206 LISTEN
netstat -lnt               # tcp 0 0 0.0.0.0:8710 LISTEN  <hdcd>
```

> 这是 hdcd 自己的 TCP 模式，**不是** UI 里的「无线调试」，所以不需要 WiFi IP、
> 也不需要配对码；App 走 loopback 即可。

## 3. 依赖命令（已在设备上确认可用）

```sh
command -v aa bm snapshot_display uitest base64 id printf rm ls
# /bin/aa /bin/bm /bin/snapshot_display /bin/uitest /bin/base64 ...
```

`uitest uiInput help` 支持的子命令：

```
dircFling [velocity stepLength]
click/doubleClick/longClick <x> <y>
swipe/drag <from_x> <from_y> <to_x> <to_y> [velocity]
fling <from_x> <from_y> <to_x> <to_y> [velocity]
keyEvent <keyID/Back/Home/Power>
keyEvent <keyID_0> <keyID_1> [keyID_2]
inputText <x> <y> <text>
text <text>                 # 在已聚焦位置输入文本
```

## 4. App 使用的 shell 命令清单

### 4.1 连接自检

```sh
printf SELF_HDC_PHONE_OK; id
command -v aa && command -v bm && command -v snapshot_display && command -v uitest && command -v base64
uitest uiInput help
```

### 4.2 截图

截图先落到设备 `/data/local/tmp`，再 base64 回传，最后删除临时文件：

```sh
snapshot_display -f /data/local/tmp/self_hdc_<runId>_gui_<n>.jpeg
base64 /data/local/tmp/self_hdc_<runId>_gui_<n>.jpeg
rm -f /data/local/tmp/self_hdc_<runId>_gui_<n>.jpeg
```

实测输出：`800 x 1280` JPEG，约 42 KB。App 收到 base64 后解码、按 factor 缩放成
发给 decider 的 JPEG（默认 0.5），但坐标换算用**物理分辨率**（`screen_width/height`）。

### 4.3 打开 / 关闭应用

```sh
bm dump -n <bundleName>                               # 解析主 UIAbility
aa force-stop '<bundleName>'                          # reset_first 时先停
aa start -b '<bundleName>' -a '<abilityName>'
```

### 4.4 触控/输入（由 decider 的 action 映射）

```sh
# click / 需要先点输入框时
uitest uiInput click <x> <y>

# 清空并输入文本（聚焦后）
uitest uiInput keyEvent 2072 2017     # select-all
uitest uiInput keyEvent 2071          # clear
uitest uiInput text '<text>'
uitest uiInput keyEvent 2054          # enter 提交（默认）

# swipe（方向式，落点按屏幕比例计算）
uitest uiInput swipe <x1> <y1> <x2> <y2>

# keyevent
uitest uiInput keyEvent <code>        # BACK=2, HOME=1, ENTER=2054
```

### 4.5 坐标换算

decider 输出的 `bbox` 为归一化坐标（0–1000）。中心点换算：

```
x = clamp(bbox_x, 0, 1000) / 1000 * physicalWidth
y = clamp(bbox_y, 0, 1000) / 1000 * physicalHeight
```

再交给 `uitest uiInput click`。

## 5. 常见问题

- `Persist ... fail errNum 106`：参数未设置过，读不到属正常；可先 set 再 get。
- `hdc shell` 报 `need connect-key`：sockets 中出现多个 target 时需 `hdc -t <key>` 指定。
- 随机端口：不设 `persist.hdc.port` 时 hdcd 每次重启会换端口；App 端端口可配置。
- 无网络：设备默认只有 loopback，云端 planner/decider 需要先给 `wlan0/eth*` 配 IP。
- App 切后台：打开目标应用后本 App 进入后台，需要 `KEEP_BACKGROUND_RUNNING` +
  `backgroundTaskManager.requestSuspendDelay` 维持任务窗口。

## 6. 回滚

```sh
param set persist.hdc.mode.tcp disable
kill <hdcd_pid>
```
