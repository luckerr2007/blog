# 二次开发改动清单

记录相对 Firefly v6.16.9 的所有改动，方便日后升级模板时对照合并。

## 一、新增文件

| 文件 | 作用 |
| --- | --- |
| `command` | 一键启停脚本（start / stop / restart / status / logs / build / preview / install） |
| `.nvmrc` | 固定 Node 22 |
| `.pages.yml` | Pages CMS 内容模型 |
| `public/_headers` | Cloudflare Pages 响应头（替代 `vercel.json`） |
| `PRD.md` | 项目需求文档 |
| `docs/WRITING.md` | 写作规范 |
| `docs/OPERATIONS.md` | 运维手册（启停/构建/部署/回滚） |
| `docs/PAGES_CMS.md` | 后台使用与字段对照 |
| `docs/CUSTOMIZATION.md` | 本文件 |

## 二、配置改动（`src/config/`）

### siteConfig.ts
- `title` → 桃苏的博客；`subtitle` → 记录技术、生活与思考
- `site_url` → `https://www.taosu.dpdns.org`
- `description` / `keywords` → 个人站表述
- `navbar.title` → 桃苏的博客；`navbar.logo` 改为图标 `fa7-solid:seedling`（不再依赖模板的 firefly-*.png）
- `siteStartDate` → `2022-08-14`
- `pages`：`friends` / `guestbook` / `projects` / `gallery` / `booknav` / `sponsor` 全部 `false`，仅 `dynamic` 保留

### profileConfig.ts
- `name` → 桃苏；`bio` → 记录技术、生活与思考。
- GitHub 链接改为 `github.com/luckerr2007`；删除模板示例邮箱

### navBarConfig.ts
- 导航精简为：主页 / 文章（归档·分类·标签）/ 关于 / 链接（GitHub、Firefly 主题）
- 移除「社交」「我的」两个空子菜单

### musicConfig.ts
- `showInNavbar` / `showInSidebar` → `false`（模板无总开关，只能关这两个入口）
- `local.playlist` → `[]`，并删除 `public/assets/music/` 里的示例音频（省 1MB）

### pioConfig.ts
- 未改动：`spineModelConfig.enable` 与 `live2dWidgetConfig.enable` 模板默认已是 `false`，保持关闭

### commentConfig.ts
- 未改动：模板默认 `type: "none"`。评论暂停即维持该值，留言板页面同步关闭

### fontConfig.ts
- **Inter / JetBrains Mono**：`provider` 由 `fontsource` 改为 `google`
  - 原因：本机访问 `cdn.jsdelivr.net` 超时，`pnpm dev` 与 `pnpm build` 直接失败（`CannotFetchFontFile`）
  - 注意：Astro Fonts API 是构建期下载 + 自托管输出，访客不依赖 Google 的可用性
- 删除 `Zen Maru Gothic`（仅 demo 用），`bannerTitleFont` 置空回落系统字体
- 本地字体示例 `GreatVibes` 保留（文件在 `public/assets/fonts/`）

### FooterConfig.html
- 版权行 + Powered by Astro & Firefly + 备案占位

## 三、内容改动

| 变更 | 说明 |
| --- | --- |
| 模板示例内容归档 | `src/content/posts`、`dynamic`、`projects` → `src/content/_archive/`，不参与构建 |
| 新文章 | `src/content/posts/guide/how-this-blog-was-built.md` |
| 旧文补档 | `src/content/posts/misc/` 下的 2022–2026 年文章，用于补全归档时间线 |
| 新动态 | `src/content/dynamic/2026-11-13-213000.md` |
| 关于页 | `src/content/spec/about.md` 重写为桃苏版本 |
| 项目占位 | `src/content/projects/taosu-blog.md`（项目页关闭，仅消除 glob loader 空目录告警） |
| 静态页归档 | `friends.mdx`、`guestbook.md` → `_archive/spec/` |

## 四、未改动但需知道的点

- `astro.config.mjs`：未改。`base: "/"` 直接适配 Cloudflare Pages 根路径；`adapter` 仅在 `CF_WORKERS` 存在时启用
- `.github/workflows/deploy.yml`：保留（当前不用 GitHub Pages，留着做构建体检；确认不需要后可删）
- `vercel.json`：保留但 Cloudflare Pages 不读取，实际生效的是 `public/_headers`
- `wrangler.jsonc`：保留（仅在使用 Workers 适配器时才相关）
- `CLAUDE.md` / `AGENTS.md`：上游的 AI 协作说明，可按需删除
- `.pages.yml` 的 `tags.values` 必须覆盖文章实际使用的全部标签（含 MVSEP、网易云、LEMOM、MIDI、MusicParser 等），否则 Pages CMS 保存时会丢掉未列出的标签

## 五、升级模板时的建议流程

```bash
git remote add upstream https://github.com/CuteLeaf/Firefly.git
git fetch upstream master
git checkout -b upgrade/firefly-<version>
git merge upstream/master --no-commit     # 逐文件解决冲突
# 重点冲突区：src/config/*、src/content/*、package.json
pnpm install && pnpm check && ./command build
```

升级后必须复查：字体 provider 是否被改回 `fontsource`、`pages` 开关是否被重置、`.pages.yml` 字段是否与新的 zod schema 对齐。

## 六、首页视觉与每日一言（v1.4）

### 关闭壁纸背景
- `backgroundWallpaper.ts`：`mode: "none"`、`playerEnable: false`、`src.desktop` / `src.mobile` → `[]`，水波纹与渐变（桌面 / 移动）全部 `false`
- `displaySettingsConfig.ts` 未改：面板总开关本就 `false`，运行时不会切回壁纸模式
- 壁纸图片仍留在 `src/assets/images/{Desktop,Mobile}Wallpaper/`，因为没有任何组件引用，不参与构建；想恢复时把路径填回 `src` 并把 `mode` 改回 `banner`

### 每日一言（新增）

| 文件 | 作用 |
| --- | --- |
| `src/types/hitokotoConfig.ts` | 配置类型（接口列表、超时、轮换区间、兜底句子） |
| `src/config/hitokotoConfig.ts` | 一言接口与兜底文案（默认分类 i 诗词 / k 哲学，轮换 1–6 小时） |
| `src/utils/hitokoto-client.ts` | 浏览器端取数：localStorage 缓存（每条随机 1–6h 到期）→ 依次请求接口 → 本地兜底 |
| `src/components/common/HitokotoQuote.astro` | 展示组件（`hero` / `widget` 两种变体），定时自动轮换，无手动按钮 |
| `src/components/widget/Hitokoto.astro` | 侧边栏小组件 |
| `src/components/layout/HomeHero.astro` | 首页顶部欢迎区（站点标题 + 打字机副标题 + 每日一言） |

- 新增组件类型 `hitokoto`：`src/types/sidebarConfig.ts` 的 `WidgetComponentType`、`src/components/layout/SideBar.astro` 的 `componentMap`
- `sidebarConfig.ts`：移除 `music` 组件，左栏与移动端底部各新增 `hitokoto`
- `src/pages/[...page].astro`：仅第 1 页渲染 `<HomeHero />`
- 轮换逻辑：每条句子写入时随机取 1–6 小时 TTL；页面常开用定时器到点换，切回前台若已过期立即换；Swup 换页后从缓存补同一句
- 请求带时间戳参数绕开一言 CDN 的 URL 缓存，保证每次轮换都真的换
- SSR 先输出按日期轮换的兜底句子，接口失败或断网时页面保持可读

### 文案清理
- `announcementConfig.ts`：示例公告 → 本站说明
- `backgroundWallpaper.ts` 的 `homeText`：模板英文诗句 → 中文副标题
- `siteConfig.ts`：bilibili / bangumi / vndb / mal 的 ID 与 Client ID 清空（对应页面本就关闭）
- `commentConfig.ts`：Giscus 仓库与分类 ID 清空（`type: "none"`）
- `friendsConfig.ts` / `galleryConfig.ts` / `sponsorConfig.ts` / `booknavConfig.ts`：删除 CuteLeaf 演示友链、相册、打赏方式与书签，保留字段格式注释

## 七、灰阶视觉复刻（v1.5）

参考 blog.toubiec.cn 的设计令牌，把主题从「绿色系 + 大圆角」改成「纯灰阶 + 小圆角 + mono 小标题」。只覆盖变量与装饰，不改布局与组件结构。

| 文件 | 说明 |
| --- | --- |
| `src/styles/theme-monochrome.css` | 新增。灰阶令牌（`--c-*`）、覆盖 Firefly 主题变量、圆角收紧到 8px、1px 边框卡片 + 悬浮位移、毛玻璃顶栏、mono 元信息、暗色反色修正 |
| `src/components/layout/ScrollProgress.astro` | 新增。顶部 2px 阅读进度条（rAF 节流，尊重 `prefers-reduced-motion`） |
| `src/components/layout/HomeHero.astro` | 重写为 editorial hero：状态点 + mono 问候语、大字标题（字距 -0.03em + 12% 前景色高亮条）、打字机副标题、每日一言 |
| `src/components/common/HitokotoQuote.astro` | hero 变体改为左对齐、出处用 mono |
| `src/layouts/Layout.astro` | 在 `variables.styl` 之后引入覆盖样式；body 内挂载 `<ScrollProgress />` |

要点：

- 强调色 `--primary` 取前景色，所有用 `bg-(--primary)` 的组件自动黑白反色；暗色下分类胶囊原本写死 `color: white`，已改成 `var(--c-bg)`
- 想换回彩色主题：删掉 `Layout.astro` 里的 `theme-monochrome.css` 引入即可，`variables.styl` 未被修改

### Apple HIG 叠加（v1.6）

| 项 | 做法 |
| --- | --- |
| 颜色 | 改用 Apple 语义色：明 `systemGroupedBackground #f2f2f7` + 卡片 `#ffffff`；暗 `#000000` + 卡片 `#1c1c1e`；label / separator 用带透明度的系统值 |
| 圆角 | Apple 尺度：控件 8–10px、卡片 12px、弹层 16–22px |
| Continuous corner | `@supports (corner-shape: squircle)` 时对卡片/按钮/胶囊/输入框启用 squircle（Chrome 139+），否则优雅退回普通圆角 |
| 材质 | 顶栏 `blur(20px) + 72% 卡片色`；`prefers-reduced-transparency` 时退化为不透明 |
| 动效 | 统一 `cubic-bezier(0.32, 0.72, 0, 1)`；按钮按压 `scale(0.96)`；`prefers-reduced-motion` 全关 |
| 命中区 | 触屏设备上导航按钮用伪元素把热区扩到 ≥44px（视觉尺寸不变） |
| 无障碍 | `prefers-contrast: more` 时加粗分隔线、次级文字提为正文色 |

同时移除了导航栏「链接 → GitHub」分组（`navBarConfig.ts`），页脚与侧栏资料卡里的 GitHub 入口保留。

## 八、动效层（v1.7）

新增 `src/styles/theme-motion.css`，把全站动画收敛成一套 token，参照 Material 3 / Apple HIG / Fluent 2 的时长与缓动约定。

| 项 | 值 |
| --- | --- |
| 时长 | `--dur-1` 100ms（按压）、`--dur-2` 150ms（微交互）、`--dur-3` 180ms（常规）、`--dur-4` 260ms（入场）、`--dur-5` 420ms（主题揭示） |
| 缓动 | `--ease-standard` (.2,0,0,1)、`--ease-decelerate` (.05,.7,.1,1)、`--ease-accelerate` (.3,0,.8,.15)、`--ease-spring` (.32,.72,0,1) |
| 位移 | 换页/入场统一 8px，出场 6px（原来 32px 偏大） |
| 换页 | 入场 180ms 标准曲线，离场 150ms 加速曲线 |
| 入场 | `.onload-animation` 260ms 减速曲线，延迟 30ms 递增、第 6 个后封顶；主内容包装层 180ms |
| 按压 | 按钮 `scale(0.97)` + 100ms，触屏不做 hover 位移 |
| 主题切换 | `runThemeTransition()` 用 View Transition 做圆形揭示（420ms spring），从触发元素扩散；不支持或 `prefers-reduced-motion` 时直接切换 |
| 进度条 | 切页进度条与顶部阅读条统一 2px、去掉发光 |
| 浮动面板 | `[data-floating-panel]` 开合统一 150ms（透明度 + `translate`），搜索/主题/显示设置/音乐面板不再硬切 |
| 骨架屏 | 全局 `.skeleton`（1.4s shimmer）供侧栏、动态流、搜索页、媒体网格共用；减弱动效时静态 |
| 列表筛选 | `.animate-fade-in-up`（180ms 上浮 4px）用于 gallery / friends / booknav 的筛选重排 |

细节取舍：

- 首屏 hero 不再单独淡入（主内容包装层已经淡入一次），避免 LCP 被两层动画推迟
- 文章卡的布局切换仍用 PostPage 的 400ms，但 hover 位移单独收回到 180ms，避免「发木」
- 只动 `transform` / `opacity`，不触发布局；焦点环不加过渡，保证键盘操作即时反馈
- Tailwind v4 的 `-translate-y-1` 落在独立的 `translate` 属性上，面板过渡必须写 `translate` 而不是 `transform`
- `prefers-reduced-motion: reduce` 时全站动画时长压到 0.01ms（含 View Transition），骨架屏直接静止
