import { http } from '@kit.NetworkKit';
import { JSON as ArkJSON } from '@kit.ArkTS';
import { EndpointConfig } from './EndpointConfig';
import { AgentRunError } from './AgentRunState';
import { DECIDER_CURRENT_STEP_PROMPT, DECIDER_SYSTEM_PROMPT, DECIDER_USER_PROMPT } from './Prompts';

export interface CloudTextPart {
  type: string;
  text: string;
}

export interface CloudImageUrl {
  url: string;
}

export interface CloudImagePart {
  type: string;
  image_url: CloudImageUrl;
}

export type CloudContentPart = CloudTextPart | CloudImagePart;

export interface CloudChatMessage {
  role: string;
  content: string | CloudContentPart[];
}

interface ChatTemplateKwargs {
  enable_thinking: boolean;
}

interface ChatRequestBody {
  model: string;
  messages: CloudChatMessage[];
  temperature: number;
  max_tokens: number;
  chat_template_kwargs?: ChatTemplateKwargs;
}

interface ResponseMessage {
  content?: string;
}

interface ResponseChoice {
  message?: ResponseMessage;
}

interface ResponseBody {
  choices?: ResponseChoice[];
}

// 极简 OpenAI 兼容客户端：Planner 与 Decider 共用，分别指向不同 base URL。
export class CloudModelClient {
  private config: EndpointConfig;
  private cancelled: boolean = false;
  private rejectPending: ((error: Error) => void) | null = null;
  private pendingRequest: http.HttpRequest | null = null;

  cancel(): void {
    this.cancelled = true;
    // destroy() 不保证立刻回调；主动拒绝等待中的 Promise。
    if (this.rejectPending !== null) { this.rejectPending(new Error('任务已取消。')); }
    if (this.pendingRequest !== null) {
      try { this.pendingRequest.destroy(); } catch (e) { /* 超时已销毁请求。 */ }
    }
  }

  constructor(config: EndpointConfig) {
    this.config = config;
  }

  async chatPlanner(prompt: string): Promise<string> {
    let messages: CloudChatMessage[] = [{ role: 'user', content: prompt }];
    let body: ChatRequestBody = {
      model: this.config.plannerModel,
      messages: messages,
      temperature: 0,
      max_tokens: 4096,
      chat_template_kwargs: { enable_thinking: false }
    };
    return await this.post(this.chatUrl(this.config.plannerBaseUrl), this.config.plannerApiKey, body);
  }

  async chatQwenDecider(task: string, historyItems: string[], imageBase64: string): Promise<string> {
    let contextText = this.buildContextText(task, historyItems);
    let imagePart: CloudImagePart = {
      type: 'image_url',
      image_url: { url: 'data:image/jpeg;base64,' + imageBase64 }
    };
    let contextPart: CloudTextPart = { type: 'text', text: contextText };
    let stepPart: CloudTextPart = { type: 'text', text: DECIDER_CURRENT_STEP_PROMPT };
    let systemMessage: CloudChatMessage = { role: 'system', content: DECIDER_SYSTEM_PROMPT };
    let userMessage: CloudChatMessage = {
      role: 'user',
      content: [contextPart, imagePart, stepPart]
    };
    let messages: CloudChatMessage[] = [systemMessage, userMessage];
    let body: ChatRequestBody = {
      model: this.config.deciderModel,
      messages: messages,
      temperature: 0,
      max_tokens: 512
    };
    return await this.post(this.chatUrl(this.config.deciderBaseUrl), this.config.deciderApiKey, body);
  }

  private buildHistoryText(historyItems: string[]): string {
    if (historyItems.length === 0) {
      return '(No history)';
    }
    let lines: string[] = [];
    for (let i = 0; i < historyItems.length; i++) {
      lines.push((i + 1) + '. ' + historyItems[i]);
    }
    return lines.join('\n');
  }

  private buildContextText(task: string, historyItems: string[]): string {
    return DECIDER_USER_PROMPT
      .replace('{task}', task)
      .replace('{history}', this.buildHistoryText(historyItems));
  }

  private chatUrl(baseUrl: string): string {
    let url = baseUrl.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.endsWith('/chat/completions')) {
      return url;
    }
    if (url.endsWith('/v1')) {
      return url + '/chat/completions';
    }
    return url + '/v1/chat/completions';
  }

  private async post(url: string, apiKey: string, body: ChatRequestBody): Promise<string> {
    if (this.cancelled) { throw new AgentRunError('cancelled', '任务已取消。'); }
    let headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ' + (apiKey.length > 0 ? apiKey : 'EMPTY')
    };
    let options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: ArkJSON.stringify(body),
      connectTimeout: 15000,
      readTimeout: 90000,
      expectDataType: http.HttpDataType.STRING
    };
    let request = http.createHttp();
    this.pendingRequest = request;
    let timer = -1;
    try {
      let response = await new Promise<http.HttpResponse>((resolve, reject): void => {
        this.rejectPending = reject;
        timer = setTimeout((): void => {
          reject(new Error('模型响应超过 90 秒，已停止等待，请稍后重试。'));
          request.destroy();
        }, 90000);
        request.request(url, options).then(resolve).catch(reject);
      });
      if (this.cancelled) { throw new AgentRunError('cancelled', '任务已取消。'); }
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error('HTTP ' + response.responseCode + ': ' +
          String(response.result).substring(0, 300));
      }
      let parsed = ArkJSON.parse(response.result as string) as ResponseBody;
      let choices: ResponseChoice[] = parsed.choices === undefined ? [] : parsed.choices;
      if (choices.length === 0) {
        throw new Error('模型返回 choices 为空');
      }
      let message = choices[0].message;
      let content = message === undefined || message.content === undefined ? '' : message.content;
      if (content.trim().length === 0) {
        throw new Error('模型返回内容为空');
      }
      return content;
    } finally {
      clearTimeout(timer);
      this.rejectPending = null;
      this.pendingRequest = null;
      try { request.destroy(); } catch (e) { /* 取消或超时已销毁请求。 */ }
    }
  }
}
