local config = require("kg.config")
local crypto = require("kg.crypto")
local transport = require("kg.transport")
local models = require("kg.models")

local discover = {}

-- 缓存歌曲 hash 到云端歌单 fileid 的映射 (用于取消喜欢时精确删除)
discover.fileIdMap = {}

-- 拉取私人漫游歌曲流
function discover.getPersonalFmSongs(mode, songPoolId)
  local session = transport.getSession()
  local userId = (session and session.userId and session.userId ~= "0") and session.userId or ""
  local token = (session and session.token) or ""
  local mid = (session and session.mid) or config.defaultMid

  local nowMs = host.now()
  local nowMsStr = string.format("%.0f", nowMs)
  local key = crypto.calc_login_key(nowMsStr)

  local body = {
    appid = config.appId,
    clienttime = tonumber(nowMsStr),
    mid = mid,
    action = "play",
    recommend_source_locked = 0,
    song_pool_id = songPoolId or 0,
    callerid = 0,
    m_type = 1,
    platform = "android",
    area_code = 1,
    remain_songcnt = 0,
    clientver = config.clientVer,
    is_overplay = 0,
    mode = mode or "normal",
    fakem = "ca981cfc583a4c37f28d2d49000013c16a0a",
    key = key,
    vip_type = "0"
  }

  if userId ~= "" then
    body.userid = userId
    body.kguid = userId
  end
  if token ~= "" then
    body.token = token
  end

  local res, err = transport.request({
    method = "POST",
    path = "/v2/personal_recommend",
    router = "persnfm.service.kugou.com",
    body = body
  })

  local songs = {}
  local list = res and res.data and (res.data.song_list or res.data.songs)
  if list and type(list) == "table" then
    for _, item in ipairs(list) do
      local s = models.song(item)
      if s and s.id and s.id ~= "" then
        table.insert(songs, s)
      end
    end
  end

  return songs
end

-- 首页推荐流 (homeFeed)
function discover.homeFeed()
  local session = transport.getSession()
  local userId = (session and session.userId and session.userId ~= "0") and session.userId or "0"

  -- 1. 获取推荐歌单 (拉取 20 个，分别分配给 recommended 和 playlists，避免内容重复)
  local plRes, err = transport.request({
    method = "POST",
    path = "/v2/special_recommend",
    router = "specialrec.service.kugou.com",
    body = {
      platform = "android",
      module_id = 1,
      page = 1,
      pagesize = 20,
      userid = userId,
      special_recommend = {
        withtag = 1,
        withsong = 0,
        sort = 1,
        ugc = 1,
        is_selected = 0,
        withrecommend = 1,
        area_code = 1,
        categoryid = 0
      },
      req_multi = 1,
      retrun_min = 5,
      return_special_falg = 1
    }
  })

  local allPlaylists = {}
  if plRes and plRes.data and plRes.data.special_list then
    for _, item in ipairs(plRes.data.special_list) do
      local p = models.playlist(item)
      if p and p.id and p.id ~= "" then
        table.insert(allPlaylists, p)
      end
    end
  end

  local recommended = {}
  local otherPlaylists = {}
  for i, pl in ipairs(allPlaylists) do
    if i <= 10 then
      table.insert(recommended, pl)
    else
      table.insert(otherPlaylists, pl)
    end
  end
  if #otherPlaylists == 0 then
    otherPlaylists = recommended
  end

  -- 2. 获取每日推荐歌曲
  local songRes, sErr = transport.request({
    method = "POST",
    path = "/everyday_song_recommend",
    router = "everydayrec.service.kugou.com",
    body = {
      platform = "android",
      userid = userId
    }
  })

  local dailySongs = {}
  if songRes and songRes.data and songRes.data.song_list then
    for _, item in ipairs(songRes.data.song_list) do
      local s = models.song(item)
      if s and s.id and s.id ~= "" then
        table.insert(dailySongs, s)
      end
    end
  end

  -- 3. 获取快速聆听 / 私人漫游歌曲 (让 quick 与 daily 彻底区分)
  local quickSongs = discover.getPersonalFmSongs("normal", 0)
  if #quickSongs == 0 then
    quickSongs = dailySongs
  end

  return {
    daily = dailySongs,
    quick = quickSongs,
    recommended = recommended,
    playlists = otherPlaylists,
    albums = {},
    featuredSongs = {}
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

-- 收藏歌曲列表 (favorites) - 对应酷狗云端“我喜欢”歌单 (listid = 2)
function discover.favorites(args)
  local session = transport.getSession()
  if not session or not session.userId or session.userId == "0" or not session.token or session.token == "" then
    return {}
  end

  local limit = tonumber(args and args.limit or 100)
  local offset = tonumber(args and args.offset or 0)
  local page = math.floor(offset / limit) + 1

  local res, err = transport.request({
    method = "POST",
    path = "/v4/get_list_all_file",
    router = "cloudlist.service.kugou.com",
    body = {
      listid = 2, -- 酷狗“我喜欢”歌单
      userid = tonumber(session.userId) or 0,
      token = session.token,
      type = 0,
      page = page,
      pagesize = limit,
      area_code = 1,
      allplatform = 1,
      show_cover = 1,
      show_relate_goods = 0
    }
  })

  local songs = {}
  local list = res and res.data and res.data.info
  if list and type(list) == "table" then
    for _, item in ipairs(list) do
      local s = models.song(item)
      if s and s.id and s.id ~= "" then
        s.starred = true
        local h = s.id:lower()
        if item.fileid then
          discover.fileIdMap[h] = item.fileid
        end
        table.insert(songs, s)
      end
    end
  end

  return songs
end

return discover
