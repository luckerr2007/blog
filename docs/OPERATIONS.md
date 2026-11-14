# 运维手册

## 一、环境要求

| 项 | 版本 | 说明 |
| --- | --- | --- |
| Node.js | ≥ 22.23.0（建议 22 LTS） | 仓库有 `.nvmrc`（22） |
| pnpm | 11.22.0 | `package.json` 的 `packageManager` 锁定，pnpm 会自动切换 |

首次准备：

```bash
nvm use            # 读 .nvmrc
corepack enable    # 或 npm i -g pnpm@11.22.0
```

## 二、一键脚本 `./command`

脚本位于仓库根目录，文件名就是 `command`（无扩展名，Bash 实现）。

| 命令 | 作用 |
| --- | --- |
| `./command start` | 启动开发服务器（默认 `http://127.0.0.1:4321`），等健康检查通过后自动开浏览器 |
| `./command stop` | 停止服务、清理残留进程并释放端口 |
| `./command restart` | 重启 |
| `./command status` | 查看进程 + HTTP 状态 |
| `./command logs [-f]` | 查看日志，`-f` 实时跟随 |
| `./command build` | 生产构建（与 Cloudflare Pages 用同一条命令） |
| `./command preview [--no-build]` | 构建并本地预览 `dist/`，`--no-build` 复用已有产物 |
| `./command install` | 强制重装依赖 |
| `./command help` | 帮助 |

可配置环境变量：

```bash
PORT=4322 ./command start        # 换端口
HOST=0.0.0.0 ./command start     # 局域网可访问
START_TIMEOUT=180 ./command start # 首次启动慢可加大超时
```

运行时文件（已在 `.gitignore`）：

| 文件 | 说明 |
| --- | --- |
| `.run/dev.pid` | 当前服务进程号 |
| `.run/dev.log` | 本次日志 |
| `.run/dev.log.1` | 上一次日志 |
| `.run/command.lock` | 并发锁目录，异常残留时 `rmdir .run/command.lock` |

常见问题：

| 现象 | 处理 |
| --- | --- |
| `端口 4321 已被其他进程占用` | `lsof -ti tcp:4321 \| xargs kill -9`，或 `PORT=4322 ./command start` |
| `另一个 command 进程正在运行` | 确认无进程后 `rmdir .run/command.lock` |
| 启动超时 | `./command logs` 看日志尾部；首次启动要下载字体，约 60-90 秒 |
| `CannotFetchFontFile` | 构建机访问不了字体 CDN。当前字体 provider 已改为 `google`，若再遇到换网络或改 `src/config/fontConfig.ts` |

## 三、构建与本地预览

```bash
./command build              # ≈100 秒，产物在 dist/
./command preview --no-build # 起本地静态服务，复查生产行为
```

构建链包含：GitHub 卡片数据、LQIP、字体子集化、Pagefind 索引。**Cloudflare Pages 单次构建上限 20 分钟**，当前约 2 分钟，余量充足。

## 四、Cloudflare Workers（静态资源）部署

当前实际使用 **Workers Builds**：仓库连 GitHub，构建产物作为静态资源上传到 Worker `blog`。

### 面板构建配置

| 项 | 值 |
| --- | --- |
| 构建命令 | `pnpm run build` |
| 部署命令 | `npx wrangler deploy` |
| 根目录 | `/` |
| 环境变量 | `NODE_VERSION=22` |
| **不要设置** | `CF_WORKERS`（会让 Astro 挂上 Cloudflare 适配器，静态站点不需要） |

`wrangler.jsonc` 的 `name` 必须与面板项目一致，否则会部署到另一个 Worker：

```jsonc
{
	"name": "blog",
	"compatibility_date": "2025-01-01",
	"compatibility_flags": ["nodejs_compat"],
	"assets": { "directory": "./dist" },
	"previews": {}
}
```

> `previews: {}` 不能省：wrangler 4.147 的 `wrangler preview`（预览部署）会校验该字段，缺了会直接报
> `Failed: error occurred while running deploy command`。

### 自动部署（master = 生产，推荐）

推送到 `master` 即由 GitHub Actions 构建并发布到生产，无需本地操作：

| 项 | 值 |
| --- | --- |
| workflow | `.github/workflows/deploy-cloudflare.yml`（push `master` / 手动 dispatch） |
| 流程 | `pnpm install` → `pnpm build` → `cloudflare/wrangler-action@v3` 执行 `deploy` |
| 必需 secret | `CLOUDFLARE_API_TOKEN`（Workers Scripts:Edit + 账号读权限）、`CLOUDFLARE_ACCOUNT_ID` |
| 兜底 | 未配置 secret 时只构建不发布，输出 warning，不会红叉 |
| 结果核对 | Actions 日志里的 `Current Version ID` = Cloudflare 面板 Production 版本 |

`Deploy to GitHub Pages`（`.github/workflows/deploy.yml`）已改为仅手动触发，站点不经过 Pages。

### 手动部署（本地）

```bash
./command build
CLOUDFLARE_API_TOKEN=xxx CLOUDFLARE_ACCOUNT_ID=xxx npx wrangler deploy
```

成功后会输出 `https://blog.<子域>.workers.dev` 与当前 Version ID。

### 域名

- 根域 `liveroom.dpdns.org` 与 `www.liveroom.dpdns.org` 均已绑定到 Worker `blog`（Custom Domain，HTTPS 自动签发）
- 新增域名：Workers & Pages → blog → Settings → Domains & Routes → Add → Custom domain 填域名即可
- 规范域名（canonical / sitemap / RSS）为 `https://www.liveroom.dpdns.org`，改域名时同步改 `siteConfig.site_url`

### 响应头与重定向

`public/_headers` 随 `dist` 一起上传，对 Workers 静态资源同样生效；如需重定向用 `public/_redirects`。`vercel.json` 不生效。

### 回滚

- 面板：Workers & Pages → blog → Deployments → 选上一个成功版本 → Rollback
- 代码层：`git revert <bad-commit> && git push` 触发重建

## 五、Page CMS 后台

见 [PAGES_CMS.md](./PAGES_CMS.md)。

## 六、评论系统（当前关闭）

`src/config/commentConfig.ts` 里 `type: "none"`，`siteConfig.pages.guestbook = false`。

需要开启时：

1. 部署 Waline 后端（推荐 Cloudflare Workers + D1，或 Vercel 一键模板）；
2. 设置环境变量：`SERVER_URL`、`SITE_NAME`、`SITE_URL=https://www.liveroom.dpdns.org`、`SECURE_DOMAINS`（含 `*.pages.dev` 预览域）；
3. 前端把 `type` 改成 `"waline"`，填 `waline.serverURL`；
4. 需要留言板时再把 `pages.guestbook` 打开。

## 七、日常维护

| 周期 | 事项 |
| --- | --- |
| 每次发文 | `./command build` 通过后再 push |
| 每月 | 检查 Cloudflare 部署记录与构建耗时；备份 `pnpm-lock.yaml` 变更 |
| 升级 | `pnpm update` 后在本地跑 `pnpm check` + `./command build`，再 push（Pages 会自动重建） |
| 依赖风险 | 不要随手改 `package.json` 的 `packageManager`，pnpm 版本与 lockfile 强相关 |
