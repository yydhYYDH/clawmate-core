import { common } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { RunScope } from '../core/RunScope';

export class Runtime {
  static context: common.UIAbilityContext;
  private static active: RunScope | null = null;
  private static delayId: number = -1;
  private static expiryTimer: number = -1;
  static begin(scope: RunScope): void { Runtime.active = scope; }
  static stop(): void { if (Runtime.active !== null) { Runtime.active.stop(); } }
  static foreground(): void {
    Runtime.releaseDelay();
  }
  static onBackground(): void {
    if (Runtime.active === null) { return; }
    try {
      let delay = backgroundTaskManager.requestSuspendDelay('完成当前用户发起的短时任务', (): void => {
        if (Runtime.active !== null) { Runtime.active.stop('suspended', '系统后台额度到期，请返回 App 后重新发起任务。'); }
      });
      Runtime.delayId = delay.requestId;
      let milliseconds = Math.max(0, delay.actualDelayTime - 1000);
      Runtime.active.limit(milliseconds);
      Runtime.expiryTimer = setTimeout((): void => {
        if (Runtime.active !== null) { Runtime.active.stop('suspended', '后台运行额度到期。'); }
      }, milliseconds);
    } catch (e) {
      Runtime.active.stop('suspended', '系统未授予短时后台运行额度，任务已暂停。');
    }
  }
  static finish(scope?: RunScope): void {
    if (scope !== undefined && Runtime.active !== scope) { return; }
    Runtime.active = null; Runtime.releaseDelay();
  }
  private static releaseDelay(): void {
    clearTimeout(Runtime.expiryTimer);
    if (Runtime.delayId >= 0) {
      try { backgroundTaskManager.cancelSuspendDelay(Runtime.delayId); } catch (e) { /* 可能已到期。 */ }
      Runtime.delayId = -1;
    }
  }
}
