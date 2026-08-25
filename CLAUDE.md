# CLAUDE.md

此文件为 Claude Code (claude.ai/code) 在此仓库中工作时提供指导。

## 构建与开发命令

- **安装依赖**: `flutter pub get`
- **运行**: `flutter run`（追加 `-d windows` / `-d android` 等指定目标平台）
- **构建 APK**: `flutter build apk --release`
- **构建 iOS**: `flutter build ios --release --no-codesign`
- **构建 Windows**: `flutter build windows --release`
- **构建 Linux**: `flutter build linux --release`
- **构建 macOS**: `flutter build macos --release`
- **静态分析**: `flutter analyze`
- **运行测试**: `flutter test`
- **单个测试**: `flutter test test/path/to_test.dart`
- **更新依赖**: `flutter pub upgrade --major-versions`

## 项目架构

### 概述

PicaComic 是一个基于 Flutter 的多源漫画阅读器（fork 自 nyne/wgh136）。支持 6 个内置漫画源以及通过 JavaScript 插件实现的自定义漫画源。

### 源码目录

| 目录 | 用途 |
|-----------|---------|
| `lib/comic_source/` | 漫画源抽象层 — 定义所有漫画源需要实现的接口 |
| `lib/network/` | 各漫画源的 HTTP 客户端、下载管理器、WebDAV 同步、HTTP 代理 |
| `lib/pages/` | UI 页面：各漫画源的专属页面、阅读器、设置、主导航 |
| `lib/components/` | 可复用的 UI 组件（列表、卡片、导航栏、对话框等） |
| `lib/foundation/` | 核心基础设施：应用状态、图片加载与缓存、日志、历史记录、收藏 |
| `lib/tools/` | 工具函数：国际化翻译、通知、IO、JS 引擎、标签翻译 |

### 漫画源系统

应用通过 `ComicSource` 类（`lib/comic_source/comic_source.dart`）实现插件式架构：

- **6 个内置源**: picacg、e-hentai、jmcomic、hitomi、htcomic、nhentai
  - 每个源是 `lib/comic_source/built_in/*.dart` 中的一个 `ComicSource.named(...)` 单例
  - 通过 `appdata.settings[82]`（位掩码字符串）启用/禁用
  - 在 `ComicSource.init()` 中注册（`lib/init.dart` 中调用）
- **自定义源**: `{App.dataPath}/comic_source/*.js` 中的 JavaScript 文件，由 `ComicSourceParser` 使用 `flutter_qjs` 解析
- 每个源提供：分类、收藏、探索页、搜索、漫画信息、图片加载、评论、设置

### 核心类型

- `ComicSource` — 定义漫画源，包含所有操作的回调函数和字段
- `BaseComic` — 抽象的漫画数据模型（`title`、`subTitle`、`cover`、`id`、`tags`、`description`）
- `CustomComic` — 具体的 `BaseComic`，附加 `sourceKey` 字段
- `Res<T>` — 通用网络结果包装（`data`、`errorMessage`、`subData`）
- `ComicInfoData` — 完整的漫画详情，包含章节、缩略图、标签；实现 `HistoryMixin`
- `Appdata` — 全局单例，管理所有设置（`List<String> settings`）、历史记录、收藏、屏蔽关键词

### 全局状态

- `appdata`（`lib/base.dart:286`）— 全局 `Appdata` 单例，包含约 90+ 个索引字符串设置
- `App`（`lib/foundation/app.dart`）— 静态类：平台检测、导航辅助、路径管理、UI 模式

### 数据流程

1. 用户操作 → 页面组件 → `ComicSource` 方法调用 → 网络请求 → `Res<T>` → UI 更新
2. 设置以索引 `List<String>` 形式存储在 `appdata.settings` 中，持久化到 `{App.dataPath}/settings`（JSON）
3. 图片通过 `CachedImageProvider` → `ImageManager` 加载，带有自定义磁盘缓存（按设置的限制大小）
4. 漫画源数据持久化到 `{App.dataPath}/comic_source/{key}.data`（JSON）
5. WebDAV 同步上传/下载设置、历史记录、收藏的 JSON 数据

### 国际化

翻译字符串在 `assets/translation.json` 中。用法：`"some string".tl`。支持 zh-CN、zh-TW、en-US。

### 阅读器（`lib/pages/reader/`）

支持多种翻页模式（从左到右、从右到左、上下滚动、连续上下滚动）、自动旋转、亮度调节、双击缩放和页面书签。

### 下载系统

`DownloadManager`（`lib/network/download.dart`）管理并行下载，使用 `downloadModel` / `custom_download_model.dart`。支持每个漫画源的专属下载实现。
