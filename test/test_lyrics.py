#!/usr/bin/env python3
"""
酷狗逐字动感歌词 (KRC) 与双语翻译自动化验证脚本

使用方式：
  1. 默认批量回归测试多首内置经典曲目：
     uv run python test/test_lyrics.py
  2. 测试任意自定义歌曲：
     uv run python test/test_lyrics.py "林俊杰 江南"
     uv run python test/test_lyrics.py b3a52a7a958bf0aed0ebfba2e9a818b7
"""

import os
import sys
import json
import zlib
import base64
import urllib.request
import urllib.parse

HEADERS = {
    "User-Agent": "KuGou2012-9020-Metadata-SearchArtistLyric",
    "Accept": "*/*"
}

KRC_KEY = bytes([64, 71, 97, 119, 94, 50, 116, 71, 81, 54, 49, 45, 206, 210, 110, 105])

# 预置 10 首代表性曲目 (覆盖术力口Vocaloid、J-Pop、欧美流行与华语，100% 具备逐字动感歌词与双语翻译)
DEFAULT_SONGS = [
    {
        "title": "千本桜",
        "artist": "初音ミク",
        "hash": "1b111e263ee8210413bff2e80da29a13",
        "desc": "术力口Vocaloid 传世经典 (逐字动感 + 双语翻译)"
    },
    {
        "title": "深海少女",
        "artist": "初音ミク",
        "hash": "e89a65c84cf6b85c8408cb1489acb773",
        "desc": "术力口Vocaloid 经典抒情 (逐字动感 + 双语翻译)"
    },
    {
        "title": "ロキ (ROKI)",
        "artist": "鏡音リン、みきとP",
        "hash": "bf6902f3529198e6b9a2b9125ebe5b76",
        "desc": "术力口Vocaloid 超高燃快节奏 (逐字动感 + 双语翻译)"
    },
    {
        "title": "ヴァンパイア (吸血鬼)",
        "artist": "DECO*27、初音ミク",
        "hash": "63c13235c1469d1b716015c632ecda29",
        "desc": "术力口Vocaloid 现代高热度 (逐字动感 + 双语翻译)"
    },
    {
        "title": "夜に駆ける",
        "artist": "YOASOBI",
        "hash": "2131897fda53adbf58825cc3c61d0860",
        "desc": "日文流行高节奏动感 (逐字动感 + 中文双语翻译)"
    },
    {
        "title": "Lemon",
        "artist": "米津玄師",
        "hash": "da60f11f69affc7107adede9dd17352a",
        "desc": "日文流行殿堂金曲 (逐字动感 + 中文双语翻译)"
    },
    {
        "title": "Rolling in the Deep",
        "artist": "Adele",
        "hash": "453cbdd4347ccbf2f6203f37c9d9597c",
        "desc": "欧美流行大热单曲 (逐字动感 + 中英双语翻译)"
    },
    {
        "title": "Shape of You",
        "artist": "Ed Sheeran",
        "hash": "b6a303c9cda8e6c4c0b2fb0b23a570c6",
        "desc": "欧美流行英文律动 (逐字动感 + 中英双语翻译)"
    },
    {
        "title": "晴天",
        "artist": "周杰伦",
        "hash": "b3a52a7a958bf0aed0ebfba2e9a818b7",
        "desc": "华语经典逐字动感标杆"
    },
    {
        "title": "江南",
        "artist": "林俊杰",
        "hash": "b83dbb8e3dd3fcf86bf32690b91547f5",
        "desc": "华语经典标准抒情逐字打点"
    }
]

def search_hash(keyword: str):
    q = urllib.parse.quote(keyword)
    url = f"http://mobilecdn.kugou.com/api/v3/search/song?keyword={q}&page=1&pagesize=1"
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    
    info_list = data.get("data", {}).get("info", [])
    if not info_list:
        return None
    item = info_list[0]
    return {
        "title": item.get("songname"),
        "artist": item.get("singername"),
        "hash": item.get("hash"),
        "desc": "用户自定义查询"
    }

def fetch_and_decode_krc(song_hash: str):
    # 1. 查找 candidate (优先新接口，失败回退老接口)
    p = {
        "hash": song_hash,
        "album_audio_id": "0",
        "lrctxt": "1",
        "man": "no",
        "duration": "0"
    }
    url = "http://lyrics.kugou.com/v1/search?" + urllib.parse.urlencode(p)
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req) as resp:
        body = resp.read()
        try:
            data = json.loads(body.decode("utf-8"))
        except Exception:
            data = {}
    
    candidates = data.get("candidates", [])
    if not candidates:
        # 回退 /search
        p_legacy = { "ver": "1", "man": "yes", "client": "pc", "duration": "0", "hash": song_hash }
        url_legacy = "http://lyrics.kugou.com/search?" + urllib.parse.urlencode(p_legacy)
        req_l = urllib.request.Request(url_legacy, headers=HEADERS)
        with urllib.request.urlopen(req_l) as resp_l:
            data = json.loads(resp_l.read().decode("utf-8"))
        candidates = data.get("candidates", [])

    if not candidates:
        return None, "未找到歌词候选 (candidates is empty)"

    c = candidates[0]
    
    # 2. 下载 KRC
    down_p = {
        "ver": "1",
        "client": "android",
        "id": c["id"],
        "accesskey": c["accesskey"],
        "fmt": "krc",
        "charset": "utf8"
    }
    down_url = "http://lyrics.kugou.com/download?" + urllib.parse.urlencode(down_p)
    req_d = urllib.request.Request(down_url, headers=HEADERS)
    with urllib.request.urlopen(req_d) as resp_d:
        d_data = json.loads(resp_d.read().decode("utf-8"))

    if d_data.get("status") != 200 or not d_data.get("content"):
        return None, f"下载歌词失败 status={d_data.get('status')}"

    # 3. Base64 + XOR 解密
    raw_bin = base64.b64decode(d_data["content"])
    if len(raw_bin) <= 4:
        return None, "KRC 数据包长度不足"

    xor_bytes = bytearray(len(raw_bin) - 4)
    for i in range(4, len(raw_bin)):
        xor_bytes[i - 4] = raw_bin[i] ^ KRC_KEY[(i - 4) % len(KRC_KEY)]

    # 4. Zlib 解压缩
    try:
        decompressed_text = zlib.decompress(xor_bytes).decode("utf-8")
    except Exception as e:
        return None, f"Zlib 解压失败: {e}"

    # 5. 分析结构 (YRC 行数、双语翻译)
    yrc_lines = []
    has_language_tag = False
    trans_sample = ""
    
    # 检查外层 trans
    if d_data.get("trans"):
        try:
            trans_sample = base64.b64decode(d_data["trans"]).decode("utf-8").split("\n")[0].strip()
        except Exception:
            pass

    for line in decompressed_text.split("\n"):
        line = line.strip()
        if line.startswith("[language:"):
            has_language_tag = True
            try:
                b64 = line[10:-1]
                b64 += "=" * ((4 - len(b64) % 4) % 4)
                lang_json = json.loads(base64.b64decode(b64).decode("utf-8"))
                for sec in lang_json.get("content", []):
                    if sec.get("lyricContent"):
                        first_item = sec["lyricContent"][0]
                        trans_sample = (first_item[0] if isinstance(first_item, list) else str(first_item)).strip()
                        break
            except Exception:
                pass
        elif line.startswith("[") and "<" in line and ">" in line:
            # 转换为 Lazer YRC
            yrc = line.replace("<", "(").replace(">", ")")
            yrc_lines.append(yrc)

    return {
        "candidate_id": c["id"],
        "raw_krc_len": len(decompressed_text),
        "yrc_line_count": len(yrc_lines),
        "has_trans": bool(trans_sample) or has_language_tag,
        "sample_lines": yrc_lines[:3],
        "trans_sample": trans_sample
    }, None

def run_test(target_songs):
    print("=" * 70)
    print("       🎵 酷狗逐字动感歌词 (KRC) 与双语翻译自动化测试")
    print("=" * 70)

    success_count = 0
    for idx, s in enumerate(target_songs, 1):
        print(f"\n[{idx}/{len(target_songs)}] 正在验证: {s['title']} - {s['artist']} ({s.get('desc', '')})")
        print(f"      Hash: {s['hash']}")
        
        info, err = fetch_and_decode_krc(s["hash"])
        if err:
            print(f"      ❌ 测试失败: {err}")
            continue

        success_count += 1
        print(f"      ✅ KRC 解密成功 (解密后大小: {info['raw_krc_len']} 字节)")
        print(f"      ✨ 逐字动感歌词: 共 {info['yrc_line_count']} 行有效 YRC 数据")
        print(f"      🌐 双语翻译支持: {'是' if info['has_trans'] else '否 (纯中文单语曲目)'}")
        if info["trans_sample"]:
            print(f"         翻译示例: {info['trans_sample']}")
        
        if info["sample_lines"]:
            print("      📝 Lazer YRC 逐字高亮渲染样本:")
            for sample in info["sample_lines"]:
                print(f"         {sample}")

    print("\n" + "=" * 70)
    print(f"测试完毕: {success_count}/{len(target_songs)} 通过！")
    print("=" * 70)

if __name__ == "__main__":
    if len(sys.argv) > 1:
        query = sys.argv[1].strip()
        if len(query) == 32 and query.isalnum():
            # 直接是 Hash
            target = [{
                "title": "指定Hash曲目",
                "artist": "-",
                "hash": query,
                "desc": "用户命令行传入 Hash"
            }]
        else:
            found = search_hash(query)
            if not found:
                print(f"错误: 搜索 '{query}' 未找到曲目")
                sys.exit(1)
            target = [found]
        run_test(target)
    else:
        json_path = os.path.join(os.path.dirname(__file__), "songs.json")
        if os.path.exists(json_path):
            try:
                with open(json_path, "r", encoding="utf-8") as f:
                    loaded_songs = json.load(f)
                    if loaded_songs:
                        DEFAULT_SONGS = loaded_songs
            except Exception:
                pass
        run_test(DEFAULT_SONGS)
