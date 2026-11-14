---
title: 改博客与发布上线：流程、命令和避坑清单
published: 2026-11-14
description: 从改配置、加文章到 Cloudflare Workers 上线与回滚，把本站的日常修改流程拆成可复现的步骤，并列出真正会让人卡住的坑。
tags: [Astro, Cloudflare Workers, 部署, 建站]
category: 博客指南
comment: false
---

搭建过程只有一次，之后全是「改一点东西，再发上去」。流程本身不复杂，坑主要集中在两个地方：**本地能跑不等于线上能跑**，以及**构建期会做很多 dev 不做的重活**。

这篇把日常修改、构建、部署和回滚串成一条可复现的路径，再把实际踩过的坑按「症状 → 原因 → 处理」列出来。搭建背景见[《这个博客是怎么搭建起来的》](/posts/guide/how-this-blog-was-built/)。

## 一、先认清改动落在哪一层

改之前先定位，能少改很多文件：

| 想改什么 | 主要位置 | 备注 |
| --- | --- | --- |
| 文章、动态、关于页 | `src/content/` | 内容与 frontmatter |
| 站点信息、导航、侧栏、主题色 | `src/config/*Config.ts` | 优先配置，不改组件 |
| 类型定义 | `src/types/` | 与 config 字段保持一一对应 |
| 全局样式、动效 token | `src/styles/` | `theme-motion.css` 管动效 |
| 页面结构与交互 | `src/components/`、`src/layouts/` | Astro + Svelte islands |
| 工具函数 | `src/utils/` | URL、日期、主题、滚动等 |
| 界面文案 | `src/i18n/` | 新增 key 要同步所有语言 |

本站的定制原则是「能改配置就不改组件」。配置入口统一从 `@/config` 导入，改完跑 `pnpm type-check`，字段拼错会直接报错。更细的二次开发记录在仓库的 `docs/CUSTOMIZATION.md`。

## 二、环境：Node 22 + pnpm，别用 npm

`package.json` 把版本钉死了：

```json
"engines": { "node": ">=22.23.0" },
"packageManager": "pnpm@11.22.0"
```

`preinstall` 里还有 `only-allow pnpm`，用 npm 或 yarn 安装会直接失败——这是故意的，避免生成第二份 lockfile。

```bash
nvm use            # 读 .nvmrc，当前是 22
corepack enable    # 或 npm i -g pnpm@11.22.0
pnpm install
```

日常命令统一走根目录的 `./command`：

| 命令 | 作用 |
| --- | --- |
| `./command start` | 起开发服务器，健康检查通过后开浏览器 |
| `./command stop` | 停服务并释放端口 |
| `./command build` | 生产构建，产物在 `dist/` |
| `./command preview` | 构建后本地预览生产产物 |
| `./command logs -f` | 跟日志 |

`start` 内部会显式传 `--host 127.0.0.1`。如果手动跑 `pnpm dev`，在部分环境下只会绑定 IPv6 回环，`127.0.0.1` 打不开，看起来像服务没起来。

## 三、发文：文件路径就是 URL

```bash
pnpm new-post guide/modify-and-deploy-the-blog
```

参数既是文件名也是目录，**用 ASCII**。脚本会把中文标题转成拼音写进 frontmatter 的 `slug`，但当前 schema 不读取这个字段，路由实际用的是文件路径（`entry.id`）。传中文路径会得到中文 URL，还会影响分享链接和 RSS。

生成后改 frontmatter：

```yaml
---
title: 改博客与发布上线：流程、命令和避坑清单
published: 2026-11-14
description: 60–120 字摘要，列表和 SEO 都会用
tags: [Astro, Cloudflare Workers, 部署]
category: 博客指南
draft: false
---
```

几个容易写错的字段：

- `published` / `updated` 写 `YYYY-MM-DD`，不要带时分秒；YAML 会把它解析成日期。
- `draft: true` 只在生产构建里隐藏；`pnpm dev` 仍然能看到，别把「本地有」当成「线上有」。
- `prevTitle` / `prevSlug` / `nextTitle` / `nextSlug` 是主题内部字段，不要手写。
- `category` 决定分类页聚合，目录只决定 URL；两者可以不同，但混用会让归档看起来别扭。
- 改文件名等于改 URL。旧链接、RSS、外部引用都会断；必须改时在 `public/_redirects` 补 301。

图片放在 `src/content/posts/images/<slug>/`，正文用相对路径引用：

```markdown
![](./images/modify-and-deploy-the-blog/step-1.webp)
```

优先 WebP/AVIF，单张控制在 300KB 以内。构建期会为本地图片生成 LQIP 占位，原图太大只会拖慢首屏，压缩不会自动救回来。

## 四、改配置：类型能兜底，语义不能

站点信息集中在 `src/config/siteConfig.ts`：

```ts
export const siteConfig: SiteConfig = {
	title: "桃苏的博客",
	subtitle: "记录技术、生活与思考",
	site_url: "https://www.liveroom.dpdns.org",
	// ...
};
```

`site_url` 不只是显示用，canonical、sitemap、RSS 和分享卡片都取它。换域名时这里、Cloudflare 的 Custom Domain、以及外部收录要一起改，否则线上会出现两套绝对 URL。

导航在 `src/config/navBarConfig.ts`。新增入口时注意 `pageKey`：页面配置里关掉的功能，导航项也不应该放出来。侧栏、字体、壁纸、评论、音乐各有独立配置，字段定义在 `src/types/`，两边对齐后再跑类型检查。

改完配置先本地确认三件事：导航能点、刷新不 404、移动端不溢出。配置错误通常不会让构建失败，只会让页面「看起来不对」。

## 五、改样式与组件：dev 通过不算数

样式入口是 `src/styles/main.css`，动效层 `theme-motion.css` 在 `Layout.astro` 里后加载。后加载且不带 `@layer` 的规则会覆盖前面的 Tailwind 工具类，改选择器前先确认层级关系，不然会出现「dev 生效、构建后被压掉」的错觉。

动效统一用 token：

```css
:root {
	--dur-2: 150ms;
	--dur-3: 180ms;
	--ease-standard: cubic-bezier(0.2, 0, 0, 1);
}
```

两个和 Tailwind 4 有关的细节：

- `-translate-y-1` 落在独立的 `translate` 属性上，过渡要写 `translate`，只写 `transform` 会出现「只淡不滑」。
- 动效只改 `transform` / `opacity`，并尊重 `prefers-reduced-motion`；加载骨架在减弱动效时应该静止。

改 Svelte 组件时注意 `client:*` 指令：`client:visible` 依赖宿主元素有尺寸，宿主高度为 0 时 IntersectionObserver 永远不触发，组件会停在加载态。交互频繁、首屏可见的组件用 `client:load` 或 `client:idle` 更稳。

## 六、本地验证分三层，各管各的

| 命令 | 能发现什么 | 发现不了什么 |
| --- | --- | --- |
| `pnpm dev` | 交互、布局、控制台报错 | 构建期生成物、Pagefind、压缩后的行为 |
| `pnpm check` + `pnpm type-check` | Astro/Svelte 模板诊断、TS 类型 | CSS、运行时逻辑、内容渲染结果 |
| `pnpm build` | frontmatter schema、MDX、CSS 导入、生成资产 | 线上缓存、域名与 DNS |

只跑 dev 最容易漏掉两类问题：**frontmatter 不合法**和**构建期资源缺失**。文章能被 dev 加载，不代表 `astro build` 能过。

生产构建不是单纯的 `astro build`，而是一串：

```text
GitHub 卡片数据 → LQIP → VNDB 封面 → astro build
→ 清理 PIO 资源 → 字体子集化 → 内联脚本压缩 → Pagefind 索引
```

所以：

- 搜索只在构建后可用。dev 里的搜索结果是写死的 mock，搜不到东西是正常的。
- 新增本地图片后要重新构建，LQIP 才会进 `src/constants/lqips.json`。
- `src/constants/lqips.json`、`src/constants/github-card-data.json` 是受版本控制的生成文件，构建可能改动它们。提交前看一遍 diff，不要无脑 `git add -A`。
- `dist/`、`.run/`、`.astro/` 都已忽略，不要提交。

## 七、部署：push master 就是生产

当前链路是 GitHub Actions 构建后用 Wrangler 发布到 Cloudflare Workers：

```text
push master → pnpm install → pnpm build → wrangler deploy
```

workflow 在 `.github/workflows/deploy-cloudflare.yml`，需要两个仓库 secret：

| Secret | 用途 |
| --- | --- |
| `CLOUDFLARE_API_TOKEN` | Workers Scripts:Edit + 账号读权限 |
| `CLOUDFLARE_ACCOUNT_ID` | 指定账号 |

没有配置 token 时 workflow 只构建、不发布，日志里是一条 warning，任务仍然是绿的。**「Actions 成功」不等于「已上线」**，要确认 `Deploy to Cloudflare Workers` 这一步真的执行了。

部署完成后核对三处：

1. Actions 日志里的 `Current Version ID`；
2. Cloudflare 面板 `Workers & Pages → blog → Deployments` 的 Production 版本；
3. 线上页面源码里的静态资源 hash 是否变化。

手动发布（本地）：

```bash
./command build
CLOUDFLARE_API_TOKEN=xxx CLOUDFLARE_ACCOUNT_ID=xxx npx wrangler deploy
```

`wrangler.jsonc` 里有三个容易出事的点：

```jsonc
{
	"name": "blog", // 必须和面板里的 Worker 同名
	"assets": { "directory": "./dist" },
	"previews": {} // 不能省，wrangler preview 会校验
}
```

另外不要给构建环境设置 `CF_WORKERS`，那会让 Astro 挂上 Cloudflare 适配器；本站是纯静态资源，不需要。

域名在 `Workers & Pages → blog → Settings → Domains & Routes` 绑定。`www` 和根域都指到同一个 Worker 时，确认 canonical 用的是 `www`，避免搜索引擎看到两份内容。

如果 Cloudflare 面板也连了 Git 自动构建，确认只保留一条发布链路，避免同一次 push 构建两次、互相覆盖版本。

## 八、上线后：缓存和移动端

- 资源 hash 变了但页面没变，先强制刷新；仍不生效再去 Cloudflare 面板 Purge Cache。
- `public/_headers` 对 `/_astro/*` 和 `/fonts/*` 设了 `immutable` 长缓存，这是安全的；但意味着旧 HTML 引用的旧资源会继续可用，排查时要看 HTML 里的 hash 而不是猜。
- `/pagefind/*` 缓存 1 天，搜索索引更新有延迟，刚发完文章搜不到不一定是指引没生成。
- 用手机实际走一遍：导航抽屉、代码块横向滚动、图片宽度、目录浮层。

`public/_headers` 和 `public/_redirects` 会随 `dist` 一起上传；仓库里的 `vercel.json` 不参与当前部署，改它不会生效。

## 九、回滚：面板快，代码才是真相

两种回滚方式，作用不同：

| 方式 | 操作 | 特点 |
| --- | --- | --- |
| 面板回滚 | Deployments → 上一个成功版本 → Rollback | 秒级恢复，但仓库代码还是坏的 |
| 代码回滚 | `git revert <bad-commit>` + push | 慢一点，但下一次发布不会再带病上线 |

只做面板回滚，下一次任何 push 都会把坏代码重新发上去。正确做法是先用面板止血，再 revert 代码。不要在 master 上 `git reset --hard` 后强推，历史会丢，CI 也会失去对照。

## 十、真正会卡住人的坑

1. **用 npm/yarn 安装**：`preinstall` 直接拦截；lockfile 也不该出现第二份。
2. **Node 版本不对**：低于 22.23 会在安装或构建阶段报奇怪的语法/依赖错误，先 `node -v`。
3. **dev server 起不来或页面不 hydrate**：端口被占、旧进程没退、或者改过依赖后 Vite 模块图坏了。`./command restart`；还不行就停掉进程重开，别在旧进程上反复热更新。
4. **草稿本地可见、线上没有**：`draft: true` 只在生产过滤，这是预期行为。
5. **dev 搜索没结果**：Pagefind 只在 build 生成，dev 是 mock。
6. **frontmatter 日期写成带时分秒**：内容 schema 校验失败，构建直接红。
7. **中文文件名**：URL 跟着变中文，脚本里的拼音 `slug` 不参与路由。新建时就用 ASCII 路径。
8. **改了文件名没做重定向**：旧链接 404，RSS 里出现重复条目。
9. **Actions 绿了但线上没变**：缺 `CLOUDFLARE_API_TOKEN`，发布步骤被跳过。
10. **Worker 名字不一致**：部署成功但发到了另一个 Worker，域名自然不更新。
11. **构建产物被提交**：`dist/` 不该进仓库；生成文件（LQIP、GitHub 卡片）要 review 后再提交。
12. **把 token 写进配置文件**：所有密钥只放 GitHub Secrets 或本地环境变量；一旦进 git 历史，删文件也没用，必须轮换。
13. **只回滚面板不改代码**：下一次 push 原地复发。
14. **随手升级大版本依赖**：Astro/Tailwind/Svelte 的破坏性变更会同时影响构建和运行时。升级后至少跑 `pnpm check`、`pnpm type-check`、`pnpm build` 三件套，再单独提交。

## 十一、发布清单

每次发文章或改代码，按这个顺序走一遍：

- [ ] `./command start`，本地看页面和交互
- [ ] `pnpm check` 与 `pnpm type-check`
- [ ] `./command build` 通过，检查生成的 `lqips.json` / `github-card-data.json` diff
- [ ] `./command preview` 复查生产产物：搜索、图片、移动端
- [ ] `git status` 只包含本次改动，没有 `dist/`、`.run/`、密钥
- [ ] commit + push master
- [ ] Actions 里 `Deploy to Cloudflare Workers` 成功，Version ID 与面板一致
- [ ] 线上强刷复查，必要时 Purge Cache

流程固定下来之后，写文章就只剩内容本身了。
