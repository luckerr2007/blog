---
title: 我是怎么改 Firefly 的，以及每次发文都做些什么
published: 2026-11-14
description: 从灰阶配色、每日一言到动效和 Cloudflare 部署，记下这两天改主题的过程、动过的文件，以及下次升级模板时不想再踩的坑。
tags: [Astro, Firefly, Cloudflare Workers, 建站]
category: 博客指南
comment: false
---

昨天把站搭起来，今天基本都在改主题。

Firefly 默认的样子不差，但绿色和圆角不太合我的口味，首页也想加点自己的东西。改着改着又发现部署和发文各有几个小坑，索性一起记下来。不是教程，更多是给自己看的备忘：哪些文件动了、为什么动、下次升级模板时别再踩一遍。

搭建过程在[另一篇](/posts/guide/how-this-blog-was-built/)里。

## 先留退路

原版还在更新，我打算长期用，所以一开始就定了个规矩：能不改上游文件就不改。

```bash
git tag baseline-firefly-6.16.9
git remote add upstream https://github.com/CuteLeaf/Firefly.git
git fetch upstream master
```

有了这个，随时能看自己偏离原版多少：

```bash
git log --oneline upstream/master..master
git diff --stat upstream/master
```

模板自带的示例文章、动态和项目，我挪到了 `src/content/_archive/`。它们不参与构建，但留在原目录会混进归档和搜索。

每改一处，就往 `docs/CUSTOMIZATION.md` 里补一行。这个文件看着麻烦，真到升级的时候能省很多时间，尤其是那些「当时为什么这么改」已经想不起来的改动。

## 换配色

模板原来的绿色我看了两天还是不适应，于是新建 `src/styles/theme-monochrome.css`，在 `Layout.astro` 里跟在 `variables.styl` 后面引入。

思路很简单，只覆盖变量，不动组件：

```css
:root {
	--c-bg: #f2f2f7;
	--c-card: #ffffff;
	--c-fg: #1c1c1e;
	--primary: var(--c-fg);
	--page-bg: var(--c-bg);
}
```

把 `--primary` 指向前景色之后，所有用 `bg-(--primary)` 的组件自己就变成黑白了，不用一个个找。暗色下 `--c-bg` 换成纯黑，`--c-card` 用 `#1c1c1e`。

这里遇到一个小问题：分类胶囊的暗色样式写死了 `color: white`，黑白主题下变成黑底黑字。暗色下要单独把它改成 `var(--c-bg)`。类似写死颜色的地方还有几处，改完最好在暗色模式里走一遍。

后来又照着 Apple HIG 调了圆角、顶栏材质和按钮命中区。还是只动这个文件，想回彩色主题，把 import 删掉就回去了。

## 关掉用不上的东西

壁纸、音乐、看板娘、友链、相册、项目页，这些我暂时都用不上。

`backgroundWallpaper.ts` 里把 `mode` 设成 `"none"`，播放器和水波纹一起关。音乐麻烦一点，模板没有总开关，只能把 `showInNavbar` 和 `showInSidebar` 都设成 `false`，再清空示例播放列表。评论区目前关着，`commentConfig.ts` 保持 `type: "none"`。

字体改过 provider。某天 `pnpm dev` 直接报 `CannotFetchFontFile`，查下来是本机访问 `cdn.jsdelivr.net` 超时。Firefly 用的 Astro Fonts API 会在构建时下载字体再自托管，把 provider 从 `fontsource` 换成 `google` 就好了。这个改动影响的是构建机，访客那边还是本地字体。

身份相关的几处也顺手换了：头像和昵称在 `profileConfig.ts`，favicon 在 `public/favicon/` 和 `siteConfig.favicon`，页脚版权是 `FooterConfig.html`。这些都走配置，不用碰组件。

## 每日一言

首页太空，加了个每日一言。组件和逻辑都是新文件：

- `src/types/hitokotoConfig.ts`、`src/config/hitokotoConfig.ts`：接口、超时、轮换区间、兜底句子；
- `src/utils/hitokoto-client.ts`：取数、缓存、接口失败回退；
- `src/components/common/HitokotoQuote.astro`、`src/components/widget/Hitokoto.astro`：首页和侧栏两个入口。

接入侧栏要改两个地方：`src/types/sidebarConfig.ts` 的 `WidgetComponentType`，以及 `src/components/layout/SideBar.astro` 里的 `componentMap`。首页则是在 `src/pages/[...page].astro` 里判断页码，只让第一页渲染 `<HomeHero />`。

逻辑上有两件事要处理。

一言接口前面有 CDN 缓存，不传时间戳会一直返回同一句。请求 URL 加上 `?t=...` 才真的换。

首页和侧栏可能同时存在，所以共用同一个 pending promise。SSR 先输出按日期选的兜底句子，接口挂了也不至于空着。

缓存是每条句子随机 1–6 小时。页面一直开着就等定时器，切回前台发现过期就立刻换。Swup 切页后先读缓存补同一句，不然刚换完切个页面又跳一下。

## 动效

动效这块单独写了 `theme-motion.css`，把时长和缓动收敛成几个 token。翻了下提交记录，前后改了三次：先抽 token，再补骨架屏，最后修侧栏的 `client:idle`。

```css
:root {
	--dur-2: 150ms;
	--dur-3: 180ms;
	--ease-standard: cubic-bezier(0.2, 0, 0, 1);
}
```

主题切换用 View Transition 做了个从按钮扩散的圆形揭示。不支持这个 API 的浏览器，或者用户开了 `prefers-reduced-motion`，就直接切换，不做降级动画。

两个和 Tailwind 4 有关的细节。`-translate-y-1` 这类类名落在独立的 `translate` 属性上，过渡写 `transform` 不会生效，要写 `translate`。另外动画尽量只碰 `transform` 和 `opacity`，骨架屏在减弱动效时也要能停下来。

改到动态侧栏时遇到一个很怪的 bug：组件一直停在加载态。查了半天，不是接口问题，是 `client:visible` 的宿主元素高度为 0，IntersectionObserver 永远不触发。

```diff
-<DynamicSidebar client:visible apiUrl={apiUrl} limit={limit} {memos} />
+<DynamicSidebar client:idle apiUrl={apiUrl} limit={limit} {memos} />
```

改完才正常。顺手把转圈换成了两条骨架，加载中看起来不至于像死掉。

## 哪些上游文件被改了

完全不动上游不现实。这些文件我改过：

`Layout.astro`（引入两个样式、挂进度条）、`HomeHero.astro`（重写）、`LightDarkSwitch.svelte`（主题揭示）、`DynamicSidebar.svelte` 和 `Dynamic.astro`（骨架和 `client:idle`）、`DynamicFeed.svelte`（动态流骨架）、`GridSkeleton.svelte`（媒体网格骨架）、`AdvancedSearch.svelte` 和 `Search.svelte`（搜索加载态、面板过渡），还有 `PostPage.astro`、`NavMenuPanel.astro` 里一些零碎过渡。

改的时候尽量只动必要的行，不整文件格式化，关键位置留一行注释。否则下次合并上游，冲突会多到不想看。

## 升级模板

流程大概是这样：

```bash
git fetch upstream
git checkout -b upgrade/firefly-<version>
git merge upstream/master --no-commit
```

冲突基本在 `src/config/*`、`src/content/*` 和 `package.json`。配置冲突先看上游是不是加了新字段，新字段留下，自己改过的值继续用；内容冲突直接保留本地；`package.json` 只接受依赖版本，脚本和 `packageManager` 以本地为准。

合并完要专门检查几项：字体 provider 有没有被改回 `fontsource`、`siteConfig.pages` 的开关有没有被重置、`.pages.yml` 的字段和新版 schema 对不对得上。然后 `pnpm install && pnpm check && pnpm build`，最后把这次升级记进 `CUSTOMIZATION.md`。

## 发文

新建文章：

```bash
pnpm new-post guide/modify-and-deploy-the-blog
```

参数既是目录也是文件名，用 ASCII。脚本会把中文转成拼音写进 frontmatter 的 `slug`，但内容 schema 里没有这个字段，路由实际取的是文件路径。传中文路径，URL 就是中文。

frontmatter 里常写错的是日期。`published` 和 `updated` 按 `YYYY-MM-DD` 写，带时分秒容易出问题。`draft: true` 只在生产构建里隐藏，本地 dev 仍然能看到。`prevTitle` 这类字段是主题内部用的，不用手写。

分类和目录是两回事：目录决定 URL，`category` 决定分类页聚合。两者可以不一样，我这篇的目录是 `guide`，分类写的是「博客指南」。

图片放在 `src/content/posts/images/<slug>/`，正文里用相对路径。格式优先 WebP，单张别超过 300KB。

不想开本地环境的时候我用 Pages CMS。它把仓库当数据库，网页上保存后直接 commit 到 master，后面走同一条部署流程。文件名得手填 ASCII slug，后台的 slugify 会把中文删掉。改过 `.pages.yml` 之后，最好拿一篇文章改个标点做一次冒烟测试，看看 `tags`、`category`、`series` 还在不在。

## 本地验证

我现在基本只跑三条：

```bash
pnpm dev
pnpm check && pnpm type-check
pnpm build
```

dev 能看交互和布局，但有些东西它不管：搜索是写死的 mock，Pagefind 只在构建时生成；新加的本地图片没有 LQIP，得重新构建才会写进 `src/constants/lqips.json`；CSS 的问题也不一定能在 dev 里暴露。

`pnpm build` 才是真的构建。本站这条命令不只有 `astro build`，前面要生成 GitHub 卡片、LQIP、VNDB 封面，后面还要做字体子集、压缩内联脚本、跑 Pagefind。本地一次大概 100 秒。

构建会改 `src/constants/lqips.json` 和 `src/constants/github-card-data.json`，这两个文件是提交进仓库的。每次 `git add` 前看一眼 diff，别把无关的缓存变化带上。

另外写了个 `./command` 脚本，省得每天找进程。它会等首页返回 200 再算启动成功，pid 和日志放 `.run/`，用 `mkdir` 做锁。最早 `restart` 写成 `stop; start`，stop 的锁还没释放，start 立刻报错，后来在中间手动释放才修好。

还有两次比较烦的：改完依赖之后 Vite 的模块图坏了，动态页一直停在骨架，控制台报 `Failed to fetch dynamically imported module`，重启 dev server 才恢复；以及手动 `pnpm dev` 只绑了 IPv6 回环，`127.0.0.1` 打不开，`./command start` 显式传 `--host 127.0.0.1` 就没这个问题。

## 部署

推 master 就会触发 GitHub Actions：

```text
pnpm install → pnpm build → wrangler deploy
```

workflow 在 `.github/workflows/deploy-cloudflare.yml`，需要 `CLOUDFLARE_API_TOKEN` 和 `CLOUDFLARE_ACCOUNT_ID` 两个 secret。没配 token 时它只构建不发布，任务还是绿的。看日志的时候别只看最后那个勾，确认 `Deploy to Cloudflare Workers` 真的执行了。

`wrangler.jsonc` 里三个地方容易出错：`name` 必须和面板里的 Worker 一致，`assets.directory` 指向 `./dist`，`previews: {}` 不能删（wrangler preview 会校验）。构建环境也不要设 `CF_WORKERS`，那会让 Astro 挂上 Cloudflare 适配器，静态站用不上。

部署完我会看三样：Actions 日志里的 Version ID、Cloudflare 面板的 Production 版本、线上 HTML 里静态资源的 hash。域名在 `Workers & Pages → blog → Settings → Domains & Routes` 绑定，`www` 和根域都指过来的时候，canonical 要统一，不然搜索引擎会看到两份。

本地也能手动发，先 `./command build`，再带 token 跑 `npx wrangler deploy`。我一般只在 Actions 出问题时才用。

还有一点，如果 Cloudflare 面板自己也连了 Git 构建，确认只留一条发布链路。一次 push 构建两遍，很容易出现面板里是新版本、域名还是旧版本的情况。

缓存方面，`public/_headers` 给 `/_astro/*` 和 `/fonts/*` 设了一年 immutable，`/pagefind/*` 是一天。页面没更新先强刷，还不行再去面板 Purge Cache。

今天推送还遇到一次和代码无关的故障：GitHub API 能访问，`git push` 却卡在 `HTTP2 framing layer`。`git ls-remote origin` 也卡住，基本能确定是到 git 端点的网络问题。临时换 SSH、用 deploy key 推了一次，推完把 key 删了。

## 回滚

面板的 Rollback 最快，Deployments 里选上一个成功版本就行。但代码还是坏的，下次 push 会把问题再带上去。所以面板回滚只能算止血，之后还是要 `git revert` 再推一次。别在 master 上 `git reset --hard` 强推，历史丢了更麻烦。

## 剩下的坑

- 用 npm 或 yarn 装依赖会被 `preinstall` 拦掉，这是故意的。
- Node 低于 22.23 时，报错不一定指向版本，先 `node -v`。
- 改完依赖不重启 dev server，可能会出现各种「组件不初始化」，先 `./command restart`。
- 草稿本地能看见、线上没有，是正常的。
- dev 搜索没结果是正常的，Pagefind 还没生成。
- 日期按 `YYYY-MM-DD` 写，带时分秒容易在 schema 校验时出问题。
- 中文文件名会让 URL 变中文。我写这篇时才注意到，`pnpm new-post` 里生成的拼音 `slug` 没被 schema 读取，路由用的是文件路径。
- 改文件名不补 `_redirects`，旧链接就 404。
- 缺 `CLOUDFLARE_API_TOKEN` 时 Actions 仍然绿，只是没发布。
- Worker 名字不一致，部署成功但发到了另一个 Worker。
- 只回滚面板不改代码，下次 push 复发。
- `dist/`、`.run/`、`.astro/` 都不该进仓库。

## 还没做的

评论和统计都还没开，`analyticsConfig.ts` 和 `commentConfig.ts` 留着位置。RSS、Atom、sitemap、OG 图是模板自带的，跟着构建走。备份靠 GitHub 和 Cloudflare 的版本记录，静态站暂时没有数据库要管。

这些等真正需要了再说。现在至少发文和发布这条线是通的，剩下的时间可以拿来写东西。
