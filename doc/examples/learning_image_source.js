// 可直接在“添加漫画源”中导入的学习示例。
// 它不访问待适配站点，只返回固定的演示数据；图片使用中性占位图，用来说明接口形状。
// 将来适配获授权、仅含成年人内容的站点时，只替换各个 load 函数中的实现。

class LearningImageSource extends ComicSource {
  name = "图片源学习示例";
  key = "learning_image_source";
  version = "1.0.0";
  // 用于“更新”按钮的地址；此示例不提供远程更新。
  url = "";

  // 首页/发现页：必须返回 { comics: [...], maxPage: number | null }。
  explore = [
    {
      title: "示例首页",
      type: "multiPageComicList",
      async load(page) {
        return {
          comics: [demoComic("demo-home-" + page, "首页演示条目 " + page)],
          maxPage: 1,
        };
      },
    },
  ];

  // 搜索页。searchOptions 是用户在搜索选项中选中的值数组。
  search = {
    optionList: [],
    async load(keyword, searchOptions, page) {
      return {
        comics: [demoComic("search-" + keyword, "搜索结果：" + keyword)],
        maxPage: 1,
      };
    },
  };

  comic = {
    // 详情页：没有章节时让 chapters 为 null。
    async loadInfo(id) {
      return {
        title: "演示图片集：" + id,
        subTitle: "学习用数据",
        cover: demoCover(),
        description: "这是一个离线学习源。详情页返回图片集元数据，阅读器从 loadEp 获取图片 URL。",
        tags: { "类型": ["示例", "无章节"] },
        chapters: null,
        recommend: [],
      };
    },

    // 无章节时 ep 为 null；必须返回 { images: [url, ...] }。
    async loadEp(id, ep) {
      return {
        images: [demoCover(), demoCover("演示图片 2")],
      };
    },
  };

  init() {
    console.log("LearningImageSource initialized");
  }
}

function demoComic(id, title) {
  return {
    id: id,
    title: title,
    subTitle: "学习示例",
    cover: demoCover(),
    tags: ["示例"],
    description: "固定返回的数据，仅用于验证 ComicSource 接口。",
  };
}

// 使用中性的占位图服务，确保示例图片也能走应用的正常网络加载链路。
function demoCover(label = "演示图片") {
  return "https://placehold.co/720x1024/png?text=" + encodeURIComponent(label);
}
