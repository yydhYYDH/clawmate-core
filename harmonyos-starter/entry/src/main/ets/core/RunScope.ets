export class RunStopped extends Error {
  status: string;
  constructor(status: string, message: string) { super(message); this.status = status; }
}

export class RunScope {
  private stopped: RunStopped | null = null;
  private listeners: (() => void)[] = [];
  private deadline: number;

  constructor(milliseconds: number = 90000) { this.deadline = Date.now() + milliseconds; }
  remaining(): number { return Math.max(0, this.deadline - Date.now()); }
  limit(milliseconds: number): void { this.deadline = Math.min(this.deadline, Date.now() + milliseconds); }
  check(): void {
    if (this.stopped !== null) { throw this.stopped; }
    if (this.remaining() <= 0) { this.stop('suspended', '运行时间已到，已暂停后续动作。'); throw this.stopped!; }
  }
  stop(status: string = 'cancelled', message: string = '任务已取消。'): void {
    if (this.stopped !== null) { return; }
    this.stopped = new RunStopped(status, message);
    let callbacks = this.listeners.slice();
    for (let callback of callbacks) {
      try { callback(); } catch (e) { /* 某个资源清理失败不能阻止其他取消监听。 */ }
    }
  }
  subscribe(callback: () => void): void { this.check(); this.listeners.push(callback); }
  unsubscribe(callback: () => void): void { this.listeners = this.listeners.filter((item: () => void): boolean => item !== callback); }
}
