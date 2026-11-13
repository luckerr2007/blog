# 写作规范

## 一、新建文章

### 方式 A：命令行（推荐，本地）

```bash
pnpm new-post 博客指南/如何写好一篇技术笔记
```

脚本会做三件事：把中文文件名转成拼音 slug、按当前日期填充 frontmatter、写入 `src/content/posts/`。

### 方式 B：Pages CMS 后台

打开 https://app.pagescms.org → 选择本仓库 → 📝 文章 → 新建。
**文件名必须手填 ASCII slug**（如 `how-this-blog-was-built`），因为后台的 slugify 会把中文整段剔除。

## 二、Frontmatter 全字段

```yaml
---
title: 标题                        # 必填
published: 2026-11-13              # 必填，YYYY-MM-DD（不要带时分秒）
updated: 2026-11-20                # 可选，更新日期
description: 60-120 字摘要          # 建议必填，用于列表与 SEO
image: ./cover.webp                # 可选，封面图；相对文章目录或完整 URL
tags: [Astro, Cloudflare]          # 可选，标签数组
category: 博客指南                  # 可选，分类（同一分类会自动聚合）
draft: false                       # true = 草稿，不参与构建
pinned: false                      # true = 置顶
lang: zh-CN                        # 仅当本文语言与站点语言不同时填写
author: 桃苏                        # 可选，默认取站点作者
comment: false                     # 评论关闭期间无效果，保留字段
password: ""                       # 可选，设置后文章加密
passwordHint: ""                   # 可选，密码提示
series: "建站手记"                  # 可选，系列名
seriesOrder: 1                     # 可选，系列内序号
sourceLink: ""                     # 可选，转载来源
licenseName: "CC BY-NC-SA 4.0"     # 可选，覆盖站点许可证
licenseUrl: "https://..."          # 可选
---
```

> `prevTitle` / `prevSlug` / `nextTitle` / `nextSlug` 是主题内部字段，不要手写。

## 三、目录与图片约定

```
src/content/posts/
├── guide/
│   └── how-this-blog-was-built.md      # 分类目录 + ASCII slug
└── images/
    └── how-this-blog-was-built/        # 该文章的配图
        ├── step-1.webp
        └── cover.webp
```

- 文章路径决定 URL：`src/content/posts/guide/xxx.md` → `/posts/guide/xxx/`
- 图片放 `src/content/posts/images/<slug>/`，正文里写 `![](./images/<slug>/step-1.webp)`（相对文章文件）
- 图片优先 WebP/AVIF，单张 ≤ 300KB，长图先压缩再入库

## 四、其他内容类型

| 类型 | 目录 | 说明 |
| --- | --- | --- |
| 动态 | `src/content/dynamic/*.md` | `published` 含时分秒；`pnpm new-d 今天...` 快速创建 |
| 项目 | `src/content/projects/*.md` | 项目页当前关闭，文件保留即可 |
| 静态页 | `src/content/spec/*.md` | 如「关于」，无 frontmatter，正文即内容 |

## 五、发布流程

1. 本地 `./command start` 预览（端口 4321）；
2. 写完 `./command build` 确认构建通过（约 100 秒）；
3. `git add -A && git commit -m "post: 文章标题" && git push`；
4. Cloudflare Pages 自动构建并上线（约 3-5 分钟）；
5. 用手机访问线上域名复查一遍移动端排版。

## 六、Markdown 扩展

主题支持：Admonitions、GitHub 仓库卡片、Expressive Code 代码块（含折叠/行号）、Mermaid、PlantUML、KaTeX 公式、代码分组 Tab。用法见归档目录 `src/content/_archive/posts/` 里的示例文章。

## 七、命名与提交信息

- 文件名：小写英文 + 连字符，不加日期前缀也行，但同一分类内保持风格一致；
- 提交信息沿用 Conventional Commits：`post: 新增 xxx`、`fix: 修正 xxx 表述`、`chore: 升级依赖`。
