# Easy Learn English（macOS）

一个基于 SwiftUI 的 macOS 原型，用于导入音频/视频、生成字幕、选择单词并管理生词本。

## 功能
- 导入音频/视频并自动生成字幕。
- 字幕列表与播放时间同步。
- 点击或 `Shift+点击` 选择单词。
- 右侧显示英文释义 + 中文翻译。
- 单词保存到本地生词本。
- 字幕缓存（已生成不重复转写）。
- 可扩展的转写提供商架构（Apple Speech 默认；外部提供商占位）。

## 运行
1. 用 Xcode 打开该目录。
2. 选择 `EasyLearnEnglish` scheme 运行。
3. 首次转写会提示语音识别权限。

## 说明
- Apple Speech 默认尽量使用本地识别以降低成本。
- 外部提供商（OpenAI/Gemini/GLM/Kimi/MinMax）为占位，需要补 API 集成：`Sources/EasyLearnEnglish/Services/TranscriptionService.swift`。
- 中文翻译当前为占位，需要接入翻译 API：`Sources/EasyLearnEnglish/Services/TranslationService.swift`。

## 数据存储
存放于 `~/Library/Application Support/EasyLearnEnglish/`：
- `library.json`
- `transcripts/<fingerprint>.json`
- `vocabulary.json`
