export interface PhoneApp {
  name: string;
  bundle: string;
}

// Planner 和名称解析共用设备的 OpenHarmony 应用目录。
export const PHONE_APPS: PhoneApp[] = [
  { name: 'RoboPi 浏览器', bundle: 'com.clawmate.browser' },
  { name: '设置', bundle: 'com.ohos.settings' },
  { name: '图库', bundle: 'com.ohos.photos' },
  { name: '相机', bundle: 'com.ohos.camera' },
  { name: '信息', bundle: 'com.ohos.mms' },
  { name: '备忘录', bundle: 'com.ohos.note' },
  { name: '联系人', bundle: 'com.ohos.contacts' },
  { name: '时钟', bundle: 'ohos.samples.etsclock' },
  { name: '音乐', bundle: 'ohos.samples.distributedmusicplayer' },
  { name: '计算器', bundle: 'ohos.samples.distributedcalc' }
];

export function phoneAppList(): string {
  return PHONE_APPS.map((app: PhoneApp): string => '- ' + app.name + ': ' + app.bundle).join('\n');
}
