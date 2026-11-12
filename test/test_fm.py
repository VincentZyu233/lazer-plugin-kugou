import hashlib
import json
import time
import urllib.parse
import requests

LITE_SALT = "LnT6xpN3khm36zse0QzvmgTZ3waWdRSA"
APP_ID = "3116"
CLIENT_VER = "11440"
DFID = "-"
MID = "68358509610070717889884130747296293671"
UUID = "8e97bb1f09bb99566860d4b9f29bf5b3"
USER_AGENT = "Android15-1070-11083-46-0-DiscoveryDRADProtocol-wifi"
USER_ID = "2522334714"
TOKEN = "0721cc03c20f2513643d9286b6fc8689a48823ad5a7453da340c2037a9c16908"

def calc_login_key(client_time_ms: int) -> str:
    s = f"{APP_ID}1001{CLIENT_VER}{client_time_ms}1"
    return hashlib.md5(s.encode("utf-8")).hexdigest()

def calc_signature(params: dict, body: str = None, salt: str = LITE_SALT) -> str:
    sorted_keys = sorted(params.keys())
    parts = [salt]
    for k in sorted_keys:
        parts.append(f"{k}={params[k]}")
    if body:
        parts.append(body)
    parts.append(salt)
    raw = "".join(parts)
    return hashlib.md5(raw.encode("utf-8")).hexdigest()

def test_personal_fm():
    now_ms = int(time.time() * 1000)
    key = calc_login_key(now_ms)
    body_data = {
        "appid": APP_ID,
        "clienttime": now_ms,
        "mid": MID,
        "action": "play",
        "recommend_source_locked": 0,
        "song_pool_id": 0,
        "callerid": 0,
        "m_type": 1,
        "platform": "android",
        "area_code": 1,
        "remain_songcnt": 0,
        "clientver": CLIENT_VER,
        "is_overplay": 0,
        "mode": "normal",
        "fakem": "ca981cfc583a4c37f28d2d49000013c16a0a",
        "key": key,
        "userid": USER_ID,
        "kguid": USER_ID,
        "token": TOKEN,
        "vip_type": "0"
    }
    client_time_sec = str(int(now_ms / 1000))
    params = {
        "appid": APP_ID,
        "clientver": CLIENT_VER,
        "dfid": DFID,
        "mid": MID,
        "uuid": UUID,
        "clienttime": client_time_sec,
        "userid": USER_ID,
        "token": TOKEN,
    }
    body_json = json.dumps(body_data, separators=(',', ':'))
    params["signature"] = calc_signature(params, body_json)
    
    url = f"https://gateway.kugou.com/v2/personal_recommend?{urllib.parse.urlencode(params)}"
    headers = {
        "User-Agent": USER_AGENT,
        "x-router": "persnfm.service.kugou.com",
        "dfid": DFID,
        "mid": MID,
        "clienttime": client_time_sec,
        "kg-rc": "1",
        "Content-Type": "application/json"
    }
    res = requests.post(url, headers=headers, data=body_json, timeout=10)
    print("FM status:", res.status_code)
    try:
        resp = res.json()
        print("FM response status:", resp.get("status"), resp.get("error_code"))
        songs = resp.get("data", {}).get("song_list", []) or resp.get("data", {}).get("songs", [])
        print("FM songs count:", len(songs))
        if songs:
            print("First FM song:", json.dumps(songs[0], ensure_ascii=False, indent=2))
    except Exception as e:
        print("FM parse error:", e, res.text)

if __name__ == "__main__":
    test_personal_fm()
