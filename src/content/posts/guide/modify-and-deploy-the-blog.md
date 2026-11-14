---
title: Firefly 二次开发与发布流程
published: 2026-11-14
updated: 2026-11-14
description: 以本站相对 Firefly 6.16.9 的改动为例，说明配置层、样式覆盖层和上游组件补丁的边界，以及每日一言、动效、内容创建、构建验证、Cloudflare Workers 发布与回滚的完整流程。
tags: [Astro, Firefly, Cloudflare Workers, 建站]
category: 博客指南
comment: false
---

这篇记录本站从默认主题到当前形态的改造，以及日常发文和发布流程。改造目标不是把 Firefly 换成另一个主题，而是在保持可升级的前提下，加入必要的视觉和功能调整。

搭建过程在[另一篇](/posts/guide/how-this-blog-was-built/)里，本文只讨论改造和发布。

## 基线与升级策略

Firefly 仍在更新，本站也准备长期使用，因此第一步是建立可对照的基线：

```bash
git tag baseline-firefly-6.16.9
git remote add upstream https://github.com/CuteLeaf/Firefly.git
git fetch upstream master
```

之后可以随时检查偏离程度：

```bash
git log --oneline upstream/master..master
git diff --stat upstream/master
```

模板自带的示例文章、动态和项目移到了 `src/content/_archive/`。它们不参与构建，但留在原目录会混进归档、首页和 Pagefind 索引。

改造遵循一条优先级：能改配置就不写样式，能写覆盖样式就不改组件，必须改上游文件时把 diff 压到最小。每处改动都记录在 `docs/CUSTOMIZATION.md`，包括文件、原因和升级时的注意事项。升级时这份清单比提交历史更容易定位问题。

## 改造分层

本站的改动分布在四层：

| 层次 | 位置 | 适用场景 |
| --- | --- | --- |
| 配置层 | `src/config/*` | 站点信息、导航、页面开关、字体、评论 |
| 覆盖样式层 | `src/styles/theme-monochrome.css`、`theme-motion.css` | 配色、圆角、材质、动效 |
| 新增组件层 | `HomeHero.astro`、`ScrollProgress.astro`、`Hitokoto.astro` | 首页欢迎区、阅读进度、每日一言 |
| 上游补丁层 | `Layout.astro`、`LightDarkSwitch.svelte`、`DynamicSidebar.svelte` 等 | 挂载点、Svelte 交互和无法从外部接入的修改 |

配置层优先，是因为 Firefly 的 27 个配置文件已经覆盖了大部分需求。新增组件层通过少量挂载点接入，升级时冲突可控。上游补丁层是最后手段，改动越少越好。

## 视觉覆盖

原版主题使用绿色和大圆角，本站改成了灰阶和小圆角。实现方式是新增 `src/styles/theme-monochrome.css`，在 `Layout.astro` 中紧跟 `variables.styl` 引入，只覆盖变量，不修改组件结构：

```css
:root {
	--c-bg: #f2f2f7;
	--c-card: #ffffff;
	--c-fg: #1c1c1e;
	--primary: var(--c-fg);
	--page-bg: var(--c-bg);
}
```

把 `--primary` 指向前景色后，所有使用 `bg-(--primary)` 的组件自动变成黑白反色，不需要逐个查找。暗色下 `--c-bg` 改为纯黑，`--c-card` 使用 `#1c1c1e`。

这里有一个容易被忽略的细节：分类胶囊的暗色样式写死了 `color: white`，黑白主题下会变成黑底黑字。暗色下需要单独改成 `var(--c-bg)`。类似写死颜色的地方还有几处，改完最好在暗色模式里完整走一遍。

后来又按 Apple HIG 调整了圆角、顶栏材质、按钮命中区和无障碍表现：控件 8–10px、卡片 12px、弹层 16–22px；顶栏使用 20px 模糊和 72% 卡片色；支持 `corner-shape: squircle` 的浏览器启用连续圆角，否则回退普通圆角；`prefers-reduced-transparency` 时退化为不透明，`prefers-contrast: more` 时加粗分隔线并提高次级文字对比度。

这些规则仍然只落在覆盖文件里。想恢复彩色主题，删除 `theme-monochrome.css` 的 import 即可，`variables.styl` 没有被修改。

## 功能开关

壁纸、音乐、看板娘、友链、相册和项目页当前都用不上。

`backgroundWallpaper.ts` 把 `mode` 设为 `"none"`，同时关闭播放器、水波纹和渐变。音乐没有总开关，只能把 `showInNavbar` 和 `showInSidebar` 都设为 `false`，并清空示例播放列表。看板娘的 `spineModelConfig.enable` 和 `live2dWidgetConfig.enable` 在模板中默认就是 `false`，保持不动。评论区维持 `type: "none"`。

字体 provider 从 `fontsource` 改成了 `google`。原因是本机访问 `cdn.jsdelivr.net` 超时，`pnpm dev` 和 `pnpm build` 都会报 `CannotFetchFontFile`。Astro Fonts API 在构建期下载字体并自托管，访客仍然从本站加载字体，provider 只影响构建机。

如果构建机同样无法访问 Google，`npm` provider 配合 `@fontsource-variable/*` 包更稳定，构建期不依赖外部网络。当前仍使用 `google`，本地构建遇到字体元数据超时时会退化为系统字体，发布前需要确认 CI 日志中没有字体告警。

身份相关配置也集中在配置层：头像和昵称在 `profileConfig.ts`，favicon 在 `public/favicon/` 和 `siteConfig.favicon`，页脚版权在 `FooterConfig.html`。

## 每日一言

首页和侧栏各有一个每日一言入口。新增文件如下：

| 文件 | 作用 |
| --- | --- |
| `src/types/hitokotoConfig.ts`、`src/config/hitokotoConfig.ts` | 接口、超时、轮换区间、兜底句子 |
| `src/utils/hitokoto-client.ts` | 取数、缓存、接口失败回退 |
| `src/components/common/HitokotoQuote.astro` | 展示组件，支持 `hero` 和 `widget` 两种变体 |
| `src/components/widget/Hitokoto.astro` | 侧栏小组件 |

接入侧栏需要改两个上游位置：`src/types/sidebarConfig.ts` 的 `WidgetComponentType`，以及 `src/components/layout/SideBar.astro` 的 `componentMap`。首页在 `src/pages/[...page].astro` 里判断页码，只让第一页渲染 `<HomeHero />`。

逻辑上有几处需要处理。

一言接口前面有 CDN 缓存，请求 URL 不带时间戳时会一直返回同一句。客户端在 URL 上追加 `?t=...`，每次轮换才能拿到新内容。

首页和侧栏可能同时存在，不能各自请求。两处共用同一个 pending promise，避免重复请求和状态不一致。

SSR 先输出按日期选择的兜底句子，接口失败或断网时页面不会出现空白区域。

缓存按句子写入时随机取 1–6 小时 TTL。页面一直开着时由定时器触发；切回前台发现过期会立即换；Swup 切页后先读缓存补同一句，避免刚换完切页又跳一次。

## 动效

动效单独放在 `theme-motion.css`，把时长和缓动收敛成 token：

```css
:root {
	--dur-2: 150ms;
	--dur-3: 180ms;
	--ease-standard: cubic-bezier(0.2, 0, 0, 1);
}
```

主题切换使用 View Transition，从触发按钮扩散出一个圆形揭示。浏览器不支持该 API，或者用户开启 `prefers-reduced-motion` 时，直接切换，不播放降级动画。

Tailwind 4 有两个细节。第一，`-translate-y-1` 这类工具类落在独立的 `translate` 属性上，过渡写 `transform` 不会生效，必须写 `translate`。第二，动画尽量只改 `transform` 和 `opacity`，骨架屏在减弱动效时也要能静止，否则“减少动态效果”形同虚设。

动态侧栏遇到过一个不报错但一直停在加载态的问题。根因不是接口，而是 `client:visible` 的宿主元素高度为 0，IntersectionObserver 永远不会触发：

```diff
-<DynamicSidebar client:visible apiUrl={apiUrl} limit={limit} {memos} />
+<DynamicSidebar client:idle apiUrl={apiUrl} limit={limit} {memos} />
```

改成 `client:idle` 后恢复。加载态也从转圈换成了两条骨架，避免看起来像卡死。

首屏 hero 没有再单独做淡入，因为主内容包装层已经淡入一次；两层动画会推迟 LCP。文章卡的 hover 位移收回到 180ms，列表布局切换仍保留 400ms，避免交互发木。

## 上游文件清单

完全不动上游文件不现实。本站修改过的文件包括：

- `src/layouts/Layout.astro`：引入两个覆盖样式，挂载 `<ScrollProgress />`；
- `src/components/layout/HomeHero.astro`：重写为 editorial 风格；
- `src/components/controls/LightDarkSwitch.svelte`：接入 View Transition 圆形揭示；
- `src/components/widget/DynamicSidebar.svelte`、`Dynamic.astro`：骨架屏和 `client:idle`；
- `src/components/pages/dynamic/DynamicFeed.svelte`：动态流骨架；
- `src/components/common/GridSkeleton.svelte`：媒体网格骨架统一 shimmer；
- `src/components/pages/AdvancedSearch.svelte`、`controls/Search.svelte`：搜索加载态和面板过渡；
- `src/components/layout/PostPage.astro`、`NavMenuPanel.astro`：零散过渡和布局修正。

修改时只动必要行，不整文件格式化，在关键位置留一行注释说明与上游的差异。否则下次 `git merge upstream/master` 会产生大量无意义冲突。

## 升级模板

升级流程如下：

```bash
git fetch upstream
git checkout -b upgrade/firefly-<version>
git merge upstream/master --no-commit
```

冲突通常集中在 `src/config/*`、`src/content/*` 和 `package.json`。处理顺序是：

1. 配置冲突先看上游是否新增字段。新增字段保留，自己改过的值继续使用；
2. 内容冲突保留本地版本，示例内容早已归档；
3. `package.json` 只接受依赖版本，脚本和 `packageManager` 以本地为准；
4. 样式和组件冲突逐个看 diff，确认覆盖层还在、类名没有被上游改掉。

合并后要专门检查：字体 provider 是否被改回 `fontsource`、`siteConfig.pages` 的开关是否被重置、`.pages.yml` 的字段是否与新版 schema 对齐。然后执行 `pnpm install && pnpm check && pnpm build`，最后把本次升级记进 `docs/CUSTOMIZATION.md`。

## 发文

新建文章：

```bash
pnpm new-post guide/modify-and-deploy-the-blog
```

参数既是目录也是文件名，必须使用 ASCII。脚本会把中文标题转成拼音写进 frontmatter 的 `slug`，但内容 schema 不读取这个字段，路由实际取的是文件路径。传中文路径，URL 就会是中文，分享和 RSS 都不方便。

frontmatter 中容易写错的是日期。`published` 和 `updated` 按 `YYYY-MM-DD` 写，带时分秒容易在 schema 校验时出问题。`draft: true` 只在生产构建里隐藏，本地 dev 仍然可见。`prevTitle`、`prevSlug` 这类字段由主题内部维护，不需要手写。

分类和目录是两个概念：目录决定 URL，`category` 决定分类页聚合。两者可以不同，例如文章放在 `guide/` 目录，分类写“博客指南”。

图片放在 `src/content/posts/images/<slug>/`，正文使用相对路径。格式优先 WebP，单张尽量控制在 300KB 以内。

不想开本地环境时使用 Pages CMS。它把仓库当数据库，网页保存后直接 commit 到 `master`，后续走同一条部署流程。文件名需要手动填写 ASCII slug，因为后台的 slugify 会删除中文。修改 `.pages.yml` 后，拿一篇文章改一个标点做冒烟测试，确认 `tags`、`category`、`series` 和正文都保留。

## 本地验证

日常验证主要跑三条命令：

```bash
pnpm dev
pnpm check && pnpm type-check
pnpm build
```

`pnpm dev` 适合看交互和布局，但有些问题它不会暴露：搜索使用 mock 数据，Pagefind 只在构建时生成；新增的本地图片没有 LQIP，需要重新构建才会写入 `src/constants/lqips.json`；部分 CSS 问题只在生产构建中出现。

`pnpm build` 执行完整构建。本站这条命令不只运行 `astro build`，前面要生成 GitHub 卡片、LQIP 和 VNDB 封面，后面还要做字体子集化、压缩内联脚本和运行 Pagefind。本地一次约 100 秒，实测约 105 秒。

构建会修改 `src/constants/lqips.json` 和 `src/constants/github-card-data.json`，这两个文件提交在仓库里。每次 `git add` 前检查 diff，不要带入无关的缓存变化。

`./command` 脚本省去了查找进程的步骤。它等首页返回 200 才算启动成功，PID 和日志放在 `.run/`，用 `mkdir` 做锁。早期 `restart` 写成 `stop; start`，`stop` 的锁尚未释放，`start` 立刻报错；后来在两步之间显式释放锁才修好。

另外两个问题与依赖和网络有关：修改依赖后 Vite 的模块图可能损坏，动态页停在骨架，控制台报 `Failed to fetch dynamically imported module`，重启 dev server 才能恢复；手动执行 `pnpm dev` 可能只绑定 IPv6 回环，`127.0.0.1` 打不开，`./command start` 显式传 `--host 127.0.0.1` 可以避免。

## 部署

推送 `master` 会触发 GitHub Actions：

```text
pnpm install → pnpm build → wrangler deploy
```

workflow 位于 `.github/workflows/deploy-cloudflare.yml`，需要 `CLOUDFLARE_API_TOKEN` 和 `CLOUDFLARE_ACCOUNT_ID`。没有配置 token 时它只构建、不发布，任务仍然显示成功。查看日志时不能只看最后的勾，要确认 `Deploy to Cloudflare Workers` 真的执行了。

`wrangler.jsonc` 有三处容易出错：`name` 必须与面板里的 Worker 一致；`assets.directory` 指向 `./dist`；`previews: {}` 不能删除，`wrangler preview` 会校验。构建环境也不要设置 `CF_WORKERS`，否则 Astro 会挂上 Cloudflare 适配器，静态站点用不上。

部署完成后检查三样：Actions 日志里的 Version ID、Cloudflare 面板的 Production 版本、线上 HTML 中静态资源的 hash。域名在 `Workers & Pages → blog → Settings → Domains & Routes` 绑定。根域和 `www` 都指向站点时，canonical 要统一，否则搜索引擎会看到两份内容。

本地也可以手动发布：先执行 `./command build`，再带 token 运行 `npx wrangler deploy`。一般只在 Actions 出现问题时使用。

如果 Cloudflare 面板自己也连接了 Git 构建，确认只保留一条发布链路。一次 push 构建两遍，容易出现面板里是新版本、域名还是旧版本的情况。

缓存方面，`public/_headers` 给 `/_astro/*` 和 `/fonts/*` 设置一年 immutable，`/pagefind/*` 设置一天。页面没有更新时先强刷，仍然不对再在面板 Purge Cache。

推送还可能遇到与代码无关的网络故障：GitHub API 可以访问，`git push` 却卡在 `HTTP2 framing layer`，`git ls-remote origin` 也卡住。这基本可以确定是到 Git 端点的网络问题。临时换 SSH 或用 deploy key 推一次，推完删除 key 即可。

## 回滚

面板的 Rollback 最快，在 Deployments 里选择上一个成功版本。但代码仍然是坏的，下次 push 会把问题再带上去。面板回滚只能止血，之后仍要 `git revert` 并重新推送。不要在 `master` 上 `git reset --hard` 强推，历史丢失后处理成本更高。

## 常见故障

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 用 npm 或 yarn 安装依赖被拦截 | `preinstall` 中的 `only-allow pnpm` | 改用 pnpm，这是有意设计 |
| Node 低于 22.23 时报错不指向版本 | Astro 7 的运行时要求 | 先执行 `node -v`，再用 nvm 切换 |
| 改完依赖后组件不初始化 | Vite 模块图损坏 | `./command restart` |
| 草稿本地可见、线上没有 | `draft: true` 只在生产构建隐藏 | 正常行为 |
| dev 搜索没有结果 | Pagefind 只在构建时生成 | 用 `pnpm build && pnpm preview` 验证 |
| 日期带时分秒导致 schema 校验失败 | 日期格式不匹配 | 统一写 `YYYY-MM-DD` |
| 中文文件名让 URL 变成中文 | `slug` 未被 schema 读取，路由取文件路径 | 新建时使用 ASCII 路径 |
| 改文件名后旧链接 404 | 没有补 `_redirects` | 在 `public/_redirects` 增加跳转 |
| 缺 `CLOUDFLARE_API_TOKEN` 时 Actions 仍绿 | 工作流只构建、不发布 | 检查 Deploy 步骤是否执行 |
| Worker 名字不一致，部署成功但发到另一个 Worker | `wrangler.jsonc` 的 `name` 与面板不一致 | 对齐名称后重新部署 |
| 只回滚面板不改代码，下次 push 复发 | 回滚没有改变 Git 历史 | 面板止血后执行 `git revert` |
| `dist/`、`.run/`、`.astro/` 被提交 | `.gitignore` 缺失或失效 | 从暂存区移除并检查忽略规则 |

## 未完成

评论和统计还没有启用，`analyticsConfig.ts` 和 `commentConfig.ts` 已留好配置位置。RSS、Atom、sitemap 和 OG 图由模板和构建流程生成。备份依赖 GitHub 和 Cloudflare 的版本记录，静态站暂时没有数据库需要维护。

当前发文和发布链路已经稳定，剩余时间主要用于内容生产。等功能出现真实需求，再接入评论和统计。
