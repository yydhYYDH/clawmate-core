import { inputMethod } from '@kit.IMEKit';
import { AppRuntime } from './AppRuntime';

export class PhoneInputMethod {
  static currentLabel(): string {
    let current = inputMethod.getCurrentInputMethod();
    let subtype = inputMethod.getCurrentInputMethodSubtype();
    return (current.label || current.name) + (subtype.language ? ' · ' + subtype.language : '');
  }

  static async openSettings(): Promise<void> {
    try {
      let target = inputMethod.getSystemInputMethodConfigAbility();
      if (target.bundleName && target.abilityName) {
        await AppRuntime.getContext().startAbility({
          bundleName: target.bundleName, abilityName: target.abilityName, moduleName: target.moduleName
        });
        return;
      }
    } catch (e) { /* 部分开发板未提供独立输入法配置页面，回退系统设置。 */ }
    await AppRuntime.getContext().startAbility({
      bundleName: 'com.ohos.settings', abilityName: 'com.ohos.settings.MainAbility'
    });
  }
}
