local models = {}

-- 歌曲实体转换
function models.song(raw)
  if not raw or type(raw) ~= "table" then return nil end

  local hash = raw.FileHash or raw.hash or raw.AudioHash or raw.HQFileHash or raw.SQFileHash or raw.hash_128 or raw.hash_320 or raw.hash_flac or ""
  if not hash or hash == "" then return nil end

  local songName = raw.SongName or raw.songname or raw.OriSongName or raw.audio_name or ""
  local singerName = raw.SingerName or raw.singername or raw.author_name or ""

  -- 如果没有提取出 songName，但有 FileName (如 "歌手 - 歌名")
  if songName == "" and (raw.FileName or raw.filename) then
    local fn = raw.FileName or raw.filename
    local s, n = string.match(fn, "^(.-)%s*-%s*(.+)$")
    if s and n then
      if singerName == "" then singerName = s end
      songName = n
    else
      songName = fn
    end
  end

  -- 提取歌手列表，优先使用结构化的 Singers / authors 数组
  local artists = {}
  local singerArr = raw.Singers or raw.authors or raw.singers
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
  local durationSec = tonumber(raw.Duration or raw.duration or raw.timelength or raw.timelength_128 or 0)
  local durationMs = durationSec
  if durationSec and durationSec > 0 and durationSec < 10000 then
    durationMs = durationSec * 1000
  end

  -- 提取专辑 ID 和名称
  local rawAlbumId = raw.AlbumID or raw.album_id or raw.AlbumId
  local albumId = nil
  if rawAlbumId and tostring(rawAlbumId) ~= "0" and tostring(rawAlbumId) ~= "" then
    albumId = tostring(rawAlbumId)
  end

  local albumName = raw.AlbumName or raw.album_name or ""

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

  local cover = raw.sizable_cover or raw.cover or raw.pic or ""
  if cover and cover ~= "" then
    cover = cover:gsub("^http://", "https://")
    cover = cover:gsub("{size}", "400")
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
  end

  local year = nil
  if raw.publish_date and type(raw.publish_date) == "string" then
    local y = raw.publish_date:match("^(%d%d%d%d)")
    if y then year = tonumber(y) end
  end

  return {
    id = tostring(raw.album_id or raw.AlbumID or raw.id or ""),
    title = tostring(raw.album_name or raw.AlbumName or raw.name or "专辑"),
    artists = artists,
    coverUrl = (cover and cover ~= "") and cover or nil,
    year = year,
    songCount = tonumber(raw.song_count or raw.AudioCount or 0),
    description = tostring(raw.intro or "")
  }
end

-- 歌单实体转换
function models.playlist(raw)
  if not raw or type(raw) ~= "table" then return nil end

  local cover = raw.imgurl or raw.pic or raw.cover or raw.special_cover or ""
  if cover and cover ~= "" then
    cover = cover:gsub("^http://", "https://")
    cover = cover:gsub("{size}", "400")
  end

  return {
    id = tostring(raw.specialid or raw.id or raw.listid or ""),
    name = tostring(raw.specialname or raw.name or raw.title or "歌单"),
    description = tostring(raw.intro or raw.description or ""),
    coverUrl = (cover and cover ~= "") and cover or nil,
    songCount = tonumber(raw.songcount or raw.total or raw.count or 0),
    owner = raw.nickname or raw.username or raw.user_name,
    isFavorites = raw.isFavorites == true
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
