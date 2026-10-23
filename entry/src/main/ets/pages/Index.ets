import { inputMethod, InputMethodListDialog } from '@kit.IMEKit';
import { AgentRunner, AgentCallbacks } from '../core/AgentRunner';
import { AgentRunError, AgentRunResult } from '../core/AgentRunState';
import { AppRuntime } from '../core/AppRuntime';
import { EndpointConfig } from '../core/EndpointConfig';
import { PhoneInputMethod } from '../core/PhoneInputMethod';
import { Logger } from '../core/Logger';
import { DshClient, DshConfig, DshFollowFrame, DshPreset, DshSession, DshWorkspace, dshAuthenticate, dshTokenFromLink, normalizeDshBase } from '../core/DshClient';

@Observed
class ChatMessage {
  id: number;
  role: string;
  paragraphs: string[] = [];
  // 流式正文：单独渲染，避免与 paragraphs 的 ForEach key 冲突。
  streamingText: string = '';
  streamBuffer: string = '';
  reasoning: string = '';
  logs: string[] = [];
  collapsed: boolean = true;
  status: string = '';
  phase: string = '';
  startedAt: number = Date.now();
  phaseStartedAt: number = Date.now();
  lastEventAt: number = Date.now();
  finishedAt: number = 0;

  constructor(id: number, role: string) { this.id = id; this.role = role; }
}

// 一个 DSH 会话在前端的完整视图：消息、帧、订阅、运行状态都按会话隔离，
// 因此多个会话可以同时跑任务。用 @Observed 让嵌套列修改也能触发刷新。
@Observed
class DshChannel {
  sessionId: string = '';
  title: string = '';
  messages: ChatMessage[] = [];
  running: boolean = false;
  stopping: boolean = false;
  phase: string = '空闲';
  activeMessageId: number = -1;
  cursor: number = 0;
  historyLoaded: boolean = false;
  historyLoading: boolean = false;
  // 状态版本号：running/phase 变化时自增，用来驱动标签栏重绘。
  // ForEach 按 key 复用节点，只改字段不会刷新。
  revision: number = 0;
  // 实例标识：用于确认各处拿到的是同一个对象（排查引用丢失）。
  instanceId: number = 0;
  unsubscribe: (() => void) | null = null;
  lastError: string = '';

  constructor(sessionId: string, title: string) {
    this.sessionId = sessionId;
    this.title = title;
    this.instanceId = Math.floor(Math.random() * 100000);
  }
}

function duration(ms: number): string {
  let seconds = Math.max(0, Math.floor(ms / 1000));
  return Math.floor(seconds / 60).toString().padStart(2, '0') + ':' + (seconds % 60).toString().padStart(2, '0');
}

// DSH 要求每条用户消息带一个客户端生成的 requestId，宿主会把它写进用户消息事件里。
function mintRequestId(): string {
  return 'req-' + Date.now().toString(16) + '-' + Math.floor(Math.random() * 0xffffffff).toString(16);
}

@Component
struct ChatMessageView {
  @ObjectLink message: ChatMessage;
  @Prop now: number = 0;
  onToggle: (id: number) => void = (_id: number): void => {};
  onSelect: () => void = (): void => {};

  private statusText(message: ChatMessage): string {
    if (message.status === 'success') { return '已完成'; }
    if (message.status === 'cancelled') { return '已取消'; }
    if (message.status === 'suspended') { return '已暂停'; }
    return '执行失败';
  }

  build() {
    Row() {
      if (this.message.role === 'user') { Blank(); }
      Column({ space: 12 }) {
        ForEach(this.message.paragraphs, (text: string, index: number): void => {
          Text(text).fontSize(15).lineHeight(23)
            .fontColor(this.message.role === 'user' ? Color.White : '#202124')
            .width('100%').copyOption(CopyOptions.LocalDevice)
            .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
            .onTextSelectionChange((start: number, end: number): void => {
              if (start >= 0 && end > start) { this.onSelect(); }
            })
        }, (text: string, index: number): string => this.message.id + '-body-' + index)
        // 流式正文单独一个 Text：ForEach 按 key 复用节点，同 key 改内容不保证刷新。
        if (this.message.streamingText.length > 0) {
          Text(this.message.streamingText).fontSize(15).lineHeight(23)
            .fontColor('#202124').width('100%').copyOption(CopyOptions.LocalDevice)
            .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
            .onTextSelectionChange((start: number, end: number): void => {
              if (start >= 0 && end > start) { this.onSelect(); }
            })
        }
        if (this.message.role === 'assistant') {
          if (this.message.status === 'running') {
            Row({ space: 8 }) {
              LoadingProgress().width(16).height(16).color('#6B7280')
              Text(this.message.phase + ' · ' + duration(this.now - this.message.phaseStartedAt))
                .fontSize(12).fontColor('#6B7280').layoutWeight(1)
            }.width('100%')
            if (this.now - this.message.lastEventAt >= 30000) {
              Text('仍在等待响应，最近更新于 ' + duration(this.now - this.message.lastEventAt) + ' 前；可随时停止。')
                .fontSize(12).fontColor('#8A6D3B').width('100%')
            }
          } else {
            Text(this.statusText(this.message) + ' · 总耗时 ' + duration(this.message.finishedAt - this.message.startedAt))
              .fontSize(12).fontColor(this.message.status === 'failed' ? '#B42318' : '#6B7280').width('100%')
          }
          Row({ space: 6 }) {
            Text(this.message.collapsed ? '▶' : '▼').fontSize(11).fontColor('#8B95A5')
            Text('执行日志 · 最近 ' + this.message.logs.length + ' 条').fontSize(12).fontColor('#8B95A5')
          }.width('100%')
          .onClick((): void => {
            this.onToggle(this.message.id);
          })
          if (!this.message.collapsed) {
            Column({ space: 4 }) {
              ForEach(this.message.logs, (line: string, index: number): void => {
                Text(line).fontSize(11).fontColor('#8B95A5').width('100%').copyOption(CopyOptions.LocalDevice)
                  .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
                  .onTextSelectionChange((start: number, end: number): void => {
                    if (start >= 0 && end > start) { this.onSelect(); }
                  })
              }, (line: string, index: number): string => this.message.id + '-log-' + index + '-' + line)
            }.width('100%').padding(8).backgroundColor('#F6F7F9').borderRadius(6)
          }
        }
      }
      .alignItems(HorizontalAlign.Start)
      .padding(12)
      .width(this.message.role === 'user' ? '82%' : '96%')
      .backgroundColor(this.message.role === 'user' ? '#3478F6' : Color.White)
      .borderRadius(12)
      if (this.message.role !== 'user') { Blank(); }
    }.width('100%').margin({ top: 6, bottom: 6 })
  }

}

@Entry
@Component
struct Index {
  @State messages: ChatMessage[] = [];
  @State inputText: string = '';
  @State running: boolean = false;
  @State stopping: boolean = false;
  @State phase: string = '空闲';
  @State showSettings: boolean = false;
  @State now: number = Date.now();
  @State keyboardLabel: string = '读取输入法…';
  @State keyboardNotice: string = '';
  @State taskNotice: string = '';
  @State taskNoticeStatus: string = '';
  @State hdcIp: string = '127.0.0.1';
  @State hdcPort: string = '8710';
  @State plannerUrl: string = '';
  @State plannerKey: string = '';
  @State deciderUrl: string = '';
  @State deciderKey: string = '';
  @State dshMode: boolean = false;
  @State dshUrl: string = 'http://192.168.60.30:3737';
  @State dshCookie: string = '';
  @State dshPairInput: string = '';
  @State dshPairNotice: string = '';
  @State dshSessions: DshSession[] = [];
  @State dshSessionId: string = '';
  @State dshChannels: DshChannel[] = [];
  @State dshChannelId: string = '';
  // 当前会话消息的镜像：与普通模式的 @State messages 一样由页面直接持有，
  // ForEach 才能可靠刷新。channel.messages 仍是数据源，写入后同步到这里。
  @State dshViewMessages: ChatMessage[] = [];
  // 页面级状态版本：channel.running/phase 变化时自增，
  // 让输入区的“发送/停止”按钮重新求值（ArkUI 只追踪 @State 读取）。
  @State dshRevision: number = 0;
  @State dshLoading: boolean = false;
  @State dshPresets: DshPreset[] = [];
  @State dshPresetId: string = '';
  @State dshWorkspaces: DshWorkspace[] = [];
  @State dshWorkspaceId: string = '';

  private runner: AgentRunner | null = null;
  private dsh: DshClient | null = null;
  private activeMessageId: number = -1;
  private nextId: number = 1;
  private timer: number = -1;
  private dshRefreshTimer: number = -1;
  private scrollTimer: number = -1;
  private taskNoticeTimer: number = -1;
  private following: boolean = true;
  private userScrolling: boolean = false;
  private scroller: Scroller = new Scroller();
  private imeChanged: () => void = (): void => { this.refreshKeyboard(); };
  private keyboardDialog: CustomDialogController = new CustomDialogController({
    builder: InputMethodListDialog(),
    onWillDismiss: (action: DismissDialogAction): void => {
      action.dismiss();
      this.refreshKeyboard();
    }
  });

  aboutToAppear(): void {
    let ep = AppRuntime.getEndpoints();
    this.hdcIp = ep.hdcIp;
    this.hdcPort = String(ep.hdcPort);
    this.plannerUrl = ep.plannerBaseUrl;
    this.plannerKey = ep.plannerApiKey;
    this.deciderUrl = ep.deciderBaseUrl;
    this.deciderKey = ep.deciderApiKey;
    AppRuntime.loadDshSettings();
    let savedUrl = AppRuntime.getDshUrl();
    if (savedUrl.length > 0) { this.dshUrl = savedUrl; }
    this.dshCookie = AppRuntime.getDshCookie();
    this.refreshKeyboard();
    try { inputMethod.getSetting().on('imeChange', this.imeChanged); } catch (e) {
      Logger.warn('输入法监听失败: ' + (e as Error).message);
    }
    // 已有 cookie 时进页面就拉一次会话列表，不必手动点刷新。
    this.autoLoadDsh();
  }

  // 启动时若已认证，自动连接并恢复会话列表与历史。
  private async autoLoadDsh(): Promise<void> {
    // 不自动切到 DSH 模式：开关默认关闭，由用户在设置里显式打开。
    // 这里只预热会话列表，方便打开后立刻有数据。
    if (this.dshCookie.length === 0) { return; }
    try {
      await this.refreshDshSessions();
      await this.loadCurrentHistory();
    } catch (e) {
      Logger.warn('[DSH] 自动加载失败: ' + (e as Error).message);
    }
  }

  aboutToDisappear(): void {
    if (this.runner !== null) { this.runner.cancel(); }
    this.stopAllDshStreams();
    clearInterval(this.timer);
    clearTimeout(this.scrollTimer);
    clearTimeout(this.taskNoticeTimer);
    clearTimeout(this.dshRefreshTimer);
    this.keyboardDialog.close();
    try { inputMethod.getSetting().off('imeChange', this.imeChanged); } catch (e) { /* 页面已退出。 */ }
  }

  private refreshKeyboard(): void {
    try { this.keyboardLabel = PhoneInputMethod.currentLabel(); } catch (e) {
      this.keyboardLabel = '无法读取输入法';
      Logger.warn((e as Error).message);
    }
  }

  private chooseKeyboard(): void {
    this.keyboardNotice = '';
    try {
      this.refreshKeyboard();
      this.keyboardDialog.open();
    } catch (e) {
      this.keyboardNotice = '无法打开输入法选择框，请稍后重试。';
      Logger.warn((e as Error).message);
    }
  }

  // ArkUI 的 @Observed 只追踪属性赋值，不追踪数组原地 push，
  // 因此所有对 channel.messages 的增删都走这里，整体替换数组。
  private appendMessage(channel: DshChannel, message: ChatMessage): void {
    let next: ChatMessage[] = [];
    for (let i = 0; i < channel.messages.length; i++) { next.push(channel.messages[i]); }
    next.push(message);
    channel.messages = next;
    this.syncDshView();
  }

  private updateMessage(id: number, update: (message: ChatMessage) => void): void {
    let message = this.messages.find((item: ChatMessage): boolean => item.id === id);
    if (message !== undefined) { update(message); }
  }

  private followOutput(): void {
    if (!this.following || this.scrollTimer >= 0) { return; }
    this.scrollTimer = setTimeout((): void => {
      this.scrollTimer = -1;
      if (this.following) { this.scroller.scrollEdge(Edge.Bottom); }
    }, 80);
  }

  private content(id: number, text: string): void {
    this.updateMessage(id, (message: ChatMessage): void => {
      if (message.paragraphs[message.paragraphs.length - 1] !== text) { message.paragraphs.push(text); }
      message.lastEventAt = Date.now();
    });
    this.followOutput();
  }

  private log(id: number, text: string): void {
    Logger.info(text);
    this.updateMessage(id, (message: ChatMessage): void => {
      message.logs.push(new Date().toLocaleTimeString() + ' ' + text);
      // UI 只保留最近 400 条，避免协议日志占满内存；完整过程仍写入 hilog。
      if (message.logs.length > 400) { message.logs.shift(); }
      message.lastEventAt = Date.now();
    });
  }

  private setPhase(id: number, phase: string): void {
    this.phase = phase;
    this.updateMessage(id, (message: ChatMessage): void => {
      message.phase = phase;
      message.phaseStartedAt = Date.now();
      message.lastEventAt = Date.now();
    });
  }

  private applySettings(): void {
    let port = Number(this.hdcPort);
    if (!Number.isInteger(port) || port < 1 || port > 65535) {
      this.keyboardNotice = 'HDC 端口必须在 1–65535 之间。';
      return;
    }
    let previous = AppRuntime.getEndpoints();
    let ep: EndpointConfig = {
      hdcIp: this.hdcIp.trim(), hdcPort: port,
      plannerBaseUrl: this.plannerUrl.trim(), plannerApiKey: this.plannerKey.trim(), plannerModel: previous.plannerModel,
      deciderBaseUrl: this.deciderUrl.trim(), deciderApiKey: this.deciderKey.trim(), deciderModel: previous.deciderModel
    };
    AppRuntime.setEndpoints(ep);
    let url = this.dshUrl.trim();
    if (url.length > 0) {
      try { this.dshUrl = normalizeDshBase(url); } catch (e) {
        this.dshPairNotice = (e as Error).message;
        return;
      }
    }
    let savedUrl = AppRuntime.getDshUrl();
    if (savedUrl !== this.dshUrl) {
      AppRuntime.setDshUrl(this.dshUrl);
      // 换地址后旧 cookie 绑定的 authority 已失效，一并清掉。
      AppRuntime.clearDshAuth();
      this.dshCookie = '';
      this.resetDshClient();
    }
    // 关闭 DSH 时只摘订阅，不碰 running/timer：
    // 那两个是普通模式 AgentRunner 的状态，误清会打断正在跑的任务。
    if (!this.dshMode) { this.stopAllDshStreams(); }
    this.showSettings = false;
  }

  private currentDsh(): DshClient {
    if (this.dsh === null) {
      let config: DshConfig = { baseUrl: this.dshUrl, cookie: this.dshCookie };
      this.dsh = new DshClient(config, (line: string): void => { Logger.info('[DSH] ' + line); });
    }
    return this.dsh;
  }

  // 重建客户端前先摘掉所有订阅，避免旧 cookie 的连接泄漏。
  private resetDshClient(): void {
    this.stopAllDshStreams();
    this.dsh = null;
    this.dshChannels = [];
    this.dshChannelId = '';
  }

  // 认证：把带 ?token= 的链接换成 dsh-auth-* cookie 并持久化。
  private async pairDsh(): Promise<void> {
    let token = dshTokenFromLink(this.dshPairInput);
    if (token.length === 0) {
      this.dshPairNotice = '请粘贴带 token 的 DSH 链接。';
      return;
    }
    let url = this.dshUrl.trim();
    if (url.length === 0) {
      this.dshPairNotice = '请先填写 DSH 地址。';
      return;
    }
    try { url = normalizeDshBase(url); } catch (e) {
      this.dshPairNotice = (e as Error).message;
      return;
    }
    this.dshPairNotice = '正在认证…';
    try {
      let cookie = await dshAuthenticate(url, token);
      this.dshUrl = url;
      this.dshCookie = cookie;
      this.resetDshClient();
      AppRuntime.setDshUrl(url);
      AppRuntime.setDshCookie(cookie);
      this.dshPairInput = '';
      this.dshPairNotice = '认证成功，cookie 已保存。';
      await this.refreshDshSessions();
    } catch (e) {
      this.dshPairNotice = '认证失败：' + (e as Error).message;
    }
  }

  private async refreshDshSessions(): Promise<void> {
    this.dshLoading = true;
    try {
      let sessions = await this.currentDsh().listSessions();
      this.dshSessions = sessions;
      this.syncChannels(sessions);
      this.dshPairNotice = '已连接，共 ' + sessions.length + ' 个会话。';
      await this.loadDshOptions();
    } catch (e) {
      this.dshSessions = [];
      this.dshPairNotice = '读取会话失败：' + (e as Error).message;
    } finally {
      this.dshLoading = false;
    }
  }

  // 按会话补建/更新 channel。
  // 必须复用已有对象：runDshTask 持有 channel 引用，重建数组会让它指向旧对象，
  // 之后的帧就写不进界面上显示的那一个。本地已存在但列表里暂缺的也保留，
  // 因为 session/list 可能还没跟上刚创建的会话。
  private syncChannels(sessions: DshSession[]): void {
    let incoming: DshChannel[] = [];
    for (let i = 0; i < sessions.length; i++) {
      let session = sessions[i];
      let channel = this.findChannel(session.sessionId);
      if (channel === undefined) {
        channel = new DshChannel(session.sessionId,
          session.title.length > 0 ? session.title : session.sessionId.substring(0, 12));
      } else {
        if (session.title.length > 0) { channel.title = session.title; }
        // 宿主侧已不在跑，而本地仍标记运行中：说明漏了 turn/end，
        // 这里直接收尾，避免界面永远停在“运行中”。
        if (!session.running && channel.running) {
          let id = channel.activeMessageId;
          let final = id >= 0 ? this.lastContent(channel, id) : '';
          this.logTo(channel, id, 'TASK END: 远端已结束（列表校正）');
          this.finishDshRun(channel,
            final.length > 0 ? final : 'DSH 回合已结束。',
            final.length > 0 ? 'success' : 'failed', '');
        }
      }
      incoming.push(channel);
    }
    // 保留本地有、远端暂时没有的 channel（按 updatedAt 排在后面）。
    for (let i = 0; i < this.dshChannels.length; i++) {
      let local = this.dshChannels[i];
      let seen = false;
      for (let j = 0; j < incoming.length; j++) {
        if (incoming[j].sessionId === local.sessionId) { seen = true; break; }
      }
      if (!seen) { incoming.push(local); }
    }
    this.dshChannels = incoming;
    if (this.dshChannelId.length === 0 || this.findChannel(this.dshChannelId) === undefined) {
      this.dshChannelId = incoming.length > 0 ? incoming[0].sessionId : '';
    }
    if (this.dshSessionId.length === 0 && incoming.length > 0) {
      this.dshSessionId = incoming[0].sessionId;
    }
    this.syncDshView();
  }

  private findChannel(sessionId: string): DshChannel | undefined {
    return this.dshChannels.find((item: DshChannel): boolean => item.sessionId === sessionId);
  }

  private currentChannel(): DshChannel | undefined {
    return this.findChannel(this.dshChannelId);
  }

  private currentChannelTitle(): string {
    let channel = this.currentChannel();
    if (channel === undefined) { return '会话'; }
    return channel.title.length > 0 ? channel.title : channel.sessionId.substring(0, 12);
  }

  // 把当前会话的消息同步到页面级 @State，ForEach 才会刷新。
  private syncDshView(): void {
    let channel = this.currentChannel();
    if (channel === undefined) {
      if (this.dshViewMessages.length > 0) { this.dshViewMessages = []; }
      return;
    }
    let next: ChatMessage[] = [];
    for (let i = 0; i < channel.messages.length; i++) { next.push(channel.messages[i]); }
    this.dshViewMessages = next;
  }

  private currentChannelRunning(): boolean {
    let channel = this.currentChannel();
    return channel !== undefined && channel.running;
  }

  private currentChannelStopping(): boolean {
    let channel = this.currentChannel();
    return channel !== undefined && channel.stopping;
  }

  private scheduleSessionRefresh(): void {
    if (this.dshRefreshTimer >= 0 || this.dshLoading) { return; }
    this.dshRefreshTimer = setTimeout((): void => {
      this.dshRefreshTimer = -1;
      this.refreshDshSessionsSilently();
    }, 600);
  }

  private async refreshDshSessionsSilently(): Promise<void> {
    if (this.dshLoading) { return; }
    this.dshLoading = true;
    try {
      let sessions = await this.currentDsh().listSessions();
      this.dshSessions = sessions;
      this.syncChannels(sessions);
    } catch (e) {
      Logger.warn('[DSH] 静默刷新会话失败: ' + (e as Error).message);
    } finally {
      this.dshLoading = false;
    }
  }

  private async loadDshOptions(): Promise<void> {
    let client = this.currentDsh();
    try {
      let presets = await client.listAgentPresets();
      this.dshPresets = presets;
      if (this.dshPresetId.length === 0) {
        let chosen = '';
        for (let i = 0; i < presets.length; i++) {
          if (presets[i].isDefault) { chosen = presets[i].id; }
        }
        this.dshPresetId = chosen.length > 0 ? chosen : (presets.length > 0 ? presets[0].id : '');
      }
    } catch (e) {
      Logger.warn('[DSH] 读取 Agent 模式失败: ' + (e as Error).message);
    }
    try {
      this.dshWorkspaces = await client.listWorkspaces();
    } catch (e) {
      this.dshWorkspaces = [];
    }
  }

  // 新建会话：成功后切到新会话，键盘收起，等待用户输入。
  private async createDshSession(): Promise<void> {
    if (this.dshLoading) { return; }
    this.dshLoading = true;
    this.dshPairNotice = '正在新建会话…';
    try {
      if (this.dshPresets.length === 0) { await this.loadDshOptions(); }
      let id = await this.currentDsh().createSession(this.dshWorkspaceId, '', this.dshPresetId);
      this.dshSessionId = id;
      this.dshChannelId = id;
      this.dshSessions = await this.currentDsh().listSessions();
      this.syncChannels(this.dshSessions);
      this.dshChannelId = id;
      this.dshPairNotice = '已新建会话 ' + id.substring(0, 20);
      Logger.info('[DSH] created session=' + id);
    } catch (e) {
      this.dshPairNotice = '新建失败：' + (e as Error).message;
    } finally {
      this.dshLoading = false;
    }
  }

  private stopDshChannel(channel: DshChannel): void {
    if (channel.unsubscribe !== null) {
      channel.unsubscribe();
      channel.unsubscribe = null;
    }
  }

  private stopAllDshStreams(): void {
    for (let i = 0; i < this.dshChannels.length; i++) {
      this.stopDshChannel(this.dshChannels[i]);
    }
  }

  // DSH 模式：把一句话交给电脑端 DSH，流式把回复写进该会话自己的消息列表。
  // sessionId 为空表示“新建一个会话再发”，channel 为空表示当前选中的会话。
  private async runDshTask(task: string, sessionId: string = ''): Promise<void> {
    this.hideTaskNotice();
    let client = this.currentDsh();
    let target = sessionId.length > 0 ? sessionId : this.dshSessionId;
    if (target.length === 0) {
      // 还没有会话：先建一个，再回到这里。
      try {
        if (this.dshPresets.length === 0) { await this.loadDshOptions(); }
        let created = await client.createSession(this.dshWorkspaceId, '', this.dshPresetId);
        this.dshSessions = await client.listSessions();
        this.syncChannels(this.dshSessions);
        this.dshChannelId = created;
        this.dshSessionId = created;
        return await this.runDshTask(task, created);
      } catch (e) {
        this.showDshFailure(this.currentChannel(), '新建会话失败：' + (e as Error).message);
        return;
      }
    }
    let channel = this.findChannel(target);
    if (channel === undefined) {
      channel = new DshChannel(target, target.substring(0, 12));
      // 整体替换 @State 数组，避免原地 push 不触发刷新。
      let next: DshChannel[] = [];
      for (let i = 0; i < this.dshChannels.length; i++) { next.push(this.dshChannels[i]); }
      next.push(channel);
      this.dshChannels = next;
    }
    this.dshChannelId = target;
    this.dshSessionId = target;
    if (channel.running) {
      // 同一会话已在跑：DSH 会排队，本地继续累积到同一个回复气泡。
      this.logTo(channel, channel.activeMessageId, '[DSH] 会话执行中，新消息已排队');
      this.verifyChannelRunning(channel);
    } else {
      this.setChannelRunning(channel, true, false, '连接 DSH');
      let id = this.nextId++;
      channel.activeMessageId = id;
      let message = new ChatMessage(id, 'assistant');
      message.status = 'running';
      message.phase = '连接 DSH';
      this.appendMessage(channel, message);
      channel.lastError = '';
      this.bindDshChannel(channel);
    }
    this.ensureTimer();
    let id = channel.activeMessageId;
    this.logTo(channel, id, '[DSH] ' + this.dshUrl + ' session=' + target);
    try {
      this.setChannelPhase(channel, '发送给 DSH');
      await client.prompt(target, task, mintRequestId());
      this.setChannelPhase(channel, '等待 DSH 回复');
      this.logTo(channel, id, '[DSH] prompt accepted');
      this.followOutput();
      this.scheduleSessionRefresh();
    } catch (e) {
      let text = (e as Error).message;
      this.contentTo(channel, id, '发送失败：' + text);
      this.logTo(channel, id, 'TASK END: ' + text);
      this.finishDshRun(channel, text, 'failed', task);
    }
  }

  // 每个 channel 只挂一条 session/follow 的 WebSocket；断流自动重连并对齐历史。
  private bindDshChannel(channel: DshChannel): void {
    if (channel.unsubscribe !== null) { return; }
    let sessionId = channel.sessionId;
    channel.unsubscribe = this.currentDsh().subscribeFollow(sessionId,
      (frame: DshFollowFrame): void => { this.onDshChannelFrame(channel, frame); },
      (message: string): void => {
        Logger.warn('[DSH] ' + sessionId + ' stream: ' + message);
        channel.lastError = message;
        // 断流时本地状态可能永远停在“运行中”，交给会话列表校验。
        this.verifyChannelRunning(channel);
      },
      (): void => {
        this.reconcileDshHistory(channel);
        this.verifyChannelRunning(channel);
      });
  }

  private onDshChannelFrame(channel: DshChannel, frame: DshFollowFrame): void {
    if (frame.cursor > channel.cursor) { channel.cursor = frame.cursor; }
    if (frame.kind === 'snapshot') { return; }
    let id = channel.activeMessageId;
    if (id < 0) {
      // 没有在跑的回合（例如别的客户端在跑）：只刷新标题/列表。
      if (frame.eventType === 'session/title' || frame.eventType === 'turn/start' ||
        frame.eventType === 'turn/end') { this.scheduleSessionRefresh(); }
      return;
    }
    if (frame.eventType === 'turn/start') {
      this.setChannelPhase(channel, 'DSH 正在执行');
      return;
    }
    if (frame.eventType === 'turn/end') {
      let final = this.lastContent(channel, id);
      this.logTo(channel, id, 'TASK END: turn/end');
      this.finishDshRun(channel, final.length > 0 ? final : 'DSH 回合已结束（无文本输出）。',
        final.length > 0 ? 'success' : 'failed', '');
      return;
    }
    if (frame.eventType === 'user/message' || frame.eventType === 'system/message' ||
      frame.eventType === 'request/header' || frame.eventType === 'request/context' ||
      frame.eventType === 'session/title' || frame.eventType === 'step/start') {
      return;
    }
    if (frame.text.length === 0) { return; }
    if (frame.eventType === 'assistant/reasoning') {
      // 思考过程只进日志，不混进正文。
      let message = channel.messages.find((item: ChatMessage): boolean => item.id === id);
      if (message !== undefined) { message.reasoning += frame.text; }
      return;
    }
    if (frame.eventType === 'assistant/chunk') {
      // assistant-stream 是过程帧，逐字追加。
      let collected = this.appendChunk(channel, id, frame.text);
      this.contentTo(channel, id, collected, true);
      return;
    }
    if (frame.eventType === 'assistant/message') {
      // 落盘后的完整消息：以它为准覆盖过程帧累积的内容。
      let message = channel.messages.find((item: ChatMessage): boolean => item.id === id);
      if (message !== undefined) {
        message.streamBuffer = frame.text;
        this.contentTo(channel, id, frame.text, true);
      }
      return;
    }
    // 其余事件（工具调用、错误、计划等）进执行日志。
    this.logTo(channel, id, '[' + frame.eventType + '] ' + frame.text.substring(0, 160));
  }

  // 流式文本按会话累加在 ChatMessage 的私有字段上，避免每帧重建整段字符串。
  private appendChunk(channel: DshChannel, id: number, text: string): string {
    let message = channel.messages.find((item: ChatMessage): boolean => item.id === id);
    if (message === undefined) { return ''; }
    message.streamBuffer += text;
    return message.streamBuffer;
  }

  private lastContent(channel: DshChannel, id: number): string {
    let message = channel.messages.find((item: ChatMessage): boolean => item.id === id);
    return message === undefined ? '' : message.streamBuffer;
  }

  // 重连后事件可能断档：向前补拉一段，只取最后一个完整回合。
  // 不能把整段历史拼起来覆盖正文，否则当前气泡会被上一轮的回复占满。
  private async reconcileDshHistory(channel: DshChannel): Promise<void> {
    if (!channel.running) { return; }
    let id = channel.activeMessageId;
    if (id < 0) { return; }
    let cursor = channel.cursor;
    if (cursor <= 0) { return; }
    try {
      let frames = await this.currentDsh().page(channel.sessionId, cursor, 30);
      // 从后往前找最后一个回合：遇到 turn/end 开始收集，遇到 user/message 停止。
      let turns: string[] = [];
      let current = '';
      let collecting = false;
      for (let i = frames.length - 1; i >= 0; i--) {
        let frame = frames[i];
        if (frame.eventType === 'turn/end') {
          if (current.length > 0) { turns.unshift(current); current = ''; }
          collecting = true;
          continue;
        }
        if (frame.role === 'user') {
          if (current.length > 0) { turns.unshift(current); current = ''; }
          break;
        }
        if (collecting && frame.text.length > 0) { current = frame.text + current; }
      }
      let text = turns.length > 0 ? turns[turns.length - 1] : current;
      if (text.length === 0) { return; }
      let message = channel.messages.find((item: ChatMessage): boolean => item.id === id);
      if (message === undefined) { return; }
      if (text.length > message.streamBuffer.length) {
        message.streamBuffer = text;
        this.contentTo(channel, id, text, true);
      }
    } catch (e) {
      Logger.warn('[DSH] 补拉历史失败: ' + (e as Error).message);
    }
  }

  private finishDshRun(channel: DshChannel, summary: string, status: string, task: string): void {
    // 订阅保留：WebSocket 按会话常驻，跨回合复用。
    // 若在这里关掉，下一轮重连会收到覆盖全部历史的 snapshot，正文会被旧内容重放。
    let id = channel.activeMessageId;
    if (id >= 0) {
      let message = channel.messages.find((item: ChatMessage): boolean => item.id === id);
      if (message !== undefined) {
        if (message.streamBuffer.length === 0 && summary.length > 0) {
          message.streamBuffer = summary;
          message.paragraphs = [summary];
        }
        message.status = status;
        message.phase = status === 'success' ? '已完成' : (status === 'cancelled' ? '已取消' : '已失败');
        message.finishedAt = Date.now();
      }
    }
    this.setChannelRunning(channel, false, false, '空闲');
    channel.activeMessageId = -1;
    // 普通任务仍在跑时不能关秒表。
    if (this.runningChannels() === 0 && this.runner === null) {
      clearInterval(this.timer);
      this.timer = -1;
      this.phase = '空闲';
    }
    let result: AgentRunResult = { status: 'failed', message: summary };
    if (status === 'success') { result.status = 'success'; }
    if (status === 'cancelled') { result.status = 'cancelled'; }
    this.showTaskNotice(result, task.length > 0 ? task : (channel.title.length > 0 ? channel.title : channel.sessionId));
    this.refreshKeyboard();
  }

  private async stopDsh(): Promise<void> {
    let channel = this.currentChannel();
    if (channel === undefined) { return; }
    if (!channel.running || channel.stopping) { return; }
    this.setChannelRunning(channel, true, true, '正在取消 DSH 回合');
    try {
      await this.currentDsh().cancel(channel.sessionId);
    } catch (e) {
      this.logTo(channel, channel.activeMessageId, '[DSH] cancel failed: ' + (e as Error).message);
    }
    let id = channel.activeMessageId;
    this.contentTo(channel, id, '已取消。');
    this.finishDshRun(channel, '任务已取消。', 'cancelled', '');
  }

  // 展示用：有多少个会话正在跑。
  private runningChannels(): number {
    let count = 0;
    for (let i = 0; i < this.dshChannels.length; i++) {
      if (this.dshChannels[i].running) { count++; }
    }
    return count;
  }

  // 只负责驱动秒表刷新；running 归普通模式的 AgentRunner 独占，
  // DSH 是否在跑看 runningChannels()，两者不能共用一个字段。
  private ensureTimer(): void {
    if (this.timer >= 0) { return; }
    this.now = Date.now();
    this.timer = setInterval((): void => { this.now = Date.now(); }, 1000);
  }

  private showDshFailure(channel: DshChannel | undefined, text: string): void {
    this.dshPairNotice = text;
    if (channel !== undefined) {
      let id = this.nextId++;
      let message = new ChatMessage(id, 'assistant');
      message.status = 'failed';
      message.paragraphs = [text];
      message.finishedAt = Date.now();
      this.appendMessage(channel, message);
    }
  }

  // 修改 channel 运行状态并推进版本号，标签栏才会重绘。
  private setChannelRunning(channel: DshChannel, running: boolean, stopping: boolean, phase: string): void {
    channel.running = running;
    channel.stopping = stopping;
    channel.phase = phase;
    channel.revision = channel.revision + 1;
    this.dshRevision = this.dshRevision + 1;
  }

  // 用宿主的真实状态校正本地 running：
  // 断流、重连、或错过 turn/end 时，本地可能一直显示“运行中”。
  private async verifyChannelRunning(channel: DshChannel): Promise<void> {
    if (!channel.running) { return; }
    try {
      let sessions = await this.currentDsh().listSessions();
      let remote: DshSession | undefined =
        sessions.find((item: DshSession): boolean => item.sessionId === channel.sessionId);
      if (remote === undefined) { return; }
      if (remote.running) {
        // 宿主还在跑，保持本地状态，补充一次历史以防漏帧。
        this.reconcileDshHistory(channel);
        return;
      }
      // 宿主已结束：收尾当前气泡，避免永远停在“运行中”。
      let id = channel.activeMessageId;
      let final = id >= 0 ? this.lastContent(channel, id) : '';
      this.logTo(channel, id, 'TASK END: 远端已结束（本地未收到 turn/end）');
      this.finishDshRun(channel,
        final.length > 0 ? final : 'DSH 回合已结束。',
        final.length > 0 ? 'success' : 'failed', '');
    } catch (e) {
      Logger.warn('[DSH] 校验会话状态失败: ' + (e as Error).message);
    }
  }

  private setChannelPhase(channel: DshChannel, phase: string): void {
    channel.phase = phase;
    channel.revision = channel.revision + 1;
    this.dshRevision = this.dshRevision + 1;
    let message = channel.messages.find((item: ChatMessage): boolean => item.id === channel.activeMessageId);
    if (message !== undefined) {
      message.phase = phase;
      message.phaseStartedAt = Date.now();
      message.lastEventAt = Date.now();
    }
  }

  // 流式正文写 streamingText（单独一个 Text 直接绑定，内容变化必刷新）；
  // replace=false 追加一段独立正文，用于工具回执这类一次性文字。
  private contentTo(channel: DshChannel, id: number, text: string, replace: boolean = false): void {
    let message = channel.messages.find((item: ChatMessage): boolean => item.id === id);
    if (message !== undefined) {
      if (replace) {
        message.streamingText = text;
      } else if (text.length > 0 &&
        (message.paragraphs.length === 0 || message.paragraphs[message.paragraphs.length - 1] !== text)) {
        let next: string[] = [];
        for (let i = 0; i < message.paragraphs.length; i++) { next.push(message.paragraphs[i]); }
        next.push(text);
        message.paragraphs = next;
      }
      message.lastEventAt = Date.now();
      this.syncDshView();
    }
    if (channel.sessionId === this.dshChannelId) { this.followOutput(); }
  }

  private logTo(channel: DshChannel, id: number, text: string): void {
    Logger.info('[' + channel.sessionId + '] ' + text);
    let message = channel.messages.find((item: ChatMessage): boolean => item.id === id);
    if (message === undefined) { return; }
    message.logs.push(new Date().toLocaleTimeString() + ' ' + text);
    if (message.logs.length > 400) { message.logs.shift(); }
    message.lastEventAt = Date.now();
  }

  private send(): void {
    let task = this.inputText.trim();
    if (!task) { return; }
    if (this.dshMode) {
      if (this.dshLoading) { return; }
      this.inputText = '';
      this.following = true;
      let channel = this.currentChannel();
      if (channel !== undefined) {
        let userMessage = new ChatMessage(this.nextId++, 'user');
        userMessage.paragraphs = [task];
        this.appendMessage(channel, userMessage);
      }
      this.runDshTask(task);
      return;
    }
    if (this.running) { return; }
    this.inputText = '';
    this.following = true;
    let time = Date.now();
    let message = new ChatMessage(this.nextId++, 'user');
    message.paragraphs = [task];
    this.messages.push(message);
    this.runTask(task);
  }

  private async runTask(task: string): Promise<void> {
    this.hideTaskNotice();
    this.running = true;
    this.stopping = false;
    let id = this.nextId++;
    this.activeMessageId = id;
    let time = Date.now();
    let message = new ChatMessage(id, 'assistant');
    message.status = 'running';
    message.phase = '准备中';
    this.messages.push(message);
    this.now = time;
    this.timer = setInterval((): void => { this.now = Date.now(); }, 1000);
    let runner = new AgentRunner(AppRuntime.getEndpoints());
    this.runner = runner;
    let callbacks: AgentCallbacks = {
      onLog: (line: string): void => { this.log(id, line); },
      onPhase: (phase: string): void => { this.setPhase(id, phase); },
      onStep: (step: number, maxSteps: number, action: string): void => {
        this.log(id, '步骤 ' + step + '/' + maxSteps + ' · ' + action);
      },
      onContent: (text: string): void => { this.content(id, text); }
    };
    let result: AgentRunResult = { status: 'failed', message: '任务未完成。' };
    try {
      result = await runner.run(task, callbacks);
      if (this.stopping) { result = { status: 'cancelled', message: '任务已取消。' }; }
    } catch (e) {
      let error = e as Error;
      result = {
        status: this.stopping ? 'cancelled' : (error instanceof AgentRunError ? error.status : 'failed'),
        message: this.stopping ? '任务已取消。' : '任务失败：' + error.message
      };
      this.log(id, 'TASK END: ' + result.message);
    } finally {
      this.content(id, result.message);
      this.updateMessage(id, (message: ChatMessage): void => {
        message.status = result.status;
        message.finishedAt = Date.now();
      });
      clearInterval(this.timer);
      this.timer = -1;
      this.running = false;
      this.stopping = false;
      this.runner = null;
      this.phase = '空闲';
      this.showTaskNotice(result, task);
      this.refreshKeyboard();
    }
  }

  private hideTaskNotice(): void {
    clearTimeout(this.taskNoticeTimer);
    this.taskNoticeTimer = -1;
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseIn }, (): void => {
      this.taskNotice = '';
    });
  }

  private showTaskNotice(result: AgentRunResult, task: string): void {
    clearTimeout(this.taskNoticeTimer);
    this.taskNoticeStatus = result.status;
    let label = result.status === 'success' ? '任务已完成' :
      (result.status === 'cancelled' ? '任务已取消' : (result.status === 'suspended' ? '任务已暂停' : '任务执行失败'));
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, (): void => {
      this.taskNotice = label + '：' + task;
    });
    this.taskNoticeTimer = setTimeout((): void => { this.hideTaskNotice(); }, 2000);
  }

  private stop(): void {
    if (this.dshMode) { this.stopDsh(); return; }
    if (this.runner === null || this.stopping) { return; }
    this.stopping = true;
    this.setPhase(this.activeMessageId, '正在停止并释放资源');
    this.runner.cancel();
  }

  @Builder
  field(label: string, value: string, onChange: (v: string) => void, secret: boolean = false) {
    Row({ space: 8 }) {
      Text(label).fontSize(12).width(84).fontColor('#666666')
      TextInput({ text: value }).type(secret ? InputType.Password : InputType.Normal)
        .fontSize(13).layoutWeight(1).height(36).onChange(onChange)
    }
  }

  @Builder
  settingsPanel() {
    Column({ space: 8 }) {
      Text('端点配置').fontSize(14).fontWeight(FontWeight.Bold)
      this.field('HDC IP', this.hdcIp, (v: string): void => { this.hdcIp = v; })
      this.field('HDC 端口', this.hdcPort, (v: string): void => { this.hdcPort = v; })
      this.field('Planner URL', this.plannerUrl, (v: string): void => { this.plannerUrl = v; })
      this.field('Planner Key', this.plannerKey, (v: string): void => { this.plannerKey = v; }, true)
      this.field('Decider URL', this.deciderUrl, (v: string): void => { this.deciderUrl = v; })
      this.field('Decider Key', this.deciderKey, (v: string): void => { this.deciderKey = v; }, true)
      Divider().margin({ top: 6, bottom: 2 })
      Row({ space: 8 }) {
        Text('发送到电脑 DSH').fontSize(13).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.dshMode })
          .onChange((on: boolean): void => { this.dshMode = on; })
      }.width('100%')
      if (this.dshMode) {
        this.field('DSH 地址', this.dshUrl, (v: string): void => { this.dshUrl = v; })
        this.field('带 token 链接', this.dshPairInput, (v: string): void => { this.dshPairInput = v; })
        Row({ space: 8 }) {
          Button('认证').fontSize(12).height(30)
            .onClick((): void => { this.pairDsh(); })
          Button('刷新会话').fontSize(12).height(30).enabled(!this.dshLoading)
            .onClick((): void => { this.refreshDshSessions(); })
          Text(this.dshCookie.length > 0 ? '已认证' : '未认证')
            .fontSize(12).fontColor(this.dshCookie.length > 0 ? '#166534' : '#8A6D3B')
          if (this.dshCookie.length > 0) {
            Button('退出').fontSize(11).height(28).backgroundColor('#E5E7EB').fontColor('#374151')
              .onClick((): void => {
                this.resetDshClient();
                this.dshCookie = '';
                AppRuntime.clearDshAuth();
                this.dshPairNotice = '已清除认证 cookie。';
              })
          }
        }.width('100%')
        if (this.dshPresets.length > 0) {
          Row({ space: 8 }) {
            Text('Agent 模式').fontSize(12).width(84).fontColor('#666666')
            Select(this.dshPresets.map((item: DshPreset): SelectOption => {
              let option: SelectOption = { value: item.name };
              return option;
            }))
              .selected(this.dshPresetIndex())
              .value(this.dshPresetLabel())
              .font({ size: 12 }).layoutWeight(1)
              .onSelect((index: number): void => {
                if (index >= 0 && index < this.dshPresets.length) {
                  this.dshPresetId = this.dshPresets[index].id;
                }
              })
          }.width('100%')
        }
        if (this.dshWorkspaces.length > 0) {
          Row({ space: 8 }) {
            Text('工作区').fontSize(12).width(84).fontColor('#666666')
            Select([{ value: '（使用 DSH 当前目录）' } as SelectOption]
              .concat(this.dshWorkspaces.map((item: DshWorkspace): SelectOption => {
                let option: SelectOption = { value: item.title.length > 0 ? item.title : item.path };
                return option;
              })))
              .selected(this.dshWorkspaceIndex())
              .value(this.dshWorkspaceLabel())
              .font({ size: 12 }).layoutWeight(1)
              .onSelect((index: number): void => {
                this.dshWorkspaceId = index <= 0 ? '' :
                  (index - 1 < this.dshWorkspaces.length ? this.dshWorkspaces[index - 1].workspaceId : '');
              })
          }.width('100%')
        }
        Row({ space: 8 }) {
          Button('新建会话').fontSize(12).height(30).enabled(!this.dshLoading)
            .onClick((): void => { this.createDshSession(); })
          if (this.dshSessions.length > 0) {
            Text('共 ' + this.dshSessions.length + ' 个').fontSize(11).fontColor('#6B7280')
          }
        }.width('100%')
        if (this.dshSessions.length > 0) {
          Text('当前会话').fontSize(12).fontColor('#666666').width('100%')
          Select(this.dshSessions.map((item: DshSession): SelectOption => {
            let option: SelectOption = { value: item.title.length > 0 ? item.title : item.sessionId };
            return option;
          }))
            .selected(this.dshSessionIndex())
            .value(this.dshSessionLabel())
            .font({ size: 12 }).width('100%')
            .onSelect((index: number, value: string): void => {
              if (index >= 0 && index < this.dshSessions.length) {
                this.dshSessionId = this.dshSessions[index].sessionId;
                this.selectChannel(this.dshSessions[index].sessionId);
              }
            })
        }
        if (this.dshPairNotice.length > 0) {
          Text(this.dshPairNotice).fontSize(11).fontColor('#6B7280').width('100%')
        }
      }
      Button('保存').fontSize(13).onClick((): void => { this.applySettings(); })
    }.padding(12).width('100%').backgroundColor('#FAFAFA')
  }

  private dshPresetIndex(): number {
    for (let i = 0; i < this.dshPresets.length; i++) {
      if (this.dshPresets[i].id === this.dshPresetId) { return i; }
    }
    return 0;
  }

  private dshPresetLabel(): string {
    let index = this.dshPresetIndex();
    if (index < 0 || index >= this.dshPresets.length) { return '选择模式'; }
    return this.dshPresets[index].name;
  }

  private dshWorkspaceIndex(): number {
    if (this.dshWorkspaceId.length === 0) { return 0; }
    for (let i = 0; i < this.dshWorkspaces.length; i++) {
      if (this.dshWorkspaces[i].workspaceId === this.dshWorkspaceId) { return i + 1; }
    }
    return 0;
  }

  private dshWorkspaceLabel(): string {
    let index = this.dshWorkspaceIndex();
    if (index <= 0) { return '（使用 DSH 当前目录）'; }
    let item = this.dshWorkspaces[index - 1];
    return item.title.length > 0 ? item.title : item.path;
  }

  private dshSessionIndex(): number {
    for (let i = 0; i < this.dshSessions.length; i++) {
      if (this.dshSessions[i].sessionId === this.dshSessionId) { return i; }
    }
    return 0;
  }

  private dshSessionLabel(): string {
    let index = this.dshSessionIndex();
    if (index < 0 || index >= this.dshSessions.length) { return '选择会话'; }
    let item = this.dshSessions[index];
    return item.title.length > 0 ? item.title : item.sessionId;
  }

  private channelBadge(channel: DshChannel): string {
    if (channel.running) { return channel.stopping ? '停止中' : '运行中'; }
    let last = channel.messages.length > 0 ? channel.messages[channel.messages.length - 1] : undefined;
    if (last !== undefined && last.role === 'assistant' && last.status === 'failed') { return '失败'; }
    if (channel.lastError.length > 0) { return '断流'; }
    return '';
  }

  private runningCount(): number {
    return this.runningChannels();
  }

  private selectChannel(sessionId: string): void {
    this.dshChannelId = sessionId;
    this.dshSessionId = sessionId;
    this.following = true;
    this.bindDshChannelIfNeeded();
    this.syncDshView();
    this.refreshKeyboard();
    this.loadCurrentHistory();
  }

  // 会话切过来时若还没订阅，补建一条 follow，拿到 cursor 后才能拉历史。
  private bindDshChannelIfNeeded(): void {
    let channel = this.currentChannel();
    if (channel === undefined) { return; }
    if (channel.unsubscribe === null) { this.bindDshChannel(channel); }
  }

  // 进入会话时拉最近一段历史，填充消息列表；已加载过的不重复拉。
  private async loadCurrentHistory(): Promise<void> {
    let channel = this.currentChannel();
    if (channel === undefined || channel.historyLoaded) { return; }
    if (channel.cursor <= 0) {
      // 等 snapshot 到达后再试一次。
      setTimeout((): void => { this.loadCurrentHistory(); }, 800);
      return;
    }
    channel.historyLoading = true;
    try {
      let frames = await this.currentDsh().page(channel.sessionId, channel.cursor, 60);
      let loaded: ChatMessage[] = [];
      for (let i = 0; i < frames.length; i++) {
        let frame = frames[i];
        if (frame.text.length === 0) { continue; }
        if (frame.role === 'user') {
          let userMessage = new ChatMessage(this.nextId++, 'user');
          userMessage.paragraphs = [frame.text];
          userMessage.status = 'success';
          userMessage.finishedAt = Date.now();
          loaded.push(userMessage);
          continue;
        }
        if (frame.eventType === 'assistant/message') {
          let assistantMessage = new ChatMessage(this.nextId++, 'assistant');
          assistantMessage.streamingText = frame.text;
          assistantMessage.streamBuffer = frame.text;
          assistantMessage.status = 'success';
          assistantMessage.finishedAt = Date.now();
          loaded.push(assistantMessage);
        }
      }
      if (loaded.length === 0) { channel.historyLoaded = true; return; }
      // 历史放在已有实时消息之前，避免覆盖本轮刚收到的内容。
      let merged: ChatMessage[] = loaded;
      for (let i = 0; i < channel.messages.length; i++) { merged.push(channel.messages[i]); }
      channel.messages = merged;
      channel.historyLoaded = true;
      this.syncDshView();
      this.followOutput();
    } catch (e) {
      Logger.warn('[DSH] 加载历史失败: ' + (e as Error).message);
    } finally {
      channel.historyLoading = false;
    }
  }

  // 并行会话标签栏：横向滚动，每个会话显示标题与运行状态徽标。
  @Builder
  channelBar() {
    Row({ space: 6 }) {
      Scroll() {
        Row({ space: 6 }) {
          ForEach(this.dshChannels, (channel: DshChannel): void => {
            Row({ space: 4 }) {
              Text(channel.title.length > 0 ? channel.title : channel.sessionId.substring(0, 10))
                .fontSize(12).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .fontColor(channel.sessionId === this.dshChannelId ? Color.White : '#374151')
                .constraintSize({ maxWidth: 120 })
              if (this.channelBadge(channel).length > 0) {
                Text(this.channelBadge(channel)).fontSize(9)
                  .fontColor(channel.sessionId === this.dshChannelId ? Color.White : '#8A6D3B')
              }
            }
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .backgroundColor(channel.sessionId === this.dshChannelId ? '#3478F6' : '#EEF1F6')
            .borderRadius(14)
            .onClick((): void => { this.selectChannel(channel.sessionId); })
          }, (channel: DshChannel): string => channel.sessionId + '#' + channel.revision)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .layoutWeight(1)
      if (this.dshChannels.length > 0) {
        Button('+').fontSize(14).width(30).height(30).padding(0)
          .backgroundColor('#EEF1F6').fontColor('#374151')
          .enabled(!this.dshLoading)
          .onClick((): void => { this.createDshSession(); })
      }
    }
    .width('100%').padding({ left: 10, right: 10, top: 2, bottom: 6 })
  }

  @Builder
  mainContent() {
    Column() {
      Row() {
        Text(this.dshMode ? 'ClawMate · DSH' : 'ClawMate Core')
          .fontSize(16).fontWeight(FontWeight.Bold).layoutWeight(1)
        if (this.dshMode && this.dshChannels.length > 0) {
          Text(this.runningCount() > 0 ? this.runningCount() + ' 个会话运行中' : this.phase)
            .fontSize(11).fontColor('#6B7280').margin({ right: 8 })
        } else {
          Text(this.phase).fontSize(11).fontColor('#6B7280').margin({ right: 8 })
        }
        // 设置面板随时可开：running 只表示有任务在跑，不该拦住配置入口。
        Button(this.showSettings ? '关闭' : '设置').fontSize(12).height(30)
          .onClick((): void => { this.showSettings = !this.showSettings; })
      }.width('100%').padding(12)
      if (this.showSettings) { this.settingsPanel() }
      if (this.dshMode) {
        this.channelBar()
        Scroll(this.scroller) {
          Column() {
            if (this.dshViewMessages.length === 0) {
              Text(this.dshChannels.length === 0 ?
                '还没有 DSH 会话，点右上角 + 新建。' : '在「' + this.currentChannelTitle() + '」里输入消息。')
                .fontSize(14).fontColor('#6B7280').padding(20)
            }
            ForEach(this.dshViewMessages, (message: ChatMessage): void => {
              ChatMessageView({ message: message, now: this.now,
                onSelect: (): void => { this.following = false; },
                onToggle: (id: number): void => {
                  this.following = false;
                  let item = this.dshViewMessages.find((candidate: ChatMessage): boolean => candidate.id === id);
                  if (item !== undefined) { item.collapsed = !item.collapsed; }
                } })
            }, (message: ChatMessage): string => 'dsh-msg-' + message.id)
          }.width('100%')
        }
        .layoutWeight(1).width('100%').align(Alignment.Top)
        .onTouch((event: TouchEvent): void => {
          if (event.type === TouchType.Down) { this.following = false; this.userScrolling = true; }
        })
        .onScrollStop((): void => {
          if (this.userScrolling) { this.following = this.scroller.isAtEnd(); this.userScrolling = false; }
        })
      } else {
        Scroll(this.scroller) {
          Column() {
            if (this.messages.length === 0) {
              Text('输入任务开始，例如“打开设置”或“新建一条备忘录”。')
                .fontSize(14).fontColor('#6B7280').padding(20)
            }
            ForEach(this.messages, (message: ChatMessage): void => {
              ChatMessageView({ message: message, now: this.now,
                onSelect: (): void => { this.following = false; }, onToggle: (id: number): void => {
                this.following = false;
                this.updateMessage(id, (item: ChatMessage): void => { item.collapsed = !item.collapsed; });
              } })
            },
              (message: ChatMessage): string => message.id.toString())
          }.width('100%').padding({ left: 10, right: 10 })
        }.layoutWeight(1).width('100%').align(Alignment.Top)
        .onTouch((event: TouchEvent): void => {
          if (event.type === TouchType.Down) { this.following = false; this.userScrolling = true; }
        })
        .onScrollStop((): void => {
          if (this.userScrolling) { this.following = this.scroller.isAtEnd(); this.userScrolling = false; }
        })
      }
      Row({ space: 8 }) {
        Text(this.keyboardLabel).fontSize(11).fontColor('#6B7280').layoutWeight(1)
        Button('切换输入法').fontSize(11).height(28)
          .enabled(this.dshMode ? true : !this.running)
          .onClick((): void => { this.chooseKeyboard(); })
      }.width('100%').padding({ left: 12, right: 12, top: 4, bottom: 4 })
      if (this.keyboardNotice) {
        Text(this.keyboardNotice).fontSize(12).fontColor('#8A6D3B').padding(8)
      }
      Row({ space: 8 }) {
        TextInput({ text: this.inputText, placeholder: this.dshMode ? '输入消息，发送给电脑 DSH' : '输入任务（支持中文）' })
          .type(InputType.Normal).fontSize(15).layoutWeight(1).height(42)
          .enabled(this.dshMode ? !this.dshLoading : !this.running)
          .copyOption(CopyOptions.LocalDevice)
          .onChange((value: string): void => { this.inputText = value; })
          .onSubmit((): void => { this.send(); })
        if (this.dshMode) {
          // 读取 dshRevision 建立依赖：channel.running 变化后按钮才会切换。
          if (this.dshRevision >= 0 && this.currentChannelRunning()) {
            Button(this.currentChannelStopping() ? '停止中' : '停止').height(42).backgroundColor('#D9534F')
              .enabled(!this.currentChannelStopping())
              .onClick((): void => { this.stopDsh(); })
          } else {
            Button('发送').height(42).enabled(this.inputText.trim().length > 0 && !this.dshLoading)
              .onClick((): void => { this.send(); })
          }
        } else if (this.running) {
          Button(this.stopping ? '停止中' : '停止').height(42).backgroundColor('#D9534F').enabled(!this.stopping)
            .onClick((): void => { this.stop(); })
        } else {
          Button('发送').height(42).enabled(this.inputText.trim().length > 0)
            .onClick((): void => { this.send(); })
        }
      }.width('100%').padding({ left: 10, right: 10, top: 4, bottom: 12 })
    }.width('100%').height('100%').backgroundColor('#FAFAFC')
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      this.mainContent()
      if (this.taskNotice) {
        Row({ space: 10 }) {
          Text(this.taskNoticeStatus === 'success' ? '✓' : '!')
            .fontSize(20).fontWeight(FontWeight.Bold)
            .fontColor(this.taskNoticeStatus === 'success' ? '#166534' : '#8A6D3B')
          Text(this.taskNotice).fontSize(14).layoutWeight(1)
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontColor(this.taskNoticeStatus === 'success' ? '#166534' : '#8A6D3B')
        }.width('92%').constraintSize({ maxWidth: 520 }).height(56)
        .padding({ left: 16, right: 16 }).margin({ top: 8 })
        .backgroundColor(this.taskNoticeStatus === 'success' ? '#EAF7EE' : '#FFF7E6')
        .borderRadius(12).shadow({ radius: 12, color: '#26000000', offsetY: 3 })
        .hitTestBehavior(HitTestMode.None)
        .transition(TransitionEffect.move(TransitionEdge.TOP).combine(TransitionEffect.OPACITY))
      }
    }.width('100%').height('100%')
  }
}
