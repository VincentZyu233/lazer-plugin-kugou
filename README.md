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

## 主页八大卡片与电台接口映射 (Home Cards & Radio Architecture)

Lazer 播放器主页顶部设置了 4 个快捷推荐卡片，中下方设置了【为你创建的电台】流。除【反复聆听】由 Lazer 本地历史驱动外，其余卡片均深度对接了酷狗推荐算法与 OpenAPI。参考 [KugouMusic.NET](https://github.com/Linsxyx/KugouMusic.NET) 的接口实现映射如下：

| 卡片名称 | 位置分类 | Lazer 宿主契约 / 事件 | 酷狗后端接口端点 | 参考 `KugouMusic.NET` 源码位置 | 机制与流转说明 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **今日限定好歌**<br>*(随机发现)* | 顶部快捷卡片 #1 | `onDaily` / `homeFeed.daily`<br>`MusicCapability.recommendations` | `POST /everyday_song_recommend`<br>(路由: `everydayrec.service.kugou.com`) | [`RawDiscoveryApi.cs` (L108-L128)](https://github.com/Linsxyx/KugouMusic.NET/blob/master/src/Libraries/KuGou.Net/Protocol/Raw/RawDiscoveryApi.cs#L108-L128)<br>`GetRecommendSongAsync` | 根据已登录用户历史画像，由酷狗算法引擎动态下发 30 首私人专属日推曲目，点击打开完整虚拟歌单。 |
| **私人漫游** | 顶部快捷卡片 #2 | `onFm`<br>`activeGateway.radio(personal)` | `POST /v1/rcmd_list`<br>(路由: `fm.service.kugou.com`) | [`RawFmApi.cs` (L13-L33)](https://github.com/Linsxyx/KugouMusic.NET/blob/master/src/Libraries/KuGou.Net/Protocol/Raw/RawFmApi.cs#L13-L33)<br>`GetRecommendAsync` | 私人 FM 推荐流，根据当前听歌上下文进行不间断的智能漫游切歌。 |
| **心动模式** | 顶部快捷卡片 #3 | `onHeart`<br>`activeGateway.radio(heart)` | `POST /everyday_style_recommend`<br>(路由: `everydayrec.service.kugou.com`) | [`RawDiscoveryApi.cs` (L131-L148)](https://github.com/Linsxyx/KugouMusic.NET/blob/master/src/Libraries/KuGou.Net/Protocol/Raw/RawDiscoveryApi.cs#L131-L148)<br>`GetRecommendStyleSongAsync` | 风格雷达推荐，拉取与用户收藏偏好契合的相似风格曲目。 |
| **反复聆听** | 顶部快捷卡片 #4 | `onReplay`<br>`widget.state.playQueue(recent)` | *客户端本地回放队列* | [`home_pages.dart` (L180)](https://github.com/chuxuehaocai/Lazer/blob/main/lib/ui/home_pages.dart#L180)<br>`widget.state.playQueue(recent)` | **纯本地闭环**：无需外部请求，直接从 Lazer 本地播放历史记录中拉起最近播放列表循环起播。 |
| **私人漫游** | 电台专栏 #1 | `_StationStrip.onFm`<br>`activeGateway.radio(personal)` | `POST /v1/rcmd_list`<br>(路由: `fm.service.kugou.com`) | [`RawFmApi.cs` (L60-L75)](https://github.com/Linsxyx/KugouMusic.NET/blob/master/src/Libraries/KuGou.Net/Protocol/Raw/RawFmApi.cs#L60-L75)<br>`GetClassSongAsync` | 电台形式呈现的算法探索频道，支持连续流式加载更多相关歌曲。 |
| **红心随机** | 电台专栏 #2 | `_StationStrip.onLiked`<br>取 `collections.liked` 乱序播放 | `POST /v4/get_list_all_file`<br>(路由: `cloudlist.service.kugou.com`) | [`RawPlaylistApi.cs` (L122-L145)](https://github.com/Linsxyx/KugouMusic.NET/blob/master/src/Libraries/KuGou.Net/Protocol/Raw/RawPlaylistApi.cs#L122-L145)<br>`GetSongsAsync (listid=1)` | 同步云端默认收藏（红心）歌单，获取全部收藏曲目后在客户端进行 Fisher-Yates 乱序播放。 |
| **心动模式** | 电台专栏 #3 | `_StationStrip.onHeart`<br>`activeGateway.radio(heart)` | `POST /everyday_style_recommend`<br>(路由: `everydayrec.service.kugou.com`) | [`RawDiscoveryApi.cs` (L131-L148)](https://github.com/Linsxyx/KugouMusic.NET/blob/master/src/Libraries/KuGou.Net/Protocol/Raw/RawDiscoveryApi.cs#L131-L148)<br>`GetRecommendStyleSongAsync` | 熟悉与新鲜交叉的电台模式，融合用户已有偏好与算法拓展曲目。 |
| **歌手电台**<br>*(如: いよわ 电台)* | 电台专栏 #4 | `_StationStrip.onArtist`<br>`activeGateway.radio(artist, seed)` | `POST /kmr/v1/audio_group/author`<br>(路由: `openapi.kugou.com`, `kg-tid: 220`) | [`RawArtistApi.cs` (L179-L208)](https://github.com/Linsxyx/KugouMusic.NET/blob/master/src/Libraries/KuGou.Net/Protocol/Raw/RawArtistApi.cs#L179-L208)<br>`GetAudiosAsync` | 提取当前播放曲目歌手 ID，流式获取该歌手热门及关联曲风列表生成专属电台。 |

> **补充：用户资料与头像静默刷新机制**  
> 每次 Lazer 宿主拉起会话校验（`checkSession`）时，插件通过 [`RawUserApi.cs` (L69-L99)](https://github.com/Linsxyx/KugouMusic.NET/blob/master/src/Libraries/KuGou.Net/Protocol/Raw/RawUserApi.cs#L69-L99) 的 `/v7/get_all_list` 接口，自动静默比对酷狗云端的最新 `create_user_pic` 与 `list_create_username`，若手机端修改了资料将自动写回本地 `storage.json`，实现无感热同步。

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
