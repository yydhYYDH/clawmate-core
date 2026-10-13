import { CloudModelClient } from './CloudModelClient';
import { PhoneBridge } from './PhoneBridge';
import { AgentActionParser } from './AgentActionParser';
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
}

export const MAX_AGENT_STEPS: number = 15;

// 极简 GUI Agent 闭环：Planner 选应用 -> self-HDC 开应用 -> 截图/Decider/执行 循环。
export class AgentRunner {
  private config: EndpointConfig;
  private client: CloudModelClient;
  private bridge: PhoneBridge | null = null;
  private cancelled: boolean = false;

  constructor(config: EndpointConfig) {
    this.config = config;
    this.client = new CloudModelClient(config);
  }

  cancel(): void {
    this.cancelled = true;
    if (this.bridge !== null) {
      this.bridge.cancel();
    }
  }

  async run(userTask: string, callbacks: AgentCallbacks): Promise<void> {
    let bridge = new PhoneBridge(this.config, callbacks.onLog);
    this.bridge = bridge;
    callbacks.onLog('[Session] 连接 self-HDC ' + this.config.hdcIp + ':' + this.config.hdcPort);
    await bridge.open();
    callbacks.onLog('[Session] self-HDC 已连接');
    try {
      let target = await this.plan(userTask, callbacks);
      callbacks.onLog('[Agent] 打开应用 ' + target.appName + ' (' + target.packageName + ')');
      await bridge.startApp(target.appName, target.packageName, true);
      await this.executeLoop(target.task, callbacks, bridge);
    } finally {
      await bridge.close();
      this.bridge = null;
      callbacks.onPhase('结束');
    }
  }

  private async plan(task: string, callbacks: AgentCallbacks): Promise<PlannerTarget> {
    callbacks.onPhase('规划中');
    callbacks.onLog('[Planner] 请求 ' + this.config.plannerBaseUrl);
    let prompt = PLANNER_PROMPT.replace('{task_description}', task);
    let raw = await this.client.chatPlanner(prompt);
    callbacks.onLog('[Planner] 响应: ' + compact(raw));
    let data: WorkflowJsonMap = AgentActionParser.extractJsonMap(raw, false);
    let appName = AgentActionParser.getMapString(data, 'app_name');
    let packageName = AgentActionParser.getMapString(data, 'package_name');
    let finalTask = AgentActionParser.getMapString(data, 'final_task_description');
    if (appName.length === 0 && packageName.length === 0) {
      throw new Error('Planner 未找到可完成该任务的应用：' +
        AgentActionParser.getMapString(data, 'reasoning', '未知原因'));
    }
    let effectiveTask = finalTask.length > 0 ? finalTask : task;
    callbacks.onLog('[Planner] app=' + appName + ' pkg=' + packageName);
    let target: PlannerTarget = {
      appName: appName.length > 0 ? appName : packageName,
      packageName: packageName,
      task: effectiveTask
    };
    return target;
  }

  private async executeLoop(task: string, callbacks: AgentCallbacks, bridge: PhoneBridge): Promise<void> {
    callbacks.onPhase('执行中');
    let history: string[] = [];
    for (let step = 0; step < MAX_AGENT_STEPS; step++) {
      this.checkCancelled();
      callbacks.onLog('[Agent] 第 ' + (step + 1) + ' 步：截图');
      let shot = await bridge.screenshot(0.5);
      let image = shot.image_b64 === undefined ? '' : shot.image_b64;
      callbacks.onLog('[Decider] 请求 ' + this.config.deciderBaseUrl + ' (imageChars=' + image.length + ')');
      let raw = await this.client.chatQwenDecider(task, history, image);
      callbacks.onLog('[Decider] 响应: ' + compact(raw));
      let parsed = AgentActionParser.parse(raw);
      callbacks.onStep(step + 1, MAX_AGENT_STEPS, parsed.action);
      if (AgentActionParser.isTerminal(parsed.action)) {
        callbacks.onLog('[Agent] 完成：' + parsed.action);
        return;
      }
      let width = shot.screen_width === undefined ? (shot.width === undefined ? 0 : shot.width) : shot.screen_width;
      let height = shot.screen_height === undefined ? (shot.height === undefined ? 0 : shot.height) : shot.screen_height;
      let payload = AgentActionParser.buildHdcActionPayload(parsed, width, height);
      await bridge.guiAction(payload);
      history.push(AgentActionParser.normalizeCloudHistoryItem(raw));
      callbacks.onLog('[Agent] 已执行 ' + parsed.action + '（历史 ' + history.length + '）');
      await sleep(600);
    }
    throw new Error('未在 ' + MAX_AGENT_STEPS + ' 步内完成任务');
  }

  private checkCancelled(): void {
    if (this.cancelled) {
      throw new Error('任务已取消');
    }
  }
}

function compact(text: string): string {
  let value = text.replace(/\s+/g, ' ').trim();
  return value.length <= 600 ? value : value.substring(0, 600) + '...';
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => {
    setTimeout(resolve, ms);
  });
}
