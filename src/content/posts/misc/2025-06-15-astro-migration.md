---
title: 把博客从 Hugo 搬到 Astro
published: 2025-06-15
description: Hugo 很快，但我想在文章里放一点交互。迁到 Astro 之后，构建变慢了，维护反而简单了。
tags: [Astro, Hugo, 建站, 博客]
category: 博客指南
comment: false
---

> 旧文存档：写于 2025 年 6 月，当时用的是 Astro 5，现在的版本和配置已经不同。

这个博客从 2022 年开始用 Hugo，一直没出过大问题。真正让我想换的是两件事：一是想在文章里放一些可交互的小组件，Hugo 的 shortcode 写起来别扭；二是主题改到后面，Go template 的嵌套越来越难读。

Astro 的好处是组件模型眼熟。文章用 Markdown 或 MDX，页面用 `.astro`，需要交互的地方挂一个 Svelte 或 React island，不需要的地方仍然是静态 HTML。内容集合（content collections）还能在构建时校验 frontmatter，比以前靠约定靠谱。

迁移大概分四步：

1. 把 `content/posts` 原样搬过去，统一 frontmatter 字段；
2. 重写列表、文章、标签和归档模板；
3. 补 RSS、sitemap、404 和重定向；
4. 用 Pagefind 替换原来的搜索。

听起来不复杂，实际花时间的都是边角：日期格式、图片路径、代码块高亮、旧链接的 301。Hugo 的 URL 是 `/posts/foo/`，Astro 按文件路径生成，稍不注意就变成 `/posts/2025/foo/`。最后在 `astro.config` 里固定了 `trailingSlash`，又补了一份 `_redirects`。

构建速度确实慢了。Hugo 全站构建不到一秒，Astro 要十几秒，图片多的时候更久。但 Astro 的增量构建和缓存做得不错，日常写文章感知不强。

值不值得换，取决于你更在意什么。想要极致构建速度，Hugo 仍然很好；想要组件化和更自由的前端表达，Astro 更合适。对我来说，这次迁移换来的是“以后想加东西时不用先跟模板搏斗”。
