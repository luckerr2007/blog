# Pages CMS 后台

Pages CMS 以 GitHub 仓库为数据库：仓库根放一个 `.pages.yml` 声明内容模型，网页端 / 手机端编辑后它通过 GitHub API 把改动 commit 回仓库，Cloudflare 检测到 push 自动重建。CMS 本身不参与构建。

- 面板：https://app.pagescms.org
- 配置：[`.pages.yml`](../.pages.yml)（当前对齐 **Pages CMS 2.x** 规范）

## 一、首次接入（必须你在浏览器里操作）

1. 打开 https://app.pagescms.org ，用 GitHub 账号登录；
2. 安装 GitHub App：**Only select repositories** → 只勾 `luckerr2007/blog`（最小权限）；
3. 点 **Connect existing repository**（**不要**点「从模板创建」，那会新建一个演示仓库）；
4. 选择仓库 + 分支 `master`；
5. 左侧应出现三个集合：**📝 文章 / 💬 动态 / 📄 静态页面**，外加一个媒体库。

> 接入后改动会直接 commit 到 `master` 并触发 Cloudflare 重建，所以第一次保存建议先改一个不重要的标点做冒烟测试。

## 二、日常使用

| 场景 | 操作 |
| --- | --- |
| 写新文章 | 📝 文章 → New → **手填 ASCII 文件名**（如 `my-first-post`）→ 填标题/日期 → 写正文 → Save |
| 改错别字 | 选中文章 → 改正文 → Save（生成一次 commit） |
| 发草稿 | 勾「草稿」，构建时自动跳过 |
| 发动态 | 💬 动态 → New → 选时间（含时分秒）→ 写内容 |
| 改「关于」 | 📄 静态页面 → about |
| 传图片 | 媒体库上传 → 得到 `/assets/xxx.webp` → 填到「封面图」或在正文里引用 |

## 三、字段与 schema 对照

`src/content.config.ts` 是唯一真相源。当前文章的 24 个 zod 字段全部在 `.pages.yml` 中有对应声明：可编辑 12 个，其余 11 个声明为 `hidden: true`（`author`/`lang`/`sourceLink`/`licenseName`/`licenseUrl`/`password`/`passwordHint`/`prevTitle`/`prevSlug`/`nextTitle`/`nextSlug`），保存时原样保留。

| zod 类型 | Pages CMS 2.x 写法 |
| --- | --- |
| `z.string()` | `type: string`（长文本用 `text`） |
| `z.date()` | `type: date` + `options.time` / `options.format`（date-fns token） |
| `z.boolean()` | `type: boolean` + `default` |
| `z.number()` | `type: number` |
| `z.array(z.string())` | **只能** `type: select` + `options.multiple: true` + `options.values` |

## 四、六个必踩的坑

1. **2.x 没有 `list: true`**：字符串数组（`tags`）只能做 `select` 多选，选项必须在 `values` 里预定义。想加新标签 → 编辑 `.pages.yml` 的 `values` 再加一项。
2. **正文必须声明 `body`**：`body` 是特殊键，映射 frontmatter 之下的正文；漏了它，保存时正文会被整段丢弃（`merge: false` 是整文件重写）。
3. **`view.sort` 是「可排序字段列表」**，不是 `"published desc"` 这种字符串；方向写在 `view.default.order`。
4. **日期格式严格**：`options.format` 写 `yyyy-MM-dd`，存量文章只有日期就不要再配时分秒；动态页用 `yyyy-MM-dd HH:mm:ss`。
5. **`exclude` 只支持精确名**：写 `["images"]`，写 `["**/images/**"]` 永远不生效。
6. **文件名别用标题生成**：slugify 会把中文整段剔除，所以配置了 `filename.field: create`，新建时必须自己填 ASCII slug。

## 五、图片

| 项 | 值 |
| --- | --- |
| 存储目录 | `public/assets/` |
| 公网路径 | `/assets/...` |
| 上传重命名 | `safe`（自动 slugify，避免中文文件名） |

媒体库是**单一来源**（`media` 写成单个对象），正文里插入图片后记得用 `/assets/xxx.webp` 这种绝对路径；`image` 字段直接填同一个路径即可。

## 六、验证与回退

**冒烟测试**：改一篇文章的标点 → Save → Carbon/Cloudflare 构建完成 → 本地 `git pull` → 核对 frontmatter（重点看 `tags`、`category`、`series`、`updated` 是否还在）。

**回退**：删掉 `.pages.yml` 并 push，仓库即可回到无后台状态，其它文件不受影响。

## 七、常见现象

| 现象 | 处理 |
| --- | --- |
| 集合列表首次加载报 500 | GitHub GraphQL 单次返回体积限制，刷新即可（之后有缓存） |
| 保存后构建失败：`tags` 类型错误 | 说明该文章 `tags` 被写成了字符串，检查是否手工改过 frontmatter |
| 后台看不到某篇文章 | 文章被 `exclude` 或位于未声明的目录（`src/content/posts` 之外） |
