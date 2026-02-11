# Easy Learn English 打包与安装流程（.app + .dmg）

本文档给出一套完整流程：
- 产出可运行的 `.app`
- 再打包成 `.dmg` 安装文件
- 最终在本机安装使用

适用环境：macOS + Xcode（本项目最低 macOS 13）。

## 1. 先产出 `.app`

### 方式 A：Xcode 图形界面（推荐）
1. 用 Xcode 打开仓库目录：`easy-learn-english`。
2. 选择 Scheme：`EasyLearnEnglish`。
3. 菜单点击 `Product -> Build`（或 `Run` 也可）。
4. 编译完成后，`.app` 通常在 DerivedData 目录，使用下面命令查找：

```bash
find ~/Library/Developer/Xcode/DerivedData -maxdepth 6 -name "EasyLearnEnglish.app" 2>/dev/null
```

5. 复制一份到桌面（便于后续打包）：

```bash
cp -R "/实际查到的路径/EasyLearnEnglish.app" ~/Desktop/

cp -R "/Users/minutch/Library/Developer/Xcode/DerivedData/EasyLearnEnglish-blvwqrlwbdivqcbqlevvadczffgs/Build/Products/Debug/EasyLearnEnglish.app" ~/Downloads/
```

### 方式 B：命令行构建（可选）
如果你希望命令行生成 Debug 版 `.app`，可在项目根目录执行：

```bash
xcodebuild \
  -scheme EasyLearnEnglish \
  -configuration Debug \
  build
```

完成后同样用 `find` 命令定位 `.app`，再复制到桌面。

## 2. 打包 `.dmg`

确保桌面已有这个文件：
- `~/Desktop/EasyLearnEnglish.app`

执行：

```bash
hdiutil create \
  -volname "EasyLearnEnglish" \
  -srcfolder ~/Desktop/EasyLearnEnglish.app \
  -ov \
  -format UDZO \
  ~/Desktop/EasyLearnEnglish.dmg
```

生成结果：
- `~/Desktop/EasyLearnEnglish.dmg`

## 3. 本地安装与运行
1. 双击 `~/Desktop/EasyLearnEnglish.dmg` 挂载镜像。
2. 将 `EasyLearnEnglish.app` 拖入 `Applications`。
3. 从“应用程序”启动。
4. 首次运行若被系统拦截：
   - 打开 `系统设置 -> 隐私与安全`
   - 在底部找到该 App，点击“仍要打开”
5. 首次使用转写功能时，允许语音识别权限。

## 4. 常见错误与排查

### 错误：`hdiutil: create failed - 无此文件或目录`
原因：`-srcfolder` 指向的 `.app` 路径不存在。  
排查：

```bash
ls -la ~/Desktop/EasyLearnEnglish.app
```

如果不存在，先用下面命令找到 `.app`：

```bash
find ~/Library/Developer/Xcode/DerivedData -maxdepth 6 -name "EasyLearnEnglish.app" 2>/dev/null
```

然后复制到桌面再执行 `hdiutil create`。

### 找到多个 `.app`，该用哪个？
- 优先选择最新构建时间的路径。
- 建议每次打包前先 `Product -> Build` 一次，确保是当前代码版本。

### `.xcarchive` 里没有 `Products/Applications/*.app`
这通常是归档产物结构与传统 App 工程不同。  
对“本地安装使用”场景，直接用 DerivedData 中构建出的 `.app` 即可，不影响打包 `.dmg`。

## 5. 一条命令快速检查（可选）
下面命令可快速确认桌面是否具备打包条件：

```bash
test -d ~/Desktop/EasyLearnEnglish.app && echo "OK: app exists" || echo "Missing: ~/Desktop/EasyLearnEnglish.app"
```
