local account = require("kgm.account")
local catalog = require("kgm.catalog")
local discover = require("kgm.discover")

local plugin = {}

function plugin.call(operation, args)
  args = args or {}

  -- 1. 平台元数据与能力声明
  if operation == "describe" then
    return {
      providers = {
        {
          id = "kugou",
          name = "酷狗音乐",
          auth = { "qr", "sms" },
          capabilities = {
            "search",
            "lyrics",
            "playlists",
            "favorites",
            "homeFeed",
            "radio",
            "recommendations",
            "comments"
          },
          loginHint = "使用酷狗音乐 App 扫码登录或手机验证码登录",
          cookieHint = "支持扫码与验证码授权"
        }
      }
    }
  end

  -- 2. 账号与登录相关
  if operation == "session" then
    return account.session()
  elseif operation == "logout" then
    return account.logout()
  elseif operation == "qrKey" then
    return account.qrKey()
  elseif operation == "qrUrl" then
    return account.qrUrl(args)
  elseif operation == "qrCheck" then
    return account.qrCheck(args)
  elseif operation == "sendCaptcha" then
    local ok, res = pcall(function() return account.sendCaptcha(args) end)
    if not ok then
      local transport = require("kgm.transport")
      transport.debugLog("FATAL sendCaptcha: " .. tostring(res))
      return { error = { code = 500, message = tostring(res) } }
    end
    return res
  elseif operation == "loginCaptcha" then
    local ok, res = pcall(function() return account.loginCaptcha(args) end)
    if not ok then
      local transport = require("kgm.transport")
      transport.debugLog("FATAL loginCaptcha: " .. tostring(res))
      return nil
    end
    return res
  end

  -- 3. 搜索与音频流、歌词、评论
  if operation == "search" then
    return catalog.search(args)
  elseif operation == "song" then
    return catalog.song(args)
  elseif operation == "stream" then
    return catalog.stream(args)
  elseif operation == "lyrics" then
    local ok, res = pcall(function() return catalog.lyrics(args) end)
    if not ok then
      local transport = require("kgm.transport")
      transport.debugLog("FATAL lyrics crash: " .. tostring(res))
      -- 不能返回空表：宿主会把空列表判定为「纯音乐」并永久写盘缓存，
      -- 之后连插件都不再询问，用户将永远看不到歌词。抛 code 70 让宿主保持可重试。
      error("Gateway code 70", 0)
    end
    return res
  elseif operation == "comments" then
    local ok, res = pcall(function() return catalog.comments(args) end)
    if not ok then
      local transport = require("kgm.transport")
      transport.debugLog("FATAL comments crash: " .. tostring(res))
      return { total = 0, hasMore = false, hot = {}, latest = {} }
    end
    return res
  elseif operation == "playlist" then
    return catalog.playlist(args)
  elseif operation == "playlistSongs" then
    return catalog.playlistSongs(args)
  elseif operation == "artist" then
    return catalog.artist(args)
  elseif operation == "artistSongs" then
    return catalog.artistSongs(args)
  elseif operation == "artistAlbums" then
    return catalog.artistAlbums(args)
  elseif operation == "radio" then
    return catalog.radio(args)
  end

  -- 4. 推荐与个人收藏
  if operation == "homeFeed" then
    return discover.homeFeed()
  elseif operation == "playlists" then
    return discover.playlists(args)
  elseif operation == "favorites" then
    return discover.favorites(args)
  elseif operation == "setFavorite" then
    return catalog.setFavorite(args)
  end

  -- 未实现的操作返回空或报错
  return nil
end

return plugin
