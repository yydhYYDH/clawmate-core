import { AgentActionParser, ParsedAgentAction } from './AgentActionParser';

export type AgentRunStatus = 'success' | 'failed' | 'suspended' | 'cancelled';

export interface AgentRunResult {
  status: AgentRunStatus;
  message: string;
}

export class AgentRunError extends Error {
  status: AgentRunStatus;

  constructor(status: AgentRunStatus, message: string) {
    super(message);
    this.status = status;
  }
}

export function agentTerminalResult(parsed: ParsedAgentAction): AgentRunResult {
  let root = AgentActionParser.getMapString(parsed.data, 'status').trim().toLowerCase();
  let status = AgentActionParser.getMapString(parsed.parameters, 'status', root).trim().toLowerCase();
  if (root === 'failed' || root === 'suspended' || root === 'cancelled') { status = root; }
  let summary = AgentActionParser.getMapString(parsed.data, 'summary').trim().substring(0, 400);
  if (parsed.action === 'done' && (status === 'success' || status === 'completed')) {
    return { status: 'success', message: summary || '模型根据最新截图确认任务已完成。' };
  }
  if (status === 'cancelled') { return { status: 'cancelled', message: '任务已取消。' }; }
  if (status === 'failed' || parsed.action === 'abort') {
    return { status: 'failed', message: summary || '任务未完成，执行已停止。' };
  }
  return { status: 'suspended', message: summary || '执行已暂停，模型未确认任务成功，请检查当前页面。' };
}

export function agentActionReceipt(parsed: ParsedAgentAction): string {
  let target = AgentActionParser.getMapString(parsed.parameters, 'target_element',
    AgentActionParser.getMapString(parsed.data, 'target_element')).trim().substring(0, 80);
  if (parsed.action === 'click') { return '已点击' + (target || '目标位置') + '，正在检查页面变化。'; }
  if (parsed.action === 'click_input' || parsed.action === 'input') {
    let text = AgentActionParser.getMapString(parsed.parameters, 'text').substring(0, 80);
    return '已执行' + (text ? '填写“' + text + '”' : '清空输入') +
      (target ? '（' + target + '）' : '') + '，正在检查输入结果。';
  }
  if (parsed.action === 'swipe') { return '已滑动页面，正在查看新的内容。'; }
  if (parsed.action === 'open_app') { return '已执行打开应用，正在检查目标页面。'; }
  if (parsed.action === 'press_back') { return '已返回上一页，正在检查页面。'; }
  if (parsed.action === 'press_home') { return '已返回桌面，正在判断下一步。'; }
  return '等待结束，正在检查当前页面。';
}
