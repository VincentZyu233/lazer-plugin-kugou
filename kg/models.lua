local models = {}

-- 歌曲实体转换
function models.song(raw)
  if not raw or type(raw) ~= "table" then return nil end

  local hash = raw.FileHash or raw.hash or raw.AudioHash or raw.HQFileHash or raw.SQFileHash or ""
  if not hash or hash == "" then return nil end

  local songName = raw.SongName or raw.songname or raw.OriSongName or ""
  local singerName = raw.SingerName or raw.singername or ""

  -- 如果没有提取出 songName，但有 FileName (如 "歌手 - 歌名")
  if songName == "" and raw.FileName then
    local s, n = string.match(raw.FileName, "^(.-)%s*-%s*(.+)$")
    if s and n then
      if singerName == "" then singerName = s end
      songName = n
    else
      songName = raw.FileName
    end
  end

  -- 提取歌手列表，优先使用结构化的 Singers 数组
  local artists = {}
  if raw.Singers and type(raw.Singers) == "table" and #raw.Singers > 0 then
    for _, s in ipairs(raw.Singers) do
      if s and s.name and s.name ~= "" then
        table.insert(artists, {
          id = tostring(s.id or s.name),
          name = tostring(s.name)
        })
      end
    end
  end

  if #artists == 0 and singerName ~= "" then
    -- 如果是分隔符格式，安全提取
    table.insert(artists, {
      id = tostring(raw.SingerID or raw.singer_id or singerName),
      name = tostring(singerName)
    })
  end

  local cover = raw.Image or raw.AlbumImg or raw.Img or raw.cover or ""
  if cover and cover ~= "" then
    cover = cover:gsub("^http://", "https://")
    cover = cover:gsub("{size}", "400")
  end

  local durationSec = tonumber(raw.Duration or raw.duration or raw.timelength or 0)
  local durationMs = durationSec
  if durationSec and durationSec > 0 and durationSec < 10000 then
    durationMs = durationSec * 1000
  end

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

-- 歌单实体转换
function models.playlist(raw)
  if not raw or type(raw) ~= "table" then return nil end

  local cover = raw.imgurl or raw.pic or raw.cover or ""
  if cover and cover ~= "" then
    cover = cover:gsub("^http://", "https://")
    cover = cover:gsub("{size}", "400")
  end

  return {
    id = tostring(raw.specialid or raw.id or raw.listid or ""),
    name = raw.specialname or raw.name or raw.title or "歌单",
    description = raw.intro or raw.description or "",
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
