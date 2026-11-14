#!/usr/bin/env python3
"""
酷狗歌曲评论区接口验证脚本

使用方式：
  1. 默认测试内置高热度曲目：
     uv run python test/test_comments.py
  2. 测试任意歌曲或 ID：
     uv run python test/test_comments.py "周杰伦 晴天"
     uv run python test/test_comments.py 32100650
"""

import sys
import json
import time
import hashlib
import urllib.request
import urllib.parse

OFFICIAL_APP_ID = "1005"
OFFICIAL_CLIENT_VER = "20489"
OFFICIAL_SALT = "OIlwieks28dk2k092lksi2UIkp"
GATEWAY_HOST = "gateway.kugou.com"

HEADERS = {
    "User-Agent": "Android15-1070-11083-46-0-DiscoveryDRADProtocol-wifi",
    "dfid": "-",
    "mid": "123456",
    "kg-rc": "1",
    "kg-thash": "5d816a0",
    "kg-rec": "1",
    "kg-rf": "B9EDA08A64250DEFFBCADDEE00F8F25F"
}

DEFAULT_TEST_SONGS = [
    {
        "title": "晴天",
        "artist": "周杰伦",
        "album_audio_id": "32100650",
        "desc": "华语评论天花板 (70万+ 评论)"
    },
    {
        "title": "夜に駆ける",
        "artist": "YOASOBI",
        "album_audio_id": "244192550",
        "desc": "日文热门歌曲评论区"
    },
    {
        "title": "海阔天空",
        "artist": "BEYOND",
        "album_audio_id": "32155307",
        "desc": "经典粤语回忆杀"
    }
]

def calc_signature(params: dict, salt: str = OFFICIAL_SALT) -> str:
    sorted_keys = sorted(params.keys())
    s = salt + "".join(f"{k}={params[k]}" for k in sorted_keys) + salt
    return hashlib.md5(s.encode("utf-8")).hexdigest()

def search_song_id(keyword: str):
    q = urllib.parse.quote(keyword)
    url = f"http://mobilecdn.kugou.com/api/v3/search/song?keyword={q}&page=1&pagesize=1"
    req = urllib.request.Request(url, headers={"User-Agent": "KuGou2012-9020-Metadata-SearchArtistLyric"})
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    
    info_list = data.get("data", {}).get("info", [])
    if not info_list:
        return None
    item = info_list[0]
    return {
        "title": item.get("songname"),
        "artist": item.get("singername"),
        "album_audio_id": str(item.get("album_audio_id") or item.get("audio_id")),
        "desc": "搜索查询曲目"
    }

def fetch_comments(mixsongid: str, page: int = 1, pagesize: int = 5):
    client_time = str(int(time.time()))
    params = {
        "appid": OFFICIAL_APP_ID,
        "clientver": OFFICIAL_CLIENT_VER,
        "clienttime": client_time,
        "mid": "123456",
        "dfid": "-",
        "uuid": "-",
        "userid": "0",
        "mixsongid": str(mixsongid),
        "need_show_image": "1",
        "p": str(page),
        "pagesize": str(pagesize),
        "show_classify": "1",
        "show_hotword_list": "1",
        "extdata": "0",
        "code": "fc4be23b4e972707f36b8a828a93ba8a"
    }
    params["signature"] = calc_signature(params)
    
    url = f"https://{GATEWAY_HOST}/mcomment/v1/cmtlist?" + urllib.parse.urlencode(params)
    h = dict(HEADERS)
    h["clienttime"] = client_time
    
    req = urllib.request.Request(url, headers=h, method="POST")
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode("utf-8"))

def run_test(target_songs):
    print("=" * 70)
    print("       💬 酷狗歌曲评论区接口与数据模型自动化测试")
    print("=" * 70)

    for idx, s in enumerate(target_songs, 1):
        print(f"\n[{idx}/{len(target_songs)}] 正在查询评论: {s['title']} - {s['artist']} ({s.get('desc', '')})")
        print(f"      AlbumAudioId: {s['album_audio_id']}")

        try:
            data = fetch_comments(s["album_audio_id"], page=1, pagesize=3)
            total = data.get("count", 0)
            cmt_list = data.get("list", [])
            print(f"      ✅ 评论拉取成功: 累计共有 {total} 条评论")
            print(f"      📝 热门/最新评论精选 (前 {len(cmt_list)} 条):")
            for c in cmt_list:
                author = c.get("user_name", "匿名")
                content = c.get("content", "").replace("\n", " ")
                like_num = c.get("like", {}).get("like_num", 0) if isinstance(c.get("like"), dict) else 0
                location = c.get("location") or "未知"
                print(f"         • [{location}] {author} (👍 {like_num}): {content[:60]}")
        except Exception as e:
            print(f"      ❌ 查询评论失败: {e}")

    print("\n" + "=" * 70)
    print("测试完毕！")
    print("=" * 70)

if __name__ == "__main__":
    if len(sys.argv) > 1:
        query = sys.argv[1].strip()
        if query.isdigit():
            target = [{
                "title": "指定ID曲目",
                "artist": "-",
                "album_audio_id": query,
                "desc": "命令行指定 ID"
            }]
        else:
            found = search_song_id(query)
            if not found:
                print(f"错误: 搜索 '{query}' 未找到曲目")
                sys.exit(1)
            target = [found]
        run_test(target)
    else:
        run_test(DEFAULT_TEST_SONGS)
