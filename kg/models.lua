local models = {}

-- 歌曲实体转换
function models.song(raw)
  if not raw or type(raw) ~= "table" then return nil end

  local hash = raw.FileHash or raw.hash or raw.AudioHash or raw.HQFileHash or raw.SQFileHash or raw.hash_128 or raw.hash_320 or raw.hash_flac or ""
  if not hash or hash == "" then return nil end

  local songName = raw.SongName or raw.songname or raw.OriSongName or raw.audio_name or ""
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
    local min, sec, ms, text = string.match(line, "%[(%d+):(%d+)[.](%d+)%](.*)")
    if min and sec and ms then
      local startMs = tonumber(min) * 60000 + tonumber(sec) * 1000 + tonumber(ms)
      table.insert(lines, {
        text = text:match("^%s*(.-)%s*$") or "",
        startMs = startMs
      })
    end
  end

  return lines
end

return models
