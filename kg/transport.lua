local config = require("kg.config")
local crypto = require("kg.crypto")

local transport = {}

-- 缓存的凭据信息
local currentSession = nil

function transport.getSession()
  if currentSession then return currentSession end
  local stored = host.storage_get("kg_session")
  if stored and stored ~= "" then
    local ok, res = pcall(function() return host.json_decode(stored) end)
    if ok and type(res) == "table" then
      currentSession = res
      return currentSession
    end
  end
  currentSession = {
    userId = "0",
    token = "",
    dfid = config.defaultDfid,
    mid = config.defaultMid,
    userName = "",
    avatar = "",
    vipType = 0
  }
  return currentSession
end

function transport.setSession(data)
  currentSession = data
  if data then
    host.storage_set("kg_session", host.json_encode(data))
  else
    host.storage_set("kg_session", "")
  end
end

function transport.clearSession()
  transport.setSession(nil)
end

-- 组装 URL 查询字符串
local function buildQueryString(params)
  local queryParts = {}
  for k, v in pairs(params) do
    table.insert(queryParts, host.url_encode(tostring(k)) .. "=" .. host.url_encode(tostring(v)))
  end
  return table.concat(queryParts, "&")
end

-- 核心统一 HTTP 请求方法
function transport.request(options)
  local session = transport.getSession()
  local method = (options.method or "GET"):upper()
  local hostName = options.host or config.gatewayHost
  local path = options.path or "/"
  local queryParams = options.params or {}
  local body = options.body
  local jsonBody = nil
  local customHeaders = options.headers or {}

  -- 处理 Body
  if type(body) == "table" then
    jsonBody = host.json_encode(body)
  elseif type(body) == "string" then
    jsonBody = body
  end

  local mergedParams = {}
  for k, v in pairs(queryParams) do
    mergedParams[k] = tostring(v)
  end

  local clientTimeSec = math.floor(host.now() / 1000)

  -- 默认自动补齐客户端公共参数
  if not options.clearDefaultParams then
    if not mergedParams["appid"] then mergedParams["appid"] = options.official and config.officialAppId or config.appId end
    if not mergedParams["clientver"] then mergedParams["clientver"] = options.official and config.officialClientVer or config.clientVer end
    if not mergedParams["dfid"] then mergedParams["dfid"] = session.dfid or config.defaultDfid end
    if not mergedParams["mid"] then mergedParams["mid"] = session.mid or config.defaultMid end
    if not mergedParams["uuid"] then mergedParams["uuid"] = session.uuid or config.defaultUuid end
    if not mergedParams["clienttime"] then mergedParams["clienttime"] = tostring(clientTimeSec) end
    if not mergedParams["userid"] then mergedParams["userid"] = session.userId or "0" end
    if session.token and session.token ~= "" and not mergedParams["token"] then
      mergedParams["token"] = session.token
    end
  end

  -- 计算签名
  if not options.notSign then
    local sig = ""
    if options.signType == "web" then
      sig = crypto.calc_web_signature(mergedParams)
    else
      local salt = options.official and config.officialSalt or config.liteSalt
      sig = crypto.calc_signature(mergedParams, jsonBody, salt)
    end
    mergedParams["signature"] = sig
  end

  local query = buildQueryString(mergedParams)
  local fullUrl = "https://" .. hostName .. path
  if query ~= "" then
    fullUrl = fullUrl .. "?" .. query
  end

  local headers = {
    ["User-Agent"] = config.userAgent,
    ["dfid"] = session.dfid or config.defaultDfid,
    ["mid"] = session.mid or config.defaultMid,
    ["clienttime"] = tostring(clientTimeSec),
    ["kg-rc"] = "1"
  }
  if options.router then
    headers["x-router"] = options.router
  end
  for k, v in pairs(customHeaders) do
    headers[k] = v
  end

  local reqSpec = {
    url = fullUrl,
    method = method,
    headers = headers
  }
  if jsonBody and (method == "POST" or method == "PUT") then
    reqSpec.body = jsonBody
    if not headers["Content-Type"] then
      headers["Content-Type"] = "application/json"
    end
  end

  local resp = host.http(reqSpec)
  if not resp or not resp.body or resp.status >= 500 then
    return nil, "HTTP Error: " .. tostring(resp and resp.status)
  end

  local ok, parsed = pcall(function() return host.json_decode(resp.body) end)
  if ok and type(parsed) == "table" then
    return parsed
  end

  return nil, "Invalid JSON payload"
end

return transport
