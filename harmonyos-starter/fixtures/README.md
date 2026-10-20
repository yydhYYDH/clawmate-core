# 课堂测试资料

运行 `python3 scripts/make-fixtures.py` 可重建所有资料，具体字节数和 SHA-256 见 `manifest.json`。

| 文件 | 期望 |
| --- | --- |
| hello-zh.txt | UTF-8 中文、标点、emoji，包含唯一实验口令 |
| hello-bom.txt | 带 UTF-8 BOM，显示时不含 BOM 字符 |
| lab-guide.md | 当作普通 UTF-8 文本导入 |
| empty.txt | 成功读入空文本，界面显示空文件 |
| oversize.txt | 比 256 KiB 多一字节，拒绝导入 |
| invalid-utf8.txt | 拒绝非法 UTF-8，不显示乱码冒充成功 |
| unsupported.bin | 非支持格式，拒绝导入或在选择器中过滤 |
| photo-grid.png | 640×400 人工网格图；先通过系统支持方式导入图库，再真实选择 |

这里只提供教学数据，不包含个人照片和真实服务凭据。选做的大图片和同名文件可以由教师另行准备。
