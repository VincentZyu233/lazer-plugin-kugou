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

-- RSA 加密 (无填充/原始模幂)
function crypto.rsa_encrypt(text)
  return host.crypto({
    operation = "rsa_modpow",
    text = text,
    inputEncoding = "utf8",
    modulus = config.rsaLiteModulus,
    exponent = config.rsaExponent,
    width = 256
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

return crypto
