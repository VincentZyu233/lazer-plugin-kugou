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

def test_add_to_favorite():
    # 测试添加一首歌到 listid=2
    # 比如: いよわ - きゅうくらりん hash: "740A46DE76C1E26EE51152AE91C3E8A7" (或者一个已知歌曲)
    test_song_name = "いよわ - きゅうくらりん"
    test_song_hash = "740A46DE76C1E26EE51152AE91C3E8A7"
    client_time = str(int(time.time()))
    params = {
        "appid": APP_ID,
        "clientver": CLIENT_VER,
        "dfid": DFID,
        "mid": MID,
        "uuid": UUID,
        "clienttime": client_time,
        "last_time": client_time,
        "last_area": "gztx",
        "userid": USER_ID,
        "token": TOKEN,
    }
    body_data = {
        "userid": USER_ID,
        "token": TOKEN,
        "listid": "2",
        "list_ver": 0,
        "type": 0,
        "slow_upload": 1,
        "scene": "false;null",
        "data": [
            {
                "number": 1,
                "name": test_song_name,
                "hash": test_song_hash,
                "size": 0,
                "sort": 0,
                "timelen": 0,
                "bitrate": 0,
                "album_id": 0,
                "mixsongid": 0
            }
        ]
    }
    body_json = json.dumps(body_data, separators=(',', ':'))
    params["signature"] = calc_signature(params, body_json)
    
    url = f"https://gateway.kugou.com/cloudlist.service/v6/add_song?{urllib.parse.urlencode(params)}"
    headers = {
        "User-Agent": USER_AGENT,
        "dfid": DFID,
        "mid": MID,
        "clienttime": client_time,
        "kg-rc": "1",
        "Content-Type": "application/json"
    }
    res = requests.post(url, headers=headers, data=body_json, timeout=10)
    print("Add status:", res.status_code)
    print("Add response:", res.text)

def test_get_favorite():
    client_time = str(int(time.time()))
    params = {
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
        "listid": 2,
        "userid": int(USER_ID),
        "area_code": 1,
        "show_relate_goods": 0,
        "pagesize": 30,
        "allplatform": 1,
        "show_cover": 1,
        "type": 0,
        "token": TOKEN,
        "page": 1
    }
    body_json = json.dumps(body_data, separators=(',', ':'))
    params["signature"] = calc_signature(params, body_json)
    
    url = f"https://gateway.kugou.com/v4/get_list_all_file?{urllib.parse.urlencode(params)}"
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
    print("Get favorite status:", res.status_code)
    try:
        data = res.json()
        print("Get favorite response:", json.dumps(data, ensure_ascii=False, indent=2))
    except:
        print(res.text)

if __name__ == "__main__":
    test_add_to_favorite()
    print("\nNow getting favorite songs...")
    test_get_favorite()
