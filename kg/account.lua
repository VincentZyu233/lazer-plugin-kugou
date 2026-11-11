local config = require("kg.config")
local transport = require("kg.transport")

local account = {}

-- 缓存二维码对应的真实扫描 URL
local qrUrls = {}

function account.session()
  local s = transport.getSession()
  if s and s.userId and s.userId ~= "0" and s.token and s.token ~= "" then
    local nick = s.userName
    if not nick or nick == "" then
      nick = "酷狗用户" .. tostring(s.userId)
    end
    return {
      id = tostring(s.userId),
      name = nick,
      avatarUrl = (s.avatar and s.avatar ~= "") and s.avatar or nil,
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
    return nil
  end

  local res, err = transport.request({
    method = "POST",
    host = config.loginHost,
    path = "/v7/login_by_verifycode",
    body = {
      mobile = phone,
      code = captcha,
      plat = 1
    }
  })

  if res and res.status == 1 and res.data then
    local s = transport.getSession()
    s.userId = tostring(res.data.userid or "0")
    s.token = tostring(res.data.token or "")
    s.userName = tostring(res.data.nickname or ("酷狗用户" .. s.userId))
    s.avatar = tostring(res.data.pic or "")
    transport.setSession(s)
    return account.session()
  end

  return nil
end

return account
