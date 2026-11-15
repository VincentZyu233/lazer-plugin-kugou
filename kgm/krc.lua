--[[
  krc.lua - 酷狗动感逐字歌词 (KRC) 纯 Lua 解密与解析引擎
  
  解密管线：
  1. Base64 解码为二进制字节流
  2. 跳过前 4 字节魔数 (krc1 / @Gaw)
  3. 16 字节固定 XOR 密钥循环解密
  4. 纯 Lua RFC 1950 (Zlib) / RFC 1951 (Deflate) Inflate 解压缩
  5. 语法转换与映射：
     - 逐字歌词：<start,dur,0> 转换为 Lazer 原生识别的 (start,dur,0) 语法 (wordByWord / YRC)
     - 时间戳对齐行：生成 lines = { { startMs = ..., text = ... } }
     - 双语翻译：解析 [language:Base64] 内嵌翻译或外部 trans 字段
--]]

local krc = {}

-- 1. 纯 Lua Inflate 解压内核
local inflate = (function()
--[[lit-meta
	name = 'TohruMKDM/inflate'
	version = '2.0.0'
	homepage = 'https://github.com/TohruMKDM/lua-inflate'
	description = 'ZIP archive inflation in pure Lua.'
	tags = {'zlib', 'inflate', 'inflation', 'compression'}
	license = 'MIT'
	author = {name = 'Tohru~ (トール)', email = 'admin@ikaros.pw'}
    contributors = {'zerkman', 'samhocevar'}
]]

---@diagnostic disable-next-line: undefined-global
local bitOp = bit32 or bit or {
  rshift = function(a, b) return a >> b end,
  lshift = function(a, b) return a << b end,
  band = function(a, b) return a & b end,
  bxor = function(a, b) return a ~ b end,
  bnot = function(a) return ~a end,
}

local rshift, lshift, band, bxor, bnot = bitOp.rshift, bitOp.lshift, bitOp.band, bitOp.bxor, bitOp.bnot
local byte, char, sub, find = string.byte, string.char, string.sub, string.find
local concat, unpack = table.concat, unpack or table.unpack
local min = math.min

local ORDER = {17, 18, 19, 1, 9, 8, 10, 7, 11, 6, 12, 5, 13, 4, 14, 3, 15, 2, 16}
local CRC32 = {[0] = 0, 1996959894, -301047508, -1727442502, 124634137, 1886057615, -379345611, -1637575261, 249268274, 2044508324, -522852066, -1747789432, 162941995, 2125561021, -407360249, -1866523247, 498536548, 1789927666, -205950648, -2067906082, 450548861, 1843258603, -187386543, -2083289657, 325883990, 1684777152, -43845254,-1973040660, 335633487, 1661365465, -99664541, -1928851979, 997073096, 1281953886, -715111964, -1570279054, 1006888145, 1258607687, -770865667, -1526024853, 901097722, 1119000684, -608450090, -1396901568, 853044451, 1172266101, -589951537, -1412350631, 651767980, 1373503546, -925412992, -1076862698, 565507253, 1454621731, -809855591, -1195530993, 671266974, 1594198024, -972236366, -1324619484, 795835527, 1483230225, -1050600021, -1234817731, 1994146192, 31158534, -1731059524, -271249366, 1907459465, 112637215, -1614814043, -390540237, 2013776290, 251722036, -1777751922, -519137256, 2137656763, 141376813, -1855689577, -429695999, 1802195444, 476864866, -2056965928, -228458418, 1812370925, 453092731, -2113342271, -183516073, 1706088902, 314042704, -1950435094, -54949764, 1658658271, 366619977, -1932296973, -69972891, 1303535960, 984961486, -1547960204, -725929758, 1256170817, 1037604311, -1529756563, -740887301, 1131014506, 879679996, -1385723834, -631195440, 1141124467, 855842277, -1442165665, -586318647, 1342533948, 654459306, -1106571248, -921952122, 1466479909, 544179635, -1184443383, -832445281, 1591671054, 702138776, -1328506846, -942167884, 1504918807, 783551873, -1212326853, -1061524307, -306674912, -1698712650, 62317068, 1957810842, -355121351, -1647151185, 81470997,1943803523, -480048366, -1805370492, 225274430, 2053790376, -468791541, -1828061283, 167816743, 2097651377, -267414716, -2029476910, 503444072, 1762050814, -144550051, -2140837941, 426522225, 1852507879, -19653770, -1982649376, 282753626, 1742555852, -105259153, -1900089351, 397917763, 1622183637, -690576408, -1580100738, 953729732, 1340076626, -776247311, -1497606297, 1068828381, 1219638859, -670225446, -1358292148, 906185462, 1090812512, -547295293, -1469587627, 829329135, 1181335161, -882789492, -1134132454, 628085408, 1382605366, -871598187, -1156888829, 570562233, 1426400815, -977650754, -1296233688, 733239954, 1555261956, -1026031705, -1244606671, 752459403, 1541320221, -1687895376, -328994266, 1969922972, 40735498, -1677130071, -351390145, 1913087877, 83908371, -1782625662, -491226604, 2075208622, 213261112, -1831694693, -438977011, 2094854071, 198958881, -2032938284, -237706686, 1759359992, 534414190, -2118248755, -155638181, 1873836001, 414664567, -2012718362, -15766928, 1711684554, 285281116, -1889165569, -127750551, 1634467795, 376229701, -1609899400, -686959890, 1308918612, 956543938, -1486412191, -799009033, 1231636301, 1047427035, -1362007478, -640263460, 1088359270, 936918000, -1447252397, -558129467, 1202900863, 817233897, -1111625188, -893730166, 1404277552, 615818150, -1160759803, -841546093, 1423857449, 601450431, -1285129682, -1000256840, 1567103746, 711928724, -1274298825, -1022587231, 1510334235, 755167117}
local NBT = {2, 3, 7}
local CNT  = {144, 112, 24, 8}
local DPT = {8, 9, 7, 8}
local STATIC_HUFFMAN = {[0] = 5, 261, 133, 389, 69, 325, 197, 453, 37, 293, 165, 421, 101, 357, 229, 485, 21, 277, 149, 405, 85, 341, 213, 469, 53, 309, 181, 437, 117, 373, 245, 501}
local STATIC_BITS = 5
local CHUNK_SIZE = 4096

local function generateCrc32(input)
    local crc = -1
    for i = 1, string.len(input) do
        local c = byte(input, i)
        crc = bxor(CRC32[bxor(c, band(crc, 255))], rshift(crc, 8))
    end
    crc = bnot(crc)
    if crc < 0 then
        crc = crc + 4294967296
    end
    return crc
end

local function flushBits(stream, int)
    stream.bits = rshift(stream.bits, int)
    stream.count = stream.count - int
end

local function peekBits(stream, int)
    local buffer, bits, count, position = stream.buffer, stream.bits, stream.count, stream.position
    while count < int do
        bits = bits + lshift(byte(buffer, position), count)
        position = position + 1
        count = count + 8
    end
    stream.bits = bits
    stream.position = position
    stream.count = count
    return band(bits, lshift(1, int) - 1)
end

local function getBits(stream, int)
    local result = peekBits(stream, int)
    stream.bits = rshift(stream.bits, int)
    stream.count = stream.count - int
    return result
end

local function getElement(stream, hufftable, int)
    local element = hufftable[peekBits(stream, int)]
    local length = band(element, 15)
    local result = rshift(element, 4)
    stream.bits = rshift(stream.bits, length)
    stream.count = stream.count - length
    return result
end

local function huffman(depths)
    local size = #depths
    local blocks, codes, hufftable = {[0] = 0}, {}, {}
    local bits, code = 1, 0
    for i = 1, size do
        local depth = depths[i]
        if depth > bits then
            bits = depth
        end
        blocks[depth] = (blocks[depth] or 0) + 1
    end
    for i = 1, bits do
        code = (code + (blocks[i - 1] or 0)) * 2
        codes[i] = code
    end
    for i = 1, size do
        local depth = depths[i]
        if depth > 0 then
            local element = (i - 1) * 16 + depth
            local rcode = 0
            for j = 1, depth do
                rcode = rcode + lshift(band(1, rshift(codes[depth], j - 1)), depth - j)
            end
            for j = 0, 2 ^ bits - 1, 2 ^ depth do
                hufftable[j + rcode] = element
            end
            codes[depth] = codes[depth] + 1
        end
    end
    return hufftable, bits
end

local function loop(output, stream, litTable, litBits, distTable, distBits)
    local index = #output + 1
    local lit
    repeat
        lit = getElement(stream, litTable, litBits)
        if lit < 256 then
            output[index] = lit
            index = index + 1
        elseif lit > 256 then
            local bits, size, dist = 0, 3, 1
            if lit < 265 then
                size = size + lit - 257
            elseif lit < 285 then
                bits = rshift(lit - 261, 2)
                size = size + lshift(band(lit - 261, 3) + 4, bits)
            else
                size = 258
            end
            if bits > 0 then
                size = size + getBits(stream, bits)
            end
            local element = getElement(stream, distTable, distBits)
            if element < 4 then
                dist = dist + element
            else
                bits = rshift(element - 2, 1)
                dist = dist + lshift(band(element, 1) + 2, bits) + getBits(stream, bits)
            end
            local position = index - dist
            repeat
                output[index] = output[position]
                index = index + 1
                position = position + 1
                size = size - 1
            until size == 0
        end
    until lit == 256
end

local function dynamic(output, stream)
    local lit, dist, length = 257 + getBits(stream, 5), 1 + getBits(stream, 5), 4 + getBits(stream, 4)
    local depths = {}
    for i = 1, length do
        depths[ORDER[i]] = getBits(stream, 3)
    end
    for i = length + 1, 19 do
        depths[ORDER[i]] = 0
    end
    local lengthTable, lengthBits = huffman(depths)
    local i = 1
    local total = lit + dist + 1
    repeat
        local element = getElement(stream, lengthTable, lengthBits)
        if element < 16 then
            depths[i] = element
            i = i + 1
        elseif element < 19 then
            local int = NBT[element  - 15]
            local count = 0
            local num = 3 + getBits(stream, int)
            if element == 16 then
                count = depths[i - 1]
            elseif element == 18 then
                num = num + 8
            end
            for _ = 1, num do
                depths[i] = count
                i = i + 1
            end
        end
    until i == total
    local litDepths, distDepths = {}, {}
    for j = 1, lit do
        litDepths[j] = depths[j]
    end
    for j = lit + 1, #depths do
        distDepths[#distDepths + 1] = depths[j]
    end
    local litTable, litBits = huffman(litDepths)
    local distTable, distBits = huffman(distDepths)
    loop(output, stream, litTable, litBits, distTable, distBits)
end

local function static(output, stream)
    local depths = {}
    for i = 1, 4 do
        local depth = DPT[i]
        for _ = 1, CNT[i] do
            depths[#depths + 1] = depth
        end
    end
    local litTable, litBits = huffman(depths)
    loop(output, stream, litTable, litBits, STATIC_HUFFMAN, STATIC_BITS)
end

local function uncompressed(output, stream)
    flushBits(stream, band(stream.count, 7))
    local length = getBits(stream, 16); getBits(stream, 16)
    local buffer, position = stream.buffer, stream.position
    for i = position, position + length - 1 do
        output[#output + 1] = byte(buffer, i, i)
    end
    stream.position = position + length
end

local function int2le(buffer, position)
    local a, b = byte(buffer, position, position + 1)
    return b * 256 + a
end

local function int4le(buffer, position)
    local a, b, c, d = byte(buffer, position, position + 3)
    return ((d * 256 + c) * 256 + b) * 256 + a
end

local inflate = {}

---@class BitStream
---@field buffer string Character Buffer
---@field position integer Position in the character buffer
---@field bits integer Bits buffer
---@field count integer Number of bits in the buffer
local BitStream = {}
BitStream.__index = BitStream

---Creates a new bitstream object with the specified buffer
---@param buffer string The character buffer to use for the bitstream.
---@return BitStream
function inflate.new(buffer)
    local EOCD
    local pos = 1
    repeat
        local i, j = find(buffer, 'PK\x05\x06', pos, true)
        if i then
            EOCD = i
            pos = j + 1
        end
    until not i
    if EOCD then
        buffer = sub(buffer, 1, EOCD + 19)..'\x00\x00'
    end
    local object = {buffer = buffer, position = 0, bits = 0, count = 0}
    return setmetatable(object, BitStream)
end
---Update the chunk size to be used in inflation. Defaults to `4096`
---@param size integer The new chunk size, should be a power of 2.
function inflate.setChunkSize(size)
    CHUNK_SIZE = size
end

---Returns an iterator that spans the list of files in the stream
---@return fun(): name: string?, offset: integer?, size: integer?, packed: boolean?, crc: integer?
function BitStream:files()
    local buffer = self.buffer
    local position = int4le(buffer, string.len(buffer) - 5) + 1
    return function()
        if int4le(buffer, position) ~= 33639248 then
            return
        end
        local packed = int2le(buffer, position + 10) ~= 0
        local crc = int4le(buffer, position + 16)
        local length = int2le(buffer, position + 28)
        local offset = int4le(buffer, position + 42) + 1
        local name = sub(buffer, position + 46, position + 45 + length)
        position = position + 46 + length + int2le(buffer, position + 30) + int2le(buffer, position + 32)
        return name, offset + 30 + length + int2le(buffer, offset + 28), int4le(buffer, offset + 18), packed, crc
    end
end
---Inflates the bitstream starting from the specified offset and optionally performs checksum verification
---@param offset integer The position at which to begin inflating.
---@param crc? integer The checksum value to use for verification.
---@return string
function BitStream:inflate(offset, crc)
    local output, buffer = {}, {}
    local last, typ
    self.bits = 0
    self.count = 0
    self.position = offset
    repeat
        last, typ = getBits(self, 1), getBits(self, 2)
        typ = typ == 0 and uncompressed(output, self) or typ == 1 and static(output, self) or typ == 2 and dynamic(output, self) 
    until last == 1
    local size = #output
    for i = 1, size, CHUNK_SIZE do
        buffer[#buffer + 1] = char(unpack(output, i, min(i + CHUNK_SIZE - 1, size)))
    end
    local result = concat(buffer)
    if crc and crc ~= generateCrc32(result) then
        error("Checksum verification failed: the computed CRC does not match the expected value.", 2)
    end
    return result
end
---Extracts a specific file from the bitstream
---@param filepath string The file to unzip.
---@param verify? boolean Whether or not to perform checksum verification.
---@return string
function BitStream:unzip(filepath, verify)
    for name, offset, size, packed, crc in self:files() do
        if name == filepath then
            return packed and self:inflate(offset, verify and crc or nil) or sub(self.buffer, offset, offset + size - 1)
        end
    end
    error('File "'..filepath..'" not found in ZIP archive.')
end
--- Extracts unpacked contents from the bitstream at the specified offset and size
--- @param offset integer The starting position from which to extract the contents.
--- @param size integer The size of the contents to extract.
function BitStream:extract(offset, size)
    return sub(self.buffer, offset, offset + size - 1)
end

return inflate

end)()

-- 2. Base64 二进制解码器
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

--- 解密并解析 KRC 密文
-- @param base64Content 酷狗返回的 KRC Base64 字符串
-- @param rawTrans 可选的酷狗返回的 trans 翻译 Base64 字符串
-- @return table 包含 lines, wordByWord, lrc, translation, synced
function krc.parse(base64Content, rawTrans)
  if not base64Content or base64Content == "" then return nil end

  local rawBin = krc.base64_decode_bin(base64Content)
  if string.len(rawBin) <= 4 then return nil end

  -- XOR 解密 (跳过前 4 字节魔数)
  local xorChars = {}
  local rawLen = string.len(rawBin)
  local xorIdx = 0
  for i = 5, rawLen do
    local k = KRC_KEY[((i - 5) % 16) + 1]
    xorIdx = xorIdx + 1
    xorChars[xorIdx] = char(bxor(byte(rawBin, i), k))
  end
  local xorStr = concat(xorChars)

  -- Zlib 解压 (从第 3 个字节起)
  local stream = inflate.new(xorStr)
  local ok, text = pcall(function() return stream:inflate(3) end)
  if not ok or not text or text == "" then
    return nil
  end

  local lines = {}
  local linesCount = 0
  local yrcLines = {}
  local yrcCount = 0
  local plainLrcLines = {}
  local plainCount = 0
  local embeddedTransLines = {}
  local rawTransCount = 0
  local transLines = {}
  local transCount = 0

  -- 纯字符串快速过滤 XML/KRC 标签，提取干净歌词文本
  local function stripTags(str)
    local out = {}
    local outIdx = 0
    local inTag = false
    local len = string.len(str)
    for i = 1, len do
      local c = sub(str, i, i)
      if c == "<" then
        inTag = true
      elseif c == ">" then
        inTag = false
      elseif not inTag then
        outIdx = outIdx + 1
        out[outIdx] = c
      end
    end
    return concat(out)
  end

  -- 1. 解析内嵌的 [language:Base64]
  for line in text:gmatch("[^\r\n]+") do
    if sub(line, 1, 10) == "[language:" then
      local b64Payload = sub(line, 11, -2)
      local jsonStr = krc.base64_decode_bin(b64Payload)
      if jsonStr and jsonStr ~= "" and host and host.json_decode then
        local okJson, langData = pcall(host.json_decode, jsonStr)
        if okJson and langData and langData.content then
          local transSec = nil
          for _, sec in ipairs(langData.content) do
            if sec.type == 1 then
              transSec = sec
              break
            end
          end
          if not transSec and #langData.content > 0 then
            transSec = langData.content[1]
          end
          if transSec and transSec.lyricContent and type(transSec.lyricContent) == "table" then
            for _, item in ipairs(transSec.lyricContent) do
              local tStr = (type(item) == "table" and item[1]) or tostring(item or "")
              rawTransCount = rawTransCount + 1
              embeddedTransLines[rawTransCount] = tStr
            end
          end
        end
      end
      break
    end
  end

  -- 2. 解析逐行歌词与逐字数据 (纯字符查找，避开 Dart RegExp 引擎缺陷)
  for rawLine in text:gmatch("[^\r\n]+") do
    if sub(rawLine, 1, 1) == "[" then
      local commaPos = find(rawLine, ",", 2, true)
      if commaPos then
        local bracketPos = find(rawLine, "]", commaPos + 1, true)
        if bracketPos then
          local startMsStr = sub(rawLine, 2, commaPos - 1)
          local durMsStr = sub(rawLine, commaPos + 1, bracketPos - 1)
          local startMs = tonumber(startMsStr)
          local durMs = tonumber(durMsStr)

          if startMs and durMs then
            linesCount = linesCount + 1
            local contentPart = sub(rawLine, bracketPos + 1)

            -- 提取纯文本
            local cleanText = stripTags(contentPart)

            -- 转换为 Lazer 原生识别的 YRC 逐字格式 (将 <rel,dur,flag> 转换为 (absStart,dur,flag))
            local yrcWords = {}
            for relStr, wDurStr, flagStr, wText in string.gmatch(contentPart, "<(%d+),(%d+),(%d+)>([^<]*)") do
              local rel = tonumber(relStr)
              local absStart = startMs + rel
              table.insert(yrcWords, "(" .. absStart .. "," .. wDurStr .. "," .. flagStr .. ")" .. wText)
            end
            local yrcLine = string.format("[%d,%d]%s", startMs, durMs, table.concat(yrcWords))
            yrcCount = yrcCount + 1
            yrcLines[yrcCount] = yrcLine

            -- 普通行时间戳
            lines[linesCount] = {
              startMs = startMs,
              text = cleanText
            }

            -- 标准 LRC 格式
            plainCount = plainCount + 1
            plainLrcLines[plainCount] = format_lrc_time(startMs) .. cleanText

            -- 对齐翻译歌词 (严密连续数组，杜绝 table.concat 稀疏洞异常)
            if rawTransCount >= linesCount then
              local transText = embeddedTransLines[linesCount] or ""
              local cleanTrans = string.match(transText, "^%s*(.-)%s*$")
              if cleanTrans and cleanTrans ~= "" then
                transCount = transCount + 1
                transLines[transCount] = format_lrc_time(startMs) .. cleanTrans
              end
            end
          end
        end
      end
    end
  end

  -- 3. 决定双语翻译输出
  local finalTranslation = nil
  if rawTrans and rawTrans ~= "" then
    local decodedTrans = krc.base64_decode_bin(rawTrans)
    if decodedTrans and decodedTrans ~= "" then
      finalTranslation = decodedTrans
    end
  end
  if not finalTranslation and transCount > 0 then
    finalTranslation = concat(transLines, "\n")
  end

  local fullYrc = concat(yrcLines, "\n")
  local fullLrc = concat(plainLrcLines, "\n")

  return {
    lines = lines,
    wordByWord = fullYrc,
    lrc = fullLrc,
    translation = finalTranslation,
    synced = linesCount > 0
  }
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
  local embeddedTransLines = {}
  local rawTransCount = 0
  local transLines = {}
  local transCount = 0

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
          local transSec = nil
          for _, sec in ipairs(langData.content) do
            if sec.type == 1 then
              transSec = sec
              break
            end
          end
          if not transSec and #langData.content > 0 then
            transSec = langData.content[1]
          end
          if transSec and transSec.lyricContent and type(transSec.lyricContent) == "table" then
            for _, item in ipairs(transSec.lyricContent) do
              local tStr = (type(item) == "table" and item[1]) or tostring(item or "")
              rawTransCount = rawTransCount + 1
              embeddedTransLines[rawTransCount] = tStr
            end
          end
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

            lines[linesCount] = {
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
              end
            end
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

  local fullYrc = concat(yrcLines, "\n")
  local fullLrc = concat(plainLrcLines, "\n")

  return {
    lines = lines,
    wordByWord = fullYrc,
    lrc = fullLrc,
    translation = finalTranslation,
    synced = linesCount > 0
  }
end

return krc
