# Waline 评论后端

博客的评论后端运行在 Cloudflare Workers + D1 上，前端通过 `@waline/client` 接入。

## 地址

| 项 | 值 |
| --- | --- |
| 服务地址 | `https://waline.taosu.dpdns.org` |
| 管理面板 | `https://waline.taosu.dpdns.org/ui` |
| Worker | `waline` |
| D1 数据库 | `waline-db` |
| D1 ID | `9149cb45-64b9-4b38-b264-3e0b69232aa7` |
| 源码目录 | `~/Documents/项目/dev/waline` |
| 上游项目 | [lsy-404/Waline_On_Worker](https://github.com/lsy-404/Waline_On_Worker)（GPL-3.0） |

管理员账号在 `~/.waline-admin`（权限 `0600`）。首次登录后请尽快在 `/ui` 里修改密码和邮箱。

## 配置

`wrangler.toml` 里的公开变量：

```toml
[vars]
SITE_NAME = "桃苏的博客"
SITE_URL = "https://www.taosu.dpdns.org"
SECURE_DOMAINS = "www.taosu.dpdns.org,taosu.dpdns.org,127.0.0.1:4321,localhost:4321"
DISABLE_USERAGENT = "false"
DISABLE_REGION = "false"
LEVELS = "1,5,10,20,50"
```

`JWT_SECRET` 通过 `wrangler secret put JWT_SECRET` 保存，不写进仓库。

## 部署与更新

```bash
cd ~/Documents/项目/dev/waline
pnpm install
pnpm exec wrangler d1 execute waline-db --remote --file=./schema.sql
pnpm exec wrangler deploy
```

如果 GitHub 直连失败，可以用 `api.github.com` 下载 tarball，或临时用 deploy key 通过 `ssh.github.com:443` 更新。

## 备份

```bash
cd ~/Documents/项目/dev/waline
pnpm exec wrangler d1 export waline-db --remote --output=backup.sql
```

## 已知边界

- 该 Worker 实现了评论、用户、审核、反垃圾、导入导出和管理面板，但 **SMTP 邮件通知、Turnstile 服务端校验、上游 `COMMENT_AUDIT` 变量尚未接入**。
- 反垃圾在管理面板的自定义设置页配置。
- 前端不显示登录入口，只允许匿名评论；管理员仍通过 `/ui` 登录。实现方式是保留 Waline 的 `login: "enable"` 以显示昵称/邮箱字段，在 `Waline.astro` 中用 CSS 隐藏登录按钮。
- 删除 D1 数据库会丢失全部评论，操作前先导出 `backup.sql`。

## 本地修改

`src/index.ts` 的 CORS 判断把 `Origin` 归一化成 host 后再与 `SECURE_DOMAINS` 比较。上游原实现直接用完整 origin（`https://www.example.com`）和配置项（`www.example.com`）比较，导致跨域请求全部失败。更新上游代码时需要保留这处修改。

`SECURE_DOMAINS` 使用不带协议的 host，例如：

```toml
SECURE_DOMAINS = "www.taosu.dpdns.org,taosu.dpdns.org,127.0.0.1:4321,localhost:4321"
```
