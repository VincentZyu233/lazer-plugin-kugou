# Lazer Kugou Music Plugin (酷狗音乐插件)

专为 [Lazer](https://github.com/chuxuehaocai/Lazer) 现代跨平台音乐播放器打造的**酷狗音乐（KuGou Music）官方/第三方 Lua Gateway 扩展插件**。

---

## 特性亮点

- **全能力支持**：
  - **歌曲搜索**：单曲、专辑、歌手多维度搜索与纠错。
  - **高品质音频流**：支持 V5 接口动态解析，标准码率至无损 FLAC 智能降级回退。
  - **同步歌词**：支持标准 LRC 歌词抓取与精确时间轴同步。
  - **双重登录**：支持酷狗音乐手机 App **Web 扫码登录**与**手机短信验证码登录**。
  - **个性化推荐**：支持每日推荐歌曲（`homeFeed`）、发现歌单广场与排行榜。
  - **收藏同步**：支持同步云端红心收藏列表。
- **轻量独立**：纯 Lua 实现，无额外原生动态库依赖，打包体积仅几十 KB。

---

## 安装使用指南

### 方法一：通过 ZIP 导入（最简单）

1. 前往本仓库的 [Releases](../../releases) 页面，下载最新的 `lazer.kugou.zip`。
2. 打开 **Lazer** 播放器，进入 **设置 -> 插件管理**。
3. 点击 **导入 ZIP 插件**，选择下载好的 `lazer.kugou.zip`。
4. 启用插件后，在播放器音源切换列表即可选择 **酷狗音乐**！

### 方法二：通过插件市场源自动更新

在 Lazer 插件源中添加本仓库或官方市场源，即可在内置插件市场一键安装与无感热更新。

---

## 本地构建与打包

项目内置了 Node.js 一键校验与打包脚本：

```bash
# 校验清单并打包为 dist/lazer.kugou.zip，同时输出 SHA-256 和 plugins.json 片段
node tools/build.js
```

---

## 鸣谢与致敬

- [chuxuehaocai/Lazer](https://github.com/chuxuehaocai/Lazer) - 优雅而纯粹的手工打造跨平台音乐播放器。
- [Linsxyx/KugouMusic.NET](https://github.com/Linsxyx/KugouMusic.NET) - 极其规范、完善的开源酷狗音乐客户端与协议逆向实现，为本项目提供了坚实的协议基础。

---

## 许可证

本项目遵循 MIT 协议开源。仅供技术学习与交流使用，音频版权归酷狗音乐及相关版权方所有。
