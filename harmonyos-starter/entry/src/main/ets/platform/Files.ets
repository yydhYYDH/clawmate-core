import { common } from '@kit.AbilityKit';
import { fileIo as fs, fileUri, picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { Attachment } from '../core/Types';
import { decodeUtf8, IMAGE_LIMIT, TEXT_LIMIT } from '../core/Domain';

export class Files {
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }

  async selectPhoto(): Promise<string> {
    let options = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 1;
    let result = await new photoAccessHelper.PhotoViewPicker().select(options);
    return result.photoUris.length > 0 ? result.photoUris[0] : '';
  }

  async selectDocument(): Promise<string> {
    let options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = ['文本|.txt,.md'];
    let result = await new picker.DocumentViewPicker(this.context).select(options);
    return result.length > 0 ? result[0] : '';
  }

  async readBounded(uri: string, limit: number): Promise<Uint8Array> {
    let file = await fs.open(uri, fs.OpenMode.READ_ONLY);
    try {
      let stat = await fs.stat(file.fd);
      if (stat.size > limit) { throw new Error('文件超过大小限制：' + limit + ' 字节。'); }
      let output = new Uint8Array(limit + 1);
      let used = 0;
      while (used <= limit) {
        let buffer = new ArrayBuffer(Math.min(65536, limit + 1 - used));
        let count = await fs.read(file.fd, buffer);
        if (count === 0) { break; }
        output.set(new Uint8Array(buffer, 0, count), used);
        used += count;
      }
      if (used > limit) { throw new Error('文件读取过程中超过大小限制。'); }
      return output.slice(0, used);
    } finally { await fs.close(file); }
  }

  async writeAll(path: string, data: ArrayBuffer): Promise<void> {
    let file = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try {
      let written = 0;
      while (written < data.byteLength) {
        let count = await fs.write(file.fd, data.slice(written));
        if (count <= 0) { throw new Error('文件未完整写入。'); }
        written += count;
      }
    } finally { await fs.close(file); }
  }

  // Picker 只记录 URI；用户返回 App 点击“确认导入”后才调用此方法。
  async importSelected(uri: string, kind: string): Promise<Attachment> {
    let name = new fileUri.FileUri(uri).name;
    if (kind === 'text' && !/\.(txt|md)$/i.test(name)) { throw new Error('仅支持 UTF-8 的 .txt 和 .md 文件。'); }
    let bytes = await this.readBounded(uri, kind === 'image' ? IMAGE_LIMIT : TEXT_LIMIT);
    if (kind === 'image' && bytes.length === 0) { throw new Error('图片为空。'); }
    let text = kind === 'text' ? decodeUtf8(bytes) : '';
    let id = Date.now().toString() + '-' + Math.floor(Math.random() * 1000000000).toString();
    let path = this.context.filesDir + '/asset-' + id;
    let preview = kind === 'image' ? path + '-preview.jpg' : '';
    let mime = '';
    try {
      await this.writeAll(path, bytes.buffer as ArrayBuffer);
      if (kind === 'image') {
        let source = image.createImageSource(bytes.buffer as ArrayBuffer);
        try {
          let info = await source.getImageInfo();
          let scale = Math.min(1, 1024 / Math.max(info.size.width, info.size.height));
          let pixels = await source.createPixelMap({ desiredSize: {
            width: Math.max(1, Math.round(info.size.width * scale)), height: Math.max(1, Math.round(info.size.height * scale))
          } });
          try {
            let packer = image.createImagePacker();
            try { await this.writeAll(preview, await packer.packToData(pixels, { format: 'image/jpeg', quality: 85 })); }
            finally { await packer.release(); }
          } finally { await pixels.release(); }
        } finally { await source.release(); }
        mime = 'image/jpeg';
      }
      return { id: id, name: name, kind: kind, path: path, preview: preview, mime: mime, size: bytes.length, text: text };
    } catch (e) {
      await this.removePath(path);
      if (preview) { await this.removePath(preview); }
      throw e as Error;
    }
  }

  async imageData(attachment: Attachment): Promise<string> {
    let bytes = await this.readBounded(attachment.preview, IMAGE_LIMIT);
    return 'data:image/jpeg;base64,' + new util.Base64Helper().encodeToStringSync(bytes);
  }

  async removePath(path: string): Promise<void> {
    if (!path.startsWith(this.context.filesDir + '/asset-')) { return; }
    try { await fs.unlink(path); } catch (e) { /* 删除不存在的半成品不影响恢复。 */ }
  }

  async remove(attachment: Attachment): Promise<void> {
    await this.removePath(attachment.path);
    if (attachment.preview) { await this.removePath(attachment.preview); }
  }
}
