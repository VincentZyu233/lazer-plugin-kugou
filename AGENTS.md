# Lazer Kugou Music Plugin - Agent Instructions

## 项目定位与目标
本项目是针对 [Lazer](https://github.com/chuxuehaocai/Lazer) 音乐播放器（Flutter/Dart 原生客户端）开发的**酷狗音乐（KuGou Music）第三方 Lua 插件**。
插件以规范的 ZIP 格式打包分发，运行在 Lazer 宿主内置的独立受限 Lua 沙箱环境中。

## 协议与逆向参考依据
- **重要前置条件**：核心协议、接口路径、加密算法及参数签名规则严格参考 `KugouMusic.NET`（C# 实现）工程。
- **环境检查**：若本地对应目录（如 `D:\aaaStuffsaaa\from_git\github\KugouMusic.NET`）不存在该参考工程，**必须第一时间提醒用户运行以下命令检出该仓库**以供对照：
  ```bash
  git clone https://github.com/Linsxyx/KugouMusic.NET
  ```

## 核心设计与宿主约束
1. **Lua 运行时限制**：
   - 严禁调用原生受限库与文件系统操作（如 `io.*`, `os.*`, `package.*`, 原生 `require`, `debug.*`）。
   - 外部调用全部依托宿主全局注入的 `host` 对象：
     - `host.http({ url, method, headers, body })`（注意：必须精确或通配匹配 `manifest.json` 声明的 HTTPS 域名白名单）
     - `host.crypto({ operation, ... })`（MD5, SHA256, AES-CBC/PKCS7, RSA modpow 等）
     - `host.storage_get(key)` / `host.storage_set(key, value)`（插件隔离的持久化存储）
     - `host.json_encode(val)` / `host.json_decode(str)` / `host.url_encode(str)` / `host.now()`
2. **模块加载规范**：
   - 宿主支持基于 `require("kg.xxx")` 规则自动查找子目录中的 `kg/xxx.lua` 源码。
3. **架构与模型规范**：
   - 数据格式必须转换为 Lazer 统一数据实体（参考 Lazer 文档 `docs/lua-plugins.md` 和 `LuaMusicGateway`）：
     - 歌曲模型包含：`id`, `title`, `artists`, `albumId`, `albumName`, `coverUrl`, `durationMs`
     - 音频流模型包含：`url`, `contentType`, `bitRate`, `suffix`, `size`, `headers`
     - 歌词模型包含：`lines`（每行 `text`, 可选 `startMs`）、`lrc`、`translation`、`offsetMs`
4. **业务策略规范**：
   - **音质策略**：优先按客户端请求音质匹配，若受限或不可用则平滑降级至可用最高码率（如 320k / 128k）。
   - **登录能力**：同时支持 Web 扫码登录（`qr`）与手机号验证码登录（`sms`）。
   - **歌词策略**：优先提供稳定规范的标准双语/逐行 LRC。
   - **安全性**：敏感信息（Token、Cookie、密码、签名 URL）绝不可泄露至日志或公开返回。
