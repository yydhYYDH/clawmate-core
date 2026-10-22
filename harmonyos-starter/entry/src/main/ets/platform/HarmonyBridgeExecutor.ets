import { Action, Capabilities, Receipt, Screenshot, Session, Settings } from '../core/Types';
import { endpoint } from '../core/Domain';
import { RunScope } from '../core/RunScope';
import { requestJson } from './HttpJson';
import { DeviceExecutor } from './DeviceExecutor';

interface SessionBody { session: string; }
interface StartBody { session: string; bundle: string; query?: string; }
interface ActionBody { session: string; action: Action; }

export class HarmonyBridgeExecutor implements DeviceExecutor {
  private base: string;
  private token: string;
  private session: string = '';
  constructor(settings: Settings) { this.base = endpoint(settings.bridgeUrl); this.token = settings.bridgeToken; }

  async open(scope: RunScope): Promise<Capabilities> {
    if (!this.token.trim()) { throw new Error('请填写电脑调试桥的临时令牌。'); }
    let caps = await requestJson<Capabilities>(this.base + '/capabilities', '{}', scope, this.token);
    if (!caps.screenshot || !caps.actions || caps.apps.length === 0) {
      throw new Error('调试桥未就绪：' + caps.reason);
    }
    // 创建会话使用独立短请求，确保上层取消后仍能拿到 ID 并释放，避免孤儿会话。
    let value = await requestJson<Session>(this.base + '/session/open', '{}', new RunScope(10000), this.token);
    this.session = value.id;
    scope.check();
    return caps;
  }
  async startApp(bundle: string, scope: RunScope, query?: string): Promise<void> {
    let body: StartBody = { session: this.session, bundle: bundle };
    if (query !== undefined) { body.query = query; }
    await requestJson<Receipt>(this.base + '/app/start', JSON.stringify(body), scope, this.token);
  }
  async screenshot(scope: RunScope): Promise<Screenshot> {
    let body: SessionBody = { session: this.session };
    let result = await requestJson<Screenshot>(this.base + '/screen', JSON.stringify(body), scope, this.token);
    if ((result.mime !== 'image/jpeg' && result.mime !== 'image/png') || typeof result.base64 !== 'string' || !result.base64 ||
      !Number.isInteger(result.width) || !Number.isInteger(result.height) || result.width < 1 || result.height < 1) {
      throw new Error('调试桥没有返回有效屏幕图像。');
    }
    return result;
  }
  async execute(action: Action, scope: RunScope): Promise<string> {
    let body: ActionBody = { session: this.session, action: action };
    let result = await requestJson<Receipt>(this.base + '/action', JSON.stringify(body), scope, this.token);
    return result.message;
  }
  async returnHost(): Promise<void> { await this.cleanup('/host/return'); }
  async cancel(): Promise<void> { await this.cleanup('/session/cancel'); }
  async close(): Promise<void> { await this.cleanup('/session/close'); this.session = ''; }
  private async cleanup(path: string): Promise<void> {
    if (!this.session) { return; }
    let body: SessionBody = { session: this.session };
    await requestJson<Receipt>(this.base + path, JSON.stringify(body), new RunScope(10000), this.token);
  }
}
