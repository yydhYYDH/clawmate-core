import { AppRuntime } from './AppRuntime';
import { EndpointConfig } from './EndpointConfig';
import { HdcClient } from './selfhdc/HdcClient';
import { parseSelfHdcEndpoint, selfHdcHasCommandFailure, selfHdcShellQuote } from './selfhdc/SelfHdcPolicy';

// 后台 startAbility 受限时，仅通过 self-HDC 拉回宿主，不恢复已结束任务的动作。
export async function returnToHost(config: EndpointConfig, filesDir: string,
  log: (message: string) => void): Promise<void> {
  let context = AppRuntime.getContext();
  let bundle = AppRuntime.bundleName();
  let ability = context.abilityInfo.name;
  try {
    await context.startAbility({ bundleName: bundle, abilityName: ability });
    log('RETURN_APP_OK: 已返回 ClawMate');
    return;
  } catch (e) {
    log('RETURN_APP_RETRY: ' + (e as Error).message + '；通过 self-HDC 返回');
  }
  // 独立连接也适用于取消/后台额度到期后原连接已被关闭的场景。
  let client = new HdcClient(log);
  try {
    let endpoint = parseSelfHdcEndpoint(config.hdcIp, String(config.hdcPort));
    await client.connect(endpoint.ip, endpoint.port, filesDir);
    let result = await client.shell('aa start -b ' + selfHdcShellQuote(bundle) +
      ' -a ' + selfHdcShellQuote(ability), 8000);
    if (result.exitCode !== 0 || selfHdcHasCommandFailure(result.output)) {
      throw new Error('aa start: ' + result.output.substring(0, 300));
    }
    log('RETURN_APP_OK: self-HDC 已返回 ClawMate');
  } catch (e) {
    log('RETURN_APP_FAILED: ' + (e as Error).message + '；请手动返回 ClawMate');
  } finally {
    client.close();
  }
}
