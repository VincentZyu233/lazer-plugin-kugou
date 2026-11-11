local config = require("kg.config")
local crypto = require("kg.crypto")
local transport = require("kg.transport")
local models = require("kg.models")

local catalog = {}

-- 搜索歌曲、歌单或专辑
function catalog.search(args)
  local query = tostring(args and args.query or "")
  local limit = tonumber(args and args.limit or 30)
  local offset = tonumber(args and args.offset or 0)
  local page = math.floor(offset / limit) + 1

  local res, err = transport.request({
    path = "/v3/search/song",
    params = {
      keyword = query,
      page = tostring(page),
      pagesize = tostring(limit),
      platform = "AndroidFilter",
      iscorrection = "1"
    },
    router = "complexsearch.kugou.com"
  })

  local songList = {}
  local rawList = res and res.data and (res.data.lists or res.data.info)
  if rawList and type(rawList) == "table" then
    for _, item in ipairs(rawList) do
      local song = models.song(item)
      if song and song.id and song.id ~= "" then
        table.insert(songList, song)
      end
    end
  end

  return {
    songs = songList,
    albums = {},
    artists = {},
    playlists = {}
  }
end

-- 获取音频播放流 (支持码率智能降级)
function catalog.stream(args)
  local hash = tostring(args and args.id or ""):lower()
  if hash == "" then
    return { error = { code = 400, message = "缺少歌曲 ID" } }
  end

  local session = transport.getSession()
  local reqQuality = tostring(args and args.quality or "high"):lower()

  -- 映射品质参数 (酷狗格式: hires, flac, 320, 128)
  local qualityOrder = { "320", "128" }
  if reqQuality == "lossless" or reqQuality == "original" then
    qualityOrder = { "flac", "320", "128" }
  elseif reqQuality == "hires" then
    qualityOrder = { "hires", "flac", "320", "128" }
  elseif reqQuality == "standard" then
    qualityOrder = { "128", "320" }
  end

  for _, q in ipairs(qualityOrder) do
    local v5Key = crypto.calc_v5_key(hash, session.userId, session.mid)
    local res, err = transport.request({
      path = "/v5/url",
      params = {
        album_id = "0",
        area_code = "1",
        hash = hash,
        ssa_flag = "is_fromtrack",
        version = config.version,
        page_id = "967177915",
        quality = q,
        album_audio_id = "0",
        behavior = "play",
        pid = "411",
        cmd = "26",
        pidversion = "3001",
        IsFreePart = "0",
        key = v5Key
      },
      router = "trackercdn.kugou.com"
    })

    if res and (res.status == 1 or res.errcode == 0) and res.url then
      local playUrl = nil
      if type(res.url) == "table" and #res.url > 0 then
        playUrl = res.url[1]
      elseif type(res.url) == "string" and res.url ~= "" then
        playUrl = res.url
      end

      if playUrl and playUrl ~= "" then
        local bitRate = 128000
        local suffix = "mp3"
        if q == "320" then
          bitRate = 320000
        elseif q == "flac" then
          bitRate = 960000
          suffix = "flac"
        elseif q == "hires" then
          bitRate = 1411200
          suffix = "flac"
        end

        return {
          url = playUrl,
          contentType = suffix == "flac" and "audio/flac" or "audio/mpeg",
          suffix = suffix,
          bitRate = bitRate,
          size = tonumber(res.fileSize or res.filesize or 0)
        }
      end
    end
  end

  return {
    error = {
      code = 70,
      httpStatus = 404,
      message = "当前歌曲无可用播放链接或需要 VIP 权限"
    }
  }
end

-- 获取歌词
function catalog.lyrics(args)
  local hash = tostring(args and args.id or ""):lower()
  if hash == "" then return {} end

  -- 1. 检索歌词 candidate
  local searchRes, err = transport.request({
    path = "/v1/search",
    host = "lyrics.kugou.com",
    params = {
      hash = hash,
      album_audio_id = "0",
      lrctxt = "1",
      man = "no",
      duration = "0"
    }
  })

  local candidate = nil
  if searchRes and searchRes.candidates and #searchRes.candidates > 0 then
    candidate = searchRes.candidates[1]
  end

  if not candidate or not candidate.id or not candidate.accesskey then
    return {}
  end

  -- 2. 下载 LRC 格式歌词 (Base64)
  local downloadRes, err2 = transport.request({
    path = "/download",
    host = "lyrics.kugou.com",
    params = {
      ver = "1",
      client = "android",
      id = tostring(candidate.id),
      accesskey = tostring(candidate.accesskey),
      fmt = "lrc",
      charset = "utf8"
    }
  })

  if downloadRes and downloadRes.status == 200 and downloadRes.content and downloadRes.content ~= "" then
    local rawLrc = crypto.base64_decode(downloadRes.content)
    if rawLrc and rawLrc ~= "" then
      local lines = models.parseLrc(rawLrc)
      return {
        {
          lines = lines,
          lrc = rawLrc,
          synced = #lines > 0
        }
      }
    end
  end

  return {}
end

-- 获取歌单详情与歌曲
function catalog.playlist(args)
  local specialId = tostring(args and args.id or "")
  if specialId == "" then return nil end

  local res, err = transport.request({
    path = "/api/v5/special/info",
    params = {
      specialid = specialId
    },
    router = "mobileservice.kugou.com"
  })

  if res and res.data then
    return models.playlist(res.data)
  end
  return nil
end

function catalog.playlistSongs(args)
  local specialId = tostring(args and args.id or "")
  local limit = tonumber(args and args.limit or 100)
  local offset = tonumber(args and args.offset or 0)
  local page = math.floor(offset / limit) + 1

  local res, err = transport.request({
    path = "/api/v5/special/song",
    params = {
      specialid = specialId,
      page = tostring(page),
      pagesize = tostring(limit)
    },
    router = "mobileservice.kugou.com"
  })

  local songs = {}
  if res and res.data and res.data.info then
    for _, item in ipairs(res.data.info) do
      local s = models.song(item)
      if s then table.insert(songs, s) end
    end
  end

  return songs
end

-- 获取歌手详情
function catalog.artist(args)
  local authorId = tostring(args and args.id or "")
  if authorId == "" then return nil end

  local res, err = transport.request({
    method = "POST",
    path = "/kmr/v3/author",
    body = {
      author_id = authorId
    },
    router = "openapi.kugou.com",
    headers = {
      ["kg-tid"] = "36"
    }
  })

  if res and res.status == 1 and res.data then
    return models.artist(res.data)
  end
  return nil
end

-- 获取歌手热门歌曲
function catalog.artistSongs(args)
  local authorId = tostring(args and args.id or "")
  if authorId == "" then return {} end

  local limit = tonumber(args and args.limit or 100)
  local offset = tonumber(args and args.offset or 0)
  local page = math.floor(offset / limit) + 1

  local res, err = transport.request({
    method = "POST",
    path = "/kmr/v1/audio_group/author",
    body = {
      author_id = authorId,
      pagesize = limit,
      page = page,
      sort = 1, -- 1=最热, 2=最新
      area_code = "all"
    },
    router = "openapi.kugou.com",
    headers = {
      ["kg-tid"] = "220"
    }
  })

  local songs = {}
  local list = res and res.data
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

-- 获取歌手专辑列表
function catalog.artistAlbums(args)
  local authorId = tostring(args and args.id or "")
  if authorId == "" then return {} end

  local limit = tonumber(args and args.limit or 30)
  local offset = tonumber(args and args.offset or 0)
  local page = math.floor(offset / limit) + 1

  local res, err = transport.request({
    method = "POST",
    path = "/kmr/v1/author/albums",
    body = {
      author_id = authorId,
      pagesize = limit,
      page = page,
      sort = 3, -- 3=最热, 1=最新
      category = 1,
      area_code = "all"
    },
    router = "openapi.kugou.com",
    headers = {
      ["kg-tid"] = "36"
    }
  })

  local albums = {}
  local list = res and res.data
  if list and type(list) == "table" then
    for _, item in ipairs(list) do
      local a = models.album(item)
      if a and a.id and a.id ~= "" then
        table.insert(albums, a)
      end
    end
  end

  return albums
end

-- 获取电台歌曲流 (私人漫游、心动模式、歌手电台)
function catalog.radio(args)
  local kind = tostring(args and args.kind or "personal"):lower()
  local limit = tonumber(args and args.limit or 30)

  -- 1. 歌手电台 (artist radio)
  if kind == "artist" and args and args.seed and tostring(args.seed) ~= "" then
    return catalog.artistSongs({ id = tostring(args.seed), limit = limit })
  end

  -- 2. 歌单心动/相似歌曲
  if args and args.playlist and tostring(args.playlist) ~= "" then
    local pSongs = catalog.playlistSongs({ id = tostring(args.playlist), limit = limit })
    if pSongs and #pSongs > 0 then
      return pSongs
    end
  end

  -- 3. 私人漫游 (personal) 或 心动模式 (heart): 从酷狗每日个性化推荐拉取歌曲流
  local session = transport.getSession()
  local userId = (session and session.userId and session.userId ~= "0") and session.userId or "0"

  local songRes, err = transport.request({
    method = "POST",
    path = "/everyday_song_recommend",
    router = "everydayrec.service.kugou.com",
    body = {
      platform = "android",
      userid = userId
    }
  })

  local songs = {}
  if songRes and songRes.data and songRes.data.song_list then
    for _, item in ipairs(songRes.data.song_list) do
      local s = models.song(item)
      if s and s.id and s.id ~= "" then
        table.insert(songs, s)
      end
    end
  end

  return songs
end

return catalog
