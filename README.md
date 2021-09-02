# ehco.sh
Ehco Tunnel Manage Script / Ehco 一键管理脚本

[English Document](https://github.com/sjlleo/ehco.sh/blob/main/README.md) | [中文版说明文档](https://leo.moe/daily/ehco-Script.html)

## 更新日志

2021.09.02

之前有很多小伙伴反馈到ehco的流量记录重启就会丢失，为了解决这个问题：

本次更新尝试采用SQLite3轻量数据库（Beta特性）来保存ehco的各中转流量历史记录。

## Ehco Introduction

The `ehco` is contributed by [Ehco1996](https://github.com/Ehco1996), see the project [here](https://github.com/Ehco1996/ehco). Thanks for his excellent project.

![image](https://user-images.githubusercontent.com/13616352/127090191-18865216-46bd-4e29-9a8d-b57dfd18a118.png)

![image](https://user-images.githubusercontent.com/13616352/124421686-93d46280-dd94-11eb-85ff-348c81a58ad1.png)

## Feature

1. Support `Show/Add/Modify/Delete` Ehco Relays
2. One-Key Installation and configure Echo automatically

## TODO

- [ ] Multistage Relay List
- [X] Support stream balancing configuration

## Usage

```bash
bash <(curl -fsSL https://git.io/ehco.sh)
```

Or you can use this command for domestic server

```bash
bash <(curl -fsSL https://kea.moe/ehco.sh)
```
