---
title: 把 Firefly 改成自己的样子：二次开发、发文与部署
published: 2026-11-14
description: 从配置、覆盖样式到改上游组件，记录本站的二次开发分层、每日一言与动效的落地过程，以及发文、构建、Cloudflare Workers 部署和回滚里真正会踩的坑。
tags: [Astro, Firefly, Cloudflare Workers, 建站]
category: 博客指南
comment: false
---

第一篇文章写的是从零把站搭起来。真正每天打交道的其实是后面这些：改一行配置、加一个组件、把绿色主题换成灰阶、写完文章再推上去。

我不是先画好架构图再动手的人。实际顺序是：先换文案，再改视觉，最后才把动效抽成 token。中间返工过几次，也踩过「本地好好的，构建后组件不 hydrate」这种坑。这篇把这些过程拆开写，重点放在**怎么改原版主题还不把升级路堵死**，以及发文和部署时哪些地方最容易翻车。

搭建过程见[《这个博客是怎么搭建起来的》](/posts/guide/how-this-blog-was-built/)。

## 一、改造之前，先给自己留条后路

Firefly 是会持续更新的模板。如果上来就把几十个上游文件改得面目全非，下一次升级只能整站重来。

我给自己定的规矩很土：**能新增就不覆盖，能覆盖就不改上游，非改不可就把 diff 压到最小**。每改一处，顺手记进仓库的 `docs/CUSTOMIZATION.md`，写清楚改了哪个文件、为什么改、升级时要注意什么。这个文件后来成了升级时最有用的一张地图。

动手前先留基线：

```bash
git tag baseline-firefly-6.16.9   # 或者记下上游对应 commit
git remote add upstream https://github.com/CuteLeaf/Firefly.git
git fetch upstream master
```

之后任何时候都能用 `git log --oneline upstream/master..master` 看自己到底偏离原版多少，用 `git diff --stat upstream/master` 看改动集中在哪些目录。偏离越小，升级越轻松。

还有一步是清理模板内容：把示例文章、动态、项目挪到 `src/content/_archive/`。它们不参与构建，但留在原目录会混进首页、归档和 Pagefind 索引，搜索时很出戏。

## 二、改造分四层，按侵入性从低到高

### 1. 配置层：先榨干模板自带的开关

Firefly 的配置覆盖得很全：站点信息、导航、侧栏、壁纸、字体、评论、音乐、看板娘，基本都在 `src/config/*Config.ts`，类型在 `src/types/`，统一从 `@/config` 导入。

本站这一层做的事情包括：

- `siteConfig.ts`：标题、副标题、`site_url`、描述、关键词、`siteStartDate`，以及页面的开关；
- `profileConfig.ts`：名字、简介、头像、GitHub 链接；
- `navBarConfig.ts`：导航精简成「主页 / 文章 / 关于」，去掉模板里的社交空菜单；
- `backgroundWallpaper.ts`：`mode: "none"`，关掉壁纸、播放器和水波纹；
- `musicConfig.ts`：模板没有总开关，只能把 `showInNavbar` 和 `showInSidebar` 都设为 `false`，再把示例播放列表清空；
- `fontConfig.ts`：把字体 provider 从 `fontsource` 改成 `google`。

最后一条是被逼的。某天 `pnpm dev` 和 `pnpm build` 一起报 `CannotFetchFontFile`，原因是本机访问 `cdn.jsdelivr.net` 超时。Astro Fonts API 是构建期下载、自托管输出，换 provider 只影响构建机，访客不会因此依赖 Google。这种改动要写进清单，升级时很容易被上游改回去。

配置改完跑 `pnpm type-check`。字段拼错、类型不匹配会直接报出来，比在浏览器里瞎找快得多。

### 2. 覆盖样式层：能靠变量解决就别动组件

视觉改造集中在两个新文件：

- `src/styles/theme-monochrome.css`：灰阶令牌、圆角、边框、毛玻璃、mono 元信息，以及后来按 Apple HIG 调的语义色和命中区；
- `src/styles/theme-motion.css`：时长、缓动、入场、换页、面板、骨架屏这些动效规则。

它们都在 `Layout.astro` 里、`variables.styl` 之后引入。上游的变量文件一行没改，想回到彩色主题，把 `theme-monochrome.css` 的 import 删掉就行。

覆盖层里有个细节：把 `--primary` 直接指向前景色，所有用 `bg-(--primary)` 的组件会自动变成黑白反色，不需要挨个改组件。

```css
:root {
	--c-bg: #f2f2f7;
	--c-card: #ffffff;
	--c-fg: #1c1c1e;
	--primary: var(--c-fg);
	--page-bg: var(--c-bg);
}
```

暗色块里把 `--c-bg` 换成纯黑、`--c-card` 换成 `#1c1c1e`，再补一套 label / separator 的透明度。但暗色下有些地方写死了 `color: white`，比如分类胶囊，得单独改成 `var(--c-bg)`，否则黑底黑字。

后来加 Apple HIG 那版时，又补了按钮命中区、`prefers-contrast`、`prefers-reduced-transparency`。这些都塞在覆盖层里，没有碰上游组件的结构。

动效层还有两个和 Tailwind 4 有关的细节。`-translate-y-1` 这类工具类落在独立的 `translate` 属性上，过渡写 `transform` 不会生效，必须写 `translate`；另外所有动画只改 `transform` / `opacity`，并在 `prefers-reduced-motion` 下关掉，骨架屏也要能静止，不然「减少动态效果」就形同虚设。

### 3. 新增组件层：只在上游留一个挂载点

首页 hero、顶部阅读进度条、每日一言，都是新增文件：

| 文件 | 作用 |
| --- | --- |
| `src/components/layout/HomeHero.astro` | 首页欢迎区：状态点、mono 问候语、大字标题、打字机副标题 |
| `src/components/layout/ScrollProgress.astro` | 顶部 2px 阅读进度条，rAF 节流 |
| `src/types/hitokotoConfig.ts` | 每日一言的配置类型 |
| `src/config/hitokotoConfig.ts` | 接口列表、超时、轮换区间、兜底句子 |
| `src/utils/hitokoto-client.ts` | 浏览器端取数、localStorage 缓存、接口失败回退 |
| `src/components/common/HitokotoQuote.astro` | 展示组件，`hero` / `widget` 两种变体 |
| `src/components/widget/Hitokoto.astro` | 侧边栏小组件 |

接入上游的地方只有三处：`Layout.astro` 挂 `<ScrollProgress />`，`src/pages/[...page].astro` 只在第 1 页渲染 `<HomeHero />`，侧栏则要在 `src/types/sidebarConfig.ts` 的 `WidgetComponentType` 和 `src/components/layout/SideBar.astro` 的 `componentMap` 里登记新类型。

每日一言踩过两个坑：

1. 一言接口前面有 CDN 缓存，不加时间戳参数会一直返回同一句。请求 URL 上带 `?t=...` 才真的换。
2. 首页和侧栏可能同时存在，不能各请求各的。现在共享同一个 pending promise，SSR 先输出按日期轮换的兜底句子，接口挂了页面也不会空。

缓存策略是每条句子写入时随机取 1–6 小时 TTL。页面一直开着就到点换，切回前台发现过期也立刻换；Swup 切页后先读缓存补同一句，避免刚换完又跳一下。

### 4. 改上游组件层：把每一处修改都当成债

有些事确实只能在原组件上改。本站动过的上游文件大致是这些：

- `src/layouts/Layout.astro`：引入两个覆盖样式、挂进度条；
- `src/components/layout/HomeHero.astro`：整体重写成 editorial 风格；
- `src/components/controls/LightDarkSwitch.svelte`：接 View Transition 圆形揭示；
- `src/components/widget/DynamicSidebar.svelte`、`Dynamic.astro`：骨架屏与 `client:idle`；
- `src/components/pages/dynamic/DynamicFeed.svelte`：动态流骨架屏；
- `src/components/common/GridSkeleton.svelte`：媒体网格骨架换成统一 shimmer；
- `src/components/pages/AdvancedSearch.svelte`、`controls/Search.svelte`：搜索加载态与面板过渡；
- `src/components/layout/PostPage.astro`、`NavMenuPanel.astro`：零散的过渡与布局修正。

改的时候尽量守住两条：只改必要行，不整文件格式化；在关键位置留一行注释说明为什么和上游不一样。否则下次 `git merge upstream/master` 会给你一堆无意义的冲突。

这一层也踩过最诡异的一个 bug：动态侧栏用 `client:visible`，宿主元素高度是 0，IntersectionObserver 永远不触发，组件一直停在加载态。改成 `client:idle` 才正常：

```diff
-<DynamicSidebar client:visible apiUrl={apiUrl} limit={limit} {memos} />
+<DynamicSidebar client:idle apiUrl={apiUrl} limit={limit} {memos} />
```

后来干脆把转圈换成骨架，加载中至少不会看起来像卡死。这类「组件不报错但永远不初始化」的问题，先查宿主尺寸和 `client:*` 指令，比在组件内部打日志快。

### 5. 常见需求对照

改的时候先在这张表里找，能省掉翻组件的时间：

| 想改 | 去哪里 |
| --- | --- |
| 站点标题、描述、域名、时区 | `src/config/siteConfig.ts` |
| 导航项、子菜单 | `src/config/navBarConfig.ts`，注意 `pageKey` 与页面开关联动 |
| 头像、昵称、简介、社交链接 | `src/config/profileConfig.ts` |
| 页脚版权与备案 | `src/config/FooterConfig.html` |
| favicon | `public/favicon/` + `siteConfig.favicon` |
| 主题色相 | `siteConfig.themeColor.hue`；要彻底灰阶就改覆盖层 |
| 字体 | `src/config/fontConfig.ts`，离线环境注意 provider |
| 文章列表布局 | `siteConfig.postListLayout`（列表/网格、封面位置、摘要行数） |
| 侧栏放什么 | `src/config/sidebarConfig.ts`，新增组件还要登记类型和 `componentMap` |
| 页面开关 | `siteConfig.pages`，关掉后导航项也会隐藏 |
| 评论 | `src/config/commentConfig.ts` |
| 壁纸与首页文字 | `src/config/backgroundWallpaper.ts` |

## 三、升级上游：把冲突当成一次 code review

升级流程不复杂，麻烦的是冲突里的取舍：

```bash
git fetch upstream
git checkout -b upgrade/firefly-<version>
git merge upstream/master --no-commit
```

冲突基本集中在三个地方：`src/config/*`、`src/content/*`、`package.json`。我的处理顺序是：

1. 配置冲突先看上游是不是新增了字段。新增的保留，自己改过的值继续用；
2. 内容冲突直接保留本地，模板示例内容早就归档到 `src/content/_archive/`；
3. `package.json` 只接受依赖版本，脚本和 `packageManager` 以本地为准；
4. 样式和组件冲突逐个看 diff，确认覆盖层还在、类名没被上游改掉。

合并完必须复查几件事：字体 provider 有没有被改回 `fontsource`、`siteConfig.pages` 的开关有没有被重置、`.pages.yml` 的字段和新版 zod schema 对不对得上。然后 `pnpm install && pnpm check && pnpm build`，最后把这次升级的处理记进 `docs/CUSTOMIZATION.md`。

升级本身不可怕，可怕的是改完没记录，三个月后自己都不知道为什么这里和上游不一样。

## 四、发文：文件路径就是 URL

新建文章：

```bash
pnpm new-post guide/modify-and-deploy-the-blog
```

参数既是目录也是文件名，**用 ASCII**。脚本会把中文标题转成拼音写进 frontmatter 的 `slug`，但当前内容 schema 不读取这个字段，路由实际取的是文件路径（`entry.id`）。传中文路径，URL 就会是中文，分享和 RSS 都别扭。

生成后至少改这几项：

```yaml
---
title: 把 Firefly 改成自己的样子：二次开发、发文与部署
published: 2026-11-14
description: 60–120 字摘要，列表和 SEO 都会用
tags: [Astro, Firefly, Cloudflare Workers]
category: 博客指南
draft: false
---
```

几个容易写错的字段：

- `published` / `updated` 写 `YYYY-MM-DD`，不要带时分秒；
- `draft: true` 只在生产构建里隐藏，`pnpm dev` 仍然能看到，别把「本地有」当成「线上有」；
- `prevTitle` / `prevSlug` / `nextTitle` / `nextSlug` 是主题内部字段，不要手写；
- `category` 决定分类页聚合，目录只决定 URL，两者可以不同，但混用会让归档看起来别扭；
- 改文件名等于改 URL，旧链接、RSS、外部引用都会断。必须改时去 `public/_redirects` 补 301。

图片放在 `src/content/posts/images/<slug>/`，正文用相对路径：

```markdown
![](./images/modify-and-deploy-the-blog/step-1.webp)
```

优先 WebP/AVIF，单张压到 300KB 以内。构建期会给本地图片生成 LQIP 占位，但原图太大，压缩不会自动救回来。

不想开本地环境时，也可以用 Pages CMS 写。它把 GitHub 仓库当数据库，`.pages.yml` 声明内容模型，网页端保存后直接 commit 到 master，后面的构建和部署与本地 push 完全一样。有两个限制：文件名必须手填 ASCII slug，后台的 slugify 会把中文整段删掉；`.pages.yml` 的字段要和 `src/content.config.ts` 的 schema 对得上，否则保存成功、构建失败。

改过内容模型之后，先拿一篇文章改个标点做冒烟测试，确认 frontmatter 里的 `tags`、`category`、`series`、`updated` 都没被吞。CMS 和本地同时改同一篇也容易冲突，动笔前先 `git pull`。

## 五、本地能跑，和线上能跑，是两件事

我习惯分三层验证，各查各的：

| 命令 | 能发现什么 | 发现不了什么 |
| --- | --- | --- |
| `pnpm dev` | 交互、布局、控制台报错 | 构建期生成物、Pagefind、压缩后的行为 |
| `pnpm check` + `pnpm type-check` | Astro/Svelte 模板诊断、TS 类型 | CSS、运行时逻辑、内容渲染结果 |
| `pnpm build` | frontmatter schema、MDX、CSS 导入、生成资产 | 线上缓存、域名与 DNS |

只跑 dev 最容易漏的是 **frontmatter 不合法**和**构建期资源缺失**。文章在 dev 里能打开，不代表 `astro build` 能过。

`./command` 是改造初期写的，原因是每天都要起服务、找进程、看日志，太烦。它做的不只是包一层 `pnpm dev`：健康检查会轮询首页直到返回 200（首次启动要下载字体，实测接近一分钟），pid 和日志写进 `.run/`，`start` 用 `mkdir` 做原子锁防止双击起两个进程。

这里也踩过一个自己挖的坑：最早 `restart` 直接写成 `stop; start`，stop 拿到锁还没释放，start 立刻报「另一个 command 进程正在运行」。后来在两步之间显式释放锁才修好。脚本看起来简单，状态管理一样会咬人。

dev 还有几个天然盲区：

- 搜索是假的。Pagefind 只在构建时生成索引，`Search.svelte` 在开发环境用的是写死的 mock，搜不到东西很正常；
- 新增本地图片不会立刻有 LQIP，要重新构建才会写进 `src/constants/lqips.json`；
- 改过依赖之后，Vite 的模块图可能坏掉。我就遇到过动态页一直停在骨架、控制台报 `Failed to fetch dynamically imported module`，重启 dev server 才恢复。这种时候别怀疑组件，先 `./command restart`；
- 手动 `pnpm dev` 在部分环境只绑 IPv6 回环，`127.0.0.1` 打不开。`./command start` 会显式传 `--host 127.0.0.1`，省得排查半天。

## 六、构建链里那些看不见的步骤

本站的 `pnpm build` 不是单纯的 `astro build`：

```text
GitHub 卡片数据 → LQIP → VNDB 封面 → astro build
→ 清理 PIO 资源 → 字体子集化 → 内联脚本压缩 → Pagefind 索引
```

本地完整跑一次大约 100 秒。几个副作用要心里有数：

- `src/constants/lqips.json`、`src/constants/github-card-data.json` 是受版本控制的生成文件，构建可能改动它们。提交前看 diff，不要无脑 `git add -A`；
- 构建期的字体子集化会打不少日志，属于正常输出，不要看到 warning 就以为构建坏了；
- Pagefind 的日志会告诉你索引了多少页、多少词。这次加文章后从 2 页涨到 3 页、1290 词，能直观看出构建有没有把新文章吃进去；
- `dist/`、`.run/`、`.astro/` 都已忽略，不要提交。

## 七、部署：push master 之后发生了什么

当前链路是 GitHub Actions 构建后交给 Wrangler：

```text
push master → pnpm install → pnpm build → wrangler deploy
```

workflow 在 `.github/workflows/deploy-cloudflare.yml`，需要两个仓库 secret：

| Secret | 用途 |
| --- | --- |
| `CLOUDFLARE_API_TOKEN` | Workers Scripts:Edit + 账号读权限 |
| `CLOUDFLARE_ACCOUNT_ID` | 指定账号 |

没配 token 时它只构建、不发布，日志里留一条 warning，任务还是绿的。我第一次就差点被这个「绿勾」骗过去。**Actions 成功不等于已经上线**，要确认 `Deploy to Cloudflare Workers` 那一步真的跑了。

部署完核对三处：Actions 日志里的 `Current Version ID`、Cloudflare 面板 `Workers & Pages → blog → Deployments` 的 Production 版本、线上 HTML 里静态资源的 hash。

手动发布：

```bash
./command build
CLOUDFLARE_API_TOKEN=xxx CLOUDFLARE_ACCOUNT_ID=xxx npx wrangler deploy
```

`wrangler.jsonc` 有三个容易出事的点：

```jsonc
{
	"name": "blog", // 必须和面板里的 Worker 同名
	"assets": { "directory": "./dist" },
	"previews": {} // 不能省，wrangler preview 会校验
}
```

也不要给构建环境设 `CF_WORKERS`。那会让 Astro 挂上 Cloudflare 适配器，而本站只是静态资源，用不上。

域名在 `Workers & Pages → blog → Settings → Domains & Routes` 绑定。`www` 和根域都指到同一个 Worker 时，确认 canonical 用的是 `www`，不然搜索引擎会看到两份内容。改域名时 `siteConfig.site_url`、Cloudflare 自定义域、外部收录要一起改。

如果 Cloudflare 面板也连了 Git 自动构建，确认只留一条发布链路。同一次 push 构建两遍，很容易出现「面板里是新版本，域名还是旧版本」的灵异现象。

还有一种失败跟代码无关：我遇到过 GitHub API 能正常访问、`git push` 却卡在 `HTTP2 framing layer` 的情况。判断方法很简单，`curl https://api.github.com` 正常、`git ls-remote origin` 却一直不动，就不是仓库或权限问题，而是到 git 端点的网络路径有问题。临时换成 SSH remote，或者用仓库的 deploy key 推一次，通常能绕过去；推完记得把临时 key 删掉。

## 八、回滚：面板止血，代码治病

两种回滚方式，作用不一样：

| 方式 | 操作 | 特点 |
| --- | --- | --- |
| 面板回滚 | Deployments → 上一个成功版本 → Rollback | 秒级恢复，但仓库代码还是坏的 |
| 代码回滚 | `git revert <bad-commit>` + push | 慢一点，但下一次发布不会再带病上线 |

只做面板回滚，下一次任何 push 都会把坏代码重新发上去。正确做法是先用面板止血，再 revert 代码。不要在 master 上 `git reset --hard` 后强推，历史会丢，CI 也失去对照。

## 九、周边开关和还没做的事

本站当前关掉的东西比打开的多：评论 `type: "none"`、留言板、友链、相册、项目、书签、赞助页全部关闭，只留了动态。看板娘和音乐也是关的，但配置保留，想开的时候有地方改。

搜索索引、RSS、Atom、sitemap、OG 图这些是模板自带的，跟着构建走，不需要单独维护。`public/_headers` 管安全头和缓存：`/_astro/*`、`/fonts/*` 是一年 immutable，`/pagefind/*` 是一天。以后要加统计或评论，优先看 `src/config/analyticsConfig.ts`、`commentConfig.ts`，别直接把脚本塞进 `Layout.astro`。

备份目前靠两样：GitHub 仓库和 Cloudflare 的版本记录。数据库类的东西没有，静态站的好处在这里体现得很明显。

## 十、最容易翻车的几个瞬间

1. 用 npm/yarn 安装。`preinstall` 会直接拦，lockfile 也不该出现第二份。
2. Node 低于 22.23。报错可能五花八门，先 `node -v`。
3. 改完依赖不重启 dev server。Vite 模块图坏了以后，页面会停在骨架或直接白屏，`./command restart` 比看代码快。
4. 草稿本地可见、线上没有。`draft: true` 只在生产过滤，这是预期行为。
5. dev 搜索没结果。Pagefind 只在 build 生成。
6. frontmatter 日期带了时分秒，构建直接红。
7. 中文文件名。URL 会跟着变中文，脚本里的拼音 `slug` 不参与路由。
8. 改文件名不做重定向。旧链接 404，RSS 里出现重复条目。
9. Actions 绿了但线上没变。先看是不是缺 `CLOUDFLARE_API_TOKEN`，发布步骤被跳过了。
10. Worker 名字不一致。部署成功，但发到了另一个 Worker。
11. 把 `dist/` 或密钥提交进仓库。token 一旦进 git 历史，删文件也没用，只能轮换。
12. 只回滚面板不改代码。下一次 push 原地复发。

## 十一、发布前检查

- [ ] `./command start`，本地看页面和交互
- [ ] `pnpm check` 与 `pnpm type-check`
- [ ] `./command build` 通过，检查生成文件 diff
- [ ] `./command preview` 复查生产产物：搜索、图片、移动端
- [ ] `git status` 只包含本次改动，没有 `dist/`、`.run/`、密钥
- [ ] push master，确认 `Deploy to Cloudflare Workers` 成功
- [ ] 线上强刷复查，必要时 Purge Cache

改造和发布都变成固定动作之后，剩下的时间才是写内容。
