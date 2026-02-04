# 功能设计 — Easy Learn English（macOS）

## 目标
- 导入音频/视频。
- 自动生成字幕（按媒体文件缓存）。
- 播放时字幕同步滚动。
- 单词可点击；支持连续单词选择。
- 显示英文释义 + 中文翻译。
- 单词可保存到生词本，并可管理。
- 多转写提供商（Apple 本地默认；OpenAI/Gemini/GLM/Kimi/MinMax 可扩展）。

## 非目标（初期）
- 云端同步 / 账号体系。
- 高级字幕编辑界面。
- 英中之外的多语言支持。
- 完全离线中文翻译引擎。

## 主要流程
1. 用户导入媒体。
2. App 检查本地字幕缓存。
3. 若无缓存，使用所选提供商转写。
4. 播放显示同步字幕；用户点击或选择单词。
5. 右侧显示释义与翻译。
6. 保存到生词本。

## 数据模型
- `MediaItem`
  - `id`, `url`, `title`, `duration`, `addedAt`, `fingerprint`.
- `Transcript`
  - `mediaFingerprint`, `provider`, `language`, `segments`.
- `TranscriptSegment`
  - `id`, `start`, `end`, `text`, `tokens`.
- `VocabularyEntry`
  - `id`, `word`, `definitionEn`, `translationZh`, `addedAt`, `sourceTitle`.

## 存储
- App Support 目录（例如：`~/Library/Application Support/EasyLearnEnglish/`）。
- `library.json`（媒体库）。
- `transcripts/<fingerprint>.json`（字幕缓存）。
- `vocabulary.json`（生词本）。

## 转写提供商
- `AppleSpeechProvider`（默认）：使用 `SFSpeechRecognizer`，尽量走本地识别降成本。
- `ExternalProvider` 占位：OpenAI、Gemini、GLM、Kimi、MinMax（后续接 API）。

## 核心服务
- `MediaLibrary`：导入、持久化、列表。
- `TranscriptStore`：按 fingerprint 缓存字幕。
- `TranscriptionService`：按设置路由到提供商。
- `TranslationService`：英文释义使用 DictionaryServices；中文翻译可接 API。
- `VocabularyStore`：保存/删除/列表。

## 错误处理
- Speech 权限缺失。
- 媒体不支持或导出失败（视频 → 音频）。
- 外部转写网络异常。
- 优雅回退到 Apple Speech。

## 权限
- 语音识别权限。
- 读取导入媒体文件的权限。

## 可扩展点
- 转写 Provider 协议化。
- 翻译 Provider 协议化。
- 字幕与词汇 JSON 格式稳定。
