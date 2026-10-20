import { AppEvents, ModelBody, Settings } from './Types';
import { RunScope } from './RunScope';
import { complete } from './ModelService';

// 仅重新生成无法解析/校验的模型回复；同一截图上不执行任何无效动作。
// 网络错误和用户取消不重试，避免把执行失败误当成格式错误。
export async function structuredModel<T>(settings: Settings, body: ModelBody, scope: RunScope,
  parse: (text: string) => T, events: AppEvents): Promise<T> {
  for (let attempt = 0; attempt <= 2; attempt++) {
    scope.check();
    let reply = await complete(settings, body, scope);
    scope.check();
    try {
      return parse(reply);
    } catch (e) {
      let reason = (e as Error).message;
      if (attempt === 2) { throw new Error('模型连续返回无效操作，任务已停止：' + reason); }
      events.log('模型回复格式不符合约定，正在纠正（' + (attempt + 1) + '/2）：' + reason);
      body.messages.push({ role: 'assistant', content: reply });
      let targetCorrection = reason.startsWith('点击目标') ?
        '本次必须改用数字坐标，不得再使用 target 字段。只输出 {"action":"click","x":横坐标,"y":纵坐标}，' +
        'x、y 都是 0–1000 的数字。请从截图定位刚才想点击的图标；不能重复输出不存在的文字标签。' :
        'click 可使用当前按钮列表中的 target；没有 target 时必须分别有数字 x 和 y，swipe 还须有 x2 和 y2。';
      body.messages.push({ role: 'user', content: '上个回复未执行，原因：' + reason +
        '。请根据同一张截图和原任务重新输出一个完整、合法的 JSON 对象。字段名必须有双引号；' +
        '坐标必须按截图宽高换算到 0–1000，不要直接使用像素坐标，不要输出算式或注释。' +
        'done 必须有 status 和非空 summary，summary 写明截图确认的结果。' + targetCorrection });
    }
  }
  throw new Error('模型操作未生成。');
}
