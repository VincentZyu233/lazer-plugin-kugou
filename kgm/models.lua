local models = {}

-- 内存缓存 hash -> album_audio_id
models.songIdCache = {}

function models.cacheAudioId(hash, audioId)
  if hash and hash ~= "" and audioId and tostring(audioId) ~= "" and tostring(audioId) ~= "0" then
    models.songIdCache[string.lower(tostring(hash))] = tostring(audioId)
  end
end

function models.getAudioId(hash)
  if not hash or hash == "" then return nil end
  return models.songIdCache[string.lower(tostring(hash))]
end

-- 歌曲实体转换
function models.song(raw)
  if not raw or type(raw) ~= "table" then return nil end

  local hash = raw.FileHash or raw.hash or raw.AudioHash or raw.HQFileHash or raw.SQFileHash or raw.hash_128 or raw.hash_320 or raw.hash_flac or ""
  if not hash or hash == "" then return nil end

  -- 记录 album_audio_id 映射 (仅记录真实的 album_audio_id / mixsongid，避免旧 audio_id 污染导致评论区 0 条评论)
  local audioId = raw.album_audio_id or raw.AlbumAudioId or raw.mixsongid or raw.MixSongID
  if audioId and tostring(audioId) ~= "0" and tostring(audioId) ~= "" then
    local candidateHashes = {
      raw.FileHash, raw.hash, raw.AudioHash, raw.HQFileHash, raw.SQFileHash,
      raw.hash_128, raw.hash_320, raw.hash_flac, raw.hash_high, raw.hash_super,
      raw.ResFileHash, raw.res_file_hash
    }
    for _, h in ipairs(candidateHashes) do
      if h and type(h) == "string" and h ~= "" then
        models.cacheAudioId(h, audioId)
      end
    end
  end

  local songName = raw.SongName or raw.songname or raw.OriSongName or raw.audio_name or ""
  local suffix = raw.Suffix or raw.suffix or raw.SongNameSuffix or raw.songNameSuffix or raw.Remark or raw.remark or ""
  if suffix ~= "" and type(suffix) == "string" and not string.find(songName, suffix, 1, true) then
    if string.sub(suffix, 1, 1) == "(" or string.sub(suffix, 1, 1) == "（" then
      songName = songName .. " " .. suffix
    else
      songName = songName .. " (" .. suffix .. ")"
    end
  end
  local singerName = raw.SingerName or raw.singername or raw.author_name or ""

  -- 如果没有提取出 songName，但有 FileName 或 name (如 "歌手 - 歌名")
  local fallbackName = raw.FileName or raw.filename or raw.name or ""
  if songName == "" and fallbackName ~= "" then
    local dashStart, dashEnd = string.find(fallbackName, " - ", 1, true)
    if dashStart then
      if singerName == "" then
        singerName = string.sub(fallbackName, 1, dashStart - 1)
      end
      songName = string.sub(fallbackName, dashEnd + 1)
    else
      songName = fallbackName
    end
    -- 去掉末尾的音频扩展名
    local sLen = string.len(songName)
    if sLen > 4 then
      local ext = string.lower(string.sub(songName, -4))
      if ext == ".mp3" or ext == ".m4a" then
        songName = string.sub(songName, 1, -5)
      elseif sLen > 5 and string.lower(string.sub(songName, -5)) == ".flac" then
        songName = string.sub(songName, 1, -6)
      end
    end
  end

  -- 提取歌手列表，优先使用结构化的 Singers / authors / singerinfo 数组
  local artists = {}
  local singerArr = raw.Singers or raw.authors or raw.singers or raw.singerinfo
  if singerArr and type(singerArr) == "table" and #singerArr > 0 then
    for _, s in ipairs(singerArr) do
      local name = s.name or s.author_name or s.singername
      if name and name ~= "" then
        table.insert(artists, {
          id = tostring(s.id or s.author_id or s.singerid or name),
          name = tostring(name)
        })
      end
    end
  end

  if #artists == 0 and singerName ~= "" then
    table.insert(artists, {
      id = tostring(raw.SingerID or raw.singer_id or raw.author_id or singerName),
      name = tostring(singerName)
    })
  end

  -- 提取封面
  local cover = raw.Image or raw.AlbumImg or raw.Img or raw.cover or raw.sizable_cover or ""
  if (not cover or cover == "") and raw.trans_param and raw.trans_param.union_cover then
    cover = raw.trans_param.union_cover
  end
  if cover and cover ~= "" then
    cover = cover:gsub("^http://", "https://")
    cover = cover:gsub("{size}", "400")
  end

  -- 提取时长 (毫秒)
  local rawDuration = tonumber(raw.Duration or raw.duration or raw.timelength or raw.timelength_128 or raw.timelen or 0)
  local durationMs = rawDuration
  if rawDuration and rawDuration > 0 and rawDuration < 10000 then
    durationMs = rawDuration * 1000
  end

  -- 提取专辑 ID 和名称
  local rawAlbumId = raw.AlbumID or raw.album_id or raw.AlbumId or (raw.albuminfo and raw.albuminfo.id)
  local albumId = nil
  if rawAlbumId and tostring(rawAlbumId) ~= "0" and tostring(rawAlbumId) ~= "" then
    albumId = tostring(rawAlbumId)
  end

  local albumName = raw.AlbumName or raw.album_name or (raw.albuminfo and raw.albuminfo.name) or ""

  return {
    id = tostring(hash),
    title = songName ~= "" and songName or "未知歌曲",
    artists = artists,
    albumId = albumId,
    albumName = albumName,
    coverUrl = (cover and cover ~= "") and cover or nil,
    durationMs = math.floor(durationMs or 0),
    starred = raw.starred == true
  }
end

-- 歌手实体转换
function models.artist(raw)
  if not raw or type(raw) ~= "table" then return nil end

  local avatar = raw.sizable_avatar or raw.avatar or raw.Avatar or raw.pic or raw.img or ""
  if avatar and avatar ~= "" then
    avatar = avatar:gsub("^http://", "https://")
    avatar = avatar:gsub("{size}", "480")
    avatar = avatar:gsub("/240/", "/480/")
    avatar = avatar:gsub("/150/", "/480/")
  end

  local desc = raw.intro or raw.Intro or ""
  if (not desc or desc == "") and raw.long_intro and type(raw.long_intro) == "table" and #raw.long_intro > 0 then
    local p = {}
    for _, item in ipairs(raw.long_intro) do
      if item and item.content then table.insert(p, item.content) end
    end
    desc = table.concat(p, "\n\n")
  end

  return {
    id = tostring(raw.author_id or raw.AuthorId or raw.id or raw.singerid or ""),
    name = tostring(raw.author_name or raw.AuthorName or raw.name or raw.singername or "未知歌手"),
    coverUrl = (avatar and avatar ~= "") and avatar or nil,
    description = tostring(desc),
    albumCount = tonumber(raw.album_count or raw.AlbumCount or 0),
    songCount = tonumber(raw.song_count or raw.AudioCount or 0)
  }
end

-- 专辑实体转换
function models.album(raw)
  if not raw or type(raw) ~= "table" then return nil end

  local cover = raw.sizable_cover or raw.cover or raw.pic or raw.img or ""
  if cover and cover ~= "" then
    cover = cover:gsub("^http://", "https://")
    cover = cover:gsub("{size}", "400")
    cover = cover:gsub("/240/", "/400/")
    cover = cover:gsub("/150/", "/400/")
  end

  local artists = {}
  local authors = raw.authors or raw.Singers or raw.singers
  if authors and type(authors) == "table" and #authors > 0 then
    for _, a in ipairs(authors) do
      local name = a.author_name or a.name or a.AuthorName
      if name and name ~= "" then
        table.insert(artists, {
          id = tostring(a.author_id or a.AuthorId or a.id or name),
          name = tostring(name)
        })
      end
    end
  elseif (raw.author_name and raw.author_name ~= "") or (raw.AuthorName and raw.AuthorName ~= "") then
    local aName = raw.author_name or raw.AuthorName
    table.insert(artists, {
      id = tostring(raw.author_id or raw.AuthorId or aName),
      name = tostring(aName)
    })
  elseif raw.singer and raw.singer ~= "" then
    table.insert(artists, {
      id = tostring(raw.singerid or raw.singer),
      name = tostring(raw.singer)
    })
  end

  local pubStr = tostring(raw.publish_date or raw.publish_time or "")
  local year = nil
  if string.len(pubStr) >= 4 then
    local subY = string.sub(pubStr, 1, 4)
    local nY = tonumber(subY)
    if nY and nY > 1900 and nY < 2100 then
      year = nY
    end
  end

  return {
    id = tostring(raw.album_id or raw.AlbumID or raw.albumid or raw.id or ""),
    title = tostring(raw.album_name or raw.AlbumName or raw.albumname or raw.name or "专辑"),
    artists = artists,
    coverUrl = (cover and cover ~= "") and cover or nil,
    year = year,
    songCount = tonumber(raw.song_count or raw.songcount or raw.AudioCount or 0),
    description = tostring(raw.intro or raw.short_intro or "")
  }
end

-- 歌单实体转换 (通用支持公共特辑歌单与用户个人歌单)
function models.playlist(raw, currentSession)
  if not raw or type(raw) ~= "table" then return nil end

  local cover = raw.imgurl or raw.pic or raw.cover or raw.special_cover or raw.img or ""
  if cover and cover ~= "" then
    cover = cover:gsub("^http://", "https://")
    cover = cover:gsub("{size}", "400")
    cover = cover:gsub("/150/", "/400/")
  end

  local owner = raw.list_create_username or raw.nickname or raw.username or raw.user_name
  local isMine = raw.is_mine == 1 or raw.type == 0
  if currentSession and currentSession.userName and currentSession.userName ~= "" and owner == currentSession.userName then
    isMine = true
  end
  local writable = raw.writable == true or isMine

  return {
    id = tostring(raw.listid or raw.specialid or raw.id or ""),
    name = tostring(raw.specialname or raw.name or raw.title or "歌单"),
    description = tostring(raw.intro or raw.description or ""),
    coverUrl = (cover and cover ~= "") and cover or nil,
    songCount = tonumber(raw.count or raw.m_count or raw.song_count or raw.songcount or raw.total or 0),
    owner = owner and tostring(owner) or nil,
    writable = writable,
    isPublic = raw.is_pri ~= 1,
    isFavorites = raw.isFavorites == true or tonumber(raw.is_def or 0) == 2
  }
end

-- 解析标准 LRC 文本为带有时间轴的行
function models.parseLrc(lrcText)
  if not lrcText or lrcText == "" then return {} end
  local lines = {}

  for line in string.gmatch(lrcText, "[^\r\n]+") do
    if string.sub(line, 1, 1) == "[" then
      local rightBracket = string.find(line, "]", 2, true)
      if rightBracket then
        local timePart = string.sub(line, 2, rightBracket - 1)
        local colonPos = string.find(timePart, ":", 1, true)
        if colonPos then
          local minStr = string.sub(timePart, 1, colonPos - 1)
          local min = tonumber(minStr)
          if min then
            local rest = string.sub(timePart, colonPos + 1)
            local dotPos = string.find(rest, ".", 1, true) or string.find(rest, ":", 1, true)
            local sec, ms = 0, 0
            if dotPos then
              sec = tonumber(string.sub(rest, 1, dotPos - 1)) or 0
              local msStr = string.sub(rest, dotPos + 1)
              local msVal = tonumber(msStr) or 0
              local msLen = string.len(msStr)
              if msLen == 2 then
                msVal = msVal * 10
              elseif msLen == 1 then
                msVal = msVal * 100
              end
              ms = msVal
            else
              sec = tonumber(rest) or 0
            end
            local startMs = min * 60000 + sec * 1000 + ms
            local text = string.sub(line, rightBracket + 1)
            local firstNonSpace = 1
            local lastNonSpace = string.len(text)
            while firstNonSpace <= lastNonSpace and string.byte(text, firstNonSpace) <= 32 do
              firstNonSpace = firstNonSpace + 1
            end
            while lastNonSpace >= firstNonSpace and string.byte(text, lastNonSpace) <= 32 do
              lastNonSpace = lastNonSpace - 1
            end
            local cleanText = string.sub(text, firstNonSpace, lastNonSpace)
            table.insert(lines, {
              text = cleanText,
              startMs = startMs
            })
          end
        end
      end
    end
  end

  return lines
end

-- 单条评论模型转换 (兼容 Lazer SongComment 格式)
function models.comment(raw)
  if not raw or type(raw) ~= "table" then return nil end

  local avatar = raw.user_pic
  if avatar and type(avatar) == "string" then
    local pStart, pEnd = string.find(avatar, "{size}", 1, true)
    if pStart and pEnd then
      avatar = string.sub(avatar, 1, pStart - 1) .. "150" .. string.sub(avatar, pEnd + 1)
    end
  end

  local likedCount = 0
  local liked = false
  if raw.like and type(raw.like) == "table" then
    likedCount = tonumber(raw.like.like_num or 0) or 0
    liked = raw.like.is_like == 1
  end

  local replies = {}
  if raw.reply_list and type(raw.reply_list) == "table" then
    for _, r in ipairs(raw.reply_list) do
      if r and r.content and r.content ~= "" then
        table.insert(replies, {
          author = tostring(r.user_name or ""),
          content = tostring(r.content or "")
        })
      end
    end
  end

  local timeMs = 0
  if raw.addtime then
    local tStr = tostring(raw.addtime)
    local num = tonumber(tStr)
    if num then
      timeMs = num > 10000000000 and num or num * 1000
    else
      -- 纯字符串解析 "YYYY-MM-DD HH:MM:SS" (避免 lua_dardo_plus 的正则缺陷)
      if string.len(tStr) >= 19 and string.sub(tStr, 5, 5) == "-" and string.sub(tStr, 8, 8) == "-" then
        local y = tonumber(string.sub(tStr, 1, 4))
        local m = tonumber(string.sub(tStr, 6, 7))
        local d = tonumber(string.sub(tStr, 9, 10))
        local h = tonumber(string.sub(tStr, 12, 13))
        local mi = tonumber(string.sub(tStr, 15, 16))
        local s = tonumber(string.sub(tStr, 18, 19))
        if y and m and d and h and mi and s then
          local days = (y - 1970) * 365 + math.floor((y - 1969) / 4)
          local mDays = { 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334 }
          if (y % 4 == 0 and y % 100 ~= 0) or (y % 400 == 0) then
            if m > 2 then days = days + 1 end
          end
          days = days + (mDays[m] or 0) + (d - 1)
          local sec = days * 86400 + h * 3600 + mi * 60 + s - 28800
          timeMs = sec * 1000
        end
      end
      if timeMs == 0 then
        timeMs = (host and host.now and host.now()) or 0
      end
    end
  end

  return {
    id = tostring(raw.id or ""),
    content = tostring(raw.content or ""),
    author = tostring(raw.user_name or "酷狗听众"),
    authorId = tostring(raw.user_id or ""),
    avatarUrl = avatar,
    time = timeMs,
    location = raw.location and tostring(raw.location) or nil,
    liked = liked,
    likedCount = likedCount,
    replies = replies
  }
end

return models
