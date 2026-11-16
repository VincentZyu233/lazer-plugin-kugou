--[[
  krc.lua - 酷狗动感逐字歌词 (KRC) 解析引擎

  解密由宿主负责（host.crypto 的 krc_decode：Base64 -> 跳过 4 字节魔数 ->
  16 字节 XOR -> zlib inflate）。本模块只做明文解析：

  1. 逐行切分，纯字节扫描（lua_dardo_plus 的 string.match 不支持 Lua 模式）
  2. 逐字歌词：<rel,dur,flag> 转换为 Lazer 原生的 (absStart,dur,flag) YRC 语法
  3. 时间戳对齐行：生成 lines = { { startMs = ..., text = ... } }
  4. 双语翻译与罗马音：解析 [language:Base64] 内嵌的 type=1 / type=0

  纯 Lua 的 inflate 内核与 base64 密文解密路径已移除：宿主不提供 krc_decode
  时无法可靠解密，且那两条路径依赖 string.gmatch / %d 模式，在 Dart 解释器下
  必然失效。base64_decode_bin 仅保留给 [language:] 负载与 LRC 兜底解码。
--]]

local krc = {}

-- 1. Base64 二进制解码器
local byte, char, sub, find, len = string.byte, string.char, string.sub, string.find, string.len
local concat = table.concat
local format = string.format
local bxor = function(a, b) return (bit32 and bit32.bxor and bit32.bxor(a, b)) or (a ~ b) end

local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local b64lookup = {}
for i = 1, string.len(b64chars) do b64lookup[byte(b64chars, i)] = i - 1 end
b64lookup[byte('-')] = 62
b64lookup[byte('_')] = 63

function krc.base64_decode_bin(str)
  if not str or str == "" then return "" end
  local t = {}
  local tIdx = 0
  local buf, bits = 0, 0
  local len = string.len(str)
  for i = 1, len do
    local c = byte(str, i)
    local val = b64lookup[c]
    if val then
      buf = (buf << 6) | val
      bits = bits + 6
      if bits >= 8 then
        bits = bits - 8
        tIdx = tIdx + 1
        t[tIdx] = char((buf >> bits) & 255)
      end
    end
  end
  return concat(t)
end

-- 3. KRC 密钥与辅助函数
local KRC_KEY = { 64, 71, 97, 119, 94, 50, 116, 71, 81, 54, 49, 45, 206, 210, 110, 105 }

local function format_lrc_time(ms)
  local totalSec = math.floor(ms / 1000)
  local m = math.floor(totalSec / 60)
  local s = totalSec % 60
  local cs = math.floor((ms % 1000) / 10)
  return string.format("[%02d:%02d.%02d]", m, s, cs)
end

--- 解析宿主已经解密好的 KRC 明文字符串为 YRC 逐字动感格式 (纯字符串截取，杜绝嵌入式正则缺陷)
-- @param text 宿主 krc_decode 解密后的明文字符串
-- @param rawTrans 可选的酷狗返回的 trans 翻译 Base64 字符串
-- @return table 包含 lines, wordByWord, lrc, translation, synced
function krc.parseDecodedText(text, rawTrans)
  if not text or text == "" then return nil end

  local lines = {}
  local linesCount = 0
  local yrcLines = {}
  local yrcCount = 0
  local plainLrcLines = {}
  local plainCount = 0
  local transSec = nil
  local romSec = nil
  local embeddedTransLines = {}
  local rawTransCount = 0
  local transLines = {}
  local transCount = 0
  local embeddedRomanLines = {}
  local rawRomanCount = 0
  local romanLines = {}
  local romanCount = 0

  -- 纯字符串按行切分
  local allLines = {}
  local pos = 1
  local textLen = len(text)
  while pos <= textLen do
    local nxt = find(text, "\n", pos, true)
    local line
    if nxt then
      line = sub(text, pos, nxt - 1)
      pos = nxt + 1
    else
      line = sub(text, pos)
      pos = textLen + 1
    end
    if len(line) > 0 and sub(line, -1) == "\r" then
      line = sub(line, 1, -2)
    end
    table.insert(allLines, line)
  end

  -- 1. 解析内嵌的 [language:Base64]
  for _, line in ipairs(allLines) do
    if sub(line, 1, 10) == "[language:" then
      local rightB = find(line, "]", 11, true)
      local b64Payload = rightB and sub(line, 11, rightB - 1) or sub(line, 11)
      local jsonStr = nil
      if host and host.crypto then
        local okDec, decStr = pcall(function()
          return host.crypto({ operation = "base64_decode", input = b64Payload })
        end)
        if okDec and decStr and decStr ~= "" then jsonStr = decStr end
      end
      if not jsonStr then
        jsonStr = krc.base64_decode_bin(b64Payload)
      end
      if jsonStr and jsonStr ~= "" and host and host.json_decode then
        local okJson, langData = pcall(host.json_decode, jsonStr)
        if okJson and langData and langData.content then
          -- type=1 为双语中文翻译。对齐 KugouMusic.NET 默认纯翻译行为，不提取 type=0 罗马音，
          -- 避免与 Lazer 宿主单副行机制竞态导致中罗穿插混杂。
          local function collect(section)
            local out = {}
            if section and section.lyricContent and type(section.lyricContent) == "table" then
              for _, item in ipairs(section.lyricContent) do
                if type(item) == "table" then
                  local parts = {}
                  for i = 1, #item do parts[i] = tostring(item[i] or "") end
                  out[#out + 1] = table.concat(parts)
                else
                  out[#out + 1] = tostring(item or "")
                end
              end
            end
            return out
          end
          for _, sec in ipairs(langData.content) do
            if sec.type == 1 and not transSec then
              transSec = sec
            elseif sec.type == 0 and not romSec then
              romSec = sec
            end
          end
          embeddedTransLines = collect(transSec)
          rawTransCount = #embeddedTransLines
          embeddedRomanLines = collect(romSec)
          rawRomanCount = #embeddedRomanLines
        end
      end
      break
    end
  end

  -- 2. 解析逐行歌词与逐字数据
  for _, rawLine in ipairs(allLines) do
    local lStart, lEnd = 1, len(rawLine)
    while lStart <= lEnd and (sub(rawLine, lStart, lStart) == " " or sub(rawLine, lStart, lStart) == "\t") do
      lStart = lStart + 1
    end
    while lEnd >= lStart and (sub(rawLine, lEnd, lEnd) == " " or sub(rawLine, lEnd, lEnd) == "\t") do
      lEnd = lEnd - 1
    end
    local line = sub(rawLine, lStart, lEnd)

    if sub(line, 1, 1) == "[" then
      local commaPos = find(line, ",", 2, true)
      local bracketPos = commaPos and find(line, "]", commaPos + 1, true)
      if commaPos and bracketPos then
        local startMs = tonumber(sub(line, 2, commaPos - 1))
        local durMs = tonumber(sub(line, commaPos + 1, bracketPos - 1))
        if startMs and durMs then
          local rest = sub(line, bracketPos + 1)
          local yrcWords = {}
          local plainTextParts = {}
          local rPos = 1
          local rLen = len(rest)

          while rPos <= rLen do
            local ltPos = find(rest, "<", rPos, true)
            if not ltPos then break end
            local c1 = find(rest, ",", ltPos + 1, true)
            local c2 = c1 and find(rest, ",", c1 + 1, true)
            local gtPos = c2 and find(rest, ">", c2 + 1, true)
            if not (c1 and c2 and gtPos) then break end

            local relStr = sub(rest, ltPos + 1, c1 - 1)
            local wDurStr = sub(rest, c1 + 1, c2 - 1)
            local flagStr = sub(rest, c2 + 1, gtPos - 1)

            local nextLt = find(rest, "<", gtPos + 1, true)
            local wText = ""
            if nextLt then
              wText = sub(rest, gtPos + 1, nextLt - 1)
              rPos = nextLt
            else
              wText = sub(rest, gtPos + 1)
              rPos = rLen + 1
            end

            local rel = tonumber(relStr)
            if rel then
              local absStart = startMs + rel
              table.insert(yrcWords, "(" .. absStart .. "," .. wDurStr .. "," .. flagStr .. ")" .. wText)
              table.insert(plainTextParts, wText)
            end
          end

          if #yrcWords > 0 then
            linesCount = linesCount + 1
            local fullLineText = concat(plainTextParts)
            local yrcLine = "[" .. startMs .. "," .. durMs .. "]" .. concat(yrcWords)
            yrcCount = yrcCount + 1
            yrcLines[yrcCount] = yrcLine

            local lineItem = {
              startMs = startMs,
              text = fullLineText
            }

            plainCount = plainCount + 1
            plainLrcLines[plainCount] = format_lrc_time(startMs) .. fullLineText

            if rawTransCount >= linesCount then
              local transText = embeddedTransLines[linesCount] or ""
              local tS, tE = 1, len(transText)
              while tS <= tE and (sub(transText, tS, tS) == " " or sub(transText, tS, tS) == "\t") do
                tS = tS + 1
              end
              while tE >= tS and (sub(transText, tE, tE) == " " or sub(transText, tE, tE) == "\t") do
                tE = tE - 1
              end
              local cleanTrans = sub(transText, tS, tE)
              if cleanTrans ~= "" then
                transCount = transCount + 1
                transLines[transCount] = format_lrc_time(startMs) .. cleanTrans
                lineItem.translation = cleanTrans
              end
            end

            if rawRomanCount >= linesCount then
              local romanText = embeddedRomanLines[linesCount] or ""
              local rS, rE = 1, len(romanText)
              while rS <= rE and (sub(romanText, rS, rS) == " " or sub(romanText, rS, rS) == "\t") do
                rS = rS + 1
              end
              while rE >= rS and (sub(romanText, rE, rE) == " " or sub(romanText, rE, rE) == "\t") do
                rE = rE - 1
              end
              local cleanRoman = sub(romanText, rS, rE)
              if cleanRoman ~= "" then
                romanCount = romanCount + 1
                romanLines[romanCount] = format_lrc_time(startMs) .. cleanRoman
                lineItem.romanization = cleanRoman
              end
            end

            lines[linesCount] = lineItem
          end
        end
      end
    end
  end

  -- 3. 决定双语翻译输出
  local finalTranslation = nil
  if rawTrans and rawTrans ~= "" then
    if host and host.crypto then
      local okT, decT = pcall(function()
        return host.crypto({ operation = "base64_decode", input = rawTrans })
      end)
      if okT and decT and decT ~= "" then finalTranslation = decT end
    end
    if not finalTranslation then
      finalTranslation = krc.base64_decode_bin(rawTrans)
    end
  end
  if not finalTranslation and transCount > 0 then
    finalTranslation = concat(transLines, "\n")
  end

  local finalRomanization = nil
  if romanCount > 0 then
    finalRomanization = concat(romanLines, "\n")
  end

  local fullYrc = concat(yrcLines, "\n")
  local fullLrc = concat(plainLrcLines, "\n")

  return {
    lines = lines,
    wordByWord = fullYrc,
    lrc = fullLrc,
    translation = finalTranslation,
    romanization = finalRomanization,
    synced = linesCount > 0
  }
end

return krc
