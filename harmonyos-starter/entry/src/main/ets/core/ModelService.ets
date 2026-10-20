import { ModelBody, ModelResponse, Settings } from './Types';
import { chatEndpoint } from './Domain';
import { RunScope } from './RunScope';
import { requestJson } from '../platform/HttpJson';
import { DEFAULT_MODEL_NAME } from './TeacherDefaults';

export async function complete(settings: Settings, body: ModelBody, scope: RunScope): Promise<string> {
  if (!settings.model.trim()) { throw new Error('请先在设置中填写模型名称。'); }
  if (settings.model === DEFAULT_MODEL_NAME) {
    body.chat_template_kwargs = { enable_thinking: false };
  }
  let response = await requestJson<ModelResponse>(chatEndpoint(settings.modelUrl), JSON.stringify(body), scope, settings.modelKey);
  let choices = response.choices || [];
  let answer = choices.length > 0 && choices[0].message !== undefined ? choices[0].message!.content || '' : '';
  if (typeof answer !== 'string' || !answer.trim()) { throw new Error('模型返回了空回复或不支持的内容格式。'); }
  return answer;
}
