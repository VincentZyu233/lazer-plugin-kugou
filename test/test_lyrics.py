#!/usr/bin/env python3
"""
酷狗逐字动感歌词 (KRC)、双语翻译与罗马音音译自动化测试验证脚本

支持功能：
  1. 验证 KRC 密文解密、Zlib 解压与 YRC 逐字时间轴打点。
  2. 验证多语言语言包解析：
     - type == 1：中文双语翻译
     - type == 0：罗马音音译 (Romanization / 拼音音译)
  3. 支持按分组批量测试或测试指定歌曲：
     uv run python test/test_lyrics.py
     uv run python test/test_lyrics.py --group vocaloid_modern
     uv run python test/test_lyrics.py "稲葉曇 ラグトレイン"
     uv run python test/test_lyrics.py 92adb9924cdee8fc549776acc2d77908
"""

import base64
import json
import os
import sys
import urllib.parse
import urllib.request
import zlib

HEADERS = {
    "User-Agent": "KuGou2012-9020-Metadata-SearchArtistLyric",
    "Accept": "*/*"
}

KRC_KEY = bytes([64, 71, 97, 119, 94, 50, 116, 71, 81, 54, 49, 45, 206, 210, 110, 105])

# ==============================================================================
# 歌曲测试曲库定义（按曲目特性、语言与风格结构化分组）
# ==============================================================================
SONG_GROUPS = {
    # --------------------------------------------------------------------------
    # 分组 1：新锐术力口 (MIMI / いよわ / 稻叶昙) —— 100% 具备【逐字动感 + 罗马音 + 中文翻译】
    # --------------------------------------------------------------------------
    "vocaloid_modern": {
        "name": "新锐术力口名 P 主（いよわ / 稻叶昙 / MIMI）",
        "description": "具备完整三行歌词轨：日文原文 + 罗马音音译 + 中文双语翻译",
        "songs": [
            {
                "title": "ラグトレイン (延误列车 / Lagtrain)",
                "artist": "稲葉曇、歌愛ユキ",
                "hash": "92adb9924cdee8fc549776acc2d77908",
                "desc": "稻叶昙传世名作，灰黑女孩封面，三行歌词基准验证曲"
            },
            {
                "title": "きゅうくらりん (Kyu-kurarin)",
                "artist": "いよわ、可不",
                "hash": "767bafb163149331f0a30723d60819f3",
                "desc": "いよわ 极高人气神作，三轨齐备 (逐字动感 + 罗马音 + 翻译)"
            },
            {
                "title": "1000年生きてる (活了一千年)",
                "artist": "いよわ、初音ミク",
                "hash": "9f56e1d827b859e1dc8e6bec20a3a3d4",
                "desc": "いよわ 殿堂金曲，三轨齐备 (逐字动感 + 罗马音 + 翻译)"
            },
            {
                "title": "ハナタバ (花束)",
                "artist": "MIMI、可不",
                "hash": "fcbc7ffd80ec9020f3ac6bf4a163cde7",
                "desc": "MIMI 治愈系代表神曲，细腻情感动感打点"
            },
            {
                "title": "今はいいんだよ。 (现在这样就好。)",
                "artist": "MIMI、可不",
                "hash": "195cd85b071a0fb1980ebdb53e324c50",
                "desc": "MIMI 可不温柔抒情作，逐字动感节奏"
            }
        ]
    },

    # --------------------------------------------------------------------------
    # 分组 2：经典术力口神曲 (Vocaloid Classics) —— 100% 具备【逐字动感 + 罗马音 + 中文翻译】
    # --------------------------------------------------------------------------
    "vocaloid_classics": {
        "name": "传世术力口经典神曲 (Vocaloid Classics)",
        "description": "殿堂级初音未来 / 镜音双子神曲，多音轨覆盖完备",
        "songs": [
            {
                "title": "千本桜",
                "artist": "初音ミク、WhiteFlame",
                "hash": "1b111e263ee8210413bff2e80da29a13",
                "desc": "术力口传世第一神曲 (逐字动感 + 罗马音 + 双语翻译)"
            },
            {
                "title": "深海少女",
                "artist": "初音ミク、ゆうゆ",
                "hash": "e89a65c84cf6b85c8408cb1489acb773",
                "desc": "术力口经典抒情慢歌 (逐字动感 + 罗马音 + 双语翻译)"
            },
            {
                "title": "メルト (Melt)",
                "artist": "Ryo、初音ミク",
                "hash": "d77911d9332ef6ba1f55d0f47c2283c3",
                "desc": "supercell / Ryo 极早期的黄金时代起点作"
            },
            {
                "title": "ロミオとシンデレラ (罗密欧与辛德瑞拉)",
                "artist": "doriko、初音ミク",
                "hash": "bab453d1d3fd883e4077213796c27cc2",
                "desc": "doriko 殿堂经典，三轨数据完整"
            },
            {
                "title": "ロキ (ROKI)",
                "artist": "鏡音リン、みきとP",
                "hash": "bf6902f3529198e6b9a2b9125ebe5b76",
                "desc": "超高燃双人快节奏互动对唱打点"
            },
            {
                "title": "ヴァンパイア (吸血鬼)",
                "artist": "DECO*27、初音ミク",
                "hash": "63c13235c1469d1b716015c632ecda29",
                "desc": "现代高热度舞曲风格 (逐字动感 + 罗马音 + 双语翻译)"
            },
            {
                "title": "六兆年と一夜物語",
                "artist": "kemu、IA",
                "hash": "652b60a6633018ddec3945d964c22ec2",
                "desc": "超高速 BPM 密集打点，考验逐字解析极限"
            },
            {
                "title": "ロストワンの号哭",
                "artist": "鏡音リン、Neru",
                "hash": "04b8a9f6b08d9dcf1482aca0658cfcc7",
                "desc": "Neru 摇滚摇滚疾走曲，动感极佳"
            },
            {
                "title": "神っぽいな (像神一样呐)",
                "artist": "ピノキオピー、初音ミク",
                "hash": "d1912b08e1596a9ff593bb6dc669b632",
                "desc": "匹诺曹P 讽刺风洗脑神曲"
            },
            {
                "title": "アンノウン・マザーグース (Unknown Mother-Goose)",
                "artist": "wowaka、初音ミク",
                "hash": "e051d18d14531fcedda5e5e029eb92ff",
                "desc": "wowaka 遗作绝唱，高密度文字与情感爆发"
            }
        ]
    },

    # --------------------------------------------------------------------------
    # 分组 3：J-Pop 热门流行金曲 (Japanese Popular Music)
    # --------------------------------------------------------------------------
    "jpop": {
        "name": "日文流行金曲 (J-Pop)",
        "description": "热播流行曲目，具备逐字动感歌词与中文双语翻译",
        "songs": [
            {
                "title": "夜に駆ける",
                "artist": "YOASOBI",
                "hash": "2131897fda53adbf58825cc3c61d0860",
                "desc": "极高节奏动感流行，逐字双语打点"
            },
            {
                "title": "Lemon",
                "artist": "米津玄師",
                "hash": "da60f11f69affc7107adede9dd17352a",
                "desc": "日剧神曲，标准动感打点与双语翻译"
            },
            {
                "title": "幽霊東京",
                "artist": "Ayase、初音ミク",
                "hash": "633586779348c8d1262fa43c528c3db1",
                "desc": "都市感流行电子作"
            }
        ]
    },

    # --------------------------------------------------------------------------
    # 分组 4：欧美流行热单 (Western Pop Hits)
    # --------------------------------------------------------------------------
    "western_pop": {
        "name": "欧美流行热单 (Western Pop)",
        "description": "英文原生逐词动感与中英双语翻译对照",
        "songs": [
            {
                "title": "Rolling in the Deep",
                "artist": "Adele",
                "hash": "453cbdd4347ccbf2f6203f37c9d9597c",
                "desc": "经典英文律动大单，逐词动感 + 中文字幕"
            },
            {
                "title": "Shape of You",
                "artist": "Ed Sheeran",
                "hash": "b6a303c9cda8e6c4c0b2fb0b23a570c6",
                "desc": "流行轻快节奏打击点"
            }
        ]
    },

    # --------------------------------------------------------------------------
    # 分组 5：华语流行标杆 (Chinese Classics)
    # --------------------------------------------------------------------------
    "chinese_classics": {
        "name": "华语经典流行 (Chinese Classics)",
        "description": "原生中文单语极高品质动感逐字歌词标杆",
        "songs": [
            {
                "title": "晴天",
                "artist": "周杰伦",
                "hash": "b3a52a7a958bf0aed0ebfba2e9a818b7",
                "desc": "华语传唱标杆，极细粒度逐字时间轴"
            },
            {
                "title": "江南",
                "artist": "林俊杰",
                "hash": "b83dbb8e3dd3fcf86bf32690b91547f5",
                "desc": "中国风抒情转音打点"
            }
        ]
    }
}


def get_all_songs():
    all_songs = []
    for g_key, group in SONG_GROUPS.items():
        for s in group["songs"]:
            s_copy = dict(s)
            s_copy["group"] = g_key
            s_copy["group_name"] = group["name"]
            all_songs.append(s_copy)
    return all_songs


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
        "desc": "用户自定义搜索",
        "group": "custom",
        "group_name": "自定义搜索"
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
    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except Exception:
        data = {}

    candidates = data.get("candidates", [])
    if not candidates:
        p_legacy = {"ver": "1", "man": "yes", "client": "pc", "duration": "0", "hash": song_hash}
        url_legacy = "http://lyrics.kugou.com/search?" + urllib.parse.urlencode(p_legacy)
        req_l = urllib.request.Request(url_legacy, headers=HEADERS)
        try:
            with urllib.request.urlopen(req_l) as resp_l:
                data = json.loads(resp_l.read().decode("utf-8"))
        except Exception:
            data = {}
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

    # 5. 分析结构 (YRC 行数、双语翻译、罗马音音译)
    yrc_lines = []
    has_language_tag = False
    trans_sample = ""
    roman_sample = ""
    has_roman = False
    has_trans = False

    # 检查外层 trans
    if d_data.get("trans"):
        try:
            trans_sample = base64.b64decode(d_data["trans"]).decode("utf-8").split("\n")[0].strip()
            if trans_sample:
                has_trans = True
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
                    sec_type = sec.get("type")
                    items = sec.get("lyricContent", [])
                    if items:
                        first_item = items[0]
                        sample_str = (first_item[0] if isinstance(first_item, list) else str(first_item)).strip()
                        if sec_type == 1 and not trans_sample:
                            has_trans = True
                            trans_sample = sample_str
                        elif sec_type == 0 and not roman_sample:
                            has_roman = True
                            roman_sample = sample_str
            except Exception:
                pass
        elif line.startswith("[") and "<" in line and ">" in line:
            # 转换为 Lazer YRC 逐字高亮格式
            yrc = line.replace("<", "(").replace(">", ")")
            yrc_lines.append(yrc)

    return {
        "candidate_id": c["id"],
        "raw_krc_len": len(decompressed_text),
        "yrc_line_count": len(yrc_lines),
        "has_trans": has_trans or (bool(trans_sample) and has_language_tag),
        "has_roman": has_roman,
        "trans_sample": trans_sample,
        "roman_sample": roman_sample,
        "sample_lines": yrc_lines[:2]
    }, None


def run_test(target_songs, header_title="酷狗逐字动感歌词 (KRC) 与多轨歌词测试"):
    print("=" * 78)
    print(f"       🎵 {header_title}")
    print("=" * 78)

    success_count = 0
    three_tier_count = 0

    current_grp = None
    for idx, s in enumerate(target_songs, 1):
        grp_name = s.get("group_name")
        if grp_name and grp_name != current_grp:
            current_grp = grp_name
            print(f"\n📂 【{current_grp}】")
            print("-" * 78)

        print(f"[{idx}/{len(target_songs)}] {s['title']} - {s['artist']}")
        print(f"      Hash: {s['hash']}  |  说明: {s.get('desc', '')}")

        info, err = fetch_and_decode_krc(s["hash"])
        if err:
            print(f"      ❌ 测试失败: {err}")
            continue

        success_count += 1
        is_three_tier = info["has_roman"] and info["has_trans"]
        if is_three_tier:
            three_tier_count += 1

        tier_tag = "🌟【三轨全齐：原文+罗马音+中文】" if is_three_tier else ("🌐【双语翻译】" if info["has_trans"] else "📝【单语动感】")

        print(f"      ✅ 解密成功 (KRC 大小: {info['raw_krc_len']} 字节)  |  {tier_tag}")
        print(f"      ✨ 逐字动感歌词: 共 {info['yrc_line_count']} 行有效 YRC 打点")
        print(f"      🌐 中文翻译: {'✅ 有' if info['has_trans'] else '❌ 无'}" + (f" -> 示例: {info['trans_sample']}" if info['trans_sample'] else ""))
        print(f"      🔤 罗马音音译: {'✅ 有' if info['has_roman'] else '❌ 无'}" + (f" -> 示例: {info['roman_sample']}" if info['roman_sample'] else ""))

        if info["sample_lines"]:
            print("      💡 Lazer YRC 逐字打点片段:")
            for sample in info["sample_lines"]:
                print(f"         {sample}")
        print()

    print("=" * 78)
    print(f"测试完毕: {success_count}/{len(target_songs)} 首测试通过！其中 {three_tier_count} 首歌具备【三轨全齐】歌词。")
    print("=" * 78)


if __name__ == "__main__":
    args = sys.argv[1:]
    
    if args and args[0] in ("--help", "-h"):
        print(__doc__)
        sys.exit(0)

    if args and args[0] == "--group":
        if len(args) < 2:
            print(f"可用分组: {list(SONG_GROUPS.keys())}")
            sys.exit(1)
        grp_key = args[1]
        if grp_key not in SONG_GROUPS:
            print(f"错误: 未知分组 '{grp_key}'，可用分组: {list(SONG_GROUPS.keys())}")
            sys.exit(1)
        target = [dict(s, group_name=SONG_GROUPS[grp_key]["name"]) for s in SONG_GROUPS[grp_key]["songs"]]
        run_test(target, header_title=f"酷狗分组测试: {SONG_GROUPS[grp_key]['name']}")
        sys.exit(0)

    if args and args[0] == "--three-tier-only":
        # 仅测试三轨齐备的歌曲
        vocaloid_songs = []
        for g in ("vocaloid_modern", "vocaloid_classics"):
            for s in SONG_GROUPS[g]["songs"]:
                vocaloid_songs.append(dict(s, group_name=SONG_GROUPS[g]["name"]))
        run_test(vocaloid_songs, header_title="三轨全齐专属测试（新锐术力口 + 传世神曲）")
        sys.exit(0)

    if args:
        query = args[0].strip()
        if len(query) == 32 and query.isalnum():
            target = [{
                "title": "指定 Hash 曲目",
                "artist": "-",
                "hash": query,
                "desc": "用户命令行传入 Hash",
                "group_name": "单曲测试"
            }]
        else:
            found = search_hash(query)
            if not found:
                print(f"错误: 搜索 '{query}' 未在酷狗曲库中找到对应歌曲")
                sys.exit(1)
            target = [found]
        run_test(target, header_title=f"单曲歌词解析测试: {query}")
    else:
        # 默认回归测试：测试所有分组
        all_songs = get_all_songs()
        run_test(all_songs)
