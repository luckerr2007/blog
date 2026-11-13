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

## 四、Cloudflare Pages 部署

### 首次创建

1. Cloudflare Dashboard → Workers & Pages → Create → Pages → Connect to Git；
2. 选择 `luckerr2007/blog`，分支 `master`；
3. 构建配置：

   | 项 | 值 |
   | --- | --- |
   | Framework preset | Astro |
   | Build command | `pnpm run build` |
   | Build output directory | `dist` |
   | Root directory | `/` |

4. 环境变量：`NODE_VERSION=22`（如需固定 pnpm，再加 `PNPM_VERSION=11.22.0`）；
5. **不要设置 `CF_WORKERS`** —— 该变量会让 Astro 挂上 Cloudflare 适配器，静态站点不需要；
6. 保存并部署，首次构建约 2-4 分钟。

### 绑定域名

1. Pages 项目 → Custom domains → 添加 `www.liveroom.dpdns.org`；
2. 按提示在 DNS 中添加 CNAME（`www` → `<project>.pages.dev`）；
3. 等待证书签发（通常几分钟），HTTPS 自动开启；
4. 把根域 `liveroom.dpdns.org` 做 301 跳到 `www`（可选，可用 Cloudflare Redirect Rules）。

### 响应头

Cloudflare Pages **不读 `vercel.json`**，缓存与安全头写在 `public/_headers`。改完需重新部署生效。

### 回滚

- 控制台：Pages 项目 → Deployments → 找到上一个成功部署 → `Rollback`；
- 代码层：`git revert <bad-commit> && git push`，触发一次新构建。

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
