local config = require("kg.config")
local transport = require("kg.transport")
local crypto = require("kg.crypto")

local account = {}

-- 缓存二维码对应的真实扫描 URL
local qrUrls = {}

function account.session()
  local s = transport.getSession()
  if s and s.userId and s.userId ~= "0" and s.token and s.token ~= "" then
    -- 尝试从酷狗云端拉取最新的用户资料进行静默刷新
    local res, err = transport.request({
      method = "POST",
      path = "/v7/get_all_list",
      params = {
        plat = "1",
        userid = s.userId,
        token = s.token
      },
      body = {
        userid = s.userId,
        token = s.token,
        total_ver = 979,
        type = 2,
        page = 1,
        pagesize = 1
      },
      router = "cloudlist.service.kugou.com"
    })

    if res and res.status == 1 and res.data and res.data.info and #res.data.info > 0 then
      local firstItem = res.data.info[1]
      local freshPic = firstItem.create_user_pic
      local freshNick = firstItem.list_create_username
      local updated = false
      if freshPic and freshPic ~= "" and freshPic ~= s.avatar then
        s.avatar = freshPic
        updated = true
      end
      if freshNick and freshNick ~= "" and freshNick ~= s.userName and freshNick ~= s.userId then
        s.userName = freshNick
        updated = true
      end
      if updated then
        transport.setSession(s)
      end
    end

    local nick = s.userName
    if not nick or nick == "" or nick == s.userId then
      nick = "酷狗用户" .. tostring(s.userId)
    end
    local avatarUrl = (s.avatar and s.avatar ~= "") and s.avatar or nil
    if avatarUrl then
      avatarUrl = avatarUrl:gsub("^http://", "https://")
    end

    return {
      id = tostring(s.userId),
      name = nick,
      avatarUrl = avatarUrl,
      membership = s.vipType == 1 and "VIP" or nil
    }
  end
  return nil
end

function account.logout()
  transport.clearSession()
  return true
end

-- 获取扫码 Key
function account.qrKey()
  local res, err = transport.request({
    host = config.loginHost,
    path = "/v2/qrcode",
    params = {
      appid = "1001",
      clientver = "11040",
      type = "1",
      plat = "4",
      srcappid = "2919",
      qrcode_txt = "https://h5.kugou.com/apps/loginQRCode/html/index.html?appid=3116&"
    },
    signType = "web"
  })

  if res and res.status == 1 and res.data and res.data.qrcode then
    local key = tostring(res.data.qrcode)
    local url = "https://h5.kugou.com/apps/loginQRCode/html/index.html?appid=3116&qrcode=" .. host.url_encode(key)
    qrUrls[key] = url
    return key
  end
  return nil
end

-- 获取扫码展示用的 URL
function account.qrUrl(args)
  local key = tostring(args and args.key or "")
  if qrUrls[key] then
    return qrUrls[key]
  end
  return "https://h5.kugou.com/apps/loginQRCode/html/index.html?appid=3116&qrcode=" .. host.url_encode(key)
end

-- 轮询二维码扫码状态
-- 酷狗 QrLoginStatus: 0=过期, 1=等待扫码, 2=已扫待确认, 4=成功
-- Lazer 状态契约: 801=等待扫码, 802=已扫码待确认, 803=成功, 800=过期/失效
function account.qrCheck(args)
  local key = tostring(args and args.key or "")
  if key == "" then return 800 end

  local res, err = transport.request({
    host = config.loginHost,
    path = "/v2/get_userinfo_qrcode",
    params = {
      plat = "4",
      appid = "3116",
      srcappid = "2919",
      qrcode = key
    },
    signType = "web"
  })

  if not res then return 801 end

  if res.status == 1 and res.data then
    local qrStatus = tonumber(res.data.status)
    -- 状态为 4，或者已有 token 即代表登录成功
    if qrStatus == 4 or (res.data.token and res.data.token ~= "") then
      local s = transport.getSession()
      s.userId = tostring(res.data.userid or res.data.id or "0")
      s.token = tostring(res.data.token or "")
      s.userName = tostring(res.data.nickname or res.data.username or ("酷狗用户" .. s.userId))
      s.avatar = tostring(res.data.pic or "")
      s.vipType = tonumber(res.data.vip_type or 0)
      transport.setSession(s)
      return 803
    elseif qrStatus == 2 then
      -- 手机已扫码，等待确认
      return 802
    elseif qrStatus == 0 then
      -- 已过期
      return 800
    else
      -- 1 或其他：等待扫码
      return 801
    end
  elseif res.errcode == 20002 or res.status == 0 then
    return 800
  end

  return 801
end

-- 发送手机短信验证码
function account.sendCaptcha(args)
  local phone = tostring(args and args.phone or "")
  if phone == "" then
    return { error = { code = 400, message = "请输入有效的手机号" } }
  end

  local res, err = transport.request({
    method = "POST",
    host = config.loginHost,
    path = "/v7/send_mobile_code",
    body = {
      businessid = 5,
      mobile = phone,
      plat = 3
    }
  })

  if res and res.status == 1 then
    return { success = true }
  end

  return {
    error = {
      code = res and res.error_code or 500,
      message = res and res.error or "发送验证码失败"
    }
  }
end

-- 手机验证码登录
function account.loginCaptcha(args)
  local phone = tostring(args and args.phone or "")
  local captcha = tostring(args and args.captcha or "")
  if phone == "" or captcha == "" then
    transport.debugLog("loginCaptcha empty phone or captcha")
    return nil
  end

  transport.debugLog("loginCaptcha start for " .. crypto.mask_mobile(phone))
  local session = transport.getSession()
  local timeMs = host.now()

  -- 1. 动态生成 AES Key 并加密登录载荷 (params)
  local aesPayload = string.format('{"mobile":"%s","code":"%s"}', phone, captcha)
  local aesStr, tempKey = crypto.aes_encrypt_dynamic(aesPayload)

  -- 2. RSA 模幂加密密钥与时间戳包 (pk，严禁浮点数 .0)
  local pkData = string.format('{"clienttime_ms":%.0f,"key":"%s"}', timeMs, tempKey)
  local pk = crypto.rsa_encrypt_pk(pkData)

  -- 3. 计算 t1 与 t2 设备指纹
  local t1 = crypto.calc_t1(timeMs)
  local t2 = crypto.calc_t2(session.installGuid, session.installMac, session.installDev, timeMs)

  -- 4. 组装酷狗移动端高安全握手 Body (手工紧凑 JSON，严禁浮点数 .0 且与 C# 字段顺序一致)
  local bodyJson = string.format(
    '{"plat":1,"support_multi":1,"t1":"%s","t2":"%s","clienttime_ms":%.0f,"mobile":"%s","key":"%s","pk":"%s","params":"%s","dfid":"-","dev":"%s","gitversion":"5f0b7c4"}',
    t1, t2, timeMs, crypto.mask_mobile(phone), crypto.calc_login_key(timeMs), pk, aesStr, session.installDev
  )

  -- 5. 发送至登录重试与容灾端点 (登录请求隔离旧 Token)
  local res, err = transport.request({
    method = "POST",
    host = config.loginRetryHost,
    path = "/v7/login_by_verifycode",
    router = config.loginRouter,
    noAuthToken = true,
    body = bodyJson,
    headers = {
      ["support-calm"] = "1"
    }
  })

  if not res then
    transport.debugLog("loginCaptcha network/http error: " .. tostring(err))
    return nil
  end

  if res.status ~= 1 then
    transport.debugLog("loginCaptcha failed resp: " .. host.json_encode(res))
    return nil
  end

  -- 6. 解密返回的 secu_params 密文
  if res.status == 1 and res.data then
    if res.data.secu_params and res.data.secu_params ~= "" then
      local okDec, decStr = pcall(crypto.aes_decrypt_dynamic, res.data.secu_params, tempKey)
      if okDec and decStr and decStr ~= "" then
        local okJson, decJson = pcall(function() return host.json_decode(decStr) end)
        if okJson and type(decJson) == "table" then
          for k, v in pairs(decJson) do
            res.data[k] = v
          end
        end
      end
    end

    local s = transport.getSession()
    s.userId = tostring(res.data.userid or res.data.id or "0")
    s.token = tostring(res.data.token or "")
    s.userName = tostring(res.data.nickname or res.data.username or ("酷狗用户" .. s.userId))
    s.avatar = tostring(res.data.pic or "")
    s.vipType = tonumber(res.data.vip_type or 0)
    transport.setSession(s)
    transport.debugLog("loginCaptcha SUCCESS: user=" .. s.userName .. " id=" .. s.userId)
    return account.session()
  end

  return nil
end

return account
