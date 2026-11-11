local models = {}

-- 解析歌手名列表（酷狗歌手名常用 "、"、";"、"/" 分隔）
local function parseArtists(singerName, singerId)
  local artists = {}
  if not singerName or singerName == "" then
    return artists
  end

  for name in string.gmatch(singerName, "[^、;/]+") do
    local trimmed = name:match("^%s*(.-)%s*$")
    if trimmed ~= "" then
      table.insert(artists, {
        id = tostring(singerId or trimmed),
        name = trimmed
      })
    end
  end
  if #artists == 0 and singerName ~= "" then
    table.insert(artists, {
      id = tostring(singerId or singerName),
      name = singerName
    })
  end
  return artists
end

-- 歌曲实体转换
function models.song(raw)
  if not raw then return nil end

  local hash = raw.FileHash or raw.hash or raw.AudioHash or raw.HQFileHash or raw.SQFileHash or ""
  local songName = raw.SongName or raw.songname or raw.FileName or ""
  local singerName = raw.SingerName or raw.singername or ""

  -- 如果只有 FileName，尝试拆分 "歌手 - 歌名"
  if songName == "" and raw.FileName then
    local s, n = string.match(raw.FileName, "^(.-)%s*-%s*(.+)$")
    if s and n then
      singerName = s
      songName = n
    else
      songName = raw.FileName
    end
  end

  local cover = raw.Image or raw.AlbumImg or raw.Img or raw.cover or ""
  if cover and cover ~= "" then
    -- 酷狗图片链接模版修复，如 {size} 替换为 400
    cover = cover:gsub("{size}", "400")
  end

  local durationSec = tonumber(raw.Duration or raw.duration or raw.timelength or 0)
  -- 酷狗某些接口 duration 是秒，某些是毫秒
  local durationMs = durationSec
  if durationSec > 0 and durationSec < 10000 then
    durationMs = durationSec * 1000
  end

  local albumId = raw.AlbumID or raw.album_id or raw.AlbumId
  local albumName = raw.AlbumName or raw.album_name or ""

  return {
    id = tostring(hash),
    title = songName ~= "" and songName or "未知歌曲",
    artists = parseArtists(singerName, raw.SingerID or raw.singer_id),
    albumId = albumId and tostring(albumId) or nil,
    albumName = albumName,
    coverUrl = cover ~= "" and cover or nil,
    durationMs = math.floor(durationMs or 0),
    starred = raw.starred == true
  }
end

-- 歌单实体转换
function models.playlist(raw)
  if not raw then return nil end

  local cover = raw.imgurl or raw.pic or raw.cover or ""
  if cover ~= "" then
    cover = cover:gsub("{size}", "400")
  end

  return {
    id = tostring(raw.specialid or raw.id or raw.listid or ""),
    name = raw.specialname or raw.name or raw.title or "歌单",
    description = raw.intro or raw.description or "",
    coverUrl = cover ~= "" and cover or nil,
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
        text = text:match("^%s*(.-)%s*$"),
        startMs = startMs
      })
    end
  end

  return lines
end

return models
