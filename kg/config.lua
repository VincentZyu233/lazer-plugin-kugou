local config = {
  -- App 标识
  appId = "3116",
  clientVer = "11440",
  version = "11440",
  userAgent = "Android15-1070-11083-46-0-DiscoveryDRADProtocol-wifi",

  -- 官方正式版标识 (某些特定接口使用)
  officialAppId = "1005",
  officialClientVer = "20489",

  -- 签名盐值
  v5KeySalt = "185672dd44712f60bb1736df5a377e82",
  liteSalt = "LnT6xpN3khm36zse0QzvmgTZ3waWdRSA",
  officialSalt = "OIlwieks28dk2k092lksi2UIkp",
  webSignatureSalt = "NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt",

  -- 默认设备指纹
  defaultDfid = "-",
  defaultMid = "",
  defaultUuid = "-",

  -- RSA 模数与指数 (用于登录参数与密码加密)
  -- Lite 公钥: modulus hex (128 bytes = 256 hex chars), exponent 65537
  rsaLiteModulus = "c40a2d0da76511f3bb1cc2bbd3afbd8bea83b4d6b05b6c13eb8920c53f1af7679b32ba0d0edb843240ef1b836efed3ee240734c14c1399fd6594d16af22f52525d14d72e0155c6dcc8638d4f7bb94f3a0b1f4c29f991972f2a160a25eb0a9e724336be7f69bbd319ffab1c6dd8470b021dc434f3faea89f4a2a01b33bdbdd08b",
  rsaExponent = 65537,

  -- 接口基础域名
  gatewayHost = "gateway.kugou.com",
  trackHost = "track.kugou.com",
  loginHost = "login-user.kugou.com",
  mobileHost = "m.kugou.com",
  searchHost = "complexsearch.kugou.com"
}

return config
