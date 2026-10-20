#!/usr/bin/env python3
"""Create deterministic classroom inputs without external packages."""
from pathlib import Path
import hashlib
import json
import struct
import zlib


def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)


def main():
    folder = Path(__file__).resolve().parents[1] / 'fixtures'
    folder.mkdir(exist_ok=True)
    content = 'ClawMate 实验资料\n实验口令是蓝色风车\n中文标点：你好，鸿蒙！🙂\n请根据本文件回答问题。\n'
    (folder / 'hello-zh.txt').write_text(content, encoding='utf-8')
    (folder / 'hello-bom.txt').write_bytes(b'\xef\xbb\xbf' + content.encode())
    (folder / 'empty.txt').write_bytes(b'')
    (folder / 'oversize.txt').write_bytes(b'A' * (256 * 1024 + 1))
    (folder / 'invalid-utf8.txt').write_bytes(b'\xff\xfe\x00\x41')
    (folder / 'unsupported.bin').write_bytes(bytes(range(256)))
    (folder / 'lab-guide.md').write_text('# 实验说明\n\n- 观察图片\n- 核对文件内容\n- 保存回复并重启\n', encoding='utf-8')
    width, height = 640, 400
    pixels = bytearray()
    for y in range(height):
        pixels.append(0)
        for x in range(width):
            pixels.extend((45, 90, 220) if (x // 80 + y // 80) % 2 == 0 else (235, 240, 252))
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(pixels)) + chunk(b'IEND', b'')
    (folder / 'photo-grid.png').write_bytes(png)
    entries = {}
    for path in sorted(folder.iterdir()):
        if path.name not in ('README.md', 'manifest.json') and path.is_file():
            data = path.read_bytes()
            entries[path.name] = {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
    (folder / 'manifest.json').write_text(json.dumps(entries, indent=2, ensure_ascii=False) + '\n')
    print('Generated', len(entries), 'fixture files in', folder)


if __name__ == '__main__':
    main()
