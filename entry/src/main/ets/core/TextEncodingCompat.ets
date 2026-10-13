import { util } from '@kit.ArkTS';

export function encodeUtf8Compat(value: string): Uint8Array {
  // 优先使用系统 UTF-8 编码；本地 Previewer 单测环境中该接口可能不可调用，失败时降级到手写实现。
  try {
    let encoded = util.TextEncoder.create('utf-8').encodeInto(value);
    return exactUint8Array(encoded);
  } catch (e) {
  }
  return encodeUtf8Manually(value);
}

export function decodeUtf8Compat(bytes: Uint8Array): string {
  // 解码同样保留系统实现优先，避免真机可用能力被本地单测兼容逻辑绕过。
  try {
    return util.TextDecoder.create('utf-8').decodeWithStream(bytes);
  } catch (e) {
  }
  let output: string[] = [];
  let index = 0;
  while (index < bytes.length) {
    let first = bytes[index];
    if (first <= 0x7F) {
      output.push(String.fromCharCode(first));
      index++;
      continue;
    }

    let codePoint = 0xFFFD;
    if (first >= 0xC2 && first <= 0xDF && index + 1 < bytes.length) {
      let second = bytes[index + 1];
      if (isContinuationByte(second)) {
        codePoint = ((first & 0x1F) << 6) | (second & 0x3F);
        index += 2;
      } else {
        index++;
      }
    } else if (first >= 0xE0 && first <= 0xEF && index + 2 < bytes.length) {
      let second = bytes[index + 1];
      let third = bytes[index + 2];
      if (isContinuationByte(second) && isContinuationByte(third)) {
        codePoint = ((first & 0x0F) << 12) | ((second & 0x3F) << 6) | (third & 0x3F);
        index += 3;
      } else {
        index++;
      }
    } else if (first >= 0xF0 && first <= 0xF4 && index + 3 < bytes.length) {
      let second = bytes[index + 1];
      let third = bytes[index + 2];
      let fourth = bytes[index + 3];
      if (isContinuationByte(second) && isContinuationByte(third) && isContinuationByte(fourth)) {
        codePoint = ((first & 0x07) << 18) | ((second & 0x3F) << 12) | ((third & 0x3F) << 6) | (fourth & 0x3F);
        index += 4;
      } else {
        index++;
      }
    } else {
      index++;
    }

    appendDecodedCodePoint(output, codePoint);
  }
  return output.join('');
}

function encodeUtf8Manually(value: string): Uint8Array {
  let bytes: number[] = [];
  for (let index = 0; index < value.length; index++) {
    let codePoint = value.charCodeAt(index);
    if (codePoint >= 0xD800 && codePoint <= 0xDBFF && index + 1 < value.length) {
      let next = value.charCodeAt(index + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) {
        codePoint = 0x10000 + ((codePoint - 0xD800) * 0x400) + (next - 0xDC00);
        index++;
      }
    }
    appendUtf8CodePoint(bytes, codePoint);
  }
  return new Uint8Array(bytes);
}

function exactUint8Array(bytes: Uint8Array): Uint8Array {
  if (bytes.byteOffset === 0 && bytes.byteLength === bytes.buffer.byteLength) {
    return bytes;
  }
  let output = new Uint8Array(bytes.byteLength);
  for (let index = 0; index < bytes.byteLength; index++) {
    output[index] = bytes[index];
  }
  return output;
}

function appendUtf8CodePoint(bytes: number[], codePoint: number): void {
  if (codePoint <= 0x7F) {
    bytes.push(codePoint);
  } else if (codePoint <= 0x7FF) {
    bytes.push(0xC0 | (codePoint >> 6));
    bytes.push(0x80 | (codePoint & 0x3F));
  } else if (codePoint <= 0xFFFF) {
    bytes.push(0xE0 | (codePoint >> 12));
    bytes.push(0x80 | ((codePoint >> 6) & 0x3F));
    bytes.push(0x80 | (codePoint & 0x3F));
  } else {
    bytes.push(0xF0 | (codePoint >> 18));
    bytes.push(0x80 | ((codePoint >> 12) & 0x3F));
    bytes.push(0x80 | ((codePoint >> 6) & 0x3F));
    bytes.push(0x80 | (codePoint & 0x3F));
  }
}

function isContinuationByte(value: number): boolean {
  return (value & 0xC0) === 0x80;
}

function appendDecodedCodePoint(output: string[], codePoint: number): void {
  if (codePoint <= 0xFFFF) {
    output.push(String.fromCharCode(codePoint));
    return;
  }
  let adjusted = codePoint - 0x10000;
  output.push(String.fromCharCode(0xD800 + (adjusted >> 10)));
  output.push(String.fromCharCode(0xDC00 + (adjusted & 0x3FF)));
}
