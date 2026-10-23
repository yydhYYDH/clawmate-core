// 局域网 DSH（DeepSeek Harness）移动端通道客户端。
//
// 协议依据 dsh web（@deepseek-ai/dsh-client-connection + dsh-api-gateway）：
//   - 认证：GET /?token=<launch-token> → 303 + Set-Cookie dsh-auth-<hash>=v1.<body>.<sig>
//     cookie 名按 authority 的 sha256 生成，所以不能写死；一次换取 30 天有效。
//   - 一元调用：POST /api/<ns>/<method>，body
//     {"type":"client-request","rpcId","method":"<ns>/<method>","payload":{"args":{...}}}
//     method 必须与 URL 去掉 /api/ 的那一段完全一致，参数统一包在 args 里。
//   - 流：WebSocket /api/remote.mux，帧为
//     {"type":"open","streamId","endpoint":"session/follow","payload":{"args":{...}}}
//     Host 回 {"type":"item","streamId","value":...} / {"type":"end","streamId"} / {"type":"error",...}
// 全程只用 Cookie，不触碰宿主的其它 /api 面。
//
// ArkTS 约束：不能用索引签名、不能直接拿对象字面量当任意 JSON 用，
// 所以每个请求/响应形状都声明成独立 interface，序列化交给 ArkJSON.stringify。

import { http, webSocket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { JSON as ArkJSON } from '@kit.ArkTS';

export interface DshConfig {
  baseUrl: string;
  cookie: string;
}

export interface DshSession {
  sessionId: string;
  title: string;
  cwd: string;
  running: boolean;
  blank: boolean;
  agentAvailable: boolean;
  agentPreset: string;
  updatedAt: number;
}

export interface DshPreset {
  id: string;
  name: string;
  description: string;
  isDefault: boolean;
}

export interface DshWorkspace {
  workspaceId: string;
  title: string;
  path: string;
}

// session/follow 下发的一帧。
export interface DshFollowFrame {
  kind: string;          // snapshot | event | assistant-stream
  seq: number;
  cursor: number;
  eventType: string;
  role: string;
  text: string;
}

// ---- 请求体：每层一个 interface，绝不使用对象字面量当 JSON ----

interface TextContent {
  type: string;
  text: string;
}

interface EmptyRequest {
}

interface SessionListArgs {
  _request: EmptyRequest;
}

interface SessionIdPayload {
  sessionId: string;
}

interface SessionIdArgs {
  request: SessionIdPayload;
}

interface SessionRenamePayload {
  sessionId: string;
  title: string;
}

interface SessionRenameArgs {
  request: SessionRenamePayload;
}

interface SessionCreatePayload {
  workspaceId?: string;
  cwd?: string;
  agentPreset?: string;
}

interface SessionCreateArgs {
  request: SessionCreatePayload;
}

interface SessionPromptPayload {
  requestId: string;
  sessionId: string;
  mode: string;
  content: TextContent[];
}

interface SessionPromptArgs {
  request: SessionPromptPayload;
}

interface FollowAddress {
  kind: string;
  sessionId: string;
}

interface SessionPagePayload {
  address: FollowAddress;
  throughSeq: number;
  maxMessages: number;
}

interface SessionPageArgs {
  request: SessionPagePayload;
}

interface RpcPayload<TArgs> {
  args: TArgs;
}

interface RpcEnvelope<TArgs> {
  type: string;
  rpcId: string;
  method: string;
  payload: RpcPayload<TArgs>;
}

interface JsonHeaders {
  'Content-Type': string;
  'Cookie': string;
}

// ---- 响应体 ----

interface ServerError {
  code?: string;
  message?: string;
}

interface ServerResult {
  ok?: boolean;
  value?: Object;
  error?: ServerError;
}

interface ServerResponse {
  type?: string;
  rpcId?: string;
  result?: ServerResult;
}

interface ProjectionValues {
  title?: string;
  agentPreset?: string;
}

interface Projections {
  asOfSeq?: number;
  values?: ProjectionValues;
}

interface SessionItem {
  sessionId?: string;
  cwd?: string;
  running?: boolean;
  blank?: boolean;
  agentAvailable?: boolean;
  updatedAt?: number;
  projections?: Projections;
}

interface SessionListValue {
  items?: SessionItem[];
}

interface CreatedSessionValue {
  sessionId?: string;
  agentPreset?: string;
}

interface PresetItem {
  id?: string;
  name?: string;
  description?: string;
  isDefault?: boolean;
}

interface PresetListValue {
  presets?: PresetItem[];
}

interface WorkspaceItem {
  workspaceId?: string;
  title?: string;
  path?: string;
}

interface WorkspaceListValue {
  items?: WorkspaceItem[];
}

interface PageContent {
  type?: string;
  text?: string;
}

interface PageMessage {
  role?: string;
  content?: PageContent[];
}

interface PageEventData {
  message?: PageMessage;
  content?: PageContent[];
  inserted?: PageMessage[];
}

interface PageEvent {
  type?: string;
  seq?: number;
  data?: PageEventData;
}

interface PageRecord {
  type?: string;
  event?: PageEvent;
}

interface PageValue {
  records?: PageRecord[];
  hasMore?: boolean;
}

// ---- WebSocket 流 ----

interface MuxChunk {
  type?: string;
  text?: string;
}

interface MuxAssistantFrame {
  type?: string;
  chunk?: MuxChunk;
}

interface MuxStatusCode {
  code?: number;
}

interface MuxError {
  code?: string;
  message?: string;
}

interface MuxValue {
  type?: string;
  cursor?: number;
  records?: PageRecord[];
  event?: PageEvent;
  frame?: MuxAssistantFrame;
}

interface MuxServerMessage {
  type?: string;
  streamId?: string;
  value?: MuxValue;
  error?: MuxError;
}

interface FollowStreamRequest {
  address: FollowAddress;
  maxMessages: number;
  assistantStream: boolean;
}

interface FollowStreamArgs {
  request: FollowStreamRequest;
}

// open 帧的 payload 也必须包一层 {args: ...}，否则宿主报
// "Remote payload must contain exactly one plain-object args field"。
interface StreamPayload {
  args: FollowStreamArgs;
}

interface OpenStreamFrame {
  type: string;
  streamId: string;
  endpoint: string;
  payload: StreamPayload;
}

interface WsHeaders {
  'Cookie': string;
}

const AUTH_COOKIE_PREFIX: string = 'dsh-auth-';
const RPC_TIMEOUT_MS: number = 30000;
const MUX_RECONNECT_MS: number = 1500;

function mintRpcId(): string {
  let random = Math.floor(Math.random() * 0xffffffff).toString(16);
  return 'm-' + Date.now().toString(16) + '-' + random;
}

function trimSlash(base: string): string {
  let url = base.trim();
  while (url.endsWith('/')) { url = url.substring(0, url.length - 1); }
  return url;
}

export function normalizeDshBase(input: string): string {
  let url = trimSlash(input);
  if (url.length === 0) { throw new Error('DSH 地址不能为空'); }
  if (!/^https?:\/\//i.test(url)) { url = 'http://' + url; }
  return url;
}

// ArkTS 的响应头是 Object，键名大小写不确定（'Set-Cookie' / 'set-cookie'）。
// 先整体序列化再定位，避免依赖索引签名（ArkTS 不允许）。
function setCookieOf(headers: Object): string {
  let text = '';
  try {
    text = ArkJSON.stringify(headers);
  } catch (e) {
    return '';
  }
  let lower = text.toLowerCase();
  let at = lower.indexOf('"set-cookie"');
  if (at < 0) { return ''; }
  // 跳到该键对应的值（":" 之后的下一个 '"'）
  let colon = text.indexOf(':', at);
  if (colon < 0) { return ''; }
  let start = text.indexOf('"', colon + 1);
  if (start < 0) { return ''; }
  let value = '';
  for (let i = start + 1; i < text.length; i++) {
    let ch = text.charAt(i);
    if (ch === '\\') {
      // 保留被转义的字符（\" -> "）
      if (i + 1 < text.length) {
        value += text.charAt(i + 1);
        i++;
      }
      continue;
    }
    if (ch === '"') { break; }
    value += ch;
  }
  return value;
}

// 从 Set-Cookie 里挑出 dsh-auth-*，返回 "name=value" 形式。
function authCookieFrom(raw: string): string {
  let segments = raw.split(',');
  for (let i = 0; i < segments.length; i++) {
    let parts = segments[i].split(';');
    for (let j = 0; j < parts.length; j++) {
      let piece = parts[j].trim();
      if (piece.startsWith(AUTH_COOKIE_PREFIX)) {
        let eq = piece.indexOf('=');
        if (eq > 0) { return piece; }
      }
    }
  }
  return '';
}

export function cookieHeaderValue(cookie: string): string {
  let text = cookie.trim();
  if (text.length === 0) { return ''; }
  let eq = text.indexOf('=');
  if (eq < 0) { return AUTH_COOKIE_PREFIX + text; }
  let semi = text.indexOf(';');
  return semi >= 0 ? text.substring(0, semi) : text;
}

// 从 launch token 链接里取 token（/…/?token=xxx 或裸 token）。
export function dshTokenFromLink(input: string): string {
  let text = input.trim();
  if (text.length === 0) { return ''; }
  let markers: string[] = ['token=', 'pair='];
  for (let i = 0; i < markers.length; i++) {
    let index = text.indexOf(markers[i]);
    if (index < 0) { continue; }
    let token = text.substring(index + markers[i].length);
    let amp = token.indexOf('&');
    if (amp >= 0) { token = token.substring(0, amp); }
    return token;
  }
  return text;
}

// 认证：把 launch token 换成持久 cookie。等价于浏览器首次打开该链接。
export async function dshAuthenticate(baseUrl: string, token: string): Promise<string> {
  let url = normalizeDshBase(baseUrl) + '/?token=' + encodeURIComponent(token);
  let headers: Record<string, string> = { 'Accept': 'text/html' };
  let options: http.HttpRequestOptions = {
    method: http.RequestMethod.GET,
    header: headers,
    connectTimeout: 8000,
    readTimeout: 15000,
    expectDataType: http.HttpDataType.STRING
  };
  let request = http.createHttp();
  // http.request 会自动跟随 3xx，而 dsh 的 cookie 只挂在第一跳（303/302）上。
  // headersReceive 在每个响应头到达时触发，重定向发生前先把它截下来。
  let captured = '';
  let onHeaders = (header: Object): void => {
    if (captured.length > 0) { return; }
    let raw = setCookieOf(header);
    if (raw.length > 0) { captured = raw; }
  };
  request.on('headersReceive', onHeaders);
  try {
    let response = await request.request(url, options);
    let raw = captured;
    if (raw.length === 0) {
      // 少数实现不会为重定向跳转触发 headersReceive，兜底看最终响应。
      raw = setCookieOf(response.header as Object);
    }
    if (raw.length === 0) {
      throw new Error('DSH 未下发认证 cookie（HTTP ' + response.responseCode + '），token 可能已失效');
    }
    let cookie = authCookieFrom(raw);
    if (cookie.length === 0) {
      throw new Error('DSH 返回的 Set-Cookie 里没有 dsh-auth-* 项');
    }
    return cookie;
  } finally {
    try { request.off('headersReceive', onHeaders); } catch (e) { /* 已结束。 */ }
    try { request.destroy(); } catch (e) { /* 已结束。 */ }
  }
}

// 从事件数据里取可见正文（只取 type === 'text'）。
function contentText(content: PageContent[] | undefined): string {
  if (content === undefined || content === null) { return ''; }
  let text = '';
  for (let i = 0; i < content.length; i++) {
    let part = content[i];
    if (part.type === 'text' && part.text !== undefined) { text += part.text; }
  }
  return text;
}

function eventText(event: PageEvent): string {
  let data = event.data;
  if (data === undefined || data === null) { return ''; }
  let collected = '';
  let message = data.message;
  if (message !== undefined && message !== null) { collected += contentText(message.content); }
  let inserted = data.inserted;
  if (inserted !== undefined && inserted !== null) {
    for (let i = 0; i < inserted.length; i++) { collected += contentText(inserted[i].content); }
  }
  if (collected.length === 0) { collected += contentText(data.content); }
  return collected;
}

function eventRole(event: PageEvent): string {
  let data = event.data;
  if (data === undefined || data === null) { return ''; }
  let message = data.message;
  if (message !== undefined && message !== null && message.role !== undefined) { return message.role; }
  return '';
}

// 只取正文增量；reasoning-delta / tool-call-* 交给日志，不混进回复正文。
function chunkText(chunk: MuxChunk | undefined): string {
  if (chunk === undefined || chunk === null || chunk.type !== 'text-delta') { return ''; }
  return chunk.text === undefined ? '' : chunk.text;
}

function chunkReasoning(chunk: MuxChunk | undefined): string {
  if (chunk === undefined || chunk === null || chunk.type !== 'reasoning-delta') { return ''; }
  return chunk.text === undefined ? '' : chunk.text;
}

// WebSocket 回调首参在成功时是 undefined，必须先判空再访问字段，
// 否则 ArkTS 把 undefined 转成接口类型会抛 TypeError 而不是返回 undefined。
function isOkCode(err: Object | undefined): boolean {
  if (err === undefined || err === null) { return true; }
  let status = err as MuxStatusCode;
  let code = status.code;
  return code === undefined || code === null || code === 0;
}

export class DshClient {
  private config: DshConfig;
  private log: (line: string) => void;

  constructor(config: DshConfig, log: (line: string) => void) {
    this.config = config;
    this.log = log;
  }

  setCookie(cookie: string): void {
    this.config.cookie = cookie;
  }

  private requireCookie(): string {
    let cookie = cookieHeaderValue(this.config.cookie);
    if (cookie.length === 0) { throw new Error('尚未认证：请先粘贴 DSH 带 token 的链接'); }
    return cookie;
  }

  // 一元 RPC：POST /api/<ns>/<method>，参数包在 payload.args 里。
  private async call<TArgs, TValue>(method: string, args: TArgs): Promise<TValue> {
    let cookie = this.requireCookie();
    let rpcId = mintRpcId();
    let payload: RpcPayload<TArgs> = { args: args };
    let envelope: RpcEnvelope<TArgs> = {
      type: 'client-request',
      rpcId: rpcId,
      method: method,
      payload: payload
    };
    let headers: JsonHeaders = {
      'Content-Type': 'application/json',
      'Cookie': cookie
    };
    let url = normalizeDshBase(this.config.baseUrl) + '/api/' + method;
    let options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: ArkJSON.stringify(envelope),
      connectTimeout: 8000,
      readTimeout: RPC_TIMEOUT_MS,
      expectDataType: http.HttpDataType.STRING
    };
    let request = http.createHttp();
    let timer = -1;
    try {
      let response = await new Promise<http.HttpResponse>((resolve, reject): void => {
        timer = setTimeout((): void => {
          reject(new Error('DSH 请求超时'));
          request.destroy();
        }, RPC_TIMEOUT_MS);
        request.request(url, options).then(resolve).catch(reject);
      });
      let body = response.result as string;
      if (response.responseCode === 401) { throw new Error('DSH 认证已失效，请重新粘贴带 token 的链接'); }
      if (response.responseCode === 404) { throw new Error('DSH 上没有方法 ' + method); }
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error('HTTP ' + response.responseCode + ': ' + body.substring(0, 200));
      }
      let parsed = ArkJSON.parse(body) as ServerResponse;
      if (parsed.type !== 'server-response' || parsed.rpcId !== rpcId) {
        throw new Error('DSH 响应信封不匹配');
      }
      let result = parsed.result;
      if (result === undefined || result === null) { throw new Error('DSH 响应缺少 result'); }
      if (result.ok !== true) {
        let error = result.error;
        if (error === undefined || error === null) { throw new Error('DSH 调用失败'); }
        let code = error.code === undefined ? '' : error.code + ': ';
        let message = error.message === undefined ? 'DSH 调用失败' : error.message;
        throw new Error(code + message);
      }
      if (result.value === undefined || result.value === null) { throw new Error('DSH 响应缺少 value'); }
      return result.value as TValue;
    } finally {
      clearTimeout(timer);
      try { request.destroy(); } catch (e) { /* 已结束。 */ }
    }
  }

  async listSessions(): Promise<DshSession[]> {
    let empty: EmptyRequest = {};
    let args: SessionListArgs = { _request: empty };
    let parsed = await this.call<SessionListArgs, SessionListValue>('session/list', args);
    let items = parsed.items === undefined ? [] : parsed.items;
    let sessions: DshSession[] = [];
    for (let i = 0; i < items.length; i++) {
      let item = items[i];
      let sessionId = item.sessionId === undefined ? '' : item.sessionId;
      if (sessionId.length === 0) { continue; }
      let title = '';
      let preset = '';
      let projections = item.projections;
      if (projections !== undefined && projections !== null) {
        let values = projections.values;
        if (values !== undefined && values !== null) {
          if (values.title !== undefined && values.title !== null) { title = values.title; }
          if (values.agentPreset !== undefined && values.agentPreset !== null) { preset = values.agentPreset; }
        }
      }
      let session: DshSession = {
        sessionId: sessionId,
        title: title,
        cwd: item.cwd === undefined ? '' : item.cwd,
        running: item.running === true,
        blank: item.blank === true,
        agentAvailable: item.agentAvailable === true,
        agentPreset: preset,
        updatedAt: item.updatedAt === undefined ? 0 : item.updatedAt
      };
      sessions.push(session);
    }
    return sessions;
  }

  async createSession(workspaceId: string = '', cwd: string = '', agentPreset: string = ''): Promise<string> {
    let payload: SessionCreatePayload = {};
    if (workspaceId.length > 0) { payload.workspaceId = workspaceId; }
    if (cwd.length > 0) { payload.cwd = cwd; }
    if (agentPreset.length > 0) { payload.agentPreset = agentPreset; }
    let args: SessionCreateArgs = { request: payload };
    let parsed = await this.call<SessionCreateArgs, CreatedSessionValue>('session/create', args);
    let sessionId = parsed.sessionId === undefined ? '' : parsed.sessionId;
    if (sessionId.length === 0) { throw new Error('DSH 未返回新会话 id'); }
    return sessionId;
  }

  async listAgentPresets(): Promise<DshPreset[]> {
    let args: EmptyRequest = {};
    let parsed = await this.call<EmptyRequest, PresetListValue>('agentPresets/list', args);
    let presets = parsed.presets === undefined ? [] : parsed.presets;
    let output: DshPreset[] = [];
    for (let i = 0; i < presets.length; i++) {
      let item = presets[i];
      let id = item.id === undefined ? '' : item.id;
      if (id.length === 0) { continue; }
      let preset: DshPreset = {
        id: id,
        name: item.name === undefined ? id : item.name,
        description: item.description === undefined ? '' : item.description,
        isDefault: item.isDefault === true
      };
      output.push(preset);
    }
    return output;
  }

  // 宿主未组合 workspace 服务时静默返回空（dsh web 默认没有 workspace/list）。
  async listWorkspaces(): Promise<DshWorkspace[]> {
    let empty: EmptyRequest = {};
    let args: SessionListArgs = { _request: empty };
    let parsed: WorkspaceListValue;
    try {
      parsed = await this.call<SessionListArgs, WorkspaceListValue>('workspace/list', args);
    } catch (e) {
      return [];
    }
    let items = parsed.items === undefined ? [] : parsed.items;
    let output: DshWorkspace[] = [];
    for (let i = 0; i < items.length; i++) {
      let item = items[i];
      let id = item.workspaceId === undefined ? '' : item.workspaceId;
      if (id.length === 0) { continue; }
      let workspace: DshWorkspace = {
        workspaceId: id,
        title: item.title === undefined ? id : item.title,
        path: item.path === undefined ? '' : item.path
      };
      output.push(workspace);
    }
    return output;
  }

  // 发送一条消息。mode=queue 排队等当前回合；requestId 由调用方生成并持久化。
  async prompt(sessionId: string, text: string, requestId: string): Promise<void> {
    let part: TextContent = { type: 'text', text: text };
    let payload: SessionPromptPayload = {
      requestId: requestId,
      sessionId: sessionId,
      mode: 'queue',
      content: [part]
    };
    let args: SessionPromptArgs = { request: payload };
    await this.call<SessionPromptArgs, Object>('session/prompt', args);
  }

  async cancel(sessionId: string): Promise<void> {
    let payload: SessionIdPayload = { sessionId: sessionId };
    let args: SessionIdArgs = { request: payload };
    await this.call<SessionIdArgs, Object>('session/cancel', args);
  }

  async rename(sessionId: string, title: string): Promise<void> {
    let payload: SessionRenamePayload = { sessionId: sessionId, title: title };
    let args: SessionRenameArgs = { request: payload };
    await this.call<SessionRenameArgs, Object>('session/rename', args);
  }

  // 历史：throughSeq 用 follow 打开时的 cursor 作为上界。
  async page(sessionId: string, throughSeq: number, maxMessages: number): Promise<DshFollowFrame[]> {
    let address: FollowAddress = { kind: 'session', sessionId: sessionId };
    let payload: SessionPagePayload = {
      address: address,
      throughSeq: throughSeq,
      maxMessages: maxMessages
    };
    let args: SessionPageArgs = { request: payload };
    let parsed = await this.call<SessionPageArgs, PageValue>('session/page', args);
    let records = parsed.records === undefined ? [] : parsed.records;
    let frames: DshFollowFrame[] = [];
    for (let i = 0; i < records.length; i++) {
      let event = records[i].event;
      if (event === undefined || event === null) { continue; }
      let eventType = event.type === undefined ? '' : event.type;
      let text = eventText(event);
      if (text.length === 0 && eventType !== 'turn/start' && eventType !== 'turn/end') { continue; }
      let frame: DshFollowFrame = {
        kind: 'event',
        seq: event.seq === undefined ? 0 : event.seq,
        cursor: throughSeq,
        eventType: eventType,
        role: eventRole(event),
        text: text
      };
      frames.push(frame);
    }
    return frames;
  }

  // 订阅一个会话：WebSocket 打开 session/follow，持续收 snapshot/event/assistant-stream。
  // 返回取消函数；断线自动重连。
  subscribeFollow(sessionId: string, onFrame: (frame: DshFollowFrame) => void,
    onError: (message: string) => void, onReconnect: () => void = (): void => {}): () => void {
    let cookie = '';
    try {
      cookie = this.requireCookie();
    } catch (e) {
      onError((e as Error).message);
      return (): void => {};
    }
    let wsBase = normalizeDshBase(this.config.baseUrl).replace(/^http/i, 'ws');
    let url = wsBase + '/api/remote.mux';
    let streamId = 's-' + Date.now().toString(16) + '-' + Math.floor(Math.random() * 0xffff).toString(16);
    let socket: webSocket.WebSocket | null = null;
    let closed = false;
    let retryTimer = -1;
    let opened = false;

    let connectRef: () => void = (): void => {};

    let scheduleReconnect = (): void => {
      if (closed || retryTimer >= 0) { return; }
      retryTimer = setTimeout((): void => {
        retryTimer = -1;
        if (closed) { return; }
        onReconnect();
        connectRef();
      }, MUX_RECONNECT_MS);
    };

    let connect = (): void => {
      if (closed) { return; }
      // 每次新建连接都重置 opened，否则重连失败会被当成首次成功。
      opened = false;
      let ws = webSocket.createWebSocket();
      socket = ws;

      ws.on('open', (err: Object | undefined, value: Object | undefined): void => {
        if (closed) { return; }
        opened = true;
        if (!isOkCode(err)) { onError('DSH 事件流打开失败'); return; }
        // assistantStream 必须显式开启，否则宿主只推持久事件、不推逐字增量。
        let address: FollowAddress = { kind: 'session', sessionId: sessionId };
        let request: FollowStreamRequest = { address: address, maxMessages: 50, assistantStream: true };
        let args: FollowStreamArgs = { request: request };
        let payload: StreamPayload = { args: args };
        let frame: OpenStreamFrame = {
          type: 'open',
          streamId: streamId,
          endpoint: 'session/follow',
          payload: payload
        };
        ws.send(ArkJSON.stringify(frame));
      });

      ws.on('message', (err: Object | undefined, value: Object | undefined): void => {
        if (closed || value === undefined || value === null) { return; }
        // 宿主可能下发二进制帧，也可能是 UTF-8 文本；两种都先归一化成字符串。
        let text = '';
        if (typeof value === 'string') {
          text = value;
        } else {
          try {
            let decoder = new util.TextDecoder('utf-8');
            text = decoder.decodeToString(new Uint8Array(value as ArrayBuffer));
          } catch (e) {
            hilog.warn(0x0000, 'ClawMateCore', '[DSH] decode frame failed');
            return;
          }
        }
        handleMuxMessage(text, onFrame, onError);
      });

      ws.on('close', (err: Object | undefined, value: Object | undefined): void => {
        if (closed) { return; }
        socket = null;
        if (!opened) { onError('DSH 事件流连接失败'); }
        scheduleReconnect();
      });

      ws.on('error', (err: BusinessError): void => {
        if (closed) { return; }
        socket = null;
        onError('DSH 事件流错误: ' + err.message);
        scheduleReconnect();
      });

      let headers: WsHeaders = { 'Cookie': cookie };
      let options: webSocket.WebSocketRequestOptions = { header: headers };
      ws.connect(url, options).catch((e: Error): void => {
        if (closed) { return; }
        onError('DSH 事件流连接失败: ' + e.message);
        scheduleReconnect();
      });
    };

    connectRef = connect;
    connect();
    return (): void => {
      closed = true;
      if (retryTimer >= 0) { clearTimeout(retryTimer); retryTimer = -1; }
      let ws = socket;
      socket = null;
      if (ws !== null) {
        try { ws.off('message'); } catch (e) { /* 已关闭。 */ }
        try { ws.off('close'); } catch (e) { /* 已关闭。 */ }
        try { ws.off('error'); } catch (e) { /* 已关闭。 */ }
        try { ws.close(); } catch (e) { /* 已关闭。 */ }
      }
    };
  }
}

function emitEvent(event: PageEvent, cursor: number, onFrame: (frame: DshFollowFrame) => void): void {
  let eventType = event.type === undefined ? '' : event.type;
  let text = eventText(event);
  let isMarker = eventType === 'turn/start' || eventType === 'turn/end';
  if (text.length === 0 && !isMarker) { return; }
  let frame: DshFollowFrame = {
    kind: 'event',
    seq: event.seq === undefined ? 0 : event.seq,
    cursor: cursor,
    eventType: eventType,
    role: eventRole(event),
    text: text
  };
  onFrame(frame);
}

function handleMuxMessage(text: string, onFrame: (frame: DshFollowFrame) => void,
  onError: (message: string) => void): void {
  let message: MuxServerMessage;
  try {
    message = ArkJSON.parse(text) as MuxServerMessage;
  } catch (e) {
    hilog.warn(0x0000, 'ClawMateCore', '[DSH] bad frame: %{public}s', text.substring(0, 120));
    return;
  }

  if (message.type === 'error') {
    let error = message.error;
    let detail = error === undefined || error === null || error.message === undefined ?
      'DSH 事件流报错' : error.message;
    onError(detail);
    return;
  }
  if (message.type === 'end') { return; }
  let value = message.value;
  if (value === undefined || value === null) { return; }
  let cursor = value.cursor === undefined ? 0 : value.cursor;

  if (value.type === 'snapshot') {
    // snapshot 是打开时的历史快照：只用来对齐游标，绝不回放正文。
    // 之前把 records 逐条 emit 会重放整段历史，导致新一轮回复被旧内容覆盖。
    let snap: DshFollowFrame = {
      kind: 'snapshot', seq: cursor, cursor: cursor, eventType: 'snapshot', role: '', text: ''
    };
    onFrame(snap);
    return;
  }

  if (value.type === 'event') {
    let event = value.event;
    if (event === undefined || event === null) { return; }
    emitEvent(event, cursor, onFrame);
    return;
  }

  if (value.type === 'assistant-stream') {
    let part = value.frame;
    if (part === undefined || part === null || part.type !== 'chunk') { return; }
    let text0 = chunkText(part.chunk);
    if (text0.length > 0) {
      let delta: DshFollowFrame = {
        kind: 'assistant-stream', seq: cursor, cursor: cursor,
        eventType: 'assistant/chunk', role: 'assistant', text: text0
      };
      onFrame(delta);
      return;
    }
    let reasoning = chunkReasoning(part.chunk);
    if (reasoning.length > 0) {
      let think: DshFollowFrame = {
        kind: 'assistant-stream', seq: cursor, cursor: cursor,
        eventType: 'assistant/reasoning', role: 'assistant', text: reasoning
      };
      onFrame(think);
    }
  }
}
