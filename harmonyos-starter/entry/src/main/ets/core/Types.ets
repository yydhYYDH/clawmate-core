import { DEFAULT_MODEL_URL, DEFAULT_MODEL_NAME, DEFAULT_MODEL_KEY } from './TeacherDefaults';

export interface Attachment {
  id: string;
  name: string;
  kind: string;
  path: string;
  preview: string;
  mime: string;
  size: number;
  text: string;
}

export interface Note {
  id: string;
  text: string;
  createdAt: number;
  attachments: Attachment[];
}

export interface Settings {
  modelUrl: string;
  model: string;
  modelKey: string;
  vision: boolean;
  bridgeUrl: string;
  bridgeToken: string;
}

export function defaultSettings(): Settings {
  return { modelUrl: DEFAULT_MODEL_URL, model: DEFAULT_MODEL_NAME, modelKey: DEFAULT_MODEL_KEY,
    vision: false, bridgeUrl: '', bridgeToken: '' };
}

export interface ContentPart {
  type: string;
  text?: string;
  image_url?: ImageUrl;
}
export interface ImageUrl { url: string; }
export interface ModelMessage { role: string; content: string | ContentPart[]; }
export interface ModelTemplate { enable_thinking: boolean; }
export interface ModelBody {
  model: string; messages: ModelMessage[]; temperature: number; max_tokens: number;
  chat_template_kwargs?: ModelTemplate;
}
export interface ModelChoice { message?: ModelAnswer; }
export interface ModelAnswer { content?: string; }
export interface ModelResponse { choices?: ModelChoice[]; }
export interface BridgeApp { name: string; bundle: string; ability: string; }
export interface Capabilities { screenshot: boolean; actions: boolean; apps: BridgeApp[]; reason: string; }
export interface Session { id: string; }
export interface Screenshot { base64: string; mime: string; width: number; height: number; }
export interface Plan { bundle: string; task: string; }
export interface Action {
  action: string;
  bundle?: string;
  x?: number;
  y?: number;
  x2?: number;
  y2?: number;
  text?: string;
  status?: string;
  summary?: string;
}
export interface Receipt { message: string; }
export interface RunResult { status: string; message: string; }
export interface AppEvents { log: (line: string) => void; phase: (phase: string) => void; }
