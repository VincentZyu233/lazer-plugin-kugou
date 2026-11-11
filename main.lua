local account = require("kg.account")
local catalog = require("kg.catalog")
local discover = require("kg.discover")

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
            "homeFeed"
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
    return account.sendCaptcha(args)
  elseif operation == "loginCaptcha" then
    return account.loginCaptcha(args)
  end

  -- 3. 搜索与音频流、歌词
  if operation == "search" then
    return catalog.search(args)
  elseif operation == "stream" then
    return catalog.stream(args)
  elseif operation == "lyrics" then
    return catalog.lyrics(args)
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
  end

  -- 4. 推荐与个人收藏
  if operation == "homeFeed" then
    return discover.homeFeed()
  elseif operation == "playlists" then
    return discover.playlists(args)
  elseif operation == "favorites" then
    return discover.favorites(args)
  end

  -- 未实现的操作返回空或报错
  return nil
end

return plugin
