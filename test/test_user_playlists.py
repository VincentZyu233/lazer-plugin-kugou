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

def test_user_playlists():
    client_time = str(int(time.time()))
    params = {
        "plat": "1",
        "appid": APP_ID,
        "clientver": CLIENT_VER,
        "dfid": DFID,
        "mid": MID,
        "uuid": UUID,
        "clienttime": client_time,
        "userid": USER_ID,
        "token": TOKEN,
    }
    body_data = {
        "userid": USER_ID,
        "token": TOKEN,
        "total_ver": 979,
        "type": 2,
        "page": 1,
        "pagesize": 30
    }
    body_json = json.dumps(body_data, separators=(',', ':'))
    params["signature"] = calc_signature(params, body_json)
    
    url = f"https://gateway.kugou.com/v7/get_all_list?{urllib.parse.urlencode(params)}"
    headers = {
        "User-Agent": USER_AGENT,
        "x-router": "cloudlist.service.kugou.com",
        "dfid": DFID,
        "mid": MID,
        "clienttime": client_time,
        "kg-rc": "1",
        "Content-Type": "application/json"
    }
    res = requests.post(url, headers=headers, data=body_json, timeout=10)
    print("Status:", res.status_code)
    try:
        resp = res.json()
        print("Response JSON:")
        print(json.dumps(resp, ensure_ascii=False, indent=2))
    except Exception as e:
        print("Error:", e, res.text)

if __name__ == "__main__":
    test_user_playlists()
