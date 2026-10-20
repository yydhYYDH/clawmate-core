import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { Attachment, defaultSettings, Note, Settings } from '../core/Types';
import { Files } from './Files';
import { decodeUtf8 } from '../core/Domain';

export class Repository {
  private context: common.UIAbilityContext;
  private files: Files;
  private notesReady: boolean = false;
  constructor(context: common.UIAbilityContext) { this.context = context; this.files = new Files(context); }

  async loadSettings(): Promise<Settings> {
    let store = await preferences.getPreferences(this.context, { name: 'clawmate-settings' });
    let result = defaultSettings();
    // 修复旧设置页可能留下的空值，回退到用户指定的教师测试默认配置。
    result.modelUrl = (await store.get('modelUrl', result.modelUrl) as string).trim() || result.modelUrl;
    result.model = (await store.get('model', result.model) as string).trim() || result.model;
    result.vision = await store.get('vision', false) as boolean;
    result.bridgeUrl = await store.get('bridgeUrl', '') as string;
    return result;
  }

  async saveSettings(settings: Settings): Promise<void> {
    let store = await preferences.getPreferences(this.context, { name: 'clawmate-settings' });
    await store.put('modelUrl', settings.modelUrl);
    await store.put('model', settings.model);
    await store.put('vision', settings.vision);
    await store.put('bridgeUrl', settings.bridgeUrl);
    // 不将手动填写的凭据写入首选项；重启后使用 TeacherDefaults 中的课堂默认密钥。
    await store.flush();
  }

  async loadNotes(): Promise<Note[]> {
    let path = this.context.filesDir + '/notes-v1.json';
    if (!(await fs.access(path))) { this.notesReady = true; return []; }
    let bytes = await this.files.readBounded(path, 4 * 1024 * 1024);
    let notes = JSON.parse(decodeUtf8(bytes)) as Note[];
    if (!Array.isArray(notes) || notes.length > 50) { throw new Error('笔记索引格式错误；已保留原文件。'); }
    for (let note of notes) {
      if (typeof note.id !== 'string' || typeof note.text !== 'string' || !Array.isArray(note.attachments)) {
        throw new Error('笔记索引格式错误；已保留原文件。');
      }
      for (let item of note.attachments) {
        if (typeof item.path !== 'string' || !item.path.startsWith(this.context.filesDir + '/asset-')) {
          throw new Error('笔记包含无效附件路径；已保留原文件。');
        }
      }
    }
    this.notesReady = true;
    return notes;
  }

  async saveNotes(notes: Note[]): Promise<void> {
    if (!this.notesReady) { throw new Error('笔记索引尚未成功加载，禁止覆盖。请先处理加载错误。'); }
    if (notes.length > 50) { throw new Error('最多保存 50 条笔记，请先删除旧笔记。'); }
    let bytes = new util.TextEncoder().encodeInto(JSON.stringify(notes));
    if (bytes.length > 4 * 1024 * 1024) { throw new Error('笔记总量超过 4 MiB，请先清理旧笔记。'); }
    let path = this.context.filesDir + '/notes-v1.json';
    await this.files.writeAll(path + '.tmp', bytes.buffer as ArrayBuffer);
    await fs.rename(path + '.tmp', path);
  }

  async removeUnused(attachments: Attachment[], notes: Note[], active: Attachment[]): Promise<void> {
    for (let item of attachments) {
      let referenced = active.some((a: Attachment): boolean => a.id === item.id) ||
        notes.some((n: Note): boolean => n.attachments.some((a: Attachment): boolean => a.id === item.id));
      if (!referenced) { await this.files.remove(item); }
    }
  }
}
