import { http } from '@kit.NetworkKit';
import { RunScope } from '../core/RunScope';

// 每次调用使用独立请求，取消主动拒绝 Promise，不依赖 destroy 是否触发回调。
export async function requestJson<T>(url: string, body: string, scope: RunScope, token: string = ''): Promise<T> {
  scope.check();
  let request = http.createHttp();
  let timer = -1;
  let rejectPending: ((reason: Error) => void) | null = null;
  let release = (): void => { try { request.destroy(); } catch (e) { /* 不覆盖请求的真实结果。 */ } };
  let onStop = (): void => {
    if (rejectPending !== null) {
      try { scope.check(); } catch (e) { rejectPending(e as Error); }
    }
    release();
  };
  try {
    let milliseconds = Math.min(30000, scope.remaining());
    let response = await new Promise<http.HttpResponse>((resolve, reject): void => {
      rejectPending = reject;
      scope.subscribe(onStop);
      timer = setTimeout((): void => { reject(new Error('请求超时，请检查服务后重试。')); release(); }, milliseconds);
      request.request(url, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token },
        extraData: body, expectDataType: http.HttpDataType.STRING,
        connectTimeout: Math.min(10000, milliseconds), readTimeout: milliseconds, maxLimit: 20 * 1024 * 1024
      }).then(resolve).catch(reject);
    });
    scope.check();
    if (response.responseCode < 200 || response.responseCode >= 300) {
      throw new Error('服务返回 HTTP ' + response.responseCode + '，请检查配置或服务日志。');
    }
    return JSON.parse(response.result as string) as T;
  } finally {
    clearTimeout(timer);
    scope.unsubscribe(onStop);
    rejectPending = null;
    release();
  }
}
