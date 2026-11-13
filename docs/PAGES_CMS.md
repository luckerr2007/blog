# Pages CMS 后台

Pages CMS 是「以 GitHub 仓库为数据库」的可视化编辑后台：仓库根放一个 `.pages.yml` 声明内容模型，网页端编辑后它通过 GitHub API 把改动 commit 回仓库，Cloudflare Pages 检测到 push 自动重建。

- 面板地址：https://app.pagescms.org
- 配置文件：[`.pages.yml`](../.pages.yml)
- 成本：云版免费，无 npm 依赖，不参与构建

## 一、首次接入

1. 打开 https://app.pagescms.org ，用 GitHub 账号登录；
2. 安装 GitHub App → 选择 **Only select repositories** → 勾选 `luckerr2007/blog`（最小权限）；
3. 回到首页点 **Connect existing repository**（不是「从模板创建」，那个会新建一个演示仓库）；
4. 选择仓库 + 分支 `master`；
5. 左侧应出现三个集合：📝 文章 / 💬 动态 / 📄 静态页面。

## 二、日常使用

| 场景 | 操作 |
| --- | --- |
| 写新文章 | 📝 文章 → New → **手填 ASCII 文件名**（如 `my-first-post`）→ 填标题/日期/标签 → 写正文 → Save |
| 改错别字 | 选中文章 → 改正文 → Save（会生成一次 commit） |
| 发草稿 | 勾选「草稿」→ 保存，构建时自动跳过 |
| 发动态 | 💬 动态 → New → 选时间（含时分秒）→ 写内容 |
| 改「关于」 | 📄 静态页面 → about → 编辑正文 |
| 传图片 | 在正文里用媒体库上传，或用「文章配图」媒体源 |

> 保存后不是立刻上线：Pages CMS → commit → Cloudflare Pages 构建（3-5 分钟）。想确认是否生效，去 Cloudflare 的 Deployments 看最新一条。

## 三、字段与 schema 对照

`src/content.config.ts` 是唯一真相源，`.pages.yml` 必须逐字段对齐。

| zod 类型 | Pages CMS 类型 | 备注 |
| --- | --- | --- |
| `z.string()` | `type: string`（长文本用 `text`） | — |
| `z.date()` | `type: date` + `options.time/format` | 文章用 `time: false` + `yyyy-MM-dd`；动态用 `time: true` |
| `z.boolean()` | `type: boolean` + `default` | — |
| `z.number()` | `type: number` | — |
| `z.array(z.string())` | `type: string` + `list: true` | — |

文章集合里声明为 `hidden: true` 的字段：`author`、`lang`、`sourceLink`、`licenseName`、`licenseUrl`、`password`、`passwordHint`、`prevTitle`、`prevSlug`、`nextTitle`、`nextSlug`。它们不会被界面编辑，但保存时会原样保留。

## 四、五个必须记住的坑

1. **正文必须有 `body` 字段**：不声明，保存时正文会被整段丢弃（`merge: false` 下是整文件重写）。
2. **`exclude` 不支持 glob**：写 `exclude: ["images"]`，写 `["**/images/**"]` 永远不生效。
3. **文件名别用 `{primary}`**：slugify 会把中文标题整段剔除，生成 `-.md` 之类的空文件。用 `field: create` 手动填 slug。
4. **日期格式严格解析**：`options.format` 配了 `yyyy-MM-dd HH:mm:ss`，存量只有日期的文章会显示空白。本站统一：文章 `YYYY-MM-DD`、动态 `YYYY-MM-DD HH:mm:ss`。
5. **大目录首次加载可能 500**：GitHub GraphQL 单次返回体积限制导致，刷新即可（之后有缓存）。

## 五、验证与回退

**冒烟测试**：随便改一篇文章的标点 → Save → 等 Pages 构建完成 → 本地 `git pull` → 检查 frontmatter 字段是否完整（重点看 `tags`、`category`、`series`）。

**回退**：直接删掉 `.pages.yml` 并 push，仓库回到无后台状态，其它文件不受影响。

## 六、图片路径说明

| 媒体源 | 仓库目录 | 引用方式 |
| --- | --- | --- |
| `assets` | `public/assets/` | `image: /assets/xxx.webp`（绝对路径，不经过 Astro 优化） |
| `post-images` | `src/content/posts/images/` | `image: ./images/xxx.webp`（相对文章文件，Astro 会优化） |

如果后台把图片传进 `src/content/posts/images/` 后构建报「找不到图片」，改用 `public/assets` + 绝对路径即可（已验证的兜底方案）。
