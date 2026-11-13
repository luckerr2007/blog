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
- `site_url` → `https://www.liveroom.dpdns.org`
- `description` / `keywords` → 个人站表述
- `navbar.title` → 桃苏的博客；`navbar.logo` 改为图标 `fa7-solid:seedling`（不再依赖模板的 firefly-*.png）
- `siteStartDate` → `2026-11-13`
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
| 新动态 | `src/content/dynamic/2026-11-13-213000.md` |
| 关于页 | `src/content/spec/about.md` 重写为桃苏版本 |
| 项目占位 | `src/content/projects/liveroom-blog.md`（项目页关闭，仅消除 glob loader 空目录告警） |
| 静态页归档 | `friends.mdx`、`guestbook.md` → `_archive/spec/` |

## 四、未改动但需知道的点

- `astro.config.mjs`：未改。`base: "/"` 直接适配 Cloudflare Pages 根路径；`adapter` 仅在 `CF_WORKERS` 存在时启用
- `.github/workflows/deploy.yml`：保留（当前不用 GitHub Pages，留着做构建体检；确认不需要后可删）
- `vercel.json`：保留但 Cloudflare Pages 不读取，实际生效的是 `public/_headers`
- `wrangler.jsonc`：保留（仅在使用 Workers 适配器时才相关）
- `CLAUDE.md` / `AGENTS.md`：上游的 AI 协作说明，可按需删除

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
