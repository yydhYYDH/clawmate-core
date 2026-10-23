import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { EndpointConfig, DEFAULT_ENDPOINTS } from './EndpointConfig';

// 全局运行上下文：持有 UIAbilityContext（用于 filesDir 与拉起自身）以及端点配置。
// DSH 的地址与认证 cookie 落在 Preferences 里，重启后自动恢复（cookie 有效期 30 天）。
export class AppRuntime {
  private static context: common.UIAbilityContext | undefined = undefined;
  private static endpoints: EndpointConfig = DEFAULT_ENDPOINTS;
  private static dshUrl: string = '';
  private static dshCookie: string = '';
  private static store: preferences.Preferences | undefined = undefined;

  private static readonly PREF_NAME: string = 'clawmate_dsh';
  private static readonly KEY_URL: string = 'dshUrl';
  private static readonly KEY_COOKIE: string = 'dshCookie';

  static setContext(context: common.UIAbilityContext): void {
    AppRuntime.context = context;
  }

  static getContext(): common.UIAbilityContext {
    if (AppRuntime.context === undefined) {
      throw new Error('AppRuntime: context 尚未就绪');
    }
    return AppRuntime.context;
  }

  static filesDir(): string {
    return AppRuntime.getContext().filesDir;
  }

  static bundleName(): string {
    return AppRuntime.getContext().abilityInfo.bundleName;
  }

  static getEndpoints(): EndpointConfig {
    return AppRuntime.endpoints;
  }

  static setEndpoints(config: EndpointConfig): void {
    AppRuntime.endpoints = config;
  }

  private static prefs(): preferences.Preferences {
    if (AppRuntime.store === undefined) {
      let options: preferences.Options = { name: AppRuntime.PREF_NAME };
      AppRuntime.store = preferences.getPreferencesSync(AppRuntime.getContext(), options);
    }
    return AppRuntime.store;
  }

  // 读取已持久化的 DSH 设置，页面启动时调用一次。
  static loadDshSettings(): void {
    try {
      let store = AppRuntime.prefs();
      let url = store.getSync(AppRuntime.KEY_URL, '') as string;
      let cookie = store.getSync(AppRuntime.KEY_COOKIE, '') as string;
      if (url.length > 0) { AppRuntime.dshUrl = url; }
      if (cookie.length > 0) { AppRuntime.dshCookie = cookie; }
    } catch (e) {
      // Preferences 不可用时退回内存态，不阻断页面。
    }
  }

  static getDshUrl(): string {
    return AppRuntime.dshUrl;
  }

  static setDshUrl(url: string): void {
    AppRuntime.dshUrl = url;
    AppRuntime.persist(AppRuntime.KEY_URL, url);
  }

  static getDshCookie(): string {
    return AppRuntime.dshCookie;
  }

  static setDshCookie(cookie: string): void {
    AppRuntime.dshCookie = cookie;
    AppRuntime.persist(AppRuntime.KEY_COOKIE, cookie);
  }

  static clearDshAuth(): void {
    AppRuntime.dshCookie = '';
    AppRuntime.persist(AppRuntime.KEY_COOKIE, '');
  }

  private static persist(key: string, value: string): void {
    try {
      let store = AppRuntime.prefs();
      store.putSync(key, value);
      store.flushSync();
    } catch (e) {
      // 写盘失败不影响本次会话内的使用。
    }
  }
}
