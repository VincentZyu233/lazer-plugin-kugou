local config = require("kg.config")
local transport = require("kg.transport")
local models = require("kg.models")

local discover = {}

-- 首页推荐流 (homeFeed)
function discover.homeFeed()
  local session = transport.getSession()

  -- 1. 获取推荐歌单
  local plRes, err = transport.request({
    method = "POST",
    path = "/v2/special_recommend",
    router = "specialrec.service.kugou.com",
    body = {
      platform = "android",
      module_id = 1,
      page = 1,
      pagesize = 12,
      special_recommend = {
        withrecommend = 1,
        sort = 1,
        ugc = 1
      }
    }
  })

  local playlists = {}
  if plRes and plRes.data and plRes.data.special_list then
    for _, item in ipairs(plRes.data.special_list) do
      local p = models.playlist(item)
      if p then table.insert(playlists, p) end
    end
  end

  -- 2. 获取每日推荐歌曲
  local songRes, sErr = transport.request({
    path = "/everyday_song_recommend",
    router = "everydayrec.service.kugou.com"
  })

  local dailySongs = {}
  if songRes and songRes.data and songRes.data.song_list then
    for _, item in ipairs(songRes.data.song_list) do
      local s = models.song(item)
      if s then table.insert(dailySongs, s) end
    end
  end

  return {
    featured = playlists,
    daily = dailySongs,
    playlists = playlists
  }
end

-- 发现页歌单列表
function discover.playlists(args)
  local limit = tonumber(args and args.limit or 30)
  local offset = tonumber(args and args.offset or 0)
  local page = math.floor(offset / limit) + 1

  local res, err = transport.request({
    method = "POST",
    path = "/v2/special_recommend",
    router = "specialrec.service.kugou.com",
    body = {
      platform = "android",
      module_id = 1,
      page = page,
      pagesize = limit,
      special_recommend = {
        withrecommend = 1,
        sort = 1,
        ugc = 1
      }
    }
  })

  local list = {}
  if res and res.data and res.data.special_list then
    for _, item in ipairs(res.data.special_list) do
      local p = models.playlist(item)
      if p then table.insert(list, p) end
    end
  end

  return list
end

-- 收藏歌曲列表 (favorites)
function discover.favorites(args)
  -- 酷狗云端红心收藏列表，未登录返回空
  local session = transport.getSession()
  if not session or not session.userId or session.userId == "0" then
    return {}
  end

  local limit = tonumber(args and args.limit or 100)
  local offset = tonumber(args and args.offset or 0)
  local page = math.floor(offset / limit) + 1

  local res, err = transport.request({
    path = "/kmr/v1/user/favorite/songs",
    params = {
      userid = session.userId,
      page = tostring(page),
      pagesize = tostring(limit)
    },
    router = "gateway.kugou.com"
  })

  local songs = {}
  if res and res.data and res.data.info then
    for _, item in ipairs(res.data.info) do
      local s = models.song(item)
      if s then
        s.starred = true
        table.insert(songs, s)
      end
    end
  end

  return songs
end

return discover
