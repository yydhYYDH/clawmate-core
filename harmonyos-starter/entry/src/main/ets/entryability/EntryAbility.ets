import { UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Runtime } from '../platform/Runtime';

export default class EntryAbility extends UIAbility {
  onCreate(): void { Runtime.context = this.context; }
  onWindowStageCreate(stage: window.WindowStage): void {
    stage.loadContent('pages/Index', (error): void => {
      if (error.code) { hilog.error(0, 'ClawMateLab', '页面加载失败 %{public}d', error.code); }
    });
  }
  onForeground(): void { Runtime.foreground(); }
  onBackground(): void { Runtime.onBackground(); }
  onDestroy(): void { Runtime.stop(); Runtime.finish(); }
  onWindowStageDestroy(): void { Runtime.stop(); }
}
