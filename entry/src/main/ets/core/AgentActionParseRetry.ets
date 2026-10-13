import { AgentActionParser, ParsedAgentAction } from './AgentActionParser';

export const MAX_SAME_SCREEN_JSON_PARSE_RETRIES: number = 3;

export interface AgentActionParseRetryInfo {
  retryNumber: number;
  maxRetries: number;
  errorMessage: string;
  rawResponse: string;
}

export type AgentActionRequest = () => Promise<string>;
export type AgentActionParseRetryHandler = (info: AgentActionParseRetryInfo) => void;

export class AgentActionParseRetry {
  // request 只负责模型请求；请求异常直接抛出。仅当解析器完成全部修复仍失败时，才在同一截图上重试。
  static async request(request: AgentActionRequest,
    onRetry?: AgentActionParseRetryHandler): Promise<ParsedAgentAction> {
    let parseFailureCount = 0;
    while (true) {
      let response = await request();
      try {
        return AgentActionParser.parse(response, true);
      } catch (e) {
        let err = e as Error;
        let errorMessage = err.message || String(e);
        if (parseFailureCount >= MAX_SAME_SCREEN_JSON_PARSE_RETRIES) {
          throw new Error('Agent JSON parse failed after ' +
            String(MAX_SAME_SCREEN_JSON_PARSE_RETRIES) + ' same-screen retries: ' + errorMessage);
        }
        parseFailureCount += 1;
        if (onRetry !== undefined) {
          onRetry({
            retryNumber: parseFailureCount,
            maxRetries: MAX_SAME_SCREEN_JSON_PARSE_RETRIES,
            errorMessage: errorMessage,
            rawResponse: response
          });
        }
      }
    }
  }
}
