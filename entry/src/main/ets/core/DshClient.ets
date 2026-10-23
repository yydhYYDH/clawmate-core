// 局域网 DSH（DeepSeek Harness）移动端通道客户端。
//
// 协议依据 dsh web（@deepseek-ai/dsh-client-connection + dsh-api-gateway），
// 已在 yydh 真机链路上逐条验证：
//   - 认证：GET /?token=<launch-token> → 303 + Set-Cookie dsh-auth-<hash>=v1.<body>.<sig>
//     cookie 名按 authority 的 sha256 生成，所以不能写死；一次换取 30 天有效。
//   - 一元调用：POST /api/<ns>/<method>，body
//     {"type":"client-request","rpcId","method":"<ns>/<method>","payload":{"args":{...}}}
//     method 必须与 URL 去掉 /api/ 的那一段完全一致，参数统一包在 args 里。
//   - 流：WebSocket /api/remote.mux，帧为
//     {"type":"open","streamId","endpoint":"session/follow","payload":{"args":{...}}}
//     Host 回 {"type":"item","streamId","value":...} / {"type":"end","streamId"} / {"type":"error",...}
// 全程只用 Cookie，不触碰宿主的其它 /api 面。

import { http, webSocket } from '@kit.NetworkKit';
import { JSON as ArkJSON } from '@kit.ArkTS';
import { WorkflowJsonMap } from './WorkflowTypes';

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

// session/follow 下发的三种帧。
export interface DshFollowFrame {
  kind: string;          // snapshot | event | assistant-stream
  seq: number;
  cursor: number;
  eventType: string;
  role: string;
  text: string;
  raw: string;
}

interface RpcEnvelope {
  type: string;
  rpcId: string;
  method: string;
  payload: WorkflowJsonMap;
}

interface ServerResponse {
  type?: string;
  rpcId?: string;
  result?: ServerResult;
}

interface ServerResult {
  ok?: boolean;
  value?: Object;
  error?: ServerError;
}

interface ServerError {
  code?: string;
  message?: string;
}

interface SessionListValue {
  items?: SessionItem[];
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

interface Projections {
  asOfSeq?: number;
  values?: ProjectionValues;
}

interface ProjectionValues {
  title?: string;
  agentPreset?: string;
}

interface CreatedSessionValue {
  sessionId?: string;
  agentPreset?: string;
}

interface PresetListValue {
  presets?: PresetItem[];
}

interface PresetItem {
  id?: string;
  name?: string;
  description?: string;
  isDefault?: boolean;
}

interface WorkspaceListValue {
  items?: WorkspaceItem[];
}

interface WorkspaceItem {
  workspaceId?: string;
  title?: string;
  path?: string;
}

interface PageValue {
  records?: PageRecord[];
  hasMore?: boolean;
}

interface PageRecord {
  type?: string;
  event?: PageEvent;
}

interface PageEvent {
  type?: string;
  seq?: number;
  data?: PageEventData;
}

interface PageEventData {
  message?: PageMessage;
  content?: PageContent[];
  inserted?: PageMessage[];
  text?: string;
}

interface PageMessage {
  role?: string;
  content?: PageContent[];
}

interface PageContent {
  type?: string;
  text?: string;
}

interface MuxFrame {
  type?: string;
  streamId?: string;
  value?: MuxValue;
  error?: ServerError;
}

interface MuxValue {
  type?: string;
  header?: MuxHeader;
  cursor?: number;
  records?: PageRecord[];
  event?: PageEvent;
  frame?: MuxAssistantFrame;
}

interface MuxHeader {
  id?: string;
  cwd?: string;
  agentPreset?: string;
}

interface MuxAssistantFrame {
  type?: string;
  chunk?: MuxChunkPayload;
}

// assistant-stream 的 chunk 是结构化块：block-start / text-delta / reasoning-delta /
// tool-call-delta / block-end 等，只有 *-delta 携带可展示文本。
interface MuxChunkPayload {
  type?: string;
  text?: string;
  delta?: string;
  content?: string;
  blockType?: string;
  index?: number;
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

// ArkTS 的响应头是普通对象，键名大小写不确定，逐个找。
function headerValue(headers: Object, name: string): string {
  let record = headers as WorkflowJsonMap;
  let lower = name.toLowerCase();
  let keys = Object.keys(record);
  for (let i = 0; i < keys.length; i++) {
    if (keys[i].toLowerCase() === lower) { return String(record[keys[i]]); }
  }
  return '';
}

// 从 Set-Cookie 里挑出 dsh-auth-*（多值响应头在不同实现里可能是逗号或数组）。
function authCookieFrom(raw: string): string {
  let segments = raw.split(',');
  for (let i = 0; i < segments.length; i++) {
    let parts = segments[i].split(';');
    for (let j = 0; j < parts.length; j++) {
      let piece = parts[j].trim();
      if (piece.startsWith(AUTH_COOKIE_PREFIX)) {
        let eq = piece.indexOf('=');
        if (eq > 0) { return piece.substring(0, eq) + '=' + piece.substring(eq + 1); }
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
  let markers = ['token=', 'pair='];
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
  let request = http.createHttp();
  try {
    let response = await request.request(url, {
      method: http.RequestMethod.GET,
      header: { 'Accept': 'text/html' },
      connectTimeout: 8000,
      readTimeout: 15000,
      expectDataType: http.HttpDataType.STRING
    });
    let raw = headerValue(response.header as Object, 'set-cookie');
    if (raw.length === 0) {
      throw new Error('DSH 未下发认证 cookie（HTTP ' + String(response.responseCode) + '），token 可能已失效');
    }
    let cookie = authCookieFrom(raw);
    if (cookie.length === 0) {
      // 已配对过的链接只回 303 不带新 cookie，此时沿用旧值由调用方决定。
      throw new Error('DSH 返回的 Set-Cookie 里没有 dsh-auth-* 项');
    }
    return cookie;
  } finally {
    try { request.destroy(); } catch (e) { /* 已结束。 */ }
  }
}

function eventText(event: PageEvent): string {
  let data = event.data;
  if (data === undefined || data === null) { return ''; }
  let collected = '';
  let message = data.message;
  if (message !== undefined && message !== null) { collected += contentText(message.content); }
  if (data.inserted !== undefined && data.inserted !== null) {
    for (let i = 0; i < data.inserted.length; i++) { collected += contentText(data.inserted[i].content); }
  }
  if (collected.length === 0) { collected += contentText(data.content); }
  return collected;
}

// 只取可见正文（type === 'text'），reasoning / tool 块不进正文。
function contentText(content: PageContent[] | undefined): string {
  if (content === undefined || content === null) { return ''; }
  let text = '';
  for (let i = 0; i < content.length; i++) {
    let part = content[i];
    if (part.type === 'text' && part.text !== undefined) { text += part.text; }
  }
  return text;
}

// 只取正文增量；reasoning-delta / tool-call-* 交给日志，不混进回复正文。
function chunkText(chunk: MuxChunkPayload | undefined): string {
  if (chunk === undefined || chunk === null) { return ''; }
  if (chunk.type !== 'text-delta') { return ''; }
  if (typeof chunk.text === 'string') { return chunk.text; }
  if (typeof chunk.delta === 'string') { return chunk.delta; }
  return '';
}

function chunkReasoning(chunk: MuxChunkPayload | undefined): string {
  if (chunk === undefined || chunk === null || chunk.type !== 'reasoning-delta') { return ''; }
  return typeof chunk.text === 'string' ? chunk.text : '';
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
  async call(method: string, args: WorkflowJsonMap): Promise<WorkflowJsonMap> {
    let cookie = this.requireCookie();
    let rpcId = mintRpcId();
    let payload: WorkflowJsonMap = { 'args': args };
    let envelope: RpcEnvelope = { type: 'client-request', rpcId: rpcId, method: method, payload: payload };
    let headers: WorkflowJsonMap = {
      'Content-Type': 'application/json',
      'Cookie': cookie
    };
    let url = normalizeDshBase(this.config.baseUrl) + '/api/' + method;
    let request = http.createHttp();
    let timer = -1;
    try {
      let response = await new Promise<http.HttpResponse>((resolve, reject): void => {
        timer = setTimeout((): void => {
          reject(new Error('DSH 请求超时'));
          request.destroy();
        }, RPC_TIMEOUT_MS);
        request.request(url, {
          method: http.RequestMethod.POST,
          header: headers,
          extraData: ArkJSON.stringify(envelope),
          connectTimeout: 8000,
          readTimeout: RPC_TIMEOUT_MS,
          expectDataType: http.HttpDataType.STRING
        }).then(resolve).catch(reject);
      });
      let body = String(response.result);
      if (response.responseCode === 401) { throw new Error('DSH 认证已失效，请重新粘贴带 token 的链接'); }
      if (response.responseCode === 404) { throw new Error('DSH 上没有方法 ' + method); }
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error('HTTP ' + String(response.responseCode) + ': ' + body.substring(0, 200));
      }
      let parsed = ArkJSON.parse(body) as ServerResponse;
      if (parsed.type !== 'server-response' || parsed.rpcId !== rpcId) {
        throw new Error('DSH 响应信封不匹配');
      }
      let result = parsed.result;
      if (result === undefined || result === null) { throw new Error('DSH 响应缺少 result'); }
      if (result.ok !== true) {
        let error = result.error;
        let message = error === undefined || error === null ? 'DSH 调用失败' :
          ((error.code === undefined ? '' : String(error.code) + ': ') + (error.message === undefined ? '' : error.message));
        throw new Error(message);
      }
      let value = result.value === undefined || result.value === null ? {} : result.value;
      return value as WorkflowJsonMap;
    } finally {
      clearTimeout(timer);
      try { request.destroy(); } catch (e) { /* 已结束。 */ }
    }
  }

  async listSessions(): Promise<DshSession[]> {
    let value = await this.call('session/list', { '_request': {} } as WorkflowJsonMap);
    let parsed = value as SessionListValue;
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
      sessions.push({
        sessionId: sessionId,
        title: title,
        cwd: item.cwd === undefined ? '' : item.cwd,
        running: item.running === true,
        blank: item.blank === true,
        agentAvailable: item.agentAvailable === true,
        agentPreset: preset,
        updatedAt: item.updatedAt === undefined ? 0 : item.updatedAt
      });
    }
    return sessions;
  }

  async createSession(workspaceId: string = '', cwd: string = '', agentPreset: string = ''): Promise<string> {
    let request: WorkflowJsonMap = {};
    if (workspaceId.length > 0) { request['workspaceId'] = workspaceId; }
    if (cwd.length > 0) { request['cwd'] = cwd; }
    if (agentPreset.length > 0) { request['agentPreset'] = agentPreset; }
    let value = await this.call('session/create', { 'request': request } as WorkflowJsonMap);
    let parsed = value as CreatedSessionValue;
    let sessionId = parsed.sessionId === undefined ? '' : parsed.sessionId;
    if (sessionId.length === 0) { throw new Error('DSH 未返回新会话 id'); }
    return sessionId;
  }

  async listAgentPresets(): Promise<DshPreset[]> {
    let value = await this.call('agentPresets/list', {} as WorkflowJsonMap);
    let parsed = value as PresetListValue;
    let presets = parsed.presets === undefined ? [] : parsed.presets;
    let output: DshPreset[] = [];
    for (let i = 0; i < presets.length; i++) {
      let item = presets[i];
      let id = item.id === undefined ? '' : item.id;
      if (id.length === 0) { continue; }
      output.push({
        id: id,
        name: item.name === undefined ? id : item.name,
        description: item.description === undefined ? '' : item.description,
        isDefault: item.isDefault === true
      });
    }
    return output;
  }

  // 工作区列表：宿主未组合该服务时静默返回空（dsh web 默认没有 workspace/list）。
  async listWorkspaces(): Promise<DshWorkspace[]> {
    try {
      let value = await this.call('workspace/list', { '_request': {} } as WorkflowJsonMap);
      let parsed = value as WorkspaceListValue;
      let items = parsed.items === undefined ? [] : parsed.items;
      let output: DshWorkspace[] = [];
      for (let i = 0; i < items.length; i++) {
        let item = items[i];
        let id = item.workspaceId === undefined ? '' : item.workspaceId;
        if (id.length === 0) { continue; }
        output.push({
          workspaceId: id,
          title: item.title === undefined ? id : item.title,
          path: item.path === undefined ? '' : item.path
        });
      }
      return output;
    } catch (e) {
      return [];
    }
  }

  // 发送一条消息。mode=queue 排队等当前回合；requestId 由客户端生成并持久化在用户消息上。
  async prompt(sessionId: string, text: string, requestId: string): Promise<void> {
    let content: WorkflowJsonMap[] = [{ 'type': 'text', 'text': text } as WorkflowJsonMap];
    let request: WorkflowJsonMap = {
      'requestId': requestId,
      'sessionId': sessionId,
      'mode': 'queue',
      'content': content
    };
    await this.call('session/prompt', { 'request': request } as WorkflowJsonMap);
  }

  async cancel(sessionId: string): Promise<void> {
    await this.call('session/cancel', { 'request': { 'sessionId': sessionId } as WorkflowJsonMap } as WorkflowJsonMap);
  }

  async rename(sessionId: string, title: string): Promise<void> {
    let request: WorkflowJsonMap = { 'sessionId': sessionId, 'title': title };
    await this.call('session/rename', { 'request': request } as WorkflowJsonMap);
  }

  // 历史：session/page 要求 throughSeq 不越过跟随游标；调用方用 follow 的 cursor 作为上界。
  async page(sessionId: string, throughSeq: number, maxMessages: number): Promise<DshFollowFrame[]> {
    let address: WorkflowJsonMap = { 'kind': 'session', 'sessionId': sessionId };
    let request: WorkflowJsonMap = {
      'address': address,
      'throughSeq': throughSeq,
      'maxMessages': maxMessages
    };
    let value = await this.call('session/page', { 'request': request } as WorkflowJsonMap);
    let parsed = value as PageValue;
    let records = parsed.records === undefined ? [] : parsed.records;
    let frames: DshFollowFrame[] = [];
    for (let i = 0; i < records.length; i++) {
      let event = records[i].event;
      if (event === undefined || event === null) { continue; }
      let eventType = event.type === undefined ? '' : event.type;
      let text = eventText(event);
      if (text.length === 0 && eventType !== 'turn/start' && eventType !== 'turn/end') { continue; }
      frames.push({
        kind: 'event',
        seq: event.seq === undefined ? 0 : event.seq,
        cursor: throughSeq,
        eventType: eventType,
        role: roleOf(event),
        text: text,
        raw: ''
      });
    }
    return frames;
  }

  // 订阅一个会话：WebSocket 打开 session/follow，持续收 snapshot/event/assistant-stream。
  // 返回取消函数。断线自动重连，重连后由调用方用 page() 补齐。
  subscribeFollow(sessionId: string, onFrame: (frame: DshFollowFrame) => void,
    onError: (message: string) => void, onReconnect: () => void = (): void => {}): () => void {
    let cookie = '';
    try { cookie = this.requireCookie(); } catch (e) {
      onError((e as Error).message);
      return (): void => {};
    }
    let url = normalizeDshBase(this.config.baseUrl).replace(/^http/i, 'ws') + '/api/remote.mux';
    let streamId = 's-' + Date.now().toString(16) + '-' + Math.floor(Math.random() * 0xffff).toString(16);
    let socket: webSocket.WebSocket | null = null;
    let closed = false;
    let retryTimer = -1;
    let opened = false;

    let scheduleReconnect = (): void => {
      if (closed || retryTimer >= 0) { return; }
      retryTimer = setTimeout((): void => {
        retryTimer = -1;
        if (closed) { return; }
        onReconnect();
        connect();
      }, MUX_RECONNECT_MS);
    };

    let connect = (): void => {
      if (closed) { return; }
      let ws = webSocket.createWebSocket();
      socket = ws;
      ws.on('open', (err: Object, value: Object): void => {
        if (closed) { return; }
        opened = true;
        if (openError(err)) { onError('DSH 事件流打开失败'); return; }
        let address: WorkflowJsonMap = { 'kind': 'session', 'sessionId': sessionId };
        // assistantStream 必须显式开启，否则宿主只推持久事件、不推逐字增量。
        let request: WorkflowJsonMap = {
          'address': address,
          'maxMessages': 50,
          'assistantStream': true
        };
        let frame: WorkflowJsonMap = {
          'type': 'open',
          'streamId': streamId,
          'endpoint': 'session/follow',
          'payload': { 'args': { 'request': request } as WorkflowJsonMap } as WorkflowJsonMap
        };
        ws.send(ArkJSON.stringify(frame));
      });
      ws.on('message', (err: Object, value: Object): void => {
        if (closed) { return; }
        // AsyncCallback<string | ArrayBuffer> 的 data 在首参成功时为字符串。
        handleMuxFrame(String(value), onFrame, onError);
      });
      ws.on('close', (err: Object, value: Object): void => {
        if (closed) { return; }
        socket = null;
        if (!opened) { onError('DSH 事件流连接失败'); }
        scheduleReconnect();
      });
      ws.on('error', (err: Object, value: Object): void => {
        if (closed) { return; }
        socket = null;
        onError('DSH 事件流错误');
        scheduleReconnect();
      });
      let options: webSocket.WebSocketRequestOptions = {
        header: { 'Cookie': cookie } as WorkflowJsonMap,
        connectTimeout: 8000
      };
      ws.connect(url, options).catch((e: Error): void => {
        if (closed) { return; }
        onError('DSH 事件流连接失败: ' + e.message);
        scheduleReconnect();
      });
    };

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

// ArkTS 的 WebSocket 回调首参是 BusinessError，空对象表示成功。
function openError(err: Object): boolean {
  if (err === undefined || err === null) { return false; }
  let code = (err as WorkflowJsonMap)['code'];
  return code !== undefined && code !== null && Number(code) !== 0;
}

function roleOf(event: PageEvent): string {
  let data = event.data;
  if (data === undefined || data === null) { return ''; }
  if (data.message !== undefined && data.message !== null && data.message.role !== undefined) {
    return data.message.role;
  }
  return '';
}

function handleMuxFrame(text: string, onFrame: (frame: DshFollowFrame) => void,
  onError: (message: string) => void): void {
  let frame: MuxFrame;
  try { frame = ArkJSON.parse(text) as MuxFrame; } catch (e) { return; }
  if (frame.type === 'error') {
    let error = frame.error;
    onError(error === undefined || error === null ?
      'DSH 事件流报错' : (error.message === undefined ? 'DSH 事件流报错' : error.message));
    return;
  }
  if (frame.type === 'end') { return; }
  let value = frame.value;
  if (value === undefined || value === null) { return; }
  let cursor = value.cursor === undefined ? 0 : value.cursor;
  if (value.type === 'snapshot') {
    let records = value.records === undefined ? [] : value.records;
    for (let i = 0; i < records.length; i++) {
      let event = records[i].event;
      if (event === undefined || event === null) { continue; }
      emitEvent(event, cursor, onFrame);
    }
    onFrame({
      kind: 'snapshot', seq: cursor, cursor: cursor, eventType: 'snapshot', role: '', text: '', raw: ''
    });
    return;
  }
  if (value.type === 'event') {
    let event = value.event;
    if (event === undefined || event === null) { return; }
    emitEvent(event, cursor, onFrame);
    return;
  }
  if (value.type === 'assistant-stream') {
    let frameValue = value.frame;
    if (frameValue === undefined || frameValue === null) { return; }
    if (frameValue.type !== 'chunk') { return; }
    let chunk = frameValue.chunk;
    let text = chunkText(chunk);
    if (text.length > 0) {
      onFrame({
        kind: 'assistant-stream', seq: cursor, cursor: cursor,
        eventType: 'assistant/chunk', role: 'assistant', text: text, raw: ''
      });
      return;
    }
    let reasoning = chunkReasoning(chunk);
    if (reasoning.length > 0) {
      onFrame({
        kind: 'assistant-stream', seq: cursor, cursor: cursor,
        eventType: 'assistant/reasoning', role: 'assistant', text: reasoning, raw: ''
      });
    }
    return;
  }
}

function emitEvent(event: PageEvent, cursor: number, onFrame: (frame: DshFollowFrame) => void): void {
  let eventType = event.type === undefined ? '' : event.type;
  let text = eventText(event);
  let isMarker = eventType === 'turn/start' || eventType === 'turn/end';
  if (text.length === 0 && !isMarker) { return; }
  onFrame({
    kind: 'event',
    seq: event.seq === undefined ? 0 : event.seq,
    cursor: cursor,
    eventType: eventType,
    role: roleOf(event),
    text: text,
    raw: ''
  });
}
