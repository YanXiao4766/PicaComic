# PicaComic 模块设计思想与写法指南

这份文档接着 `PROJECT_ARCHITECTURE_GUIDE.md` 往下讲。上一份更像“项目地图”，告诉你文件在哪里、流程怎么走；这一份更像“设计说明书”，重点回答：

- 这个模块负责什么？
- 代码为什么这么写？
- 这种写法有什么好处？
- 如果我是 Flutter 新手，我应该怎么读、怎么改？

你可以把整个项目想成一台机器：

```text
main/init/base 负责开机和全局配置
ComicSource 负责把不同漫画源变成统一接口
pages 负责组织页面
components 负责复用 UI
network 负责请求、解析和下载
foundation 负责状态、缓存、历史、图片等基础能力
reader 负责统一阅读体验
```

最核心的设计思想是：

```text
把“不一样”的东西关在底层，把“一样”的体验放在上层复用。
```

不同漫画源的网站、接口、图片规则都不一样，这是“不一样”；但 App 的分类页、搜索页、漫画列表、详情页、阅读器体验是“一样”的。这个项目大量代码都是围绕这件事设计的。

## 1. 启动与初始化模块

核心文件：

```text
lib/main.dart
lib/init.dart
lib/base.dart
lib/foundation/app.dart
```

### 这个模块负责什么

启动模块负责把 App 从“进程刚启动”变成“可以显示主界面”的状态。

它要做的事情很多：

- 初始化 Flutter。
- 初始化翻译。
- 读取设置和用户数据。
- 初始化缓存目录、数据目录。
- 初始化 Cookie、网络代理、下载管理器。
- 初始化漫画源。
- 初始化历史记录、本地收藏、通知。
- 配置主题、语言、路由。
- 判断进入引导页、锁屏页还是主界面。

### 典型写法

`main.dart` 里：

```dart
void main(List<String> args) {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await AppTranslation.init();
    await init();
    runApp(const MyApp());
  }, (error, stack) {
    LogManager.addLog(LogLevel.error, "Unhandled Exception", "$error\n$stack");
  });
}
```

`init.dart` 里：

```dart
Future<void> init() async {
  await App.init();
  await appdata.readData();
  await ComicSource.init();
  await Future.wait([
    downloadManager.init(),
    NhentaiNetwork().init(),
    JmNetwork().init(),
    LocalFavoritesManager().init(),
    HistoryManager().init(),
    AppTranslation.init(),
  ]);
}
```

### 为什么要这么写

启动过程被拆成两层：

- `main.dart`：Flutter 和 UI 层入口。
- `init.dart`：业务数据和服务初始化。

这是一种很常见的分层方式。因为 UI 启动前，有些东西必须先准备好，比如：

- 数据目录必须先知道，否则日志、缓存、数据库不知道写到哪里。
- 设置必须先读出来，否则不知道主题、语言、是否首次使用。
- 漫画源必须先初始化，否则分类页、搜索页没有数据。

如果所有初始化都塞在 `main.dart`，入口文件会越来越臃肿，而且很难看出哪些是 Flutter 初始化，哪些是业务初始化。

### 这样写的好处

- `main.dart` 保持清晰，主要关心 App 生命周期和 UI 根节点。
- `init.dart` 集中管理启动前准备，方便排查启动失败。
- `runZonedGuarded` 可以兜住未捕获异常，写入日志。
- `Future.wait` 可以并行初始化多个互不依赖的模块，减少启动耗时。

### 新手理解方式

可以把启动流程想成开店：

```text
main.dart：打开店门、挂招牌、决定顾客看到哪个入口。
init.dart：开灯、连网、准备货架、读取库存、整理账本。
base.dart：保存店铺配置，例如主题、源启用状态、下载目录。
App：提供店铺公共工具，例如导航、数据路径、平台判断。
```

### 改动建议

如果你要新增一个“App 启动时必须准备”的模块，优先放在 `init.dart`。例如新增一个数据库管理器，应该类似：

```dart
await Future.wait([
  ExistingManager().init(),
  NewManager().init(),
]);
```

如果只是 UI 页面进入后才需要的数据，不要放启动初始化里，否则会拖慢打开 App。

## 2. App 与全局工具模块

核心文件：

```text
lib/foundation/app.dart
lib/foundation/widget_utils.dart
lib/foundation/app_page_route.dart
```

### 这个模块负责什么

`App` 是一个全局工具类，主要做这些事：

- 判断平台：Android、iOS、Windows、Linux、macOS。
- 保存全局 `navigatorKey`。
- 保存主界面内部导航 `mainNavigatorKey`。
- 封装页面跳转。
- 提供全局上下文 `globalContext`。
- 保存数据目录和缓存目录。
- 判断 UI 模式：手机、平板、桌面。
- 获取当前语言。

### 典型写法

```dart
static final navigatorKey = GlobalKey<NavigatorState>();
static GlobalKey<NavigatorState>? mainNavigatorKey;

static Future<T?> to<T extends Object?>(
  BuildContext context,
  Widget Function() page,
) {
  return Navigator.of(context).push<T>(
    AppPageRoute(builder: (context) => page()),
  );
}
```

页面里常见：

```dart
App.globalTo(() => ComicPage(sourceKey: "jm", id: comic.id));
context.to(() => SearchResultPage(...));
```

### 为什么要这么写

原生 Flutter 的 `Navigator.of(context).push(...)` 每次写起来比较长，而且这个项目有一些统一需求：

- 路由动画要统一。
- 页面跳转要写日志。
- 有些地方没有方便的局部 `context`，需要全局跳转。
- 主界面内部还有一层 Navigator，需要区分根导航和主界面导航。

所以项目把导航封装到 `App` 和扩展方法里。

### 这样写的好处

- 页面跳转代码更短。
- 路由行为集中管理。
- 方便做全局日志和返回逻辑。
- 多平台差异可以被封装起来。

### 需要注意的风险

全局 `context` 很方便，但也容易滥用。新手要记住：

- 有局部 `context` 时，优先用局部 `context`。
- 跨模块或异步回调里，才考虑 `App.globalContext`。
- 异步后使用 `context` 要注意页面是否还存在。

## 3. 全局设置 Appdata 模块

核心文件：

```text
lib/base.dart
```

### 这个模块负责什么

`Appdata` 是项目的全局配置和轻量持久化中心。它保存：

- 搜索历史。
- 收藏标签。
- 屏蔽关键词。
- 首次使用状态。
- 大量设置项。
- 历史记录管理器入口。
- 下载管理器入口。

全局实例：

```dart
var appdata = Appdata();
var downloadManager = DownloadManager();
```

### 典型写法

设置保存在一个 `List<String>`：

```dart
List<String> settings = [
  "1",   // 0 点击屏幕左右区域翻页
  "dd",  // 1 排序方式
  ...
  "0",   // 25 漫画列表显示模式
  ...
];
```

为了让代码更好读，后面又封装了 `_Settings`：

```dart
class _Settings {
  int get comicsListDisplayType => int.parse(appdata.settings[25]);

  set comicsListDisplayType(int value) {
    appdata.settings[25] = value.toString();
  }
}
```

使用时：

```dart
appdata.appSettings.comicsListDisplayType
appdata.appSettings.fullyHideBlockedWorks
```

### 为什么要这么写

`List<String>` 保存设置不是最现代、最类型安全的方式，但它有历史原因和兼容优势：

- 老版本数据可以按下标继续读。
- 保存到本地文件/SharedPreferences 很简单。
- 新增设置只需要在末尾追加，旧数据不会丢。
- 跨平台读写成本低。

不过这种写法的缺点也明显：`settings[25]` 本身看不出含义。所以项目又用 `_Settings` 包了一层，试图把下标变成有名字的 getter。

### 这样写的好处

- 兼容旧数据。
- 持久化简单。
- 设置同步容易。
- 对老项目迁移成本低。

### 这样写的代价

- 下标容易写错。
- 设置项删除/插入很危险。
- 所有值都是字符串，需要手动转 int/bool。

### 新手改动建议

如果要新增设置：

1. 只在 `settings` 末尾追加，不要插入中间。
2. 给注释写清楚含义。
3. 在 `_Settings` 添加 getter/setter。
4. 页面代码尽量用 `appdata.appSettings.xxx`，不要直接写 `settings[数字]`。

错误示例：

```dart
if (appdata.settings[91] == "1") { ... }
```

推荐示例：

```dart
if (appdata.appSettings.myNewFeatureEnabled) { ... }
```

## 4. ComicSource 漫画源抽象模块

核心文件：

```text
lib/comic_source/comic_source.dart
lib/comic_source/category.dart
lib/comic_source/favorites.dart
lib/comic_source/built_in/*.dart
```

### 这个模块负责什么

这个模块负责定义“一个漫画源应该具备哪些能力”。

不同源差异很大：

- Picacg 是 JSON API。
- nhentai 多数页面是 HTML 解析。
- JM 有特殊域名、图片重组、登录。
- EH/EX 有 Cookie 和复杂图片限制。

但 App 页面需要统一使用它们。所以项目定义了 `ComicSource`，让每个源把自己的能力填进去。

### 典型写法

以 Picacg 为例，简化后像这样：

```dart
final picacg = ComicSource.named(
  name: "picacg",
  key: "picacg",
  categoryData: CategoryData(...),
  categoryComicsData: CategoryComicsData.named(
    load: (category, param, options, page) {
      return PicacgNetwork().getCategoryComics(...);
    },
  ),
  searchPageData: SearchPageData.named(
    loadPage: (keyword, page, options) {
      return PicacgNetwork().search(keyword, options[0], page);
    },
  ),
  comicPageBuilder: (context, id, cover) => PicacgComicPage(id, cover),
);
```

### 为什么要用配置式写法

`ComicSource.named(...)` 看起来像在填表。它的设计思想是：

```text
页面层问：你支持分类吗？你支持搜索吗？你怎么加载详情？
漫画源答：这些函数给你，调用它们就行。
```

这样页面层不用写：

```dart
if (sourceKey == "picacg") {
  PicacgNetwork().search(...)
} else if (sourceKey == "jm") {
  JmNetwork().search(...)
}
```

而是统一写：

```dart
ComicSource.find(sourceKey)!.searchPageData!.loadPage!(...)
```

### 这样写的好处

- 页面层不需要知道每个源的细节。
- 新增漫画源时主要添加一个 `ComicSource` 配置和 network 实现。
- 分类页、搜索页、列表页可以复用。
- 每个源可以只实现自己支持的能力。
- 特殊源可以覆盖默认页面，比如提供自己的详情页。

### CategoryData 为什么要拆出来

`CategoryData` 描述分类页展示什么：

```dart
CategoryData(
  title: "Picacg",
  key: "picacg",
  categories: [
    FixedCategoryPart("分类", _categories, "category"),
  ],
  enableRankingPage: true,
)
```

它只描述“有哪些标签、点击标签是什么类型”，不直接请求网络。

这是典型的声明式设计：

```text
数据结构描述页面该长什么样。
页面根据数据结构自动生成 UI。
```

好处是分类页不用为每个源写一套 UI。

### FavoriteData 为什么要拆出来

`FavoriteData` 描述网络收藏能力：

```dart
FavoriteData(
  key: "jm",
  title: "禁漫天堂",
  multiFolder: true,
  loadComic: ...,
  loadFolders: ...,
  addOrDelFavorite: ...,
)
```

不同源收藏能力不一样：

- 有的只有一个收藏夹。
- 有的支持多个文件夹。
- 有的支持新建/删除收藏夹。
- 有的只支持读取，不支持增删。

所以用可空函数表达能力：

```dart
final Future<Res<bool>> Function(String key)? deleteFolder;
```

如果是 `null`，页面就知道这个功能不可用。

### 新手改动建议

想改某个源的“入口能力”，先看：

```text
lib/comic_source/built_in/源.dart
```

想改这个源“怎么请求数据”，再看：

```text
lib/network/源_network/
```

不要一开始就去改页面层。大多数源相关问题，优先在 `built_in` 和 `network` 里解决。

## 5. 页面层 pages 模块

核心目录：

```text
lib/pages/
```

### 这个模块负责什么

页面层负责组织用户看到的完整页面，比如：

- 主页面。
- 分类页。
- 搜索页。
- 漫画详情页。
- 阅读器。
- 收藏页。
- 设置页。

页面层通常不应该直接关心底层 HTTP 请求细节，它更像“导演”：

```text
页面决定显示什么组件，以及什么时候调用某个抽象能力。
```

### 典型页面链路

分类页链路：

```text
AllCategoryPage
  ↓
CategoryPage
  ↓
CategoryComicsPage
  ↓
_CategoryComicsList extends ComicsPage
  ↓
CategoryComicsData.load
  ↓
对应 Network
```

搜索页链路：

```text
PreSearchPage
  ↓
SearchResultPage
  ↓
_SearchPageComicList extends ComicsPage
  ↓
SearchPageData.loadPage
  ↓
对应 Network
```

详情页链路：

```text
ComicPage
  ↓
检查 source.comicPageBuilder
  ↓
自定义详情页 或 通用 _ComicPageImpl
```

### 为什么页面层这么写

页面层大量使用“抽象回调”：

```dart
final CategoryComicsLoader loader;

Future<Res<List<BaseComic>>> getComics(int i) async {
  return await loader(category, param, options, i);
}
```

这意味着页面只知道“我要第几页数据”，不知道数据从哪个 API 来。

这种写法叫依赖抽象，而不是依赖具体实现。

### 这样写的好处

- 分类页可以同时服务 Picacg、JM、nhentai 等源。
- 搜索页可以同时服务多个源。
- 页面代码更稳定，源变化时通常不用改页面。
- 可以把 UI 问题和网络问题分开排查。

### 新手怎么看页面代码

看页面时，不要一开始追所有函数。先问三个问题：

1. 这个页面显示哪些 UI 区块？
2. 用户点击后跳到哪里？
3. 数据是通过哪个 loader 传进来的？

比如看 `CategoryComicsPage`：

- UI：上面是 AppBar，中间是漫画列表，列表头部是排序选项。
- 点击排序：更新 `optionsValue`，刷新列表 key。
- 数据：来自 `data.load`。

这样读就不会迷路。

## 6. components 通用组件模块

核心目录：

```text
lib/components/
```

重点文件：

```text
lib/components/components.dart
lib/components/comics_list.dart
lib/components/comic_tile.dart
lib/components/appbar.dart
lib/components/button.dart
lib/components/menu.dart
lib/components/pop_up_widget.dart
```

### 这个模块负责什么

`components` 是通用 UI 零件库。它提供：

- AppBar。
- 按钮。
- 弹窗。
- 菜单。
- 漫画卡片。
- 漫画网格列表。
- 加载动画。
- 自定义滚动组件。

`components.dart` 是一个聚合文件：

```dart
library components;

part 'comics_list.dart';
part 'comic_tile.dart';
part 'button.dart';
...
```

### 为什么要用 part

这个项目把很多组件拆成多个文件，但又希望它们共享同一个 library 的私有内容，所以用了 Dart 的 `part` 机制。

简单理解：

```text
components.dart 是一本书的封面。
comics_list.dart、comic_tile.dart 是这本书的章节。
这些章节合起来属于同一个 library。
```

好处：

- 外部只要 import `components.dart`。
- 内部组件可以共享一些私有类/函数。
- 文件不会全部挤在一个超大 Dart 文件里。

代价：

- `part of 'components.dart';` 对新手不太直观。
- 文件不能单独作为独立 library 使用。

### ComicsPage 为什么是泛型抽象类

文件：`lib/components/comics_list.dart`

核心定义：

```dart
abstract class ComicsPage<T extends BaseComic> extends StatelessWidget {
  Future<Res<List<T>>> getComics(int i);
  String get sourceKey;
}
```

它的意思是：

- 这是一个漫画列表页面。
- 具体漫画类型可以不同，但必须继承 `BaseComic`。
- 子类必须告诉我怎么按页加载数据。
- 子类必须告诉我属于哪个漫画源。

### 为什么这么写

如果不用抽象组件，每个源都要写一套：

- 加载中 UI。
- 错误 UI。
- 空页面 UI。
- 网格布局。
- 滑到底部加载下一页。
- 分页模式。
- 跳页按钮。
- 屏蔽关键词过滤。

这会产生大量重复代码。

`ComicsPage` 把这些通用逻辑收起来，只把“数据怎么来”留给子类。

这就是模板方法思想：

```text
父类规定流程。
子类填入变化的部分。
```

### 这样写的好处

- 列表体验统一。
- 修 bug 一次影响多个列表。
- 新增源更简单，只需要提供 `getComics`。
- 像“跳转页数按钮”这种功能，可以集中加在 `ComicsPage`。

### 最近跳页按钮为什么适合放在 ComicsPage

你要的需求是：

```text
nhentai、Picacg、禁漫天堂连续滚动列表都支持输入页数跳转。
```

这不是某一个源的数据解析问题，而是“漫画列表交互问题”。所以它应该放在通用列表组件。

现在代码思路是：

```dart
void jumpToPage(getComics, page, {replaceLoadedComics = false}) async {
  var res = await getComics(page);
  current = page;
  comics = List<T>.from(res.data);
}
```

右下角按钮只对部分源显示：

```dart
bool get enableQuickPageJump =>
    sourceKey == "nhentai" || sourceKey == "picacg" || sourceKey == "jm";
```

这样做的好处是：

- 不影响所有源。
- 功能复用同一套实现。
- 未来要支持新源，只加一个 `sourceKey` 即可。

### 新手改动建议

改 `components` 要比改单个页面更谨慎，因为影响范围大。

建议：

- 只改某个源的表现时，优先改该源的 `comicTileBuilderOverride`。
- 改所有漫画列表行为时，再改 `comics_list.dart`。
- 改所有漫画卡片布局时，再改 `comic_tile.dart`。

## 7. network 网络层模块

核心目录：

```text
lib/network/
```

重点文件：

```text
lib/network/res.dart
lib/network/base_comic.dart
lib/network/app_dio.dart
lib/network/picacg_network/
lib/network/jm_network/
lib/network/nhentai_network/
lib/network/eh_network/
lib/network/hitomi_network/
lib/network/htmanga_network/
```

### 这个模块负责什么

网络层负责：

- 发 HTTP 请求。
- 处理 Cookie、Header、Token。
- 解析 JSON 或 HTML。
- 把网站/API 返回值变成 App 内部模型。
- 处理错误。
- 提供下载模型。

### Res<T> 为什么存在

文件：`lib/network/res.dart`

核心结构：

```dart
class Res<T> {
  final String? errorMessage;
  final T? _data;
  bool get error => errorMessage != null;
  T get data => _data ?? (throw Exception(errorMessage));
  final dynamic subData;
}
```

这个项目大量方法返回：

```dart
Future<Res<List<BaseComic>>>
Future<Res<ComicInfoData>>
Future<Res<bool>>
```

### 为什么不直接 throw

网络失败是正常情况，不一定是程序 bug。例如：

- 账号失效。
- 403。
- 连接超时。
- 网站改版导致解析失败。
- 没有更多页面。

如果这些都用异常一路 throw，页面层会到处写 try/catch。

使用 `Res<T>` 后，页面可以统一写：

```dart
var res = await getComics(page);
if (res.error) {
  message = res.errorMessage;
} else {
  comics = res.data;
}
```

### 这样写的好处

- 成功和失败都用同一种返回结构表达。
- UI 层更容易显示错误信息。
- `subData` 可以携带额外信息，比如最大页数。
- 网络层可以把底层异常转换成用户能看懂的错误。

### BaseComic 为什么存在

文件：`lib/network/base_comic.dart`

```dart
abstract class BaseComic {
  String get title;
  String get subTitle;
  String get cover;
  String get id;
  List<String> get tags;
  String get description;
}
```

Picacg、JM、nhentai 的列表项模型都不一样，但漫画卡片需要的字段大体相同：

- 标题。
- 封面。
- ID。
- 副标题。
- 标签。
- 描述。

所以用 `BaseComic` 规定最低要求。

### 这样写的好处

- `ComicsPage<BaseComic>` 可以显示任意源的列表项。
- 卡片组件只依赖统一接口。
- 不同源可以保留自己的额外字段。

### app_dio.dart 为什么要封装 Dio

`Dio` 是底层 HTTP 客户端，但项目需要更多公共能力：

- 请求日志。
- 响应日志。
- 超时设置。
- 错误信息改写。
- 代理。
- HTTP/2。
- 失败重试。
- 特殊 host/SNI 规则。

所以项目用 `app_dio.dart` 集中封装。

如果每个 network 文件都自己配置 Dio，会出现：

- 超时不一致。
- 日志不一致。
- 代理不一致。
- 错误处理不一致。
- 重试逻辑重复。

### JSON API 和 HTML 解析的区别

Picacg 更像 JSON API：

```dart
var jsonResponse = jsonDecode(res.data) as Map<String, dynamic>;
return Res(jsonResponse);
```

nhentai 更像 HTML 解析：

```dart
var document = parse(res.data);
var comicDoms = document.querySelectorAll("div.gallery");
```

这就是为什么不同源的 network 文件写法差异很大。

抽象层的价值就在这里：不管底层是 JSON 还是 HTML，最终都变成 `Res<List<BaseComic>>`。

## 8. 状态管理 StateController 模块

核心文件：

```text
lib/foundation/state_controller.dart
```

### 这个模块负责什么

项目没有使用 Provider、Riverpod、Bloc、GetX，而是自己写了一套轻量状态管理。

核心类：

- `StateController`
- `StateBuilder`
- `SimpleController`
- `StateWithController`

### 典型写法

Controller：

```dart
class ComicsPageLogic<T> extends StateController {
  bool loading = true;
  List<T>? comics;

  void refresh() {
    loading = true;
    comics = null;
    update();
  }
}
```

Widget：

```dart
StateBuilder<ComicsPageLogic<T>>(
  init: ComicsPageLogic<T>(),
  tag: tag,
  builder: (logic) {
    return ...;
  },
)
```

更新：

```dart
logic.update();
```

查找：

```dart
StateController.find<ComicsPageLogic<T>>(tag: tag)
```

### 为什么要这么写

这个项目很多页面需要“页面外部也能找到某个状态对象”。例如：

- 列表页刷新。
- 阅读器工具栏控制阅读逻辑。
- 搜索页建议框更新。
- 多个组件共享同一个页面状态。

如果只用 Flutter 原生 `setState`，状态只能方便地在当前 `State` 里用。跨组件调用会比较麻烦。

`StateController` 提供了一个全局注册表：

```dart
static final _controllers = <StateControllerWrapped>[];
```

配合 `tag`，就能找到某个页面对应的 controller。

### tag 为什么重要

同一个类型可能有多个实例。例如你可以打开多个漫画列表页，它们都用 `ComicsPageLogic`。

如果没有 tag，系统不知道你要更新哪个列表。

所以列表页会定义：

```dart
String? get tag => "$category with $param and $options";
```

### 这样写的好处

- 比引入大型状态管理框架轻。
- 使用方式简单。
- 跨组件查找状态方便。
- 对这个项目的页面结构足够用。

### 这样写的风险

- Controller 是全局列表管理，生命周期要小心。
- tag 写错会找不到或找错 controller。
- 不像成熟框架那样有严格约束。

### 新手改动建议

如果只是一个小组件内部状态，用 `StatefulWidget + setState` 就够。

如果状态要被页面多个地方共享，或者需要外部调用刷新，可以考虑 `StateController`。

## 9. 阅读器 reader 模块

核心目录：

```text
lib/pages/reader/
```

重点文件：

```text
comic_reading_page.dart
reading_data.dart
reading_logic.dart
image_view.dart
image.dart
tool_bar.dart
touch_control.dart
eps_view.dart
reading_settings.dart
reading_type.dart
```

### 这个模块负责什么

阅读器负责把漫画图片按用户设置展示出来，包括：

- 翻页。
- 章节切换。
- 图片加载。
- 阅读进度记录。
- 横竖屏。
- 沉浸式 UI。
- 手势和点击区域。
- 工具栏。
- 本地下载图片读取。

### 为什么阅读器要拆成很多 part

阅读器功能很复杂。如果全写在一个文件，会非常难维护。

所以项目拆成：

- `comic_reading_page.dart`：阅读器页面入口。
- `reading_data.dart`：不同源如何加载章节和图片。
- `reading_logic.dart`：当前页、当前章节、跳页逻辑。
- `image_view.dart`：图片列表/翻页视图。
- `tool_bar.dart`：顶部/底部工具栏。
- `touch_control.dart`：点击区域和手势。
- `eps_view.dart`：章节列表抽屉。

这种拆法的思想是：

```text
一个大功能，按职责拆成多个小文件。
```

### ReadingData 为什么重要

文件：`lib/pages/reader/reading_data.dart`

核心抽象：

```dart
abstract class ReadingData {
  String get title;
  String get id;
  String get sourceKey;
  bool get hasEp;
  Map<String, String>? get eps;

  Future<Res<List<String>>> loadEpNetwork(int ep);
  Stream<DownloadProgress> loadImageNetwork(int ep, int page, String url);
}
```

阅读器页面不应该关心：

- Picacg 怎么拿章节图片。
- JM 图片怎么重组。
- nhentai 图片 URL 怎么解析。
- EH 图片如何绕限制。

这些差异都放进不同 `ReadingData`：

```dart
PicacgReadingData
JmReadingData
NhentaiReadingData
EhReadingData
HitomiReadingData
HtReadingData
```

### 为什么这么写

阅读器只想问两个问题：

```text
第 ep 章有哪些图片？
第 ep 章第 page 张图片怎么加载？
```

至于不同源怎么回答，这是 `ReadingData` 的职责。

这样阅读器 UI 就可以复用：

```text
同一个阅读器
  ↓
不同 ReadingData
  ↓
不同漫画源
```

### 本地下载和网络加载为什么放在 ReadingData

`ReadingData.loadEp()` 会先判断是否已下载：

```dart
if (downloaded && checkEpDownloaded(ep)) {
  return Res(List.filled(length, ""));
} else {
  return await loadEpNetwork(ep);
}
```

`loadImage()` 也类似：

```dart
if (downloaded && checkEpDownloaded(ep)) {
  yield 本地图片;
} else {
  yield* loadImageNetwork(ep, page, url);
}
```

这让阅读器 UI 不需要知道图片来自本地还是网络。

### 这样写的好处

- 阅读器体验统一。
- 新源只要实现自己的 `ReadingData`。
- 下载阅读和在线阅读共用同一个界面。
- 图片加载差异被隔离。

### 新手改动建议

如果你要改阅读器 UI，先看：

```text
image_view.dart
tool_bar.dart
touch_control.dart
reading_settings.dart
```

如果你要改某个源图片加载，先看：

```text
reading_data.dart
ImageManager
对应源 network
```

不要把某个源的特殊逻辑直接写进通用 UI，除非真的无法抽象。

## 10. 图片加载与缓存模块

核心文件：

```text
lib/foundation/image_manager.dart
lib/foundation/cache_manager.dart
lib/foundation/image_loader/
```

### 这个模块负责什么

图片模块负责：

- 网络图片下载。
- 图片进度。
- 图片缓存。
- 特殊源图片处理。
- 本地文件图片读取。
- 给 Flutter UI 提供 `ImageProvider`。

### ImageManager 为什么存在

如果直接在 UI 里写 `Image.network(url)`，会有很多问题：

- 无法统一缓存。
- 无法显示下载进度。
- 无法处理特殊 Header/Cookie。
- 无法处理 JM 图片重组。
- 无法控制并发和重复加载。
- 无法和下载管理器复用逻辑。

所以项目用 `ImageManager` 做统一入口。

典型方法：

```dart
Stream<DownloadProgress> getImage(String url, [Map<String, String>? headers])
```

它返回的是 `Stream<DownloadProgress>`，表示图片下载过程是持续产生进度的。

### CacheManager 为什么单独存在

`CacheManager` 负责缓存文件和缓存数据库。

它要解决：

- URL 到本地缓存文件的映射。
- 缓存过期。
- 缓存大小限制。
- 缓存类型记录。

核心思想：

```text
ImageManager 负责怎么下载。
CacheManager 负责下载后放哪里、什么时候清理。
```

### 为什么缓存要用 SQLite

缓存不只是文件，还需要记录元信息：

- key。
- 目录。
- 文件名。
- 过期时间。
- 文件类型。

这些信息用 SQLite 查找和清理更方便。

### 这样写的好处

- UI 不关心图片来源。
- 图片缓存统一。
- 下载、阅读、缩略图可以复用底层逻辑。
- 特殊源处理集中在底层。

### 新手改动建议

如果图片显示失败：

1. 先看源对应的 `ReadingData.loadImageNetwork`。
2. 再看 `ImageManager` 对应方法。
3. 最后看 `CacheManager` 是否缓存异常。

不要一上来改 UI，因为 UI 可能只是拿不到正确图片流。

## 11. 下载模块

核心文件：

```text
lib/network/download.dart
lib/network/download_model.dart
lib/network/*_network/*download*.dart
lib/pages/download_page.dart
```

### 这个模块负责什么

下载模块负责：

- 下载队列。
- 下载目录。
- 下载进度。
- 下载失败处理。
- 已下载漫画数据库。
- App 重启后恢复未完成下载。
- 不同源的下载模型。

### DownloadManager 为什么是总入口

文件：`lib/network/download.dart`

`DownloadManager` 管理全局下载状态：

```dart
var downloading = Queue<DownloadingItem>();
bool isDownloading = false;
Database? _db;
```

它是一个单例：

```dart
factory DownloadManager() => cache ?? (cache = DownloadManager._create());
```

### 为什么下载需要队列

下载漫画不是一次请求就完成，而是大量图片请求。多个漫画同时下载时，如果不排队，会有问题：

- 并发太高导致封 IP 或 429。
- UI 进度不好管理。
- App 退出后恢复困难。
- 错误重试复杂。

队列可以让下载任务有顺序、有状态。

### 为什么不同源有不同下载模型

不同源图片获取方式不一样：

- Picacg API 返回图片 URL。
- JM 图片可能需要解密/重组。
- nhentai 页面要先解析图片列表。
- EH 有特殊限制。

所以项目用不同下载模型处理源差异，但由 `DownloadManager` 统一管理队列。

### 这样写的好处

- 下载页面只看统一下载状态。
- 下载任务可以恢复。
- 源差异不会污染全局下载管理器。
- 新增源时只需要实现自己的下载 item/model。

### 新手改动建议

如果你想改“下载 UI”，看：

```text
lib/pages/download_page.dart
```

如果你想改“下载逻辑”，看：

```text
lib/network/download.dart
lib/network/对应源_network/下载文件
```

如果你想改“图片怎么保存”，看：

```text
DownloadManager.getImage()
对应 DownloadingItem
```

## 12. 历史记录与本地收藏模块

核心文件：

```text
lib/foundation/history.dart
lib/foundation/local_favorites.dart
lib/pages/history_page.dart
lib/pages/favorites/
```

### 历史记录负责什么

历史记录保存：

- 读过哪本漫画。
- 读到第几章。
- 读到第几页。
- 封面、标题、来源。
- 已读章节。
- 最大页数。

核心模型：

```dart
class History {
  HistoryType type;
  DateTime time;
  String title;
  int ep;
  int page;
  String target;
}
```

### HistoryMixin 为什么存在

很多模型都可以变成历史记录，比如漫画详情、某些网络模型。

`HistoryMixin` 规定最少需要：

```dart
String get title;
String? get subTitle;
String get cover;
String get target;
HistoryType get historyType;
```

这样 `History.fromModel(model: data, ...)` 就能从不同模型创建历史。

### 为什么历史记录要和阅读器联动

阅读器每次切换页/章节后，会更新历史：

```dart
history?.ep = logic.order;
history?.page = logic.index;
HistoryManager().saveReadHistory(history!, updateMePage);
```

这样用户下次打开同一本漫画，可以继续阅读。

### 本地收藏负责什么

本地收藏是 App 自己保存的收藏，不一定依赖网站账号。

它和网络收藏不同：

- 网络收藏在对应网站账号里。
- 本地收藏存在 App 本地数据库/文件中。

这样即使某个源没有收藏 API，也可以本地收藏。

### 这样写的好处

- 历史和收藏不绑定某一个源。
- 离线下载和本地收藏可以互相配合。
- 阅读器、详情页、我的页面可以共享历史数据。

## 13. 分类模块

核心文件：

```text
lib/comic_source/category.dart
lib/pages/category_page.dart
lib/pages/category_comics_page.dart
```

### 这个模块负责什么

分类模块负责两件事：

1. 描述分类页面有哪些标签。
2. 点击标签后加载该分类下的漫画列表。

### CategoryData 的写法

```dart
CategoryData(
  title: "nhentai",
  key: "nhentai",
  categories: [
    FixedCategoryPart("language", [...], "category", [...]),
    RandomCategoryPartWithRuntimeData("Tags", () => nhentaiTags.values, 50, "search"),
  ],
  enableRankingPage: false,
)
```

### FixedCategoryPart 和 RandomCategoryPart 为什么分开

有些分类是固定的，例如 Picacg 分类、JM 分类。

有些分类适合随机展示，例如 nhentai 的大量 tags。

所以项目抽象出：

- `FixedCategoryPart`：固定标签。
- `RandomCategoryPart`：从固定列表随机取。
- `RandomCategoryPartWithRuntimeData`：从运行时数据随机取。

### categoryType 为什么存在

点击标签后的行为不一定一样：

- `category`：进入分类漫画列表。
- `search`：直接当关键词搜索。
- `search_with_namespace`：带命名空间搜索。

所以分类数据里带 `categoryType`，页面根据类型决定跳转方式。

### 这样写的好处

- 分类页 UI 完全通用。
- 每个源只提供数据结构。
- 点击行为也可以声明式控制。
- 随机标签、固定标签共用同一套显示逻辑。

## 14. 搜索模块

核心文件：

```text
lib/pages/pre_search_page.dart
lib/pages/search_result_page.dart
lib/comic_source/comic_source.dart
```

### 这个模块负责什么

搜索模块负责：

- 选择搜索源。
- 输入关键词。
- 搜索建议。
- 搜索选项。
- 语言过滤。
- 显示搜索结果列表。

### SearchPageData 的写法

```dart
SearchPageData.named(
  loadPage: (keyword, page, options) {
    return NhentaiNetwork().search(keyword, page, NhentaiSort.fromValue(options[0]));
  },
  enableLanguageFilter: true,
  enableTagsSuggestions: true,
  searchOptions: [
    SearchOptions(...),
  ],
)
```

### 为什么搜索能力放在 ComicSource

不同源搜索参数完全不同：

- Picacg 有排序参数。
- nhentai 有 tags、language、popular sort。
- JM 有自己的排序方式。

页面只想知道：

```text
关键词是什么？
第几页？
选项是什么？
```

具体怎么拼 URL、怎么传参数，是漫画源自己的事。

### 这样写的好处

- 搜索页可以复用。
- 每个源可以定义自己的搜索选项。
- 某些源可以覆盖搜索结果页。
- 语言过滤可以作为统一增强。

## 15. 详情页模块

核心文件：

```text
lib/pages/comic_page.dart
lib/pages/picacg/comic_page.dart
lib/pages/jm/jm_comic_page.dart
lib/pages/nhentai/comic_page.dart
lib/pages/ehentai/eh_gallery_page.dart
```

### 这个模块负责什么

详情页负责展示：

- 标题。
- 封面。
- 作者/上传者。
- 标签。
- 简介。
- 章节。
- 阅读按钮。
- 下载按钮。
- 收藏按钮。
- 推荐内容。
- 评论入口。

### 为什么有通用详情页和自定义详情页

有些源的数据结构能适配通用详情页：

```dart
_ComicPageImpl
```

但有些源差异很大，需要自定义页面：

```dart
comicPageBuilder: (context, id, cover) => PicacgComicPage(id, cover)
```

这是一种“默认实现 + 特殊覆盖”的设计。

### 这样写的好处

- 普通源不用重复写详情页。
- 特殊源可以完全自定义。
- 页面入口统一是 `ComicPage(sourceKey, id)`。
- 调用方不用关心最终打开的是通用页还是自定义页。

### 新手改动建议

如果你改的是所有详情页共同 UI，看 `lib/pages/comic_page.dart`。

如果你只改 Picacg/JM/nhentai 的详情页，看对应子目录。

## 16. 账号与 Cookie 模块

核心相关文件：

```text
lib/comic_source/comic_source.dart
lib/network/cookie_jar.dart
lib/network/picacg_network/methods.dart
lib/network/nhentai_network/login.dart
lib/network/jm_network/jm_network.dart
```

### 这个模块负责什么

不同源登录方式不同：

- Picacg 使用账号密码换 token。
- nhentai 使用 Web 登录和 Cookie。
- JM 有自己的登录接口和 Cookie。
- EH/EX 也高度依赖 Cookie。

项目用 `AccountConfig` 描述账号能力：

```dart
AccountConfig.named(
  login: ...,
  onLogin: ...,
  logout: ...,
  infoItems: ...,
)
```

### 为什么 login 和 onLogin 都存在

有些源可以用账号密码直接登录：

```dart
login: (account, pwd) async { ... }
```

有些源需要打开网页登录，流程不是简单账号密码：

```dart
onLogin: (context) async { ... }
```

所以两种入口都保留。

### 这样写的好处

- 账号页面可以统一展示源账号。
- 每个源保留自己的登录方式。
- Cookie/token 可以保存在 `ComicSource.data`。
- 退出登录逻辑也由源自己定义。

## 17. 多平台与 Android 打包模块

核心文件：

```text
android/app/build.gradle
android/app/src/main/AndroidManifest.xml
android/app/src/main/kotlin/.../MainActivity.kt
lib/main.dart
lib/foundation/app.dart
```

### 这个模块负责什么

平台层负责：

- Android 包名。
- APK 签名。
- ABI 拆包。
- 权限。
- Deep Link。
- Flutter 与原生 Activity。
- 桌面窗口配置。

### 为什么 Flutter 项目还有 android/ios/windows 目录

Flutter 负责 UI 和业务逻辑，但最终运行在不同平台上。

Android 上需要：

- `AndroidManifest.xml` 声明权限和 Activity。
- `build.gradle` 配置包名、签名、ABI。
- Kotlin/Java 处理平台特定逻辑。

桌面端需要窗口管理，所以 `main.dart` 里有：

```dart
if (App.isDesktop) {
  await windowManager.ensureInitialized();
}
```

### 当前 Clone 版本为什么改 applicationId

你想让自己打包的版本和官方版共存，所以需要不同包名：

```gradle
applicationId "com.github.pacalini.pica_comic.clone"
```

Android 判断“是不是同一个 App”主要看 applicationId。不同 applicationId 就不会覆盖官方版。

### 这样写的好处

- 保留官方版。
- Clone 版本可以独立安装和测试。
- 数据目录也独立，不互相污染。

## 18. 翻译与标签翻译模块

核心文件：

```text
lib/tools/translations.dart
lib/tools/tags_translation.dart
assets/translation.json
assets/tags.json
assets/tags_tw.json
```

### 这个模块负责什么

项目支持中文、繁中、英文显示，还支持漫画标签翻译。

常见写法：

```dart
"搜索".tl
tag.translateTagsToCN
```

### 为什么用扩展方法

`.tl` 看起来像字符串自己的能力，这是 Dart extension 的用法。

好处：

- UI 里翻译写法很短。
- 不用每次写 `translate("xxx")`。
- 文字和翻译调用靠得近，阅读方便。

### 为什么启动时要初始化翻译

翻译数据来自 assets JSON。读取 assets 是异步的，所以 App 启动时必须先初始化：

```dart
await AppTranslation.init();
```

否则 UI 里一调用 `.tl`，就可能出现未初始化错误。

## 19. 日志与错误处理模块

核心文件：

```text
lib/foundation/log.dart
lib/main.dart
lib/network/app_dio.dart
```

### 这个模块负责什么

日志模块负责记录：

- App 初始化状态。
- 未捕获异常。
- Flutter ErrorWidget 异常。
- 网络请求和响应。
- 下载/数据库/IO 错误。

### 为什么要集中写日志

这个项目很多问题发生在用户手机上，不一定能直接 Debug。

日志文件可以帮助排查：

- 哪个 URL 请求失败。
- 服务器返回什么状态码。
- 解析 HTML 时哪里异常。
- SQLite 是否加载失败。
- 初始化卡在哪一步。

你之前排查 `_db has not been initialized`、nhentai 301/308，就用到了日志思路。

### 这样写的好处

- 线上问题可追踪。
- 网络问题有上下文。
- 用户反馈时可以导出日志。

## 20. 代码复用的核心思想总结

这个项目最值得学习的是几组抽象。

### 20.1 ComicSource 隔离漫画源差异

坏写法：

```dart
if (source == "picacg") {
  ...
} else if (source == "jm") {
  ...
} else if (source == "nhentai") {
  ...
}
```

项目写法：

```dart
ComicSource.find(sourceKey)!.searchPageData!.loadPage!(...)
```

好处：

- 页面层不关心具体源。
- 新增源更容易。
- 源之间互不污染。

### 20.2 BaseComic 统一列表项形状

坏写法：

```dart
buildPicacgTile(ComicItemBrief comic)
buildJmTile(JmComicBrief comic)
buildNhentaiTile(NhentaiComicBrief comic)
```

项目写法：

```dart
buildComicTile(context, BaseComic comic, sourceKey)
```

好处：

- 列表网格可以复用。
- 卡片组件可以复用。
- 不同源只要补齐字段。

### 20.3 Res<T> 统一成功/失败

坏写法：

```dart
try {
  var data = await request();
} catch (e) {
  ...
}
```

项目写法：

```dart
var res = await request();
if (res.error) {
  showToast(message: res.errorMessage);
} else {
  use(res.data);
}
```

好处：

- UI 层错误处理统一。
- 网络层可以返回用户可读错误。
- `subData` 可以顺便带分页信息。

### 20.4 ComicsPage 统一列表体验

坏写法：

```text
每个源写一套列表、加载、分页、错误页。
```

项目写法：

```dart
class _CategoryComicsList extends ComicsPage<BaseComic> {
  Future<Res<List<BaseComic>>> getComics(int i) => loader(...);
}
```

好处：

- 分页和跳页逻辑只写一次。
- UI 一致。
- 修 bug 范围集中。

### 20.5 ReadingData 统一阅读器

坏写法：

```text
Picacg 一个阅读器，JM 一个阅读器，nhentai 一个阅读器。
```

项目写法：

```text
一个阅读器 + 多个 ReadingData
```

好处：

- 阅读体验一致。
- 每个源只实现图片加载。
- 下载阅读和在线阅读统一。

## 21. 模块之间的依赖方向

理解依赖方向很重要。比较健康的方向是：

```text
pages/components
    ↓ 依赖
comic_source 抽象
    ↓ 依赖
network/foundation
```

更具体一点：

```text
页面层调用 ComicSource
ComicSource 调用 Network
Network 返回 Res<BaseComic/ComicInfoData>
页面层用 Components 展示
Foundation 提供状态、缓存、历史、图片等基础能力
```

尽量不要反过来：

- Network 不应该主动操作复杂 UI。
- Foundation 不应该依赖某个具体页面。
- 通用组件不应该写太多具体源特殊逻辑。

当然项目里因为历史原因会有一些例外，但你改新功能时应该尽量保持这个方向。

## 22. 新手如何安全改代码

### 改之前先定位是哪类问题

如果是“请求错了、解析错了”：

```text
network/对应源
```

如果是“某个源分类、搜索选项不对”：

```text
comic_source/built_in/对应源.dart
```

如果是“列表交互、分页、跳页、刷新”：

```text
components/comics_list.dart
```

如果是“卡片显示字段不对”：

```text
对应源的 comicTileBuilderOverride
components/comic_tile.dart
```

如果是“详情页显示不对”：

```text
pages/comic_page.dart
pages/对应源/comic_page.dart
```

如果是“阅读器翻页、工具栏、手势”：

```text
pages/reader/
```

### 改通用模块要更谨慎

通用模块包括：

```text
components/
foundation/
comic_source/comic_source.dart
network/res.dart
network/base_comic.dart
```

它们被很多地方使用。改动前最好问：

- 会不会影响所有源？
- 能不能只在某个源里改？
- 是否需要加开关？
- 是否会破坏旧数据？

你最近做跳页按钮时，选择加：

```dart
enableQuickPageJump
```

就是一种比较安全的做法：通用实现，但通过源 key 控制范围。

### 验证建议

小改动：

```powershell
flutter analyze lib/具体文件.dart
```

大改动：

```powershell
flutter analyze
flutter build apk --release --target-platform android-arm64 --split-per-abi
```

安装：

```powershell
adb install -r build/app/outputs/apk/release/PicaComic-Clone-4.2.11-arm64-v8a.apk
```

## 23. 读源码时的思维方式

不要逐行硬啃。建议用“问题驱动”读法。

### 读一个页面时问

- 这个页面显示什么？
- 数据从哪里来？
- 用户点击后去哪？
- 状态保存在哪里？

### 读一个 network 方法时问

- 请求 URL 是怎么拼的？
- Header/Cookie/Token 从哪里来？
- 返回的是 JSON 还是 HTML？
- 解析成了哪个模型？
- 错误怎么包装成 `Res`？

### 读一个组件时问

- 它是通用组件还是业务组件？
- 哪些参数是外部传入的？
- 哪些状态由 Controller 管理？
- 它影响多少页面？

### 读一个抽象类时问

- 它想统一什么？
- 哪些方法是变化点？
- 哪些字段是页面层必须知道的？
- 子类/实现类在哪里？

## 24. 最后用一句话理解每个大模块

- `main/init/base`：负责 App 开机、读设置、准备全局服务。
- `App`：负责平台判断、全局路径、全局导航。
- `ComicSource`：负责把不同漫画源包装成统一能力。
- `built_in`：负责声明每个内置源支持什么功能。
- `pages`：负责页面组织和用户流程。
- `components`：负责可复用 UI，尤其是漫画列表和卡片。
- `network`：负责请求、解析、错误包装和下载模型。
- `StateController`：负责轻量状态管理。
- `reader`：负责统一阅读体验。
- `ImageManager/CacheManager`：负责图片下载、缓存和特殊图片处理。
- `DownloadManager`：负责下载队列、数据库和恢复。
- `HistoryManager`：负责阅读历史和续读。
- `local_favorites`：负责 App 本地收藏。
- `tools`：负责翻译、链接、通知、IO 等工具能力。
- `android`：负责 Android 打包、权限、包名和原生入口。

这个项目代码量不小，但核心思想其实很稳：

```text
用抽象统一上层体验，用具体实现处理底层差异。
```

只要你始终沿着这句话去读代码，就会越来越容易判断“这个功能应该写在哪里”。

