import { inputMethod, InputMethodListDialog } from '@kit.IMEKit';
import { AgentRunner, AgentCallbacks } from '../core/AgentRunner';
import { AgentRunError, AgentRunResult } from '../core/AgentRunState';
import { AppRuntime } from '../core/AppRuntime';
import { EndpointConfig } from '../core/EndpointConfig';
import { PhoneInputMethod } from '../core/PhoneInputMethod';
import { Logger } from '../core/Logger';

@Observed
class ChatMessage {
  id: number;
  role: string;
  paragraphs: string[] = [];
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

function duration(ms: number): string {
  let seconds = Math.max(0, Math.floor(ms / 1000));
  return Math.floor(seconds / 60).toString().padStart(2, '0') + ':' + (seconds % 60).toString().padStart(2, '0');
}

@Component
struct ChatMessageView {
  @ObjectLink message: ChatMessage;
  @Prop now: number = 0;
  onToggle: (id: number) => void = (_id: number): void => {};

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
            .width('100%').copyOption(CopyOptions.InApp)
        }, (text: string, index: number): string => this.message.id + '-body-' + index)
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
                Text(line).fontSize(11).fontColor('#8B95A5').width('100%').copyOption(CopyOptions.InApp)
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
  @State hdcIp: string = '127.0.0.1';
  @State hdcPort: string = '8710';
  @State plannerUrl: string = '';
  @State plannerKey: string = '';
  @State deciderUrl: string = '';
  @State deciderKey: string = '';

  private runner: AgentRunner | null = null;
  private activeMessageId: number = -1;
  private nextId: number = 1;
  private timer: number = -1;
  private scrollTimer: number = -1;
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
    this.refreshKeyboard();
    try { inputMethod.getSetting().on('imeChange', this.imeChanged); } catch (e) {
      Logger.warn('输入法监听失败: ' + (e as Error).message);
    }
  }

  aboutToDisappear(): void {
    if (this.runner !== null) { this.runner.cancel(); }
    clearInterval(this.timer);
    clearTimeout(this.scrollTimer);
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
      this.keyboardNotice = '无法打开选择框，请通过“系统设置”切换。';
      Logger.warn((e as Error).message);
    }
  }

  private async keyboardSettings(): Promise<void> {
    try {
      await PhoneInputMethod.openSettings();
      this.keyboardNotice = '请在系统设置中管理输入法。只有英文键盘时，需要先安装中文输入法。';
    } catch (e) {
      this.keyboardNotice = '无法打开输入法设置，请到系统设置中启用中文输入法。';
      Logger.warn((e as Error).message);
    }
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
    this.showSettings = false;
  }

  private send(): void {
    let task = this.inputText.trim();
    if (!task || this.running) { return; }
    this.inputText = '';
    this.following = true;
    let time = Date.now();
    let message = new ChatMessage(this.nextId++, 'user');
    message.paragraphs = [task];
    this.messages.push(message);
    this.runTask(task);
  }

  private async runTask(task: string): Promise<void> {
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
      this.refreshKeyboard();
    }
  }

  private stop(): void {
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
      Button('保存').fontSize(13).onClick((): void => { this.applySettings(); })
    }.padding(12).width('100%').backgroundColor('#FAFAFA')
  }

  build() {
    Column() {
      Row() {
        Text('ClawMate Core').fontSize(16).fontWeight(FontWeight.Bold).layoutWeight(1)
        Text(this.phase).fontSize(11).fontColor('#6B7280').margin({ right: 8 })
        Button(this.showSettings ? '关闭' : '设置').fontSize(12).height(30).enabled(!this.running)
          .onClick((): void => { this.showSettings = !this.showSettings; })
      }.width('100%').padding(12)
      if (this.showSettings) { this.settingsPanel() }
      Scroll(this.scroller) {
        Column() {
          if (this.messages.length === 0) {
            Text('输入任务开始，例如“打开设置”或“新建一条备忘录”。')
              .fontSize(14).fontColor('#6B7280').padding(20)
          }
          ForEach(this.messages, (message: ChatMessage): void => {
            ChatMessageView({ message: message, now: this.now, onToggle: (id: number): void => {
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
      Row({ space: 8 }) {
        Text(this.keyboardLabel).fontSize(11).fontColor('#6B7280').layoutWeight(1)
        Button('切换输入法').fontSize(11).height(28).enabled(!this.running)
          .onClick((): void => { this.chooseKeyboard(); })
        Button('系统设置').fontSize(11).height(28).enabled(!this.running)
          .onClick((): void => { this.keyboardSettings(); })
      }.width('100%').padding({ left: 12, right: 12, top: 4, bottom: 4 })
      if (this.keyboardNotice) {
        Text(this.keyboardNotice).fontSize(12).fontColor('#8A6D3B').padding(8)
      }
      Row({ space: 8 }) {
        TextInput({ text: this.inputText, placeholder: '输入任务（支持中文）' })
          .type(InputType.Normal).fontSize(15).layoutWeight(1).height(42).enabled(!this.running)
          .onChange((value: string): void => { this.inputText = value; })
          .onSubmit((): void => { this.send(); })
        if (this.running) {
          Button(this.stopping ? '停止中' : '停止').height(42).backgroundColor('#D9534F').enabled(!this.stopping)
            .onClick((): void => { this.stop(); })
        } else {
          Button('发送').height(42).enabled(this.inputText.trim().length > 0)
            .onClick((): void => { this.send(); })
        }
      }.width('100%').padding({ left: 10, right: 10, top: 4, bottom: 12 })
    }.width('100%').height('100%').backgroundColor('#FAFAFC')
  }
}
