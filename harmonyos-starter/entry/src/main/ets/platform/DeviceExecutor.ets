import { Action, Capabilities, Screenshot } from '../core/Types';
import { RunScope } from '../core/RunScope';

// 这是项目自己的平台接口。学生迁移 OH 时在这里接入设备实现。
export interface DeviceExecutor {
  open(scope: RunScope): Promise<Capabilities>;
  startApp(bundle: string, scope: RunScope): Promise<void>;
  screenshot(scope: RunScope): Promise<Screenshot>;
  execute(action: Action, scope: RunScope): Promise<string>;
  returnHost(): Promise<void>;
  cancel(): Promise<void>;
  close(): Promise<void>;
}
