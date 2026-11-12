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

| 卡片 / 场景 | 位置 | Lazer 宿主契约 | 酷狗接口与 `KugouMusic.NET` 源码映射 |
| :--- | :--- | :--- | :--- |
| **今日限定好歌** | 顶部快捷 #1 | `onDaily` / `homeFeed.daily` | `POST /everyday_song_recommend` ([`RawDiscoveryApi.cs` L108](https://github.com/Linsxyx/KugouMusic.NET/blob/master/src/Libraries/KuGou.Net/Protocol/Raw/RawDiscoveryApi.cs#L108)) |
| **私人漫游** | 顶部 #2 / 电台 #1 | `onFm` / `radio.personal` | `POST /v1/rcmd_list` ([`RawFmApi.cs` L13](https://github.com/Linsxyx/KugouMusic.NET/blob/master/src/Libraries/KuGou.Net/Protocol/Raw/RawFmApi.cs#L13)) |
| **心动模式** | 顶部 #3 / 电台 #3 | `onHeart` / `radio.heart` | `POST /everyday_style_recommend` ([`RawDiscoveryApi.cs` L131](https://github.com/Linsxyx/KugouMusic.NET/blob/master/src/Libraries/KuGou.Net/Protocol/Raw/RawDiscoveryApi.cs#L131)) |
| **反复聆听** | 顶部快捷 #4 | `onReplay` / `playQueue.recent` | *客户端本地回放队列* ([`home_pages.dart` L180](https://github.com/chuxuehaocai/Lazer/blob/main/lib/ui/home_pages.dart#L180)) |
| **红心随机** | 电台专栏 #2 | `onLiked` / `collections.liked` | `POST /v4/get_list_all_file` ([`RawPlaylistApi.cs` L122](https://github.com/Linsxyx/KugouMusic.NET/blob/master/src/Libraries/KuGou.Net/Protocol/Raw/RawPlaylistApi.cs#L122)) |
| **歌手电台** | 电台专栏 #4 | `onArtist` / `radio.artist` | `POST /kmr/v1/audio_group/author` ([`RawArtistApi.cs` L179](https://github.com/Linsxyx/KugouMusic.NET/blob/master/src/Libraries/KuGou.Net/Protocol/Raw/RawArtistApi.cs#L179)) |

### 核心卡片机制与流转说明

> **1. 今日限定好歌 (`onDaily`)**  
> 基于已登录用户的长期听歌历史与画像，由酷狗算法引擎动态下发 30 首私人专属日推曲目。在 Lazer 中点击该卡片将自动拉取并呈现为完整的每日推荐虚拟歌单。

> **2. 私人漫游 (`onFm`)**  
> 对应酷狗私人 FM 模式。根据当前听歌上下文进行不间断智能切歌，支持无限下拉与连续流式预加载，适合沉浸式无尽探索。

> **3. 心动模式 (`onHeart`)**  
> 风格雷达推荐，拉取与用户收藏偏好高契合度的相似风格曲目，融合用户已知偏好与算法拓展。

> **4. 反复聆听 (`onReplay`)**  
> **纯客户端本地闭环**：无需发起任何网络请求，Lazer 直接从本地播放历史记录中拉起最近播放列表并循环起播。

> **5. 红心随机 (`onLiked`)**  
> 通过 `/v4/get_list_all_file` 接口拉取云端默认收藏（红心）歌单，获取全部收藏曲目后在客户端使用 Fisher-Yates 算法进行随机打乱起播。

> **6. 歌手电台 (`onArtist`)**  
> 智能提取当前播放曲目的歌手 ID 或歌手名，通过 `/kmr/v1/audio_group/author` 流式获取该歌手的热门歌曲及曲风关联曲目，自动生成该歌手的专属电台。

> **7. 用户资料与头像静默刷新机制**  
> 每次 Lazer 宿主拉起会话校验（`checkSession`）时，插件通过 [`RawUserApi.cs` (L69-L99)](https://github.com/Linsxyx/KugouMusic.NET/blob/master/src/Libraries/KuGou.Net/Protocol/Raw/RawUserApi.cs#L69-L99) 的 `/v7/get_all_list` 接口，自动静默比对酷狗云端的最新 `create_user_pic` 与 `list_create_username`，若手机端修改了头像或昵称将自动写回本地 `storage.json`，实现无感热同步。

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
