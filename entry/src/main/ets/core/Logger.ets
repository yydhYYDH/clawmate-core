import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'ClawMateCore';

// 同时输出到 hilog，便于用 `hdc hilog -T ClawMateCore` 抓运行日志。
export class Logger {
  static info(message: string): void {
    hilog.info(DOMAIN, TAG, '%{public}s', Logger.clamp(message));
  }

  static warn(message: string): void {
    hilog.warn(DOMAIN, TAG, '%{public}s', Logger.clamp(message));
  }

  static error(message: string): void {
    hilog.error(DOMAIN, TAG, '%{public}s', Logger.clamp(message));
  }

  private static clamp(message: string): string {
    let text = message.replace(/\s+/g, ' ').trim();
    return text.length <= 900 ? text : text.substring(0, 900) + '...';
  }
}
