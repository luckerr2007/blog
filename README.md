# 桃苏的博客

基于 [Firefly](https://github.com/CuteLeaf/Firefly)（v6.16.9，MIT）二次开发的个人博客，使用 Astro 静态生成，部署在 Cloudflare Pages。

- 线上站点：https://www.liveroom.dpdns.org
- 代码仓库：https://github.com/luckerr2007/blog

## 快速开始

```bash
# 环境：Node >= 22.23.0、pnpm 11.22.0（仓库 .nvmrc 已锁定 Node 22）
nvm use && corepack enable

# 一键启动（自动装依赖 → 起服务 → 健康检查 → 开浏览器）
./command start

# 一键关闭（杀进程组 + 释放端口）
./command stop
```

脚本完整用法：

| 命令 | 作用 |
| --- | --- |
| `./command start` | 启动开发服务器（默认 `http://127.0.0.1:4321`） |
| `./command stop` | 停止并释放端口 |
| `./command restart` | 重启 |
| `./command status` | 查看状态 |
| `./command logs -f` | 实时日志 |
| `./command build` | 生产构建（与 Cloudflare Pages 同一条命令） |
| `./command preview` | 本地预览 `dist/` |
| `./command help` | 帮助 |

可覆盖的变量：`PORT`、`HOST`、`START_TIMEOUT`。

## 文档

| 文档 | 内容 |
| --- | --- |
| [PRD.md](./PRD.md) | 需求与技术方案（含验收标准、风险） |
| [docs/WRITING.md](./docs/WRITING.md) | 写作规范、frontmatter 全字段、发布流程 |
| [docs/OPERATIONS.md](./docs/OPERATIONS.md) | 启停脚本、构建、Cloudflare Pages 部署与回滚 |
| [docs/PAGES_CMS.md](./docs/PAGES_CMS.md) | Pages CMS 后台接入与字段对照 |
| [docs/CUSTOMIZATION.md](./docs/CUSTOMIZATION.md) | 相对上游模板的全部改动 |

## 目录速览

```
command              # 一键启停脚本
.pages.yml           # Pages CMS 内容模型
public/_headers      # Cloudflare Pages 响应头
src/config/          # 站点配置（标题、导航、页脚、字体…）
src/content/posts/   # 文章
src/content/_archive/# 模板示例内容（不参与构建）
docs/                # 项目文档
.run/                # 运行时 pid/日志（git 忽略）
```

## 当前状态

| 项 | 状态 |
| --- | --- |
| 本地开发 / 构建 | ✅ 通过（`pnpm check` 0 error，构建约 100 秒） |
| 一键脚本 | ✅ 全部子命令实测通过 |
| 看板娘 / 音乐播放器 | ⛔ 已关闭 |
| 评论区 | ⏸ 暂停（`commentConfig.type = "none"`），需要时接 Waline |
| Pages CMS | 🧩 配置已就绪（`.pages.yml`），需在 app.pagescms.org 授权接入 |
| Cloudflare Pages | 🚀 待接入仓库并绑定域名 |

## 致谢

- 主题：[Firefly](https://github.com/CuteLeaf/Firefly) by CuteLeaf
- 上游模板：[Fuwari](https://github.com/saicaca/fuwari) by saicaca

主题采用 MIT 协议，本项目保留原始 `LICENSE` 与版权声明。若你要参考本项目的组件设计，请同样注明来自 Firefly。
