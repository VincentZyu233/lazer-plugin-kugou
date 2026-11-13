local config = require("kg.config")

local crypto = {}

function crypto.md5(text)
  if not text or text == "" then return "" end
  return host.crypto({ operation = "md5", text = tostring(text) })
end

function crypto.sha256(text)
  if not text or text == "" then return "" end
  return host.crypto({ operation = "sha256", text = tostring(text) })
end

function crypto.base64_encode(text)
  return host.crypto({ operation = "base64", text = tostring(text or "") })
end

function crypto.base64_decode(text)
  return host.crypto({ operation = "base64_decode", text = tostring(text or "") })
end

-- AES-CBC-PKCS7 加密，返回 hex 字符串
function crypto.aes_cbc_encrypt(text, key, iv)
  return host.crypto({
    operation = "aes",
    mode = "cbc",
    key = key,
    iv = iv,
    text = text,
    encoding = "hex"
  })
end

-- AES-CBC-PKCS7 解密，输入 hex 字符串，返回明文字符串
function crypto.aes_cbc_decrypt(hexData, key, iv)
  return host.crypto({
    operation = "aes",
    mode = "cbc",
    decrypt = true,
    key = key,
    iv = iv,
    text = hexData,
    encoding = "hex"
  })
end

-- 字符串转 Hex 字符串
function crypto.str_to_hex(str)
  local hex = {}
  for i = 1, #str do
    table.insert(hex, string.format("%02x", string.byte(str, i)))
  end
  return table.concat(hex)
end

-- RSA 加密 (无填充/原始模幂，尾部以 0x00 字节补齐至 128 字节/256 字符 Hex)
function crypto.rsa_encrypt(text)
  local hex = crypto.str_to_hex(text)
  if #hex < 256 then
    hex = hex .. string.rep("00", math.floor((256 - #hex) / 2))
  end
  return host.crypto({
    operation = "rsa_modpow",
    text = hex,
    inputEncoding = "hex",
    modulus = config.rsaLiteModulus
  })
end

-- V5 播放链接专用 key 计算
function crypto.calc_v5_key(hash, userid, mid)
  local raw = tostring(hash) .. config.v5KeySalt .. config.appId .. tostring(mid or "") .. tostring(userid or "0")
  return crypto.md5(raw)
end

-- 酷狗常规参数签名: MD5(salt + 升序拼装key=value + body + salt)
function crypto.calc_signature(params, body, salt)
  salt = salt or config.liteSalt
  local keys = {}
  for k in pairs(params) do
    table.insert(keys, k)
  end
  table.sort(keys)

  local parts = { salt }
  for _, k in ipairs(keys) do
    table.insert(parts, k)
    table.insert(parts, "=")
    table.insert(parts, tostring(params[k]))
  end
  if body and body ~= "" then
    table.insert(parts, body)
  end
  table.insert(parts, salt)

  return crypto.md5(table.concat(parts))
end

-- 酷狗 Web 接口签名
function crypto.calc_web_signature(params, salt)
  salt = salt or config.webSignatureSalt
  local keys = {}
  for k in pairs(params) do
    table.insert(keys, k)
  end
  table.sort(keys)

  local parts = { salt }
  for _, k in ipairs(keys) do
    table.insert(parts, k)
    table.insert(parts, "=")
    table.insert(parts, tostring(params[k]))
  end
  table.insert(parts, salt)

  return crypto.md5(table.concat(parts))
end

-- 登录与个性化推荐专用 key 计算: MD5(appId + liteSalt + clientVer + clientTimeMs)
function crypto.calc_login_key(timeMs)
  local raw = tostring(config.appId) .. tostring(config.liteSalt) .. tostring(config.clientVer) .. tostring(timeMs)
  return crypto.md5(raw)
end

-- 生成设备标识随机大写字母与数字串 (16位)
function crypto.random_dev(len)
  len = len or 16
  local chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  local res = {}
  local seed = host.now()
  math.randomseed(seed)
  for i = 1, len do
    local idx = math.random(1, #chars)
    table.insert(res, string.sub(chars, idx, idx))
  end
  return table.concat(res)
end

-- 生成随机 ASCII 字符串
function crypto.random_string(len)
  len = len or 16
  local chars = "abcdefghijklmnopqrstuvwxyz0123456789"
  local res = {}
  local seed = host.now()
  math.randomseed(seed)
  for i = 1, len do
    local idx = math.random(1, #chars)
    table.insert(res, string.sub(chars, idx, idx))
  end
  return table.concat(res)
end

-- 生成随机 Hex 字符串 (例如 32 位 GUID / Mac)
function crypto.random_hex(len)
  len = len or 32
  local chars = "0123456789abcdef"
  local res = {}
  local seed = host.now()
  math.randomseed(seed)
  for i = 1, len do
    local idx = math.random(1, #chars)
    table.insert(res, string.sub(chars, idx, idx))
  end
  return table.concat(res)
end

-- 动态 AES-256-CBC 加密 (酷狗移动端 params 加密)
-- 返回 hexData, tempKey
function crypto.aes_encrypt_dynamic(data)
  local tempKey = crypto.random_string(16):lower()
  local md5Key = crypto.md5(tempKey)
  local actualKey = md5Key
  local actualIv = string.sub(md5Key, 17, 32)
  local hexData = crypto.aes_cbc_encrypt(data, actualKey, actualIv)
  return hexData, tempKey
end

-- 动态 AES-256-CBC 解密 (酷狗移动端 secu_params 解密)
function crypto.aes_decrypt_dynamic(hexData, tempKey)
  local md5Key = crypto.md5(tempKey)
  local actualKey = md5Key
  local actualIv = string.sub(md5Key, 17, 32)
  return crypto.aes_cbc_decrypt(hexData, actualKey, actualIv)
end

-- 酷狗移动端专用 pk 参数生成 (RSA 无填充模幂加密转大写)
function crypto.rsa_encrypt_pk(pkData)
  local hex = crypto.rsa_encrypt(pkData)
  return string.upper(hex)
end

-- 计算 t1 (AES 加密 |clienttime_ms)
function crypto.calc_t1(timeMs)
  local raw = "|" .. tostring(timeMs)
  return crypto.aes_cbc_encrypt(raw, config.liteT1Key, config.liteT1Iv)
end

-- 计算 t2 (AES 加密 guid|fixedHash|mac|dev|clienttime_ms)
function crypto.calc_t2(installGuid, installMac, installDev, timeMs)
  local raw = tostring(installGuid or "") .. "|" .. config.t2FixedHash .. "|" .. tostring(installMac or "") .. "|" .. tostring(installDev or "") .. "|" .. tostring(timeMs)
  return crypto.aes_cbc_encrypt(raw, config.liteT2Key, config.liteT2Iv)
end

-- 手机号掩码脱敏 (如 17274961080 -> 17*****0)
function crypto.mask_mobile(phone)
  phone = tostring(phone or "")
  if string.len(phone) >= 11 then
    return string.sub(phone, 1, 2) .. "*****" .. string.sub(phone, 11, 11)
  end
  return phone
end

return crypto
