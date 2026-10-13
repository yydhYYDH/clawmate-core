import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { wantAgent, Want } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { HdcClient } from './selfhdc/HdcClient';
import { PhoneHdcActions, phoneHdcString } from './selfhdc/PhoneHdcActions';
import { phoneHdcBundle, phoneHdcMainAbility } from './selfhdc/PhoneHdcApp';
import {
  parseSelfHdcEndpoint,
  selfHdcHasCommandFailure,
  selfHdcShellQuote
} from './selfhdc/SelfHdcPolicy';
import { selfHdcWrite, selfHdcEnsureDirectory } from './selfhdc/SelfHdcFiles';
import { parsePhoneHdcUiInputHelp } from './selfhdc/PhoneHdcCapabilities';
import { readSelfHdcNetworks } from './selfhdc/SelfHdcNetwork';
import { HdcBridgeResponse, WorkflowJsonMap } from './WorkflowTypes';
import { AppRuntime } from './AppRuntime';
import { EndpointConfig } from './EndpointConfig';

// self-HDC 桥：App 直接连本机 hdcd，用 shell 命令截图/触控/拉起应用。
export class PhoneBridge {
  private config: EndpointConfig;
  private log: (message: string) => void;
  private client: HdcClient;
  private actions: PhoneHdcActions = new PhoneHdcActions();
  private cancelled: boolean = false;
  private expired: boolean = false;
  private geometryReady: boolean = false;
  private continuous: boolean = false;
  private suspendId: number = -1;
  private deadline: number = 0;
  private shotSequence: number = 0;
  private actionSequence: number = 0;
  private closed: boolean = false;
  private opened: boolean = false;
  private filesDir: string = '';

  constructor(config: EndpointConfig, log: (message: string) => void) {
    this.config = config;
    this.log = log;
    this.client = new HdcClient((event: string): void => { this.log(event); });
  }

  async open(): Promise<void> {
    this.check();
    this.filesDir = AppRuntime.filesDir();
    selfHdcEnsureDirectory(this.filesDir + '/self_hdc');
    let endpoint = parseSelfHdcEndpoint(this.config.hdcIp, String(this.config.hdcPort));
    this.log('PHONE transport=direct-device-TCP os=' + deviceInfo.osFullName +
      ' api=' + deviceInfo.sdkApiVersion + ' target=' + endpoint.ip + ':' + endpoint.port);
    if (endpoint.ip !== '127.0.0.1' && endpoint.ip !== 'localhost') {
      let network = await readSelfHdcNetworks();
      if (network.localIpv4.indexOf(endpoint.ip) < 0) {
        throw new Error('PHONE_HDC_NOT_SELF: ' + endpoint.ip + ' 不是本机地址');
      }
    }
    this.check();
    await this.client.connect(endpoint.ip, endpoint.port, this.filesDir);
    this.check();
    let probe = await this.execute('printf SELF_HDC_PHONE_OK; id', 'shell-probe', false, false);
    if (probe.indexOf('SELF_HDC_PHONE_OK') < 0 || probe.indexOf('uid=') < 0) {
      throw new Error('PHONE_HDC_PROBE: 无法确认 shell 身份');
    }
    await this.execute(
      'command -v aa && command -v bm && command -v snapshot_display && command -v uitest && command -v base64',
      'tool-preflight', false, false);
    await this.probeUiInputCapabilities();
    await this.startKeepAlive();
    this.opened = true;
  }

  // 优先申请“持续任务”（无固定额度），失败再回退到临时任务（额度由系统给定，通常 60s）。
  private async startKeepAlive(): Promise<void> {
    try {
      let want: Want = {
        bundleName: AppRuntime.bundleName(),
        abilityName: 'EntryAbility'
      };
      let info: wantAgent.WantAgentInfo = {
        wants: [want],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 100,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      let agent = await wantAgent.getWantAgent(info);
      await backgroundTaskManager.startBackgroundRunning(AppRuntime.getContext(),
        backgroundTaskManager.BackgroundMode.DATA_TRANSFER, agent);
      this.continuous = true;
      this.deadline = 0;
      this.log('BACKGROUND continuous task started (DATA_TRANSFER)');
    } catch (e) {
      this.log('BACKGROUND continuous failed: ' + (e as Error).message + '; 回退临时任务');
      let delay = backgroundTaskManager.requestSuspendDelay('ClawMate Core 手机 GUI 任务', (): void => {
        if (this.closed) { return; }
        this.expired = true;
        this.log('PHONE_HDC_BACKGROUND_EXPIRED: 后台额度到期，停止后续动作');
        this.client.close();
      });
      this.suspendId = delay.requestId;
      this.deadline = Date.now() + delay.actualDelayTime;
      this.log('BACKGROUND request=' + delay.requestId + ' budgetMs=' + delay.actualDelayTime);
      if (delay.actualDelayTime < 30000) {
        throw new Error('PHONE_HDC_BACKGROUND: 后台可用时间不足 30 秒');
      }
    }
  }

  hasExpired(): boolean {
    return this.expired || (this.deadline > 0 && Date.now() >= this.deadline);
  }

  cancel(): void {
    this.cancelled = true;
    this.client.close();
  }

  async close(): Promise<void> {
    this.closed = true;
    this.client.close();
    if (this.continuous) {
      this.continuous = false;
      try {
        await backgroundTaskManager.stopBackgroundRunning(AppRuntime.getContext());
        this.log('BACKGROUND continuous task stopped');
      } catch (e) {
        this.log('BACKGROUND stop continuous failed: ' + (e as Error).message);
      }
    }
    if (this.suspendId >= 0) {
      try { backgroundTaskManager.cancelSuspendDelay(this.suspendId); } catch (e) {
        this.log('BACKGROUND release failed: ' + (e as Error).message);
      }
      this.suspendId = -1;
    }
  }

  async startApp(appName: string, packageName: string, resetFirst: boolean = true): Promise<void> {
    this.check();
    this.actions.reset();
    this.geometryReady = false;
    let bundle = phoneHdcBundle(appName, packageName);
    if (bundle === AppRuntime.bundleName()) {
      this.log('APP start skipped (已在本应用)');
      return;
    }
    let ability = phoneHdcMainAbility(
      await this.execute('bm dump -n ' + selfHdcShellQuote(bundle), 'resolve-main-ability', false, false));
    this.log('APP bundle=' + bundle + ' mainAbility=' + ability + ' reset=' + resetFirst);
    if (resetFirst) {
      await this.execute('aa force-stop ' + selfHdcShellQuote(bundle), 'app-stop');
    }
    await this.execute('aa start -b ' + selfHdcShellQuote(bundle) + ' -a ' + selfHdcShellQuote(ability), 'app-start');
    await this.pause(2000);
  }

  async screenshot(factor: number = 0.5): Promise<HdcBridgeResponse> {
    if (!Number.isFinite(factor) || factor <= 0 || factor > 1) {
      throw new Error('PHONE_HDC_IMAGE: screenshot factor 必须 >0 且 <=1');
    }
    this.check();
    let runId = Date.now();
    let remote = '/data/local/tmp/self_hdc_' + runId + '_gui_' + (++this.shotSequence) + '.jpeg';
    try {
      // 截图结果的正确性由后续 JPEG 魔数/大小校验保证；snapshot_display 在部分设备上会打印
      // 良性 I/O warning，故此处不再按输出文本判失败，只认退出码。
      await this.execute('snapshot_display -f ' + selfHdcShellQuote(remote), 'screenshot', false, false);
      let encoded = (await this.execute('base64 ' + selfHdcShellQuote(remote), 'screenshot-transfer', true, false))
        .replace(/\s/g, '');
      if (!encoded || encoded.length % 4 !== 0 || !/^[A-Za-z0-9+/]+={0,2}$/.test(encoded)) {
        throw new Error('PHONE_HDC_IMAGE: 截图 Base64 非法');
      }
      let bytes = new util.Base64Helper().decodeSync(encoded);
      if (bytes.length < 32 || bytes.length > 12 * 1024 * 1024 || bytes[0] !== 255 || bytes[1] !== 216 ||
        bytes[2] !== 255 || bytes[bytes.length - 2] !== 255 || bytes[bytes.length - 1] !== 217) {
        throw new Error('PHONE_HDC_IMAGE: JPEG 不完整或超出大小限制');
      }
      let source = image.createImageSource(bytes.buffer);
      let info: image.ImageInfo;
      let resized: ArrayBuffer;
      let modelWidth = 0;
      let modelHeight = 0;
      try {
        info = await source.getImageInfo();
        modelWidth = Math.max(1, Math.floor(info.size.width * factor));
        modelHeight = Math.max(1, Math.floor(info.size.height * factor));
        let pixels = await source.createPixelMap({ desiredSize: { width: modelWidth, height: modelHeight } });
        let packer = image.createImagePacker();
        try {
          resized = await packer.packToData(pixels, { format: 'image/jpeg', quality: 90 });
        } finally {
          await packer.release();
          await pixels.release();
        }
      } finally {
        await source.release();
      }
      this.actions.setScreen(info.size.width, info.size.height);
      this.geometryReady = true;
      selfHdcWrite(this.filesDir + '/self_hdc/latest_screenshot.jpeg', bytes);
      this.log('SCREENSHOT physical=' + info.size.width + 'x' + info.size.height +
        ' model=' + modelWidth + 'x' + modelHeight + ' bytes=' + bytes.length);
      return {
        status: 'ok',
        image_b64: new util.Base64Helper().encodeToStringSync(new Uint8Array(resized)),
        width: modelWidth,
        height: modelHeight,
        screen_width: info.size.width,
        screen_height: info.size.height,
        message: 'phone JPEG screenshot'
      };
    } finally {
      try {
        await this.execute('rm -f ' + selfHdcShellQuote(remote), 'screenshot-cleanup');
      } catch (e) {
        this.log('CLEANUP remaining=' + remote + ' error=' + (e as Error).message);
      }
    }
  }

  async guiAction(payload: WorkflowJsonMap): Promise<HdcBridgeResponse> {
    this.check();
    let action = phoneHdcString(payload, 'action');
    let sequence = ++this.actionSequence;
    this.log('ACTION_BEGIN seq=' + sequence + ' action=' + action);
    try {
      if (action === 'app_start') {
        await this.startApp(phoneHdcString(payload, 'app_name'),
          phoneHdcString(payload, 'package_name'), payload['reset_first'] !== false);
      } else if (action === 'app_stop') {
        this.actions.reset();
        this.geometryReady = false;
        let bundle = phoneHdcBundle('', phoneHdcString(payload, 'package_name'));
        await this.execute('aa force-stop ' + selfHdcShellQuote(bundle), 'app-stop');
      } else {
        if (!this.geometryReady) {
          await this.screenshot();
        }
        let plan = this.actions.plan(payload);
        for (let item of plan.commands) {
          this.check();
          if (item.command) {
            await this.execute(item.command, item.label, item.sensitive);
          }
          if (item.delayMs > 0) {
            await this.pause(item.delayMs);
          }
        }
        this.actions.commit(plan);
      }
      this.log('ACTION_END seq=' + sequence + ' action=' + action + ' status=ok');
      return { status: 'ok', action: action, message: 'phone ' + action + ' accepted' };
    } catch (e) {
      this.actions.reset();
      this.log('ACTION_FAILED seq=' + sequence + ' action=' + action + ' error=' + (e as Error).message);
      throw e as Error;
    }
  }

  private async probeUiInputCapabilities(): Promise<void> {
    this.check();
    this.log('DEVICE_COMMAND label=uiInput-capabilities command=uitest uiInput help');
    let result = await this.client.shell('uitest uiInput help', 20000);
    this.check();
    let help = parsePhoneHdcUiInputHelp(result.exitCode, result.output);
    this.log('CAPABILITIES uiInput verified=' + help.commands.join(',') + ' helpExit=' + result.exitCode);
  }

  private async execute(command: string, label: string, sensitive: boolean = false,
    checkOutput: boolean = true): Promise<string> {
    this.check();
    this.log('DEVICE_COMMAND label=' + label + ' command=' + (sensitive ? '(text omitted)' : command));
    let result = await this.client.shell(command, 20000, sensitive, sensitive);
    this.check();
    let failed = result.exitCode !== 0 || (checkOutput && selfHdcHasCommandFailure(result.output));
    this.log('DEVICE_OUTPUT label=' + label + ' exit=' + result.exitCode + ' failed=' + failed +
      (sensitive ? ' (contents omitted)' : ' text=' + result.output.substring(0, 1000)));
    if (failed) {
      throw new Error('PHONE_HDC_COMMAND: ' + label + ' exit=' + result.exitCode +
        (sensitive ? '' : ' ' + result.output.substring(0, 500)));
    }
    return result.output;
  }

  private check(): void {
    if (this.hasExpired()) {
      throw new Error('PHONE_HDC_BACKGROUND_EXPIRED: 后台额度已用尽');
    }
    if (this.closed || this.cancelled) {
      throw new Error('PHONE_HDC_CANCELLED: 已停止，不再发送动作');
    }
  }

  private async pause(ms: number): Promise<void> {
    let end = Date.now() + ms;
    while (Date.now() < end) {
      this.check();
      await new Promise<void>((resolve: () => void): void => {
        setTimeout(resolve, Math.min(100, end - Date.now()));
      });
    }
    this.check();
  }
}
