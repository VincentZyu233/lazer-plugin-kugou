# Lazer Kugou Music Plugin - Agent Instructions

## 项目定位与目标
本项目是针对 [Lazer](https://github.com/chuxuehaocai/Lazer) 音乐播放器（Flutter/Dart 原生客户端）开发的**酷狗音乐（KuGou Music）第三方 Lua 插件**。
插件以规范的 ZIP 格式打包分发，运行在 Lazer 宿主内置的独立受限 Lua 沙箱环境（基于 Dart 实现的 `lua_dardo_plus` 解释器）中。

## 协议与逆向参考依据
- **重要前置条件**：核心协议、接口路径、加密算法及参数签名规则严格参考 `KugouMusic.NET`（C# 实现）工程。
- **环境检查**：若本地对应目录（如 `D:\aaaStuffsaaa\from_git\github\KugouMusic.NET`）不存在该参考工程，**必须第一时间提醒用户运行以下命令检出该仓库**以供对照：
  ```bash
  git clone https://github.com/Linsxyx/KugouMusic.NET
  ```

---

## 宿主底层沙箱避坑红线 (Critical Lazer Sandbox Guidelines)

Lazer 宿主基于 Dart 的 `LuaPluginRuntime` 与 `lua_dardo_plus` 运行插件代码，存在以下**致命底层约束与黑盒缺陷**，所有开发者与 Agent 必须无条件严格遵守：

### 1. 全局标准库剥离（禁止访问 `os.*` / `io.*`）
* **宿主行为**：Lazer 在启动 VM 时执行 `lua.setGlobal(key)` 将 `'io', 'os', 'package', 'debug', 'dofile', 'loadfile', 'load', 'loadstring', 'require', 'print'` **全部置为了 `nil`**。
* **致命陷阱**：调用 `os.time()`、`os.date()` 或 `io.*` 会立即触发 `attempt to index a nil value` 导致当前调用崩溃。
* **规避准则**：
  * 获取当前时间戳**必须且只能使用 `host.now()`**（返回毫秒整数，等价于 `DateTime.now().millisecondsSinceEpoch`）。
  * 插件内计算缓存超时（TTL）统一采用毫秒时间差：`host.now() - at < ttl_ms`。

### 2. Dart 解释器模式匹配缺陷（禁止使用 `%d`/`%s` 模式串）
* **解释器缺陷**：`lua_dardo_plus` 的 `string.match` 内部直接调用了 Dart 的 `RegExp(pattern).firstMatch(tail!)`，且**只返回 `group(0)`**。
* **致命陷阱**：
  * Lua 专属的字符类转义（如 `%d` 数字、`%s` 空格、`%w`、`%-`）在 Dart 正则表达式中被作为**普通字面量字符 `%` 和对应字母**处理，导致数字或空白匹配永远失败并返回 `nil`！
  * 多捕获组解构全部失效（只返回单个 `group(0)`，其余解构变量全为 `nil`）。
* **规避准则**：
  * **严禁在核心逻辑中依赖带有 Lua `%` 转义模式的 `string.match`**。
  * 数字与数值提取统一采用**纯字符字节流扫描**（`string.byte >= 48 and <= 57`）。
  * 字符串查找统一采用带 plain 标志的明文检索：`string.find(str, substr, 1, true)`。

### 3. Table 到 Dart 类型转换严格契约（List vs Map）
* **宿主转换规则**：
  * 仅当 Table 的键为**连续整数 `1..N`** 时，Dart 才会将其转换为 Dart `List`。
  * 空表 `{}` 会被解释器先转换为 Dart 空 `Map`（宿主 `_page` 会特判处理为空 List）。
  * **一旦 Table 包含非连续整数键或字符串键，Dart 立即将其转为 `Map`**。
* **致命陷阱**：在需要返回列表的方法（如 `favorites`, `playlistSongs`, `albumSongs`, `artistSongs`）中，若把分页 Token、count 或 meta 信息混入同一个 Table 返回，宿主在执行 `raw is! List` 检查时会立即抛出 `MusicGatewayException(reason: 'invalid payload')`，导致界面整页报错。
* **规避准则**：
  * 列表分页方法**必须严格返回纯数组 Table**，禁止夹带任何非数字键属性。

### 4. 网络请求限制与域名白名单（`host.http`）
* **宿主限制**：
  * 单次 HTTP 请求超时由宿主硬编码为 **30 秒**。
  * 请求体与响应体限制：单次 body 超过 2MB 会被宿主抛出 `FormatException('Request too large')`。
  * 必须在 `manifest.json` 的 `network` 白名单中显式声明目标域名。
  * 宿主强制剥离 `host`, `content-length`, `connection` 标头，不可自定义覆盖。
* **规避准则**：网络请求必须包裹在 `pcall` 中，并实现轻量超时熔断，失败时返回安全空数据，绝不阻塞调用队列。

### 5. 存储 1MB 物理天花板（`host.storage_set`）
* **宿主限制**：单个插件的 `storage.json` 总大小超过 1MB 时，宿主直接抛出 `FormatException('Storage full')`。
* **规避准则**：`host.storage_set` 仅用于持久化用户的 Token、Cookie、Session 及简单标记，**严禁将大批量歌曲列表或大型 JSON 写入 storage**。大列表缓存只能保存在 Lua 模块级局部变量中。

### 6. 并发与 Isolate 崩溃重启机制
* **宿主限制**：插件运行在独立 Isolate 的单线程事件循环中，后台调用（`scrobble`, `playStats`, `lyrics`, `song`）超时预算仅有 10 秒。一旦超时，宿主将强制终止并**重启整个 Lua VM**。
* **规避准则**：严禁死循环或阻塞式网络请求，异常需秒级退出并返回降级兜底。

---

## 酷狗专有核心规范与业务策略 (KuGou Specifics)

1. **加解密与签名策略**：
   - 参考 `KugouMusic.NET`，使用 MD5 盐值混淆与 AES-CBC / PKCS7 参数加解密。
   - 依赖宿主注入的 `host.crypto` 进行高效加密运算。
2. **双重登录能力**：
   - 支持 Web 扫码登录（`qr`）与手机号验证码登录（`sms`），由状态机保证凭据安全持久化。
3. **音质双哈希阶梯与平滑降级**：
   - 基于 `hash` 与 `album_audio_id` 对比酷狗多音质阶梯（128k, 320k, FLAC, Hi-Res）。
   - 客户端请求高码率受限时，平滑降级至可用最高码率，返回完整的音频流模型。
4. **KRC / LRC 歌词体系**：
   - 优先输出标准 LRC，支持逐行时间戳（`startMs`）与双语翻译展示。
5. **安全与隐私**：
   - 敏感信息（Token、Cookie、密码、签名 URL）绝不可泄露至日志或公开返回。
