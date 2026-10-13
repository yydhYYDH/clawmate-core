import { common } from '@kit.AbilityKit';
import { EndpointConfig, DEFAULT_ENDPOINTS } from './EndpointConfig';

// 全局运行上下文：持有 UIAbilityContext（用于 filesDir 与拉起自身）以及端点配置。
export class AppRuntime {
  private static context: common.UIAbilityContext | undefined = undefined;
  private static endpoints: EndpointConfig = DEFAULT_ENDPOINTS;

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
}
