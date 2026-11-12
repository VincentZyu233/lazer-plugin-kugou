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

# 当前登录用户的 Token 与 UserId
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


def test_search_author(name: str):
    print(f"\n=================== [1] 搜索歌手: {name} ===================")
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
        "keyword": name,
        "page": "1",
        "pagesize": "5",
        "platform": "AndroidFilter",
        "iscorrection": "1",
    }
    params["signature"] = calc_signature(params)
    url = f"https://gateway.kugou.com/v1/search/author?{urllib.parse.urlencode(params)}"
    headers = {
        "User-Agent": USER_AGENT,
        "x-router": "complexsearch.kugou.com",
        "dfid": DFID,
        "mid": MID,
        "clienttime": client_time,
        "kg-rc": "1",
    }
    res = requests.get(url, headers=headers, timeout=10)
    data = res.json()
    print(f"HTTP Status: {res.status_code}, status: {data.get('status')}")
    lists = data.get("data", {}).get("lists", [])
    if lists:
        first = lists[0]
        print(f"匹配到首个歌手: {first.get('AuthorName')} (ID: {first.get('AuthorId')})")
        print(f"头像: {first.get('Avatar')}")
        print(f"歌曲数: {first.get('AudioCount')}, 专辑数: {first.get('AlbumCount')}")
        return str(first.get("AuthorId"))
    else:
        print("未搜索到匹配歌手")
        return None


def test_artist_detail(author_id: str):
    print(f"\n=================== [2] 歌手详情 /kmr/v3/author (ID: {author_id}) ===================")
    client_time = str(int(time.time()))
    body_dict = {"author_id": author_id}
    body_str = json.dumps(body_dict, separators=(",", ":"))
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
    params["signature"] = calc_signature(params, body_str)
    url = f"https://gateway.kugou.com/kmr/v3/author?{urllib.parse.urlencode(params)}"
    headers = {
        "User-Agent": USER_AGENT,
        "x-router": "openapi.kugou.com",
        "kg-tid": "36",
        "dfid": DFID,
        "mid": MID,
        "clienttime": client_time,
        "kg-rc": "1",
        "Content-Type": "application/json",
    }
    res = requests.post(url, headers=headers, data=body_str, timeout=10)
    print(f"HTTP Status: {res.status_code}")
    data = res.json()
    print(f"status: {data.get('status')}, error_code: {data.get('error_code')}")
    info = data.get("data", {})
    if info:
        print(f"歌手名: {info.get('author_name')}")
        print(f"头像: {info.get('sizable_avatar')}")
        print(f"简介片段: {str(info.get('intro'))[:100]}...")


def test_artist_songs(author_id: str):
    print(f"\n=================== [3] 歌手热门歌曲 /kmr/v1/audio_group/author (ID: {author_id}) ===================")
    client_time = str(int(time.time()))
    body_dict = {
        "author_id": author_id,
        "pagesize": 10,
        "page": 1,
        "sort": 1,
        "area_code": "all",
    }
    body_str = json.dumps(body_dict, separators=(",", ":"))
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
    params["signature"] = calc_signature(params, body_str)
    url = f"https://gateway.kugou.com/kmr/v1/audio_group/author?{urllib.parse.urlencode(params)}"
    headers = {
        "User-Agent": USER_AGENT,
        "x-router": "openapi.kugou.com",
        "kg-tid": "220",
        "dfid": DFID,
        "mid": MID,
        "clienttime": client_time,
        "kg-rc": "1",
        "Content-Type": "application/json",
    }
    res = requests.post(url, headers=headers, data=body_str, timeout=10)
    print(f"HTTP Status: {res.status_code}")
    data = res.json()
    print(f"status: {data.get('status')}, error_code: {data.get('error_code')}, total: {data.get('total')}")
    songs = data.get("data", [])
    print(f"返回歌曲数量: {len(songs)}")
    for i, s in enumerate(songs[:5]):
        print(f"  [{i+1}] {s.get('audio_name')} | Hash: {s.get('hash')} | 专辑: {s.get('album_name')}")


def main():
    for name in ["いよわ", "初音ミク"]:
        author_id = test_search_author(name)
        if author_id:
            test_artist_detail(author_id)
            test_artist_songs(author_id)


if __name__ == "__main__":
    main()
