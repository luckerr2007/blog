---
title: 这个博客是怎么搭建起来的
published: 2026-11-13
pinned: true
description: 从选型到上线：用 Astro + Firefly 搭建本站，本地一键启停脚本、Cloudflare Pages 部署、Pages CMS 可视化后台的完整记录，包含踩过的坑。
tags: [Astro, Firefly, Cloudflare Pages, Pages CMS, 建站]
category: 博客指南
comment: false
---

这个博客从「空仓库」到「能写文章」，一共经历了五步：选模板、跑起来、写一键脚本、做二次开发、接部署与后台。下面按时间顺序把过程、配置和踩过的坑都记下来，方便以后自己回溯，也方便想搭同类博客的人少走弯路。

## 一、为什么选 Firefly

需求很明确：**静态、快、好看、能长期自己维护**。

对比过几种方案：

- Hexo / Hugo：生态成熟，但主题样式偏「博客模板感」，深度定制要改模板源码；
- 自己写 Astro 主题：自由度最高，但导航、搜索、目录、暗色模式这些要一个个做；
- [Firefly](https://github.com/CuteLeaf/Firefly)：基于 Astro 7 + Svelte 5 + Tailwind 4，衍生自 [Fuwari](https://github.com/saicaca/fuwari)，开箱就有 Pagefind 全文搜索、i18n、代码块增强、Mermaid、KaTeX、RSS、sitemap、OG 图。

Firefly 决定性的优势是**配置化程度高**：`src/config/` 下有 27 个配置文件，站点信息、导航、侧栏、壁纸、字体、评论、音乐、看板娘全都能改，而不必动组件。这正好符合「只想定制，不想重写」的诉求。

## 二、把项目跑起来

### 环境

Firefly 的 `package.json` 里写得很清楚：

```json
"engines": { "node": ">=22.23.0" },
"packageManager": "pnpm@11.22.0"
```

所以准备两样东西：

```bash
node -v   # v22.x（>= 22.23.0）
pnpm -v   # 11.22.0
```

项目根目录的 `.npmrc` 开了 `manage-package-manager-versions=true`，pnpm 会按 `package.json` 的 `packageManager` 自动切到 11.22.0；`preinstall` 又用 `only-allow pnpm` 挡掉了 npm/yarn，避免 lockfile 被污染。

### 落地与安装

```bash
git clone https://github.com/CuteLeaf/Firefly.git
# 把源码放进自己的仓库（不带上游 git 历史）
git init -b master
git remote add origin https://github.com/luckerr2007/blog.git
pnpm install
```

我额外加了 `.nvmrc`（内容 `22`），把 Node 版本钉死，换机器时不容易踩版本坑。

## 三、一键启停脚本 `command`

静态博客日常就两件事：写文章时起服务、写完关掉。每次都敲 `pnpm dev`、再找进程 kill，很烦。于是写了根目录下的 `command`（没有扩展名，Bash 脚本）：

```bash
./command start      # 启动 + 等健康检查通过 + 自动开浏览器
./command stop       # 杀进程组 + 兜底按端口清理 + 删 pid
./command restart
./command status     # 进程 + HTTP 状态
./command logs -f    # 实时日志
./command build      # 与 Cloudflare Pages 同一条构建命令
./command preview    # 本地预览 dist
./command install    # 强制重装依赖
```

几个设计要点：

1. **端口与 pid 文件**：默认 `PORT=4321`、`HOST=127.0.0.1`，pid 写进 `.run/dev.pid`，日志写 `.run/dev.log`（上一次轮转为 `.run/dev.log.1`）。`.run/` 已加进 `.gitignore`。
2. **健康检查**：不是「起了进程就算成功」，而是轮询 `http://127.0.0.1:4321/` 直到返回 200。首次启动要下载字体，实测约 56 秒，所以超时设到 120 秒，超时会把日志尾部打出来再清理进程。
3. **幂等**：已经在跑时再次 `start` 只提示并打开浏览器，不会起第二个进程。
4. **清理彻底**：`stop` 先 `pkill -P` 杀子进程、再 `kill` 父进程，3 秒不退就 `SIGKILL`，最后用 `lsof -ti tcp:4321 -sTCP:LISTEN` 兜底检查端口是否真的空出来了。
5. **锁**：`.run/command.lock` 用 `mkdir` 做原子锁，防止双击启动两个服务。

> 踩坑记录：一开始 `restart` 是 `stop; start` 直接串联，结果 stop 拿到锁后没释放，start 立刻报「另一个 command 进程正在运行」。修法是 restart 在两步之间显式释放锁，再做一次 `start`。

## 四、二次开发做了什么

原则：**能改配置就不改组件**。改动全部落在 `src/config/`：

| 项目 | 改动 |
| --- | --- |
| 站点信息 | `siteConfig.ts`：标题「桃苏的博客」、副标题、`site_url` 指向本站域名、描述、关键词、`siteStartDate` |
| 资料卡 | `profileConfig.ts`：名字「桃苏」、签名、GitHub 链接（顺手删掉模板里的示例邮箱） |
| 导航 | `navBarConfig.ts`：精简为 主页 / 文章（归档·分类·标签）/ 关于 / 链接，去掉没有内容的入口 |
| 页面开关 | `siteConfig.ts` 的 `pages`：友链、留言板、项目、相册、书签、打赏全部关掉，只留动态 |
| 音乐播放器 | `musicConfig.ts`：模板没有总开关，要同时关 `showInNavbar` 和 `showInSidebar` |
| 看板娘 | `pioConfig.ts`：`spineModelConfig.enable` 与 `live2dWidgetConfig.enable` 都是 `false` |
| 页脚 | `FooterConfig.html`：版权 + 备案占位 |
| 内容 | 模板示例文章/动态/项目整体移到 `src/content/_archive/`，不参与构建 |

关掉音乐和看板娘之后，首屏不再加载 Live2D 模型和播放器资源，页面明显更轻。

## 五、字体：一个必须记下来的坑

第一次 `pnpm dev` 直接失败：

```text
[CannotFetchFontFile] An error occurred while fetching the font file from
https://cdn.jsdelivr.net/fontsource/fonts/zen-maru-gothic@5.3.1/latin-300-normal.woff2
```

原因：Firefly 默认用 Astro Fonts API 的 `fontsource` provider，字体文件走 `cdn.jsdelivr.net`。这台机器访问 jsDelivr 直接超时（`curl` 返回 `000`），于是开发服务器和构建全都被卡住。

三种解法：

1. 换 CDN / 代理 —— 治标，换台机器又坏；
2. 全部改用本地字体文件 —— 字体版权和体积要自己扛；
3. **改用其他 provider** —— 我选了这条：把 `Inter` 与 `JetBrains Mono` 的 `provider` 从 `fontsource` 改成 `google`，并删掉只在 demo 里用的日文字体 `Zen Maru Gothic`（`bannerTitleFont` 置空，回落到系统字体）。

关键点：**Astro Fonts API 是构建期下载、自托管输出**，访客拿到的是本站域名下的 `/_astro/*.woff2`，不依赖 Google 的可用性。provider 只影响构建机的网络。

## 六、部署到 Cloudflare Pages

选它而不是 GitHub Pages，主要图省事：仓库名是 `blog` 的话，GitHub Pages 会变成 `https://<user>.github.io/blog/` 这种子路径，`base` 要从 `/` 改成 `/blog/`，RSS、sitemap、Pagefind、OG 图全都要跟着验证一遍。Cloudflare Pages 直接根路径，`base: "/"` 不用动。

配置：

| 项 | 值 |
| --- | --- |
| Framework preset | Astro |
| Build command | `pnpm run build` |
| Build output directory | `dist` |
| Root directory | `/` |
| 环境变量 | `NODE_VERSION=22` |

两个容易忽略的点：

- **不要设 `CF_WORKERS`**。Firefly 的 `astro.config.mjs` 里只有这个变量存在时才挂 `@astrojs/cloudflare` 适配器，静态站点不需要它。
- 仓库里原本只有 `vercel.json` 的 headers，Cloudflare Pages 不读这个文件，缓存和安全头要写在 `public/_headers` 里。

## 七、Pages CMS：给自己一个可视化后台

静态博客最大的痛点是「发文章要改文件再 push」。Pages CMS 的思路很轻：**GitHub 仓库就是数据库**，仓库根放一个 `.pages.yml` 声明内容模型，然后在网页后台点几下，它通过 GitHub API 把改动 commit 回来，部署平台检测到 push 自动重建。CMS 本身不参与构建，不想要了删掉配置文件即可。

`.pages.yml` 里最关键的是**字段必须和 `content.config.ts` 的 zod schema 对齐**，否则会出现「后台保存成功、构建报错」，甚至正文被整段丢掉。几个死规则：

1. 有正文的集合必须声明 `body` 字段，否则保存时正文消失；
2. 主题用但你不常改的字段（如 `licenseName`、`prevTitle`）要声明成 `hidden: true`，否则重写文件时被丢弃；
3. `exclude` 只支持精确名字，不支持 glob，写 `exclude: ["images"]`；
4. 文件名不要用 `{primary}` 由标题生成 —— slugify 会把中文整段剔除，用 `field: create` 手动填 ASCII slug；
5. 日期格式要统一，`time: false` + `yyyy-MM-dd` 最稳。

## 八、评论：暂时不开

评论一开始打算用 Waline，它能跑在 Vercel / Cloudflare Workers 上，前端 Firefly 原生支持（`commentConfig.type = "waline"`）。但评论系统需要独立后端、数据库和管理员初始化，属于「要长期维护」的组件。

所以当前决定：**先关评论**（`commentConfig.type = "none"`，留言板页面同时关闭），把内容写起来更重要。等真的有人看、有互动需求了，再按「Workers + D1」把 Waline 接上，前端只需要填一个 `serverURL`。

## 九、踩坑汇总

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| `dev` 启动失败，`CannotFetchFontFile` | 字体走 jsDelivr，网络不可达 | 换 `google` provider，删掉 demo 日文字体 |
| `[WARN] No data found for font family JetBrains Mono` | 该字体没有对应子集数据 | 仅告警，不影响构建，后续按需改用 `npm` provider |
| `restart` 报「另一个 command 进程正在运行」 | 锁未在 stop 与 start 之间释放 | restart 中显式释放锁 |
| `stop` 后 `lsof -ti:4321` 仍有输出 | 这是浏览器到端口的**客户端**连接，不是监听 | 检查要加 `-sTCP:LISTEN` |
| 构建耗时偏长（约 105 秒） | 字体子集化 + Pagefind 索引 | 本地可接受，Pages 免费额度内没问题 |

## 接下来

- 补一个自己的头像和 favicon，现在还是模板自带的；
- 把 Pages CMS 的后台接上，手机上也能发文章；
- 需要互动时再启评论；
- 域名已经指向 `www.liveroom.dpdns.org`，HTTPS 由 Cloudflare 自动签发。

> 本文记录的是本站真实搭建过程，涉及的工具与版本均可在 `package.json` 中核对。
