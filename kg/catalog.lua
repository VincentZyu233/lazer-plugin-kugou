local config = require("kg.config")
local crypto = require("kg.crypto")
local transport = require("kg.transport")
local models = require("kg.models")
local discover = require("kg.discover")

local catalog = {}

-- 搜索歌曲、歌手、专辑与歌单
function catalog.search(args)
  local query = tostring(args and args.query or "")
  local limit = tonumber(args and args.limit or 30)
  local offset = tonumber(args and args.offset or 0)
  local page = math.floor(offset / limit) + 1

  if query == "" then
    return { songs = {}, albums = {}, artists = {}, playlists = {} }
  end

  -- 1. 搜索单曲
  local songList = {}
  local songRes, _ = transport.request({
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
  local rawSongs = songRes and songRes.data and (songRes.data.lists or songRes.data.info)
  if rawSongs and type(rawSongs) == "table" then
    for _, item in ipairs(rawSongs) do
      local s = models.song(item)
      if s and s.id and s.id ~= "" then
        table.insert(songList, s)
      end
    end
  end

  -- 2. 搜索歌手
  local artistList = {}
  local authorRes, _ = transport.request({
    path = "/v1/search/author",
    params = {
      keyword = query,
      page = tostring(page),
      pagesize = tostring(limit),
      platform = "AndroidFilter",
      iscorrection = "1"
    },
    router = "complexsearch.kugou.com"
  })
  local rawAuthors = authorRes and authorRes.data and authorRes.data.lists
  if rawAuthors and type(rawAuthors) == "table" then
    for _, item in ipairs(rawAuthors) do
      local a = models.artist(item)
      if a and a.id and a.id ~= "" then
        table.insert(artistList, a)
      end
    end
  end

  -- 3. 搜索专辑
  local albumList = {}
  local albumRes, _ = transport.request({
    path = "/v1/search/album",
    params = {
      keyword = query,
      page = tostring(page),
      pagesize = tostring(limit),
      platform = "AndroidFilter",
      iscorrection = "1"
    },
    router = "complexsearch.kugou.com"
  })
  local rawAlbums = albumRes and albumRes.data and albumRes.data.lists
  if rawAlbums and type(rawAlbums) == "table" then
    for _, item in ipairs(rawAlbums) do
      local alb = models.album(item)
      if alb and alb.id and alb.id ~= "" then
        table.insert(albumList, alb)
      end
    end
  end

  -- 4. 搜索歌单
  local playlistList = {}
  local specialRes, _ = transport.request({
    path = "/v1/search/special",
    params = {
      keyword = query,
      page = tostring(page),
      pagesize = tostring(limit),
      platform = "AndroidFilter",
      iscorrection = "1"
    },
    router = "complexsearch.kugou.com"
  })
  local rawSpecials = specialRes and specialRes.data and specialRes.data.lists
  if rawSpecials and type(rawSpecials) == "table" then
    for _, item in ipairs(rawSpecials) do
      local pl = models.playlist(item)
      if pl and pl.id and pl.id ~= "" then
        table.insert(playlistList, pl)
      end
    end
  end

  return {
    songs = songList,
    albums = albumList,
    artists = artistList,
    playlists = playlistList
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

  if specialId == "__lazer_favorites__" or specialId:find("favorites") then
    return {
      id = specialId,
      name = "我喜欢",
      isFavorites = true,
      songCount = 0
    }
  end

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
  if specialId == "__lazer_favorites__" or specialId:find("favorites") then
    return discover.favorites(args)
  end

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

-- 作者信息内存缓存表 (支持按照名字和 ID 双向查询)
local authorCache = {}

local function debugLog(msg)
  local logs = host.storage_get("debug_logs") or "[]"
  local ok, arr = pcall(function() return host.json_decode(logs) end)
  if not ok or type(arr) ~= "table" then arr = {} end
  table.insert(arr, { time = host.now(), msg = tostring(msg) })
  if #arr > 30 then table.remove(arr, 1) end
  host.storage_set("debug_logs", host.json_encode(arr))
end

local function isNumericId(val)
  if not val or val == "" then return false end
  local n = tonumber(tostring(val))
  return n ~= nil and n > 0
end

local function resolveAuthor(idOrName)
  if not idOrName or idOrName == "" then return nil, nil end
  local str = tostring(idOrName)
  debugLog("resolveAuthor start: " .. str)

  if authorCache[str] then
    local cached = authorCache[str]
    local cid = tostring(cached.AuthorId or cached.author_id or str)
    debugLog("resolveAuthor hit cache: " .. cid)
    return cid, cached
  end

  -- 如果已经是纯数字并且不为 0
  if isNumericId(str) then
    debugLog("resolveAuthor is numeric: " .. str)
    return str, nil
  end

  -- 否则使用 /v1/search/author 搜索歌手名字，获取真实 AuthorId 与基础元数据
  local res, err = transport.request({
    path = "/v1/search/author",
    params = {
      keyword = str,
      page = "1",
      pagesize = "5",
      platform = "AndroidFilter",
      iscorrection = "1"
    },
    router = "complexsearch.kugou.com"
  })

  debugLog("resolveAuthor search result: " .. tostring(res and res.status) .. " err: " .. tostring(err))

  if res and res.status == 1 and res.data and res.data.lists and #res.data.lists > 0 then
    local match = res.data.lists[1]
    local authorId = tostring(match.AuthorId or "")
    if authorId ~= "" then
      authorCache[str] = match
      authorCache[authorId] = match
      debugLog("resolveAuthor matched: " .. authorId .. " name: " .. tostring(match.AuthorName))
      return authorId, match
    end
  end

  return str, nil
end

-- 获取歌手详情
function catalog.artist(args)
  local rawId = tostring(args and args.id or "")
  debugLog("catalog.artist called with rawId: " .. rawId)
  if rawId == "" then return nil end

  local authorId, cachedAuthor = resolveAuthor(rawId)
  debugLog("catalog.artist resolved to authorId: " .. tostring(authorId))

  local detail = nil
  if isNumericId(authorId) then
    local res, err = transport.request({
      method = "POST",
      path = "/kmr/v3/author",
      body = {
        author_id = tostring(authorId)
      },
      router = "openapi.kugou.com",
      headers = {
        ["kg-tid"] = "36"
      }
    })

    debugLog("catalog.artist kmr/v3/author res: " .. tostring(res and res.status) .. " err: " .. tostring(err))

    if res and res.status == 1 and res.data then
      detail = models.artist(res.data)
      debugLog("catalog.artist detail coverUrl: " .. tostring(detail and detail.coverUrl))
    end
  end

  -- 兜底或数据融合：若获取详情失败或缺少头像，优先使用搜索拿到的歌手元数据
  if not detail or not detail.coverUrl or detail.coverUrl == "" then
    if cachedAuthor then
      local fallback = models.artist(cachedAuthor)
      if fallback then
        if detail then
          detail.coverUrl = fallback.coverUrl
          if (detail.songCount or 0) == 0 then detail.songCount = fallback.songCount end
          if (detail.albumCount or 0) == 0 then detail.albumCount = fallback.albumCount end
        else
          detail = fallback
        end
        debugLog("catalog.artist used fallback coverUrl: " .. tostring(detail and detail.coverUrl))
      end
    end
  end

  return detail
end

-- 获取歌手热门歌曲
function catalog.artistSongs(args)
  local rawId = tostring(args and args.id or "")
  debugLog("catalog.artistSongs called with rawId: " .. rawId)
  if rawId == "" then return {} end

  local authorId, cachedAuthor = resolveAuthor(rawId)
  local limit = tonumber(args and args.limit or 100)
  local offset = tonumber(args and args.offset or 0)
  local page = math.floor(offset / limit) + 1

  local songs = {}

  -- 1. 优先使用纯数字 authorId 请求 OpenAPI
  if isNumericId(authorId) then
    local res, err = transport.request({
      method = "POST",
      path = "/kmr/v1/audio_group/author",
      body = {
        author_id = tostring(authorId),
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

    debugLog("catalog.artistSongs kmr/v1 res: " .. tostring(res and (res.data and #res.data or "no-data")) .. " err: " .. tostring(err))

    local list = res and res.data
    if list and type(list) == "table" then
      for _, item in ipairs(list) do
        local s = models.song(item)
        if s and s.id and s.id ~= "" then
          -- 如果歌曲自带的歌手列表缺乏有效 ID，补齐此歌手的数字 ID
          if authorId and (#s.artists == 0 or s.artists[1].id == s.artists[1].name) then
            local aName = (s.artists[1] and s.artists[1].name ~= "") and s.artists[1].name or (cachedAuthor and cachedAuthor.AuthorName or rawId)
            s.artists = { { id = tostring(authorId), name = aName } }
          end
          table.insert(songs, s)
        end
      end
    end
  end

  debugLog("catalog.artistSongs after api, songs count: " .. tostring(#songs))

  -- 2. 兜底保障：若 OpenAPI 未返回歌曲或 ID 解析受阻，直接通过综合搜索拉取该歌手的歌曲
  if #songs == 0 then
    local queryName = (cachedAuthor and cachedAuthor.AuthorName) or rawId
    debugLog("catalog.artistSongs fallback searching queryName: " .. queryName)
    local sRes = catalog.search({ query = queryName, limit = limit, offset = offset })
    if sRes and sRes.songs and #sRes.songs > 0 then
      songs = sRes.songs
    end
    debugLog("catalog.artistSongs fallback found count: " .. tostring(#songs))
  end

  return songs
end

-- 获取歌手专辑列表
function catalog.artistAlbums(args)
  local rawId = tostring(args and args.id or "")
  if rawId == "" then return {} end

  local authorId, cachedAuthor = resolveAuthor(rawId)
  local limit = tonumber(args and args.limit or 30)
  local offset = tonumber(args and args.offset or 0)
  local page = math.floor(offset / limit) + 1

  if not isNumericId(authorId) then
    return {}
  end

  local res, err = transport.request({
    method = "POST",
    path = "/kmr/v1/author/albums",
    body = {
      author_id = tostring(authorId),
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

  transport.debugLog("catalog.radio called kind=" .. tostring(kind) .. " seed=" .. tostring(args and args.seed))

  -- 1. 歌手电台 (artist radio)
  if kind == "artist" and args and args.seed and tostring(args.seed) ~= "" then
    local aSongs = catalog.artistSongs({ id = tostring(args.seed), limit = limit })
    if aSongs and #aSongs > 0 then return aSongs end
  end

  -- 2. 私人漫游 (personal / personalfm): 调取酷狗真实私人 FM 流
  if kind == "personal" or kind == "personalfm" then
    local songs = discover.getPersonalFmSongs("normal", 0)
    if songs and #songs > 0 then return songs end
  end

  -- 3. 心动模式 (heart): 调取风格/口味个性化推荐池
  if kind == "heart" then
    local songs = discover.getPersonalFmSongs("normal", 1)
    if songs and #songs > 0 then return songs end
  end

  -- 4. 歌单心动/相似歌曲 (若指定了有效普通歌单)
  if args and args.playlist and tostring(args.playlist) ~= "" and tostring(args.playlist) ~= "__lazer_favorites__" then
    local pSongs = catalog.playlistSongs({ id = tostring(args.playlist), limit = limit })
    if pSongs and #pSongs > 0 then
      return pSongs
    end
  end

  -- 5. 如果心动模式或私人漫游酷狗个性化流为空，尝试使用收藏歌曲作为安全源
  local favSongs = discover.favorites({ limit = 30, offset = 0 })
  if favSongs and #favSongs > 0 then
    transport.debugLog("catalog.radio fallback to favorites count=" .. tostring(#favSongs))
    return favSongs
  end

  -- 6. 兜底方案：每日推荐歌曲
  local session = transport.getSession()
  local userId = (session and session.userId and session.userId ~= "0") and session.userId or "0"

  local songRes, err = transport.request({
    method = "POST",
    path = "/everyday_song_recommend",
    router = "everydayrec.service.kugou.com",
    body = {
      platform = "android",
      userid = tostring(userId)
    }
  })

  local fallbackSongs = {}
  if songRes and songRes.data and songRes.data.song_list then
    for _, item in ipairs(songRes.data.song_list) do
      local s = models.song(item)
      if s and s.id and s.id ~= "" then
        table.insert(fallbackSongs, s)
      end
    end
  end

  transport.debugLog("catalog.radio fallback to daily count=" .. tostring(#fallbackSongs))
  return fallbackSongs
end

-- 设置/取消歌曲红心收藏 (同步酷狗云端“我喜欢”歌单)
function catalog.setFavorite(args)
  local session = transport.getSession()
  if not session or not session.userId or session.userId == "0" or not session.token or session.token == "" then
    transport.debugLog("catalog.setFavorite failed: no session")
    return false
  end

  local hash = tostring(args and args.id or "")
  if hash == "" then
    transport.debugLog("catalog.setFavorite failed: empty hash")
    return false
  end
  local isFav = args.favorite == true
  transport.debugLog("catalog.setFavorite hash=" .. hash .. " fav=" .. tostring(isFav))

  if isFav then
    -- 添加到“我喜欢” (listid = 2)
    local name = tostring(args.name or args.title or "歌曲")
    local nowSec = tostring(math.floor(host.now() / 1000))
    local res, err = transport.request({
      method = "POST",
      path = "/cloudlist.service/v6/add_song",
      params = {
        last_time = nowSec,
        last_area = "gztx",
        userid = tostring(session.userId),
        token = session.token
      },
      body = {
        userid = tostring(session.userId),
        token = session.token,
        listid = "2",
        list_ver = 0,
        type = 0,
        slow_upload = 1,
        scene = "false;null",
        data = {
          {
            number = 1,
            name = name,
            hash = hash:upper(),
            size = 0,
            sort = 0,
            timelen = 0,
            bitrate = 0,
            album_id = 0,
            mixsongid = 0
          }
        }
      }
    })
    transport.debugLog("catalog.setFavorite add res=" .. tostring(res and res.status) .. " err=" .. tostring(err))
    if res and res.data and res.data.info and res.data.info[1] then
      local fid = res.data.info[1].fileid
      if fid then
        discover.fileIdMap[hash:lower()] = fid
      end
    end
    return true
  else
    -- 取消收藏：从“我喜欢”删除 (listid = 2)
    local fid = discover.fileIdMap[hash:lower()]
    if not fid then
      -- 查一次列表刷新映射
      discover.favorites({ limit = 500, offset = 0 })
      fid = discover.fileIdMap[hash:lower()]
    end
    transport.debugLog("catalog.setFavorite delete fid=" .. tostring(fid))
    if fid then
      local res, err = transport.request({
        method = "POST",
        path = "/v4/delete_songs",
        router = "cloudlist.service.kugou.com",
        body = {
          listid = "2",
          userid = tostring(session.userId),
          token = session.token,
          type = 0,
          list_ver = 0,
          data = {
            { fileid = fid }
          }
        }
      })
      transport.debugLog("catalog.setFavorite delete res=" .. tostring(res and res.status) .. " err=" .. tostring(err))
      discover.fileIdMap[hash:lower()] = nil
    end
    return true
  end
end

return catalog
