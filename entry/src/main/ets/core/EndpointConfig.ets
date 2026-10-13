// 运行时端点配置。默认指向本次联调使用的 planner / decider 模型服务，
// 以及设备本机 hdcd 的 TCP 端口（见 docs/HDC_SELF_CONTROL.md）。
export interface EndpointConfig {
  // self-HDC：连本机 hdcd 的 TCP 监听地址。默认 loopback。
  hdcIp: string;
  hdcPort: number;
  plannerBaseUrl: string;
  plannerApiKey: string;
  plannerModel: string;
  deciderBaseUrl: string;
  deciderApiKey: string;
  deciderModel: string;
}

export const DEFAULT_ENDPOINTS: EndpointConfig = {
  hdcIp: '127.0.0.1',
  hdcPort: 8710,
  plannerBaseUrl: 'http://123.60.91.241:9003',
  plannerApiKey: 'mobiagent-key',
  plannerModel: '',
  deciderBaseUrl: 'http://123.60.91.241:8080',
  deciderApiKey: 'mobiagent-key',
  deciderModel: ''
};
