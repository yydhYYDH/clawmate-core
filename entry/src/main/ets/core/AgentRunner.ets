import { CloudModelClient } from './CloudModelClient';
import { PhoneBridge } from './PhoneBridge';
import { AgentActionParser } from './AgentActionParser';
import { AgentActionParseRetry } from './AgentActionParseRetry';
import { agentActionReceipt, agentTerminalResult, AgentRunError, AgentRunResult } from './AgentRunState';
import { PLANNER_PROMPT } from './Prompts';
import { EndpointConfig } from './EndpointConfig';
import { WorkflowJsonMap } from './WorkflowTypes';

export interface PlannerTarget {
  appName: string;
  packageName: string;
  task: string;
}

export interface AgentCallbacks {
  onLog: (line: string) => void;
  onPhase: (phase: string) => void;
  onStep: (step: number, maxSteps: number, action: string) => void;
  onContent: (text: string) => void;
}

export const MAX_AGENT_STEPS: number = 15;

export class AgentRunner {
  private config: EndpointConfig;
  private client: CloudModelClient;
  private bridge: PhoneBridge | null = null;
  private cancelled: boolean = false;
  private failure: Error | null = null;

  constructor(config: EndpointConfig) {
    this.config = config;
    this.client = new CloudModelClient(config);
  }

  cancel(): void {
    this.cancelled = true;
    this.client.cancel();
    if (this.bridge !== null) { this.bridge.cancel(); }
  }

  async run(userTask: string, callbacks: AgentCallbacks): Promise<AgentRunResult> {
    let bridge = new PhoneBridge(this.config, callbacks.onLog, (error: Error): void => {
      this.failure = error;
      this.client.cancel();
    });
    this.bridge = bridge;
    let launched = false;
    let timer = setTimeout((): void => {
      this.failure = new Error('任务超过 10 分钟，已停止执行。');
      this.client.cancel();
      bridge.cancel();
    }, 10 * 60 * 1000);
    try {
      this.check();
      callbacks.onPhase('连接设备');
      callbacks.onContent('任务已开始，正在连接设备。');
      callbacks.onLog('[Session] 连接 self-HDC ' + this.config.hdcIp + ':' + this.config.hdcPort);
      // 初始化也在 finally 的保护范围内。
      await bridge.open();
      this.check();
      callbacks.onLog('[Session] self-HDC 已连接');
      let target = await this.plan(userTask, callbacks);
      this.check();
      callbacks.onPhase('打开' + target.appName);
      callbacks.onContent('已选择' + target.appName + '，正在打开应用。');
      callbacks.onLog('[Agent] 打开应用 ' + target.appName + ' (' + target.packageName + ')');
      launched = true;
      await bridge.startApp(target.appName, target.packageName, true);
      this.check();
      callbacks.onContent('已执行打开' + target.appName + '，接下来查看页面并操作。');
      return await this.executeLoop(target.task, callbacks, bridge);
    } catch (e) {
      // 取消后的 HTTP/HDC 底层异常不能覆盖真实终止原因。
      this.check();
      throw e as Error;
    } finally {
      clearTimeout(timer);
      callbacks.onPhase('收尾中');
      this.client.cancel();
      try {
        if (launched) { await bridge.returnHost(); }
      } finally {
        await bridge.close();
        this.bridge = null;
      }
    }
  }

  private async plan(task: string, callbacks: AgentCallbacks): Promise<PlannerTarget> {
    callbacks.onPhase('等待任务规划');
    callbacks.onLog('[Planner] 请求 ' + this.config.plannerBaseUrl);
    let raw = await this.client.chatPlanner(PLANNER_PROMPT.replace('{task_description}', task));
    this.check();
    callbacks.onLog('[Planner] 响应: ' + compact(raw));
    let data: WorkflowJsonMap = AgentActionParser.extractJsonMap(raw, false);
    let appName = AgentActionParser.getMapString(data, 'app_name');
    let packageName = AgentActionParser.getMapString(data, 'package_name');
    if (appName.length === 0 && packageName.length === 0) {
      throw new Error('没有找到可以完成该任务的应用。');
    }
    let finalTask = AgentActionParser.getMapString(data, 'final_task_description');
    return { appName: appName || packageName, packageName: packageName, task: finalTask || task };
  }

  private async executeLoop(task: string, callbacks: AgentCallbacks, bridge: PhoneBridge): Promise<AgentRunResult> {
    let history: string[] = [];
    for (let step = 0; step < MAX_AGENT_STEPS; step++) {
      this.check();
      callbacks.onPhase('获取屏幕');
      callbacks.onLog('[Agent] 第 ' + (step + 1) + ' 步：截图');
      let shot = await bridge.screenshot(0.5);
      this.check();
      let image = shot.image_b64 || '';
      callbacks.onPhase(history.length > 0 ? '检查上一步结果并等待下一步' : '等待下一步操作');
      let parsed = await AgentActionParseRetry.request(async (): Promise<string> => {
        this.check();
        callbacks.onLog('[Decider] 请求 ' + this.config.deciderBaseUrl);
        let raw = await this.client.chatQwenDecider(task, history, image);
        this.check();
        callbacks.onLog('[Decider] 响应: ' + compact(raw));
        return raw;
      }, (info): void => { callbacks.onLog('[Decider] JSON 解析重试 ' + info.retryNumber); });
      this.check();
      let progress = AgentActionParser.getMapString(parsed.data, 'progress').trim().substring(0, 400);
      if (history.length > 0 && progress.length > 0) { callbacks.onContent(progress); }
      callbacks.onStep(step + 1, MAX_AGENT_STEPS, parsed.action);
      if (AgentActionParser.isTerminal(parsed.action)) {
        let result = agentTerminalResult(parsed);
        callbacks.onLog('[Agent] 结束 status=' + result.status);
        return result;
      }
      let width = shot.screen_width || shot.width || 0;
      let height = shot.screen_height || shot.height || 0;
      let payload = AgentActionParser.buildHdcActionPayload(parsed, width, height);
      callbacks.onPhase('执行第 ' + (step + 1) + ' 步');
      await bridge.guiAction(payload);
      this.check();
      callbacks.onContent('第 ' + (step + 1) + ' 步：' + agentActionReceipt(parsed));
      history.push(AgentActionParser.normalizeCloudHistoryItem(parsed.raw));
      callbacks.onLog('[Agent] 已执行 ' + parsed.action);
      callbacks.onPhase('等待页面稳定');
      await new Promise<void>((resolve): void => { setTimeout(resolve, 600); });
    }
    // 最后一个动作之后仍取一次截图验证，避免恰好在第 15 步完成却被直接判失败。
    this.check();
    callbacks.onPhase('检查最终结果');
    let shot = await bridge.screenshot(0.5);
    let raw = await this.client.chatQwenDecider(task, history, shot.image_b64 || '');
    this.check();
    callbacks.onLog('[Decider] 最终检查: ' + compact(raw));
    let parsed = AgentActionParser.parse(raw);
    if (AgentActionParser.isTerminal(parsed.action)) { return agentTerminalResult(parsed); }
    return { status: 'suspended', message: '已执行 15 步，仍未确认完成；已暂停，请检查当前结果。' };
  }

  private check(): void {
    if (this.cancelled) { throw new AgentRunError('cancelled', '任务已取消。'); }
    if (this.failure !== null) { throw this.failure; }
    if (this.bridge !== null && this.bridge.hasExpired()) {
      throw new Error('后台运行时间已到期，已停止操作。');
    }
  }
}

function compact(text: string): string {
  let value = text.replace(/\s+/g, ' ').trim();
  return value.length <= 600 ? value : value.substring(0, 600) + '...';
}
