import { AgentRunner, AgentCallbacks } from '../core/AgentRunner';
import { AppRuntime } from '../core/AppRuntime';
import { EndpointConfig } from '../core/EndpointConfig';

interface ChatMessage {
  id: number;
  role: string; // 'user' | 'log' | 'result'
  text: string;
}

@Entry
@Component
struct Index {
  @State messages: ChatMessage[] = [];
  @State inputText: string = '';
  @State running: boolean = false;
  @State phase: string = '空闲';
  @State showSettings: boolean = false;

  @State hdcIp: string = '127.0.0.1';
  @State hdcPort: string = '8710';
  @State plannerUrl: string = '';
  @State plannerKey: string = '';
  @State deciderUrl: string = '';
  @State deciderKey: string = '';

  private runner: AgentRunner | null = null;
  private nextId: number = 1;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    let ep: EndpointConfig = AppRuntime.getEndpoints();
    this.hdcIp = ep.hdcIp;
    this.hdcPort = String(ep.hdcPort);
    this.plannerUrl = ep.plannerBaseUrl;
    this.plannerKey = ep.plannerApiKey;
    this.deciderUrl = ep.deciderBaseUrl;
    this.deciderKey = ep.deciderApiKey;
    this.append('log', 'ClawMate Core 就绪。输入任务开始，例如「打开设置」或「在新备忘录里写一句话」。');
    this.append('log', 'self-HDC 目标 ' + ep.hdcIp + ':' + ep.hdcPort +
      '；planner ' + ep.plannerBaseUrl + '；decider ' + ep.deciderBaseUrl);
  }

  private append(role: string, text: string): void {
    this.messages.push({ id: this.nextId++, role: role, text: text });
    setTimeout((): void => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 30);
  }

  private applySettings(): void {
    let port = Number(this.hdcPort);
    let ep: EndpointConfig = {
      hdcIp: this.hdcIp.trim(),
      hdcPort: Number.isFinite(port) ? port : 8710,
      plannerBaseUrl: this.plannerUrl.trim(),
      plannerApiKey: this.plannerKey.trim(),
      plannerModel: '',
      deciderBaseUrl: this.deciderUrl.trim(),
      deciderApiKey: this.deciderKey.trim(),
      deciderModel: ''
    };
    AppRuntime.setEndpoints(ep);
    this.showSettings = false;
    this.append('log', '已保存端点配置：HDC ' + ep.hdcIp + ':' + ep.hdcPort);
  }

  private send(): void {
    let task = this.inputText.trim();
    if (task.length === 0 || this.running) {
      return;
    }
    this.inputText = '';
    this.append('user', task);
    this.runTask(task);
  }

  private async runTask(task: string): Promise<void> {
    this.running = true;
    let runner = new AgentRunner(AppRuntime.getEndpoints());
    this.runner = runner;
    let callbacks: AgentCallbacks = {
      onLog: (line: string): void => { this.append('log', line); },
      onPhase: (phase: string): void => { this.phase = phase; },
      onStep: (step: number, maxSteps: number, action: string): void => {
        this.phase = '第 ' + step + '/' + maxSteps + ' 步 · ' + action;
      }
    };
    try {
      await runner.run(task, callbacks);
      this.append('result', '任务完成 ✅');
    } catch (e) {
      this.append('result', '任务失败 ❌ ' + (e as Error).message);
    } finally {
      this.running = false;
      this.runner = null;
      this.phase = '空闲';
    }
  }

  private stop(): void {
    if (this.runner !== null) {
      this.runner.cancel();
      this.append('log', '已请求停止…');
    }
  }

  @Builder
  messageBubble(message: ChatMessage) {
    Row() {
      if (message.role === 'user') {
        Blank();
        Text(message.text)
          .fontSize(15)
          .fontColor(Color.White)
          .padding(10)
          .constraintSize({ maxWidth: '78%' })
          .backgroundColor('#3478F6')
          .borderRadius(12)
      } else {
        Text(message.text)
          .fontSize(13)
          .fontColor(message.role === 'result' ? '#B00020' : '#333333')
          .padding(10)
          .constraintSize({ maxWidth: '88%' })
          .backgroundColor(message.role === 'result' ? '#FDECEA' : '#F1F1F3')
          .borderRadius(10)
        Blank();
      }
    }
    .width('100%')
    .margin({ top: 4, bottom: 4 })
  }

  @Builder
  settingsPanel() {
    Column({ space: 8 }) {
      Text('端点配置').fontSize(14).fontWeight(FontWeight.Bold)
      this.field('HDC IP', this.hdcIp, (v: string): void => { this.hdcIp = v; })
      this.field('HDC 端口', this.hdcPort, (v: string): void => { this.hdcPort = v; })
      this.field('Planner URL', this.plannerUrl, (v: string): void => { this.plannerUrl = v; })
      this.field('Planner Key', this.plannerKey, (v: string): void => { this.plannerKey = v; })
      this.field('Decider URL', this.deciderUrl, (v: string): void => { this.deciderUrl = v; })
      this.field('Decider Key', this.deciderKey, (v: string): void => { this.deciderKey = v; })
      Row({ space: 12 }) {
        Button('保存').fontSize(13).onClick((): void => { this.applySettings(); })
        Button('取消').fontSize(13).backgroundColor('#888888')
          .onClick((): void => { this.showSettings = false; })
      }
    }
    .padding(12)
    .width('100%')
    .backgroundColor('#FAFAFA')
    .border({ width: { bottom: 1 }, color: '#E0E0E0' })
  }

  @Builder
  field(label: string, value: string, onChange: (v: string) => void) {
    Row({ space: 8 }) {
      Text(label).fontSize(12).width(84).fontColor('#666666')
      TextInput({ text: value })
        .fontSize(13)
        .layoutWeight(1)
        .height(36)
        .onChange(onChange)
    }
  }

  build() {
    Column() {
      Row() {
        Text('ClawMate Core').fontSize(16).fontWeight(FontWeight.Bold).layoutWeight(1)
        Text(this.phase).fontSize(12).fontColor('#666666').margin({ right: 10 })
        Button(this.showSettings ? '关闭' : '设置')
          .fontSize(12).height(30)
          .onClick((): void => { this.showSettings = !this.showSettings; })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })

      if (this.showSettings) {
        this.settingsPanel()
      }

      Scroll(this.scroller) {
        Column() {
          ForEach(this.messages, (item: ChatMessage): void => {
            this.messageBubble(item)
          }, (item: ChatMessage): string => item.id.toString())
        }
        .width('100%')
        .padding({ left: 10, right: 10 })
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .width('100%')

      Row({ space: 8 }) {
        TextInput({ text: this.inputText, placeholder: '输入任务，例如：打开设置' })
          .fontSize(15)
          .layoutWeight(1)
          .height(42)
          .enabled(!this.running)
          .onChange((value: string): void => { this.inputText = value; })
          .onSubmit((): void => { this.send(); })
        if (this.running) {
          Button('停止').height(42).backgroundColor('#D9534F')
            .onClick((): void => { this.stop(); })
        } else {
          Button('发送').height(42)
            .enabled(this.inputText.trim().length > 0)
            .onClick((): void => { this.send(); })
        }
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 8, bottom: 12 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.White)
  }
}
