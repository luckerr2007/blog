---
title: 换到 Mac 之后，重新整理了一遍开发环境
published: 2023-08-06
updated: 2024-05-02
description: 从 Windows 迁到 Apple Silicon，记录 Homebrew、终端、编辑器和几个常用工具的配置。
tags: [macOS, 工具, 效率]
category: 工具
comment: false
---

> 旧文存档：写于 2023 年 8 月，软件版本和价格可能已经变化。

主力机从 Windows 换到 MacBook Air 之后，花了一个周末重新整理环境。不是为了折腾而折腾，主要是路径、快捷键和包管理都不一样，旧习惯直接搬过来会很难受。

**包管理。** Homebrew 装命令行工具和图形应用，尽量用 `brew bundle` 把依赖写进 `Brewfile`。Apple Silicon 的路径是 `/opt/homebrew`，有些旧脚本还写着 `/usr/local`，要改。

**终端。** iTerm2 + zsh，没有上很复杂的框架。提示符用 Starship，配置放在 dotfiles 里。常用别名不多：`gst`、`ll`、`..`，够用就行。

**编辑器。** VS Code 仍然是主力，装了主题、GitLens 和几个语言插件。JetBrains 的 IDE 只在看大项目时打开，平时启动太慢。

**窗口管理。** Rectangle 负责快捷键分屏，Raycast 替代 Spotlight，顺手管剪贴板历史。两个都是免费版就够用。

**开发环境。** Node 用 fnm 管版本，Python 用 pyenv，Docker Desktop 只在需要时启动。数据库尽量用 Docker，不往系统里装一堆服务。

迁移过程中最麻烦的是键盘。Command 和 Control 的位置换了，肌肉记忆改了差不多两周。其次是换行符和文件权限，Git 仓库里偶尔会出现整文件 diff，后来统一了 `.gitattributes` 才消停。

环境这东西很个人化，别人的清单只能当参考。真正有用的配置，都是自己遇到问题之后补上的。

---

后记（2024-05）：后来把外接显示器换成 27 寸，桌面也重新整理了一遍，写在[《重新整理书桌》](/posts/misc/2024-05-02-desk-setup/)。
