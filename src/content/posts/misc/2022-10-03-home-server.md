---
title: 把吃灰的旧笔记本装成 Ubuntu 服务器
published: 2022-10-03
description: 一台 2016 年的 ThinkPad，装 Ubuntu Server 22.04，跑 Docker、Samba 和下载任务，顺便当备份盘。
tags: [折腾, 家庭服务器, Ubuntu]
category: 折腾
comment: false
---

> 旧文存档：写于 2022 年 10 月，硬件和网络信息已做模糊处理。

家里有一台 2016 年的 ThinkPad，i5-6200U、8GB 内存、256GB SSD，屏幕早就花了，卖也卖不了几个钱。周末把它装成 Ubuntu Server 22.04，放在书柜底层当小服务器。

安装过程没什么好写的，U 盘启动、最小化安装、开 SSH。真正花时间的是后面几件事。

**固定地址。** 路由器里给有线网卡绑了 MAC，避免每次重启后地址变化。Wi-Fi 直接不用，2.4G 在这台机器上很不稳定，插网线省心。

**关盖不休眠。** 改 `/etc/systemd/logind.conf` 的 `HandleLidSwitch`，再把电源计划调成性能优先。机器放在角落，风扇偶尔会响，但温度还能接受。

**Docker。** 装了 Docker Engine，跑 Samba、qBittorrent 和一个定时备份脚本。没有用 Portainer，`docker compose` 已经够用。

**Samba。** 只开给局域网，用户名密码单独设置，没有开匿名。共享目录按“下载、归档、备份”分开，权限尽量收紧。

**备份。** 每周把重要目录 rsync 到一块外接硬盘，脚本写在 cron 里。没有做 RAID，也没有 UPS，重要数据还是留一份在云上。

这套东西谈不上 NAS，只能说把闲置硬件利用起来了。稳定运行了一个月，最大的问题是 SSD 容量太小，下载多了要记得清理。
