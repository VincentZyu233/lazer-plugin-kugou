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

def do_search(endpoint_type: str, keyword: str):
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
        "keyword": keyword,
        "page": "1",
        "pagesize": "5",
        "platform": "AndroidFilter",
        "iscorrection": "1",
    }
    params["signature"] = calc_signature(params)
    path = f"/v1/search/{endpoint_type}"
    url = f"https://gateway.kugou.com{path}?{urllib.parse.urlencode(params)}"
    headers = {
        "User-Agent": USER_AGENT,
        "x-router": "complexsearch.kugou.com",
        "dfid": DFID,
        "mid": MID,
        "clienttime": client_time,
        "kg-rc": "1",
    }
    res = requests.get(url, headers=headers, timeout=10)
    print(f"\n--- Search {endpoint_type} result: status {res.status_code} ---")
    try:
        data = res.json()
        print("Status code:", data.get("status"))
        data_block = data.get("data", {})
        print("Total:", data_block.get("total"))
        lists = data_block.get("lists", [])
        print(f"Lists length: {len(lists)}")
        if lists:
            print("First item preview:")
            print(json.dumps(lists[0], ensure_ascii=False, indent=2))
    except Exception as e:
        print("Parse error:", e, res.text[:200])

if __name__ == "__main__":
    for t in ["author", "album", "special"]:
        do_search(t, "初音未来")
