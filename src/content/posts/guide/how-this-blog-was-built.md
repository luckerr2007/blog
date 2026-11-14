---
title: 从选型到上线：这个博客的搭建记录
published: 2026-11-13
updated: 2026-11-14
pinned: true
description: 从选型、环境准备、本地一键脚本，到 Firefly 定制、Cloudflare Workers 部署和 Pages CMS 后台，记录本站从空仓库到可发文状态的完整过程与故障处理。
tags: [Astro, Firefly, Cloudflare Pages, Pages CMS, 建站]
category: 博客指南
comment: false
---

这个博客从空仓库到可以稳定发文，经历了几个相对独立的阶段：选模板、准备环境、补本地脚本、做主题定制、接入部署与内容后台。每个阶段的决策都留下了记录，这里按实际顺序整理，重点说明配置项和出现过的问题，方便以后回溯，也方便搭同类站点时少走弯路。

## 选型

需求很明确：静态输出、首屏快、视觉可调整、能长期维护。

对比过三类方案：

- Hexo 和 Hugo：生态成熟，但主题的“模板感”较强，深度定制最终仍要改模板源码；
- 自己写 Astro 主题：自由度最高，但导航、搜索、目录、暗色模式这些基础设施要逐个实现；
- Firefly：基于 Astro 7、Svelte 5 和 Tailwind 4，衍生自 Fuwari，自带 Pagefind 全文搜索、i18n、Expressive Code、Mermaid、KaTeX、RSS、sitemap 和 OG 图。

Firefly 的决定性优势是配置化程度。`src/config/` 下有 27 个配置文件，站点信息、导航、侧栏、壁纸、字体、评论、音乐和看板娘都能在配置层修改，不必先动组件。这符合“只做定制，不重写主题”的目标。

## 环境准备

Firefly 的 `package.json` 写明了运行时要求：

```json
"engines": { "node": ">=22.23.0" },
"packageManager": "pnpm@11.22.0"
```

本地需要准备：

```bash
node -v   # v22.x（>= 22.23.0）
pnpm -v   # 11.22.0
```

根目录的 `.npmrc` 开启了 `manage-package-manager-versions=true`，pnpm 会按 `packageManager` 字段自动切换到 11.22.0；`preinstall` 又用 `only-allow pnpm` 拦截 npm 和 yarn，避免 lockfile 被混用。另加了 `.nvmrc`，内容为 `22`，换机器时可以直接 `nvm use`。

初始化仓库时没有保留上游的 Git 历史：

```bash
git clone https://github.com/CuteLeaf/Firefly.git blog
cd blog
rm -rf .git
git init -b master
git remote add origin https://github.com/luckerr2007/blog.git
pnpm install
```

## 本地启停脚本

静态博客日常只有两件事：写文章时启动开发服务器，写完关闭。每次都手动执行 `pnpm dev`、再查找进程并 kill，效率很低。根目录的 `command` 脚本把这些操作收在一起：

```bash
./command start      # 启动、等待健康检查、打开浏览器
./command stop       # 结束进程组，按端口兜底清理，删除 PID
./command restart
./command status     # 进程与 HTTP 状态
./command logs -f    # 实时日志
./command build      # 与 Cloudflare 相同的构建命令
./command preview    # 本地预览 dist
./command install    # 强制重装依赖
```

几个实现细节：

1. 默认 `PORT=4321`、`HOST=127.0.0.1`，PID 写入 `.run/dev.pid`，日志写入 `.run/dev.log`，上一次日志轮转为 `.run/dev.log.1`。`.run/` 已加入 `.gitignore`。
2. 启动成功以 HTTP 200 为准，而不是“进程存在”。脚本轮询首页，首次启动需要下载字体，实测约 56 秒，因此超时设为 120 秒；超时会打印日志尾部并清理进程。
3. 已经在运行时再次执行 `start` 只提示并打开浏览器，不会启动第二个实例。
4. `stop` 先 `pkill -P` 结束子进程，再向父进程发 TERM，3 秒后退到 KILL，最后用 `lsof -ti tcp:4321 -sTCP:LISTEN` 确认端口已经释放。
5. `.run/command.lock` 用 `mkdir` 做原子锁，防止双击启动两个服务。

早期 `restart` 直接写成 `stop; start`，`stop` 拿到锁后没有释放，`start` 立刻报“另一个 command 进程正在运行”。后来在两步之间显式释放锁并重新执行 `start`，问题才消失。

`start` 显式传入 `--host 127.0.0.1` 也有实际原因：手动执行 `pnpm dev` 时，Astro 可能只绑定 IPv6 回环，浏览器访问 `127.0.0.1` 会失败。

## 主题定制

原则是先改配置，再写覆盖样式，最后才改上游组件。本站的改动集中在四个层次：

| 层次 | 位置 | 用途 |
| --- | --- | --- |
| 配置 | `src/config/*` | 站点信息、导航、页面开关、字体、评论 |
| 覆盖样式 | `src/styles/theme-monochrome.css`、`theme-motion.css` | 配色、圆角、材质、动效 |
| 新增组件 | `HomeHero.astro`、`ScrollProgress.astro`、`Hitokoto.astro` | 首页欢迎区、阅读进度、每日一言 |
| 上游补丁 | `Layout.astro`、`LightDarkSwitch.svelte`、`DynamicSidebar.svelte` 等 | 无法从外部接入的挂载点和交互 |

配置层完成了大部分工作：

| 项目 | 改动 |
| --- | --- |
| 站点信息 | `siteConfig.ts`：标题、副标题、`site_url`、描述、关键词、`siteStartDate` |
| 资料卡 | `profileConfig.ts`：名字、签名、GitHub 链接，删除模板示例邮箱 |
| 导航 | `navBarConfig.ts`：精简为主页、文章、关于、链接，去掉空菜单 |
| 页面开关 | `siteConfig.pages`：关闭友链、留言板、项目、相册、书签和打赏，只保留动态 |
| 音乐播放器 | `musicConfig.ts`：模板没有总开关，同时关闭 `showInNavbar` 和 `showInSidebar` |
| 看板娘 | `pioConfig.ts`：模板默认已关闭，保持 `false` 即可 |
| 页脚 | `FooterConfig.html`：版权信息和备案占位 |
| 示例内容 | 模板文章、动态、项目移到 `src/content/_archive/`，不参与构建 |

关闭音乐和看板娘后，首屏不再加载 Live2D 模型和播放器资源，页面体积和主线程压力都明显下降。

每改一处，都在 `docs/CUSTOMIZATION.md` 里补一行，记录文件、原因和升级时的注意事项。这份清单在后续合并上游时比提交历史更有用。

## 字体故障

第一次执行 `pnpm dev` 时启动失败：

```text
[CannotFetchFontFile] An error occurred while fetching the font file from
https://cdn.jsdelivr.net/fontsource/fonts/zen-maru-gothic@5.3.1/latin-300-normal.woff2
```

Firefly 默认使用 Astro Fonts API 的 `fontsource` provider，字体文件从 `cdn.jsdelivr.net` 下载。这台机器访问该域名会超时，`curl` 返回 `000`，开发服务器和构建都会被卡住。

可选方案有三种：

1. 换 CDN 或代理，治标，换台机器可能再次出现；
2. 全部改用本地字体文件，但字体版权和体积需要自己承担；
3. 更换 provider，把 `Inter` 和 `JetBrains Mono` 从 `fontsource` 改为 `google`，并删除仅用于示例的日文字体 `Zen Maru Gothic`，把 `bannerTitleFont` 置空，回落到系统字体。

最终选择第三种。关键点是：Astro Fonts API 在构建期下载字体并自托管输出，访客拿到的是本站域名下的 `/_astro/*.woff2`，不依赖 Google 的可用性；provider 只影响构建机的网络。

`google` provider 只解决了 jsDelivr 的可达性问题。如果构建机同样无法访问 Google，更稳妥的方案是改用 `npm` provider，把 `@fontsource-variable/inter` 和 `@fontsource-variable/jetbrains-mono` 作为依赖安装，构建期直接从 `node_modules` 读取，不再依赖外部网络。当前配置仍使用 `google`，本地网络受限时会出现字体告警，构建不会失败，但产物会回落到系统字体；发布前应确认 CI 的构建日志里没有同类告警。

构建时还会出现 `[WARN] No data found for font family JetBrains Mono`。这是字体子集数据缺失的告警，不影响产物，后续需要时再改用 `npm` provider。

## 部署

最初部署在 Cloudflare Pages，原因很直接：仓库名是 `blog`，如果使用 GitHub Pages，站点会落在 `https://<user>.github.io/blog/` 子路径，`base` 要从 `/` 改成 `/blog/`，RSS、sitemap、Pagefind 和 OG 图都要跟着验证。Cloudflare Pages 直接使用根路径，`base: "/"` 不需要改。

Pages 的配置如下：

| 项 | 值 |
| --- | --- |
| Framework preset | Astro |
| Build command | `pnpm run build` |
| Build output directory | `dist` |
| Root directory | `/` |
| 环境变量 | `NODE_VERSION=22` |

有两个容易忽略的点。第一，不要设置 `CF_WORKERS`。`astro.config.mjs` 只在该变量存在时挂载 `@astrojs/cloudflare` 适配器，纯静态站点不需要它。第二，`vercel.json` 里的响应头不会被 Cloudflare 读取，缓存和安全头要写在 `public/_headers`。

后来生产部署迁移到 Cloudflare Workers，Pages 流程保留为手动触发的备用方案。当前链路是：push 到 `master` 后，GitHub Actions 执行 `pnpm install`、`pnpm build`，再由 `wrangler deploy` 发布到 Worker `blog`。

`.github/workflows/deploy-cloudflare.yml` 需要 `CLOUDFLARE_API_TOKEN` 和 `CLOUDFLARE_ACCOUNT_ID` 两个 secret。未配置 token 时，工作流只构建、不发布，任务仍是绿色；看日志时不能只看最后的勾，要确认 `Deploy to Cloudflare Workers` 真正执行。

`wrangler.jsonc` 有三个约束：`name` 必须与面板里的 Worker 一致；`assets.directory` 指向 `./dist`；`previews: {}` 不能删除，`wrangler preview` 会校验这个字段。

如果 Cloudflare 面板也连接了 Git 构建，需要确认只保留一条发布链路。一次 push 构建两遍，容易出现面板显示新版本、域名仍指向旧版本的情况。

缓存策略在 `public/_headers`：`/_astro/*` 和 `/fonts/*` 设置一年 immutable，`/pagefind/*` 设置一天。页面没有更新时先强制刷新，仍然不对再在面板 Purge Cache。

## Pages CMS

静态博客的痛点是“发文章要改文件再 push”。Pages CMS 的思路很轻：GitHub 仓库就是数据库，仓库根放一个 `.pages.yml` 声明内容模型，网页后台通过 GitHub API 把改动 commit 回仓库，部署平台检测到 push 后自动重建。CMS 本身不参与构建，不需要时删掉配置文件即可。

`.pages.yml` 最重要的约束是字段必须与 `src/content.config.ts` 的 zod schema 对齐，否则会出现“后台保存成功、构建报错”，甚至正文整段丢失。几条硬规则：

1. 有正文的集合必须声明 `body` 字段，否则保存时正文消失；
2. 主题会读取但不常改的字段（如 `licenseName`、`prevTitle`）要声明为 `hidden: true`，否则重写文件时会被丢弃；
3. `exclude` 只支持精确名字，不支持 glob，写 `exclude: ["images"]`；
4. 文件名不要用 `{primary}` 由标题生成，slugify 会把中文整段剔除，应使用 `field: create` 手动填写 ASCII slug；
5. 日期格式统一为 `time: false` + `yyyy-MM-dd`；
6. `tags` 使用 `select` + `multiple` 时，所有可能出现的标签都必须预定义，否则后台保存会丢掉未列出的标签。

改完 `.pages.yml` 后，最好拿一篇文章改一个标点做冒烟测试，确认 `tags`、`category`、`series` 和正文都还在。

## 评论

评论系统最初考虑 Waline。它可以运行在 Vercel 或 Cloudflare Workers 上，Firefly 原生支持，前端只需配置 `serverURL`。但评论需要独立后端、数据库和管理员初始化，属于需要长期维护的组件。

当前决定先关闭评论：`commentConfig.type = "none"`，留言板页面同时关闭，把精力放在内容上。等出现真实的互动需求，再按“Workers + D1”接入 Waline。

## 故障记录

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| `dev` 启动失败，`CannotFetchFontFile` | 字体走 jsDelivr，网络不可达 | 换 `google` provider，删除示例日文字体 |
| `[WARN] No data found for font family JetBrains Mono` | 该字体缺少子集数据 | 仅告警，不影响构建 |
| `restart` 报“另一个 command 进程正在运行” | 锁未在 stop 与 start 之间释放 | restart 中显式释放锁 |
| `stop` 后 `lsof -ti:4321` 仍有输出 | 这是浏览器到端口的客户端连接，不是监听 | 检查时加上 `-sTCP:LISTEN` |
| 手动 `pnpm dev` 后 `127.0.0.1` 打不开 | 只绑定了 IPv6 回环 | 显式传 `--host 127.0.0.1` |
| 构建耗时约 105 秒 | 字体子集化、Pagefind 索引和图片处理 | 本地可接受，Pages/Workers 免费额度内没问题 |

## 现状与待办

- 头像、favicon、站点信息和页脚已经替换为本站版本。
- Pages CMS 的配置文件已经就位，接入 GitHub 授权后可以在网页或手机上发文。
- 评论和统计保持关闭，`commentConfig.ts` 和 `analyticsConfig.ts` 已留好位置。
- 域名指向 `www.liveroom.dpdns.org`，HTTPS 由 Cloudflare 自动签发。
- RSS、Atom、sitemap 和 OG 图跟随构建生成，暂不需要额外维护。

> 本文记录的是本站实际搭建过程，涉及的工具与版本可以在 `package.json`、`docs/CUSTOMIZATION.md` 和 workflow 文件中核对。
