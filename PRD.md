# 个人博客系统 PRD（基于 Firefly 二次开发）

| 项目 | 内容 |
| --- | --- |
| 文档版本 | v1.2（决策落定，M1–M3 已实施，M4 待接入 Cloudflare） |
| 编写日期 | 2026-11-13 |
| 作者 / 站点主人 | 桃苏 |
| 目标仓库 | https://github.com/luckerr2007/blog（已公开） |
| 基线模板 | [CuteLeaf/Firefly](https://github.com/CuteLeaf/Firefly) v6.16.9（commit `994c0b8`，MIT） |
| 部署平台 | **Cloudflare Pages**（静态站点，根路径部署） |
| 评论系统 | **本期暂停**（`type: "none"`）；后续可选 Waline |
| 内容后台 | **Pages CMS**（`app.pagescms.org` + 仓库内 `.pages.yml`） |
| 线上域名 | **https://www.taosu.dpdns.org** |
| 当前进度 | M1 ✅ / M2 ✅ / M3 ✅ / M4 ✅ **已上线 Cloudflare Workers**（`www.taosu.dpdns.org`） |
| 本地工作目录 | `/Users/luckerr/Documents/项目/dev/blog` |

---

## 1. 背景与目标

### 1.1 背景
- 仓库 `luckerr2007/blog` 已创建但**为空**（`git ls-remote` 无任何引用），需从模板落地完整源码并做首个提交。
- Firefly 是基于 Astro 7 + Svelte 5 + Tailwind 4 的静态博客模板（衍生于 Fuwari），原生支持 Waline 评论、i18n、Pagefind 搜索。
- 需求链路：**本地跑通 → 根目录一键启停脚本 → 二次开发（含 Pages CMS 后台）→ 部署 Cloudflare Pages 上线**。

### 1.2 目标
1. **G1**：本地 `blog/` 得到可运行、可构建的博客源码，开发地址 `http://localhost:4321`。
2. **G2**：根目录 `command` 脚本一键「启动 / 关闭 / 重启 / 状态 / 日志 / 构建」。
3. **G3**：完成有边界的二次开发：桃苏站点身份、关闭看板娘与音乐播放器、Waline 评论、Pages CMS 可视化后台、首篇文章。
4. **G4**：Cloudflare Pages 自动部署（Git 集成，push 即构建），自定义域名可访问、可回滚。

### 1.3 成功判断
- `./command start` 后 60 秒内看到站点；`./command stop` 后端口释放、无残留进程。
- 线上站点可访问，评论可收发，Pages CMS 改一篇文章能自动触发重建并成功上线。
- Lighthouse 移动端 Perf / A11y / SEO ≥ 90。
- 后续写作有三条路径：本地 `pnpm new-post`、Pages CMS 网页端、手机浏览器。

---

## 2. 现状与约束（已核实事实）

| 项目 | 实测结果 | 影响 |
| --- | --- | --- |
| 目标仓库 | 空仓库，无 commit / 无分支 | 需 `git init` + 首个提交，不能 `git pull` |
| Firefly 版本 | `6.16.9`，Astro `7.3.2` | 依赖冻结在 Astro 7 体系 |
| 工程栈 | Astro 7 + Svelte 5 + Tailwind 4 + TypeScript 6 + Biome | 二开按此栈实现 |
| Node / pnpm | `engines.node >= 22.23.0`、`packageManager: pnpm@11.22.0`、`preinstall` 强制 pnpm；本机 Node v26.7.0、pnpm 12.6.0 | 需锁定 Node 22 + pnpm 11.22.0（风险 R1/R3） |
| 评论系统 | `src/config/commentConfig.ts` **原生支持 `type: "waline"`**（`serverURL`/`lang`/`emoji`/`login`/`visitorCount`） | 只需配置 + 部署后端，无需改组件 |
| 看板娘 | `src/config/pioConfig.ts`：`spineModelConfig.enable`、`live2dWidgetConfig` 独立开关 | 置 false 即关闭 |
| 音乐播放器 | `src/config/musicConfig.ts` **无总开关**，由 `showInNavbar` / `showInSidebar` 控制 | 两者置 false 关闭入口与侧栏组件（需验证无脚本残留） |
| 部署路径 | `astro.config.mjs`：`site: siteConfig.site_url`、`base: "/"` | **Cloudflare Pages 根路径部署，无需改造 base**（原 GitHub Pages 项目页的 `/blog/` 子路径问题消失） |
| Astro 输出模式 | 静态输出；仅当 `CF_WORKERS` 环境变量存在时才挂 `@astrojs/cloudflare` 适配器 | Pages 静态部署**不要**设 `CF_WORKERS` |
| 缓存/安全头 | 仓库仅提供 `vercel.json`（headers），Cloudflare Pages 不读取 | 需新增 `public/_headers` 替代 |
| 构建链 | `pnpm build` = GitHub 卡片 / LQIP / VNDB 封面预生成 → `astro build --force` → 资源清理 → 字体子集化 → 内联脚本压缩 → Pagefind | 耗时长（Pages 单次构建上限 20 分钟）+ 部分步骤依赖外网 API（R2） |
| 内容模型 | `src/content.config.ts` 定义 4 个集合（posts / dynamic / projects / spec），posts 含 24 个字段 | Pages CMS 的 `.pages.yml` 必须逐字段对齐，否则「CMS 保存成功但构建失败」 |
| 文章脚本 | `scripts/new-post.js` 会把中文文件名转拼音并写入 frontmatter | Pages CMS 的 `{primary}` 会剔除中文 → 新建文件必须用 `field: create` 手动命名 |
| 许可证 | MIT，版权 `saicaca`(2024) + `CuteLeaf`(2025)，README 要求注明来源 | 必须保留 LICENSE 与致谢 |

---

## 3. 范围

### 3.1 In Scope
- 模板落地、依赖安装、本地 dev/build 跑通。
- 根目录 `command` 一键启停脚本（含日志、PID、健康检查、幂等）。
- 二次开发：站点身份（桃苏）、关闭看板娘/音乐、视觉、内容骨架、Waline 评论、Pages CMS 后台配置、SEO、性能。
- Cloudflare Pages 部署（Git 集成 + 自定义域名 + 环境变量 + `_headers`）。
- 首篇文章《重建这个博客：从选型到上线》成稿发布。
- 文档：`README.md`（个人使用说明）、`docs/WRITING.md`、`docs/OPERATIONS.md`、`docs/CUSTOMIZATION.md`。

### 3.2 Out of Scope
- 自研后端 / 自研 CMS / 数据库管理界面。
- 用户注册登录体系、多作者协作、付费会员、邮件订阅。
- 移动端 App / 小程序。
- 全站多语言内容翻译（仅保证 UI i18n 正常）。
- 整套设计系统重画（只做主题化定制与必要组件调整）。
- Waline 的高级插件与反垃圾深度调优（仅做基础可用 + 安全项）。

---

## 4. 已确认决策（v1.2）

| ID | 决策点 | 确认结果 | 落地位置 |
| --- | --- | --- | --- |
| D1 | 部署平台 | **Cloudflare Pages**，静态输出，`base: "/"` 不变，域名 `https://www.taosu.dpdns.org` | Cloudflare 控制台 Git 集成 + `siteConfig.site_url` |
| D2 | 主分支 / 仓库 | `luckerr2007/blog`，`master` | Git / Cloudflare 构建分支 |
| D3 | 评论系统 | **本期暂停**：`commentConfig.type = "none"`，留言板页面关闭；Waline 作为后续启用方案 | `src/config/commentConfig.ts`、`siteConfig.ts#pages.guestbook` |
| D4 | 统计 | 暂不启用（预留 `analyticsConfig.ts`） | 二开阶段按需 |
| D5 | 看板娘 / 音乐播放器 | **全部关闭** | `pioConfig.ts`（spine + live2d 双开关）、`musicConfig.ts`（`showInNavbar`/`showInSidebar` = false） |
| D6 | 首批文章 | **1 篇：《重建这个博客：从选型到上线》**（完整记录选型→本地→二开→Waline→Pages CMS→Cloudflare Pages） | `src/content/posts/` |
| D7 | 站点语言 | `zh_CN` 单语 | `siteConfig.ts` |
| D8 | 模板示例内容 | 归档到 `src/content/_archive/`，不参与构建 | 内容目录 |
| D9 | 作者署名 | **桃苏**（站点标题 / profile / 页脚 / 文章默认 `author`） | `siteConfig.ts`、`profileConfig.ts`、`FooterConfig.html`、`.pages.yml` 默认值 |
| D10 | 内容后台 | **Pages CMS**（GitHub App + `.pages.yml`） | 仓库根 `.pages.yml` |

### 4.1 已确认的补充信息（v1.2）

| 编号 | 事项 | 确认结果 | 对实现的影响 |
| --- | --- | --- | --- |
| Q1 | 最终域名 | **`www.taosu.dpdns.org`** | 已写入 `siteConfig.site_url`；sitemap / RSS / OG / canonical 全部据此生成 |
| Q2 | Waline 后端 | **本期不做**（评论暂停） | 前端维持 `type: "none"`，不引入后端依赖 |
| Q3 | 仓库可见性 | **Public** | Pages CMS 的 GitHub App 可正常授权 |
| Q4 | GitHub Actions | **保留 `deploy.yml`** | 不作为部署主链路（主链路是 Cloudflare Pages Git 集成），保留作构建体检 |

---

## 5. 功能需求

### 5.1 M1：本地部署落地（P0）

| 编号 | 需求 | 验收 |
| --- | --- | --- |
| F1.1 | Firefly v6.16.9 源码落入 `blog/`，**剥离上游 git 历史**，`git init` 并关联目标仓库 | `git remote -v` 指向 `luckerr2007/blog` |
| F1.2 | 保留 `LICENSE`（MIT + 原版权），README 保留 Firefly / Fuwari 致谢 | 可检索到 `CuteLeaf`、`saicaca` |
| F1.3 | pnpm 11.22.0 安装依赖，提交 `pnpm-lock.yaml` | `pnpm install` 退出码 0 |
| F1.4 | `pnpm dev` 启动，`http://localhost:4321` 返回 200 | 首页可见 |
| F1.5 | `pnpm build` 产出 `dist/`，`pnpm preview` 可预览且无 404 资源 | `dist/index.html` 存在 |
| F1.6 | 新增 `.nvmrc`（22）、`.gitignore` 增补 `.run/`、`.env` | 文件就位 |

### 5.2 M2：一键启停脚本（P0）

**交付物**：根目录 `command`（Bash，可执行，`#!/usr/bin/env bash`）。

| 命令 | 行为 | 成功输出 |
| --- | --- | --- |
| `./command start`（默认） | 自检 → 按需安装依赖 → 后台 `pnpm dev --port 4321 --host 127.0.0.1` → 健康检查 → 打开浏览器 | `✅ 已启动: http://localhost:4321（PID xxx，日志 .run/dev.log）` |
| `./command stop` | 读 `.run/dev.pid` → 杀进程组 → 兜底按端口清理 → 删 pid | `✅ 已停止，端口 4321 已释放` |
| `./command restart` | stop → start | 同上 |
| `./command status` | 进程存活 + 端口占用 + HTTP 状态码 | `运行中 / 未运行` |
| `./command logs [-f]` | 输出 `.run/dev.log` 末 100 行，`-f` 跟随 | — |
| `./command build` | 前台构建，输出耗时与 `dist` 体积（与 Cloudflare 构建一致性检查） | `✅ 构建完成，dist x.x MB` |
| `./command preview` | 构建后 `astro preview`，复用启停逻辑 | 预览地址 |
| `./command install` | `pnpm install --force` | 成功提示 |
| `./command help` | 中文帮助 | — |

**实现要求（逐条可测）**
1. 环境自检：Node ≥ 22.23.0、pnpm 存在（缺失时提示 `corepack enable` / `npm i -g pnpm@11.22.0` 并退出）。
2. 幂等：运行中再次 `start` 只提示并打开浏览器，不起第二个进程。
3. 并发安全：`.run/command.lock` 原子锁。
4. 健康检查：最长 60 秒轮询 `/`；失败打印日志尾 30 行并清理进程。
5. 进程清理：优先 `kill -TERM -PGID`，3 秒后 `SIGKILL`；兜底 `lsof -ti:4321`。
6. 日志轮转：`.run/dev.log` 与 `.run/dev.log.1`。
7. `.run/` 自动创建并写入 `.gitignore`。
8. macOS/Linux 必须通过；Git Bash 可用；原生 PowerShell 版为 P2。
9. 中文彩色提示，退出码语义正确（0 成功 / 1 失败）。
10. 端口、主机可用 `PORT` / `HOST` 环境变量覆盖。

### 5.3 M3：二次开发（P0）

#### M3-1 站点身份：桃苏（P0）
- `src/config/siteConfig.ts`：`title`（如「桃苏的博客」）、`subtitle`、`site_url`（Q1 域名）、`description`、`keywords`、`themeColor`、favicon；`pages` 中 `bilibili/bangumi/vndb/mal` 保持 false。
- `src/config/profileConfig.ts`：`name: "桃苏"`、`bio`、头像（替换 `assets/images/avatar.avif`）、社交链接（GitHub / Email / RSS）。
- `src/config/navBarConfig.ts`：首页 / 文章归档 / 标签 / 关于 / 友链（无内容入口先移除）。
- `src/config/FooterConfig.html`：`© 2025 桃苏` + 备案占位 + 「Powered by Astro & Firefly」。
- `src/config/licenseConfig.ts`：保留 CC BY-NC-SA 4.0（可按需改）。

#### M3-2 关闭看板娘与音乐播放器（P0）
- `pioConfig.ts`：`spineModelConfig.enable = false`；`live2dWidgetConfig` 的启用开关一并置 false。
- `musicConfig.ts`：`showInNavbar = false`、`showInSidebar = false`（模板无总开关）。
- 验收：构建产物中不再请求 Live2D/Spine 模型与音乐资源；首页 JS 体积较模板基线下降；导航栏无音乐入口、侧栏无播放器。

#### M3-3 视觉与内容骨架（P0）
- 壁纸：横幅模式 + 轻量 WebP（≤ 300KB），保留纯色降级。
- 示例内容（`posts/*` demo、`dynamic/*`、`projects/*`）移入 `src/content/_archive/`，不参与构建。
- 目录约定：`src/content/posts/<category>/<slug>.md`，配图 `src/content/posts/images/<slug>/`。
- 移动端 375px 无横向溢出；暗色模式正常。

#### M3-4 首篇文章《重建这个博客：从选型到上线》（P0）
必含章节（也是交付文档）：
1. 为什么选 Firefly（Astro 静态生成、性能、可定制）。
2. 本地环境准备（Node 22、pnpm 11.22.0、克隆与安装）。
3. 一键脚本 `./command start|stop` 的用法与原理（PID、日志、健康检查）。
4. 二次开发要点：桃苏站点信息、关闭看板娘/音乐、主题色与壁纸。
5. Waline 评论部署与接入（`serverURL`、`login`、`visitorCount`、表情包、反垃圾基础项）。
6. Pages CMS 接入：`.pages.yml` 结构、GitHub App 授权、字段与 zod schema 对齐的坑。
7. Cloudflare Pages 部署：构建命令、输出目录、`NODE_VERSION`、自定义域名、`_headers`。
8. 踩坑记录（pnpm 版本、date 字段格式、中文文件名、base 与绝对链接）。
- frontmatter：`category: 博客指南`、`tags: [Astro, Firefly, Cloudflare Pages, Waline, Pages CMS]`、`draft: false`、`pinned: true`。

#### M3-5 评论：本期暂停（P1 后续）

- 决策：**暂时关闭评论区**，`commentConfig.ts` 保持 `type: "none"`，`siteConfig.pages.guestbook = false`。
- 后续启用路径（已写入 `docs/OPERATIONS.md`）：部署 Waline 后端（Cloudflare Workers + D1 或 Vercel 一键模板）→ 配置 `SERVER_URL` / `SITE_NAME` / `SITE_URL` / `SECURE_DOMAINS` → 前端把 `type` 改为 `"waline"` 并填 `waline.serverURL` → 重新打开留言板页面开关。
- 验收（启用时）：发表评论 → 后台可见 → 前端刷新可见；后端不可达时页面不报错。

#### M3-6 Pages CMS 后台（P0，配置已完成，待账号授权）
- 仓库根新增 `.pages.yml`：
  - `media`：`public/assets` → `/assets`（站点图片）；`src/content/posts/images`（文章配图，验证 Astro 能否解析）。
  - `content` 集合：
    - `posts`（`src/content/posts`，`yaml-frontmatter`，`filename.field: create`）：`title`(string, required)、`published`(date, `time:false`, `yyyy-MM-dd`)、`description`(text)、`image`(string)、`tags`(list, creatable)、`category`(string)、`draft`(boolean)、`pinned`(boolean)、`comment`(boolean)、`series`(string)、`seriesOrder`(number)、`body`(rich-text, required)；**`exclude: ["images"]`**（精确名，非 glob）。
    - 隐藏字段（`hidden: true`，防止 CMS 重写时丢弃）：`author`、`lang`、`sourceLink`、`licenseName`、`licenseUrl`、`password`、`passwordHint`、`prevTitle`、`prevSlug`、`nextTitle`、`nextSlug`。
    - `dynamic`（`src/content/dynamic`）：`published`(date, `time:true`)、`pinned`、`location`、`body`。
    - `projects`（`src/content/projects`）：`title`、`published`、`draft`、`order`、`description`、`image`、`tags`、`status`、`body`。
    - `spec`（`src/content/spec`，如「关于」页）：仅 `body`。
- 接入步骤：`app.pagescms.org` GitHub 登录 → 安装 GitHub App（仅选定仓库）→ 连接现有仓库（**不是**「从模板创建」）→ 选 `master` 分支。
- 验收（冒烟测试）：改一篇文章标题保存 → Cloudflare Pages 自动重建成功 → 线上生效 → `git pull` 检查 frontmatter 无字段丢失、无格式错乱。

#### M3-7 SEO 与质量门禁（P0）
- `site_url` 为线上域名；`sitemap-index.xml`、`rss.xml`、`robots.txt`、OG 图 URL 均可访问。
- 每篇文章 `description` 非空；校验 `title` / `canonical` / `og:*` / `twitter:card`。
- `pnpm check` 零 error；`pnpm lint`（Biome）通过。
- Lighthouse 移动端：Perf ≥ 90、A11y ≥ 90、BP ≥ 90、SEO ≥ 90。
- 密码文章与草稿不出现在 Pagefind 索引与 sitemap 中。

### 5.4 M4：Cloudflare Pages 上线（P0）

| 编号 | 需求 | 验收 |
| --- | --- | --- |
| F4.1 | 首个提交推送到 `master`（含源码、lockfile、`.pages.yml`、`.nvmrc`） | 远端文件树完整 |
| F4.2 | Cloudflare Pages 新建项目，连接 GitHub 仓库；Framework preset `Astro`、Build command `pnpm run build`、Output `dist`、Root `/` | 首次构建成功 |
| F4.3 | 环境变量：`NODE_VERSION=22`（必要时补 `PNPM_VERSION=11.22.0`）；构建日志确认 pnpm 版本为 11.22.0 | 日志可证明 |
| F4.4 | **不设置 `CF_WORKERS`**（避免挂 Cloudflare 适配器，保持纯静态） | 产物为静态 HTML |
| F4.5 | 新增 `public/_headers` 替代 `vercel.json`：`/_astro/*` 长缓存不可变、全站安全响应头 | 响应头校验通过 |
| F4.6 | 绑定自定义域名（Q1），DNS 生效、HTTPS 证书签发 | 域名 200 + 有效证书 |
| F4.7 | 预览环境（非 `master` 分支 / PR）可构建，Waline `SECURE_DOMAINS` 覆盖预览域 | 预览站评论可用 |
| F4.8 | 移除冗余部署 workflow（Q4），保留质量门禁 workflow；`vercel.json` 与 `wrangler.jsonc` 处置写明（保留/删除） | 仓库无死配置 |
| F4.9 | 回滚方案：Cloudflare 控制台一键回滚到上一部署 + `git revert` 两种路径写入 `docs/OPERATIONS.md` | 文档可执行 |

---

## 6. 非功能需求

| 类别 | 要求 |
| --- | --- |
| 性能 | 首屏 LCP < 2.5s（4G 移动）、CLS < 0.1；关闭 Live2D/音乐后首页 JS 明显下降 |
| 构建 | Cloudflare Pages 单次构建 < 20 分钟（硬上限）；本地 `./command build` 记录基线耗时 |
| 可维护性 | 改动集中在 `src/config/*`、`src/styles/`、`public/`；组件改动登记 `docs/CUSTOMIZATION.md` |
| 可移植性 | 新机器 `pnpm install && ./command start` 即可复现 |
| 安全 | 不提交密钥；Waline 管理员凭据不入库；`.env` 入 gitignore；评论开启审核与限流 |
| 合规 | 保留 MIT LICENSE 与上游署名；页脚保留「Powered by Astro & Firefly」；备案位预留 |
| 可用性 | Waline 后端故障时评论区降级为空壳，不阻塞文章阅读 |
| 兼容性 | Chrome / Edge / Safari 最近两个大版本；375–1920px 无溢出 |

---

## 7. 目标目录结构

```
blog/
├── command                   # ★ 一键启停（M2）
├── .pages.yml                # ★ Pages CMS 内容模型（M3-6）
├── .nvmrc                    # Node 22
├── PRD.md
├── README.md                 # 个人使用说明 + 上游致谢
├── astro.config.mjs
├── package.json              # 可加 dev/build 便捷脚本
├── pnpm-lock.yaml
├── public/
│   ├── _headers              # ★ Cloudflare Pages 响应头
│   └── assets/               # Pages CMS 媒体库目标
├── src/
│   ├── config/               # 二开主战场（27 个配置）
│   ├── content/
│   │   ├── posts/            # 正式文章（含《重建这个博客：从选型到上线》）
│   │   ├── dynamic/  projects/  spec/
│   │   └── _archive/         # 模板示例内容（不构建）
│   └── ...
├── docs/
│   ├── WRITING.md            # 写作规范（frontmatter 全字段）
│   ├── OPERATIONS.md         # 启停 / 构建 / 部署 / 回滚 / Waline 运维
│   ├── PAGES_CMS.md          # 后台使用与 .pages.yml 字段对照表
│   └── CUSTOMIZATION.md      # 二开改动清单
└── .run/                     # 运行时 pid/log（git 忽略）
```

---

## 8. 里程碑与工期（人日，串行）

| 阶段 | 内容 | 交付 | 估算 |
| --- | --- | --- | --- |
| M0 | 决策确认（已完成 D1–D10）+ Q1–Q4 补齐 | 决策记录 | 0.3 |
| M1 | 模板落地 + 依赖 + dev/build 跑通 | 可运行源码、首个 commit | 1 |
| M2 | `command` 脚本 + 自测 | 脚本 + 说明 | 1 |
| M3a | 桃苏站点身份 / 视觉 / 关闭看板娘与音乐 | 配置改造 commit | 1 |
| M3b | 内容骨架 + 首篇文章成稿 | 文章 + WRITING.md | 1.5 |
| M3c | Waline 后端部署 + 前端接入 | 可收发评论 | 1 |
| M3d | Pages CMS `.pages.yml` + 冒烟测试 | 后台可编辑文章 | 1 |
| M3e | SEO / 性能 / 门禁 | `pnpm check` + Lighthouse 报告 | 1 |
| M4 | Cloudflare Pages 部署 + 域名 + 验收 + 回滚文档 | 线上站点 | 1 |
| — | **合计** | | **≈ 8.8 人日** |

> 检查点：M1、M2、M3b、M3c+3d、M3e、M4 各需你验收后再进入下一阶段。

---

## 9. 验收标准（DoD）

**本地**
1. 全新克隆 → `./command start` → 60 秒内 200。
2. `./command status` 的 PID/端口与 `.run/dev.pid` 一致。
3. `./command stop` 后端口 4321 无监听、无残留 `astro`/`node` 子进程。
4. 重复 `start` 不产生第二个进程。
5. `pnpm check` / `pnpm lint` 零 error；`pnpm build` 成功，`dist/` 含 `index.html`、`rss.xml`、`sitemap-index.xml`、`pagefind/`。

**二次开发**
6. 站点标题/副标题/头像/签名/页脚均为「桃苏」，`grep` 无 Firefly 默认 demo 文案与 `CuteLeaf` 示例链接残留（LICENSE 与致谢除外）。
7. 构建产物无 Live2D/Spine 模型与音乐资源请求；导航无音乐入口、侧栏无播放器。
8. 无内容页面入口已移除，直接访问返回 404。
9. 首篇文章可访问，标签/归档正确聚合；草稿与密码文章不进 sitemap 与搜索索引。
10. Waline 评论可发可读可审；后端不可达时页面不报错。
11. Pages CMS 修改文章 → 重新构建成功 → frontmatter 无损。
12. 375px 无横向滚动；暗色模式正常。

**线上**
13. 自定义域名 HTTPS 访问 200，静态资源无 404（DevTools Network）。
14. RSS / sitemap / robots / OG 图 URL 均为线上可访问且域名正确。
15. push 触发 Pages 构建成功，5–10 分钟内线上生效；控制台回滚可用。
16. LICENSE 与上游署名保留，仓库无任何密钥。

---

## 10. 风险与对策

| ID | 风险 | 影响 | 对策 |
| --- | --- | --- | --- |
| R1 | 本机 Node v26.7.0 高于模板验证版本，`sharp`/`astro` 可能异常 | 安装或构建失败 | 加 `.nvmrc`=22，`command` 启动前校验并提示 `nvm use`；Pages 侧设 `NODE_VERSION=22` |
| R2 | 构建脚本请求 GitHub / VNDB API，Pages 构建环境可能限流或超时 | 线上构建失败 | 为这些预生成脚本加开关（跳过或读缓存），Pages 环境变量关闭非必需项 |
| R3 | pnpm 版本错配（本机 12.6.0 vs 锁定 11.22.0；Pages 自动探测 pnpm） | 安装失败或 lockfile 不兼容 | 文档固定 `npm i -g pnpm@11.22.0`；首次 Pages 构建核对日志，必要时设 `PNPM_VERSION` |
| R4 | **Pages CMS 字段与 zod schema 不对齐** | CMS 保存成功但构建报错，或正文/字段被丢弃 | `.pages.yml` 逐字段对照 `content.config.ts`；必含 `body`；未编辑字段声明 `hidden: true`；`exclude: ["images"]` 用精确名 |
| R5 | Pages CMS 上传图片进 `src/` 后 Astro 解析失败 | 封面裂图 | 先验证；失败则统一走 `public/assets` + `/assets/xxx` 绝对路径 |
| R6 | Waline 后端域名 / `SECURE_DOMAINS` 配置错误 | 评论加载失败 | 站点域与预览域都加入 `SECURE_DOMAINS`；本地用 `localhost` 测试；前端加降级提示 |
| R7 | Waline 免费额度/冷启动、国内访问速度 | 评论加载慢 | Workers 方案配额足；必要时给后端绑自定义域并开缓存；前端懒加载 |
| R8 | Cloudflare Pages 单次构建 20 分钟上限 + 字体子集化耗时 | 构建超时 | 控制文章与图片体积；观察首次构建耗时，超标则对字体子集化做缓存或裁剪语种 |
| R9 | 中文文件名在 Pages CMS 被 slugify 剔除，生成 `-.md` 类空文件 | 内容混乱 | `filename.field: create` 手动输入 ASCII slug |
| R10 | 日期格式严格解析（`yyyy-MM-dd` vs 含时分秒） | 后台显示空白 | 全站统一 `YYYY-MM-DD`（动态除外，含时分秒） |
| R11 | 仓库私有导致 Pages CMS / 评论集成受限 | 后台不可用 | 建议 Public（Q3） |
| R12 | 上游署名被误删 | 违反 MIT 与社区规范 | 验收项 16 固定检查 LICENSE 与致谢 |

---

## 11. 交付物清单

1. `blog/` 完整可运行源码（`pnpm-lock.yaml`、`.nvmrc`、LICENSE 与致谢保留）。
2. 根目录 `command` 脚本 + `docs/OPERATIONS.md`。
3. 二次开发成果：桃苏站点身份、关闭看板娘/音乐、Waline 评论、`public/_headers`、SEO 与性能达标。
4. `.pages.yml` + `docs/PAGES_CMS.md`（后台使用与字段对照）。
5. 首篇文章《重建这个博客：从选型到上线》。
6. Cloudflare Pages 线上站点 + 自定义域名 + 验收记录 + 回滚步骤。
7. 本 PRD（v1.1 作为变更基线）。

---

## 12. 后续迭代（登记，不在本次范围）
- `command.cmd` / PowerShell 原生版。
- Waline 评论自动备份到 GitHub、图片上传到 Cloudflare R2 / 图床。
- Umami 或 Cloudflare Web Analytics 统计接入。
- 动态/相册自动同步（Memos、对象存储）。
- 文章定时发布与草稿预览分支。

---

## 附：变更记录
| 版本 | 日期 | 变更 |
| --- | --- | --- |
| v1.0 | 2026-11-13 | 首版：GitHub Pages + Giscus + M0–M4 |
| v1.2 | 2026-11-13 | 决策落定并进入实施：域名 `www.taosu.dpdns.org`、**评论暂停**（`type: "none"`，Waline 保留为后续方案）、仓库已 Public、保留 `.github/workflows/deploy.yml`；M1（本地部署）与 M2（`command` 脚本）已完成并实测；M3 已完成站点身份/关闭看板娘与音乐/内容骨架/首篇文章/`.pages.yml`/`public/_headers`/四份文档；修正字体 CDN 不可达问题 |
| v1.3 | 2026-11-13 | 实际上线形态修正为 **Cloudflare Workers（静态资源）**（非 Pages）：Worker 名 `blog`，`wrangler.jsonc` 补 `previews: {}`，根域与 `www` 均绑定 Custom Domain；头像与 favicon 换成自定义素材，修复页脚版权重复 |
| v1.4 | 2026-11-14 | 首页视觉与功能迭代：关闭全站壁纸背景（`mode: "none"`，纯色 + 首页 hero 卡）、新增「每日一言」（一言 API + 首页/侧边栏展示 + 本地缓存与兜底 + 换一句）、清理模板与第三方文案（公告、英文横幅、追番/游戏/MAL 配置、Giscus、友链/相册/打赏/书签示例） |
