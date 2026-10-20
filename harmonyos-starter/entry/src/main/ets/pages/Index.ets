import { Attachment, defaultSettings, Note, RunResult, Settings } from '../core/Types';
import { makeQuestion } from '../core/Domain';
import { RunScope, RunStopped } from '../core/RunScope';
import { complete } from '../core/ModelService';
import { AgentRunner } from '../core/AgentRunner';
import { Files } from '../platform/Files';
import { Repository } from '../platform/Repository';
import { Runtime } from '../platform/Runtime';
import { HarmonyBridgeExecutor } from '../platform/HarmonyBridgeExecutor';

interface Message {
  id: number;
  role: string;
  text: string;
  status: string;
  attachments: Attachment[];
}

@Entry
@Component
struct Index {
  @State tab: number = 0;
  @State mode: number = 0;
  @State input: string = '';
  @State messages: Message[] = [];
  @State attachments: Attachment[] = [];
  @State notes: Note[] = [];
  @State notice: string = '';
  @State phase: string = '就绪';
  @State logs: string[] = [];
  @State showLogs: boolean = false;
  @State running: boolean = false;
  @State ioBusy: boolean = false;
  @State pendingUri: string = '';
  @State pendingKind: string = '';
  @State modelUrl: string = '';
  @State modelName: string = '';
  @State modelKey: string = '';
  @State vision: boolean = false;
  @State bridgeUrl: string = '';
  @State bridgeToken: string = '';
  @State targetBundle: string = '';
  @State targetAbility: string = '';

  private files: Files | null = null;
  private repo: Repository | null = null;
  private scope: RunScope | null = null;
  private executor: HarmonyBridgeExecutor | null = null;
  private alive: boolean = true;
  private counter: number = 1;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.alive = true;
    this.files = new Files(Runtime.context);
    this.repo = new Repository(Runtime.context);
    this.initialize();
  }
  aboutToDisappear(): void { this.alive = false; this.stop(); }

  private async initialize(): Promise<void> {
    this.ioBusy = true;
    try {
      let settings = await this.repo!.loadSettings();
      let notes = await this.repo!.loadNotes();
      if (!this.alive) { return; }
      this.modelUrl = settings.modelUrl;
      this.modelName = settings.model;
      this.modelKey = settings.modelKey;
      this.vision = settings.vision;
      this.bridgeUrl = settings.bridgeUrl;
      this.notes = notes;
      this.notice = '请选择资料问答或设备任务。首次使用请配置服务。';
    } catch (e) { this.notice = '初始化失败：' + (e as Error).message; }
    finally { this.ioBusy = false; }
  }

  private settings(): Settings {
    let value = defaultSettings();
    value.modelUrl = this.modelUrl.trim(); value.model = this.modelName.trim(); value.modelKey = this.modelKey;
    value.vision = this.vision; value.bridgeUrl = this.bridgeUrl.trim(); value.bridgeToken = this.bridgeToken;
    return value;
  }

  private async saveSettings(): Promise<void> {
    let settings = this.settings();
    if (!settings.modelUrl || !settings.model) { this.notice = '服务地址和模型名称不能为空。'; return; }
    this.ioBusy = true;
    try { await this.repo!.saveSettings(settings); this.notice = '设置已保存。重启后使用教师预置密钥；手动密钥和桥令牌仅本次运行有效。'; }
    catch (e) { this.notice = (e as Error).message; }
    finally { this.ioBusy = false; }
  }

  private async select(kind: string): Promise<void> {
    this.ioBusy = true;
    this.notice = '';
    try {
      let uri = kind === 'image' ? await this.files!.selectPhoto() : await this.files!.selectDocument();
      if (!this.alive) { return; }
      this.pendingUri = uri;
      this.pendingKind = uri ? kind : '';
      this.notice = uri ? '已选择，返回后点击“确认导入”。此时尚未读取或发送资料。' : '未选择资料。';
    } catch (e) { this.notice = '选择未完成：' + (e as Error).message; }
    finally { this.ioBusy = false; }
  }

  private async importPending(): Promise<void> {
    this.ioBusy = true;
    try {
      let item = await this.files!.importSelected(this.pendingUri, this.pendingKind);
      if (!this.alive) { await this.files!.remove(item); return; }
      let removed = this.attachments.filter((a: Attachment): boolean => a.kind === item.kind);
      this.attachments = this.attachments.filter((a: Attachment): boolean => a.kind !== item.kind).concat([item]);
      await this.repo!.removeUnused(removed, this.notes, this.allActive());
      this.pendingUri = ''; this.pendingKind = '';
      this.notice = '已导入 ' + item.name + (item.size === 0 ? '（空文件）' : '') + '，点击发送后才会提交给模型。';
    } catch (e) { this.notice = '导入失败：' + (e as Error).message; }
    finally { this.ioBusy = false; }
  }

  private allActive(): Attachment[] {
    let items = this.attachments.slice();
    for (let message of this.messages) { items = items.concat(message.attachments); }
    return items;
  }

  private async removeAttachment(item: Attachment): Promise<void> {
    this.ioBusy = true;
    try {
      this.attachments = this.attachments.filter((a: Attachment): boolean => a.id !== item.id);
      await this.repo!.removeUnused([item], this.notes, this.allActive());
    } catch (e) { this.notice = (e as Error).message; }
    finally { this.ioBusy = false; }
  }

  private log(line: string): void { if (this.alive) { this.logs = this.logs.concat([line]).slice(-100); } }

  private showLatest(): void {
    this.getUIContext().getFocusController().clearFocus();
    this.getUIContext().getPromptAction().showToast({ message: this.running ? '任务已开始' : '任务已结束，请查看回复' });
    setTimeout((): void => {
      if (this.alive && this.tab === 0) { this.scroller.scrollEdge(Edge.Bottom); }
    }, 100);
  }

  private async send(): Promise<void> {
    let question = this.input.trim();
    if (!question || this.running || this.ioBusy) { return; }
    if (this.pendingUri) { this.notice = '请先确认导入，或放弃待导入资料。'; return; }
    if (this.mode === 1 && this.attachments.length > 0) { this.notice = '设备任务不发送资料附件。请先移除附件或切换到资料问答。'; return; }
    if (this.mode === 1 && !this.vision) { this.notice = '设备任务需要视觉模型，请在设置中确认支持图片。'; return; }
    let settings = this.settings();
    let selected = this.attachments.slice();
    let scope = new RunScope(this.mode === 1 ? 120000 : 90000);
    let id = this.counter++;
    this.scope = scope; this.running = true; this.input = ''; this.notice = ''; this.logs = [];
    this.messages = this.messages.concat([{ id: this.counter++, role: 'user', text: question, status: '', attachments: selected },
      { id: id, role: 'assistant', text: '', status: 'running', attachments: selected }]);
    this.showLatest();
    Runtime.begin(scope);
    let result: RunResult = { status: 'failed', message: '尚未完成。' };
    try {
      if (this.mode === 0) {
        this.phase = '准备资料';
        let images: string[] = [];
        for (let item of selected) {
          scope.check();
          if (item.kind === 'image') { images.push(await this.files!.imageData(item)); }
        }
        scope.check();
        let body = makeQuestion(settings.model, question, selected, images, settings.vision);
        this.phase = '等待模型';
        let reply = await complete(settings, body, scope);
        scope.check();
        result = { status: 'success', message: reply };
      } else {
        let executor = new HarmonyBridgeExecutor(settings);
        this.executor = executor;
        result = await new AgentRunner(settings, executor).run(question, scope, {
          log: (line: string): void => { this.log(line); },
          phase: (value: string): void => { if (this.alive) { this.phase = value; } }
        });
        scope.check();
      }
    } catch (e) {
      let error = e as Error;
      result = { status: error instanceof RunStopped ? error.status : 'failed', message: error.message };
    } finally {
      Runtime.finish(scope);
      this.scope = null; this.executor = null;
      if (this.alive) {
        this.messages = this.messages.map((m: Message): Message => m.id === id ?
          { id: m.id, role: m.role, text: result.message, status: result.status, attachments: m.attachments } : m);
        this.phase = '就绪'; this.running = false;
        this.tab = 0;
        this.showLatest();
      }
    }
  }

  private stop(): void {
    if (this.scope !== null) { this.scope.stop(); }
    if (this.executor !== null) {
      this.executor.cancel().catch((): void => { this.log('取消尚未得到桥接端确认。'); });
    }
  }

  private async saveNote(message: Message): Promise<void> {
    this.ioBusy = true;
    try {
      let note: Note = { id: Date.now().toString(), text: message.text, createdAt: Date.now(), attachments: message.attachments.slice() };
      let next = [note].concat(this.notes);
      await this.repo!.saveNotes(next); this.notes = next; this.notice = '笔记已保存，正常退出并重启后可查看。';
    } catch (e) { this.notice = '保存失败：' + (e as Error).message; }
    finally { this.ioBusy = false; }
  }

  private async deleteNote(note: Note): Promise<void> {
    this.ioBusy = true;
    try {
      let next = this.notes.filter((n: Note): boolean => n.id !== note.id);
      await this.repo!.saveNotes(next); this.notes = next;
      await this.repo!.removeUnused(note.attachments, next, this.allActive());
    } catch (e) { this.notice = (e as Error).message; }
    finally { this.ioBusy = false; }
  }

  private async restoreNote(note: Note): Promise<void> {
    this.ioBusy = true;
    try {
      let old = this.attachments.slice();
      this.attachments = note.attachments.slice(); this.mode = 0; this.tab = 0;
      await this.repo!.removeUnused(old, this.notes, this.allActive());
      this.notice = '笔记资料已附加，可以继续提问。';
    } catch (e) { this.notice = (e as Error).message; }
    finally { this.ioBusy = false; }
  }

  private async launchApp(): Promise<void> {
    this.ioBusy = true;
    try {
      if (!this.targetBundle.trim() || !this.targetAbility.trim()) { throw new Error('请填写教师已验证的目标包名和 Ability 名称。'); }
      await Runtime.context.startAbility({ bundleName: this.targetBundle.trim(), abilityName: this.targetAbility.trim() });
      this.notice = '启动请求已被接受；请实际检查目标应用是否出现在前台。';
    } catch (e) { this.notice = '启动失败：' + (e as Error).message; }
    finally { this.ioBusy = false; }
  }

  @Builder
  private chatPage() {
    Row({ space: 10 }) {
      Button('资料问答').backgroundColor(this.mode === 0 ? '#315CF5' : '#8893A6')
        .onClick((): void => { this.mode = 0; }).enabled(!this.running && !this.ioBusy)
      Button('设备任务').backgroundColor(this.mode === 1 ? '#315CF5' : '#8893A6')
        .onClick((): void => { this.mode = 1; }).enabled(!this.running && !this.ioBusy)
    }.width('100%')
    if (this.mode === 1) {
      Text('设备任务需要电脑调试桥与视觉模型。后台额度到期会暂停，不承诺持续保活。')
        .fontSize(12).fontColor('#6B7280').width('100%')
    }
    Scroll(this.scroller) {
      Column({ space: 12 }) {
        if (this.messages.length === 0) {
          Text('把图片和实验说明交给 ClawMate，或让它协助操作设备。').fontColor('#667085').padding(24)
        }
        ForEach(this.messages, (m: Message) => {
          Column({ space: 8 }) {
            Text(m.role === 'user' ? '你' : 'ClawMate · ' + m.status).fontSize(12).fontColor('#667085').width('100%')
            Text(m.text || this.phase).fontSize(16).fontColor('#182230').width('100%').copyOption(CopyOptions.LocalDevice)
            if (m.attachments.length > 0) {
              Text('资料：' + m.attachments.map((a: Attachment): string => a.name).join('、')).fontSize(12).fontColor('#667085')
            }
            if (m.role === 'assistant' && m.status === 'success') {
              Button('保存笔记').fontSize(12).onClick((): void => { this.saveNote(m); }).enabled(!this.running && !this.ioBusy)
            }
          }.alignItems(HorizontalAlign.Start).padding(14).width('100%')
          .backgroundColor(m.role === 'user' ? '#E9EEFF' : Color.White).borderRadius(14)
        }, (m: Message): string => m.id.toString() + '-' + m.status)
      }.width('100%')
    }.layoutWeight(1).width('100%')
    if (this.attachments.length > 0) {
      Scroll() {
        Column({ space: 8 }) {
          ForEach(this.attachments, (a: Attachment) => {
            Row({ space: 8 }) {
              if (a.kind === 'image') { Image('file://' + a.preview).width(64).height(64).objectFit(ImageFit.Contain) }
              Column() {
                Text(a.name + ' · ' + a.size + ' B').fontSize(12).maxLines(1)
                if (a.kind === 'text') { Text(a.text.substring(0, 120) || '空文件').fontSize(12).maxLines(3).fontColor('#667085') }
              }.layoutWeight(1)
              Button('移除').fontSize(12).onClick((): void => { this.removeAttachment(a); }).enabled(!this.running && !this.ioBusy)
            }.width('100%')
          }, (a: Attachment): string => a.id)
        }
      }.constraintSize({ maxHeight: 150 }).width('100%')
    }
    if (this.pendingUri) {
      Row({ space: 8 }) {
        Text('资料待导入').fontSize(12).layoutWeight(1)
        Button('确认导入').onClick((): void => { this.importPending(); }).enabled(!this.ioBusy && !this.running)
        Button('放弃').onClick((): void => { this.pendingUri = ''; this.pendingKind = ''; }).enabled(!this.ioBusy && !this.running)
      }
    }
    Row({ space: 8 }) {
      Button('图片').onClick((): void => { this.select('image'); }).enabled(!this.running && !this.ioBusy && this.mode === 0)
      Button('文件').onClick((): void => { this.select('text'); }).enabled(!this.running && !this.ioBusy && this.mode === 0)
      Button(this.showLogs ? '收起日志' : '日志').onClick((): void => { this.showLogs = !this.showLogs; })
    }.width('100%')
    if (this.showLogs) {
      Scroll() { Text(this.logs.join('\n') || '尚无设备任务日志').fontSize(11).copyOption(CopyOptions.LocalDevice).width('100%') }
        .height(80).width('100%')
    }
    Row({ space: 8 }) {
      TextInput({ text: this.input, placeholder: this.mode === 0 ? '输入资料问题' : '例如：打开计算器，计算 12 × 34' })
        .enterKeyType(EnterKeyType.Send).onSubmit((): void => { this.send(); })
        .onChange((value: string): void => { this.input = value; }).layoutWeight(1).enabled(!this.running && !this.ioBusy)
      if (this.running) { Button('停止').backgroundColor('#B42318').onClick((): void => { this.stop(); }) }
      else { Button('发送').onClick((): void => { this.send(); }).enabled(!this.ioBusy && this.input.trim().length > 0) }
    }.width('100%')
  }

  @Builder
  private notesPage() {
    Scroll() {
      Column({ space: 12 }) {
        Text('本地笔记 · ' + this.notes.length + ' / 50').fontSize(18).width('100%')
        if (this.notes.length === 0) { Text('在回复下方点击“保存笔记”。笔记与资料副本保存在本机。').fontColor('#667085') }
        ForEach(this.notes, (note: Note) => {
          Column({ space: 10 }) {
            Text(new Date(note.createdAt).toLocaleString()).fontSize(12).fontColor('#667085')
            Text(note.text).width('100%').copyOption(CopyOptions.LocalDevice)
            Text('关联资料：' + (note.attachments.map((a: Attachment): string => a.name).join('、') || '无')).fontSize(12)
            Row({ space: 10 }) {
              Button('继续问资料').onClick((): void => { this.restoreNote(note); }).enabled(!this.running && !this.ioBusy)
              Button('删除').onClick((): void => { this.deleteNote(note); }).enabled(!this.running && !this.ioBusy)
            }
          }.padding(14).backgroundColor(Color.White).borderRadius(14).width('100%')
        }, (note: Note): string => note.id)
      }.width('100%')
    }.layoutWeight(1).width('100%')
  }

  @Builder
  private settingsPage() {
    Scroll() {
      Column({ space: 14 }) {
        Text('模型服务').fontSize(18).width('100%')
        Text('服务地址').fontSize(13).fontColor('#546174').width('100%')
        TextInput({ text: this.modelUrl, placeholder: '服务地址，如 https://服务地址/v1' })
          .onChange((v: string): void => { this.modelUrl = v; }).enabled(!this.running && !this.ioBusy)
        Text('模型名称').fontSize(13).fontColor('#546174').width('100%')
        TextInput({ text: this.modelName, placeholder: '模型名称' })
          .onChange((v: string): void => { this.modelName = v; }).enabled(!this.running && !this.ioBusy)
        Text('API Key（预置课堂默认）').fontSize(13).fontColor('#546174').width('100%')
        TextInput({ text: this.modelKey, placeholder: 'API Key（仅内存）' }).type(InputType.Password)
          .onChange((v: string): void => { this.modelKey = v; }).enabled(!this.running && !this.ioBusy)
        Row() {
          Text('此模型支持图片').layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.vision }).onChange((v: boolean): void => { this.vision = v; })
            .enabled(!this.running && !this.ioBusy)
        }.width('100%')
        Text('设备任务调试桥').fontSize(18).width('100%')
        Text('电脑需连接这台手机并运行随附 bridge/server.py。填写手机可访问的电脑地址；127.0.0.1 表示手机自身。')
          .fontSize(12).fontColor('#667085')
        Text('桥地址').fontSize(13).fontColor('#546174').width('100%')
        TextInput({ text: this.bridgeUrl, placeholder: '桥地址，如 http://电脑局域网地址:8765' })
          .onChange((v: string): void => { this.bridgeUrl = v; }).enabled(!this.running && !this.ioBusy)
        Text('桥接令牌（仅内存）').fontSize(13).fontColor('#546174').width('100%')
        TextInput({ text: this.bridgeToken, placeholder: '桥接令牌（仅内存）' }).type(InputType.Password)
          .onChange((v: string): void => { this.bridgeToken = v; }).enabled(!this.running && !this.ioBusy)
        Button('保存设置').onClick((): void => { this.saveSettings(); }).enabled(!this.running && !this.ioBusy)
        Text('公开接口启动检查').fontSize(18).width('100%')
        Text('填写已确认的目标入口。此检查只发起启动，不证明目标业务已完成。').fontSize(12).fontColor('#667085')
        Text('目标 bundleName').fontSize(13).fontColor('#546174').width('100%')
        TextInput({ text: this.targetBundle, placeholder: '目标 bundleName' })
          .onChange((v: string): void => { this.targetBundle = v; }).enabled(!this.running && !this.ioBusy)
        Text('目标 abilityName').fontSize(13).fontColor('#546174').width('100%')
        TextInput({ text: this.targetAbility, placeholder: '目标 abilityName' })
          .onChange((v: string): void => { this.targetAbility = v; }).enabled(!this.running && !this.ioBusy)
        Button('发起启动').onClick((): void => { this.launchApp(); }).enabled(!this.running && !this.ioBusy)
      }.width('100%').padding({ bottom: 20 })
    }.layoutWeight(1).width('100%')
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Text('ClawMate Lab').fontSize(24).fontWeight(FontWeight.Bold).fontColor('#182230').layoutWeight(1)
        Text(this.ioBusy ? '处理中' : this.phase).fontSize(12).fontColor('#667085')
      }.width('100%')
      Row({ space: 10 }) {
        Button('对话').onClick((): void => { this.tab = 0; })
        Button('笔记').onClick((): void => { this.tab = 1; })
        Button('设置').onClick((): void => { this.tab = 2; })
      }.width('100%')
      if (this.notice) { Text(this.notice).fontSize(12).fontColor('#6B4E00').width('100%').constraintSize({ maxHeight: 64 }) }
      if (this.tab === 0) { this.chatPage() }
      else if (this.tab === 1) { this.notesPage() }
      else { this.settingsPage() }
      if (this.tab !== 0 && this.running) {
        Button('停止当前任务').backgroundColor('#B42318').onClick((): void => { this.stop(); })
      }
    }.padding(16).width('100%').height('100%').backgroundColor('#F3F5FA')
  }
}
