# 本地调试与打包（最简版）

本文档说明：如何在本机调试开发，并最终打包为可分发的 `dmg`。

## 1. 本地调试（Xcode）
1. 用 Xcode 打开仓库目录。
2. 选择 `EasyLearnEnglish` scheme。
3. 运行即可本地调试。
4. 首次运行会提示语音识别权限，点允许即可。

## 2. 生成可执行 App
1. 在 Xcode 顶部选择 **Product → Archive**。
2. Archive 完成后会打开 Organizer。
3. 选择最新的 Archive，点击 **Distribute App**。
4. 选择 **Copy App**（最简单），导出得到 `EasyLearnEnglish.app`。

## 3. 打包 DMG（最简命令）
假设 `EasyLearnEnglish.app` 在 `~/Desktop`：

```bash
hdiutil create \
  -volname "EasyLearnEnglish" \
  -srcfolder ~/Desktop/EasyLearnEnglish.app \
  -ov \
  -format UDZO \
  ~/Desktop/EasyLearnEnglish.dmg
```

完成后会在桌面生成 `EasyLearnEnglish.dmg`。

## 4. 分发给他人
- 把 `EasyLearnEnglish.dmg` 发送给对方。
- 对方双击挂载后，将 App 拖到“应用程序”即可。

## 常见问题（最简）
- 若提示“来自未知开发者”：用户可在 系统设置 → 隐私与安全 中允许打开。
