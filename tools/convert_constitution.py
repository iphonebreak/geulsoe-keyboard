#!/usr/bin/env python3
"""대한민국헌법 조문 → 채움글 국가 상징 팩 항목 (원문: 법제처 국가법령정보센터).

입력: tools/data/constitution-law.go.kr-61603.html
      https://www.law.go.kr/lsEfInfoP.do?lsiSeq=61603 의 본문 조각
      (curl "https://www.law.go.kr/LSW/lsInfoR.do?lsiSeq=61603&efYd=19880225" -e "https://www.law.go.kr/" -A "Mozilla/5.0")
      헌법은 저작권법 제7조에 따라 보호받지 않는 저작물. 사용자 결정(2026-09-08): 위키 계열이 아니라 법제처 원문을 쓴다.
출력: Packages/TadakData/Sources/TadakData/Resources/Snippets.json 의 헌법 항목을 갈아끼운다
      (전문 + 제1조~제130조, 트리거 "헌법 N조" / "헌법 제N조" / "헌법 전문" / "헌법전문"). 다른 항목은 보존. 부칙 제외.
      본문은 법제처 표기 그대로 (항 번호 뒤 공백 없음, 가운뎃점 ㆍ).

재생성: python3 tools/convert_constitution.py
"""
import html, json, re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT / "tools/data/constitution-law.go.kr-61603.html"
OUT = ROOT / "Packages/TadakData/Sources/TadakData/Resources/Snippets.json"

def text_of(fragment: str) -> str:
    fragment = re.sub(r"<[^>]+>", " ", fragment)
    fragment = html.unescape(fragment)
    return re.sub(r"\s+", " ", fragment).strip()

doc = SRC.read_text(encoding="utf-8", errors="replace")
body = doc.split("<!-- 부칙 영역 끝 -->")[0] if "<!-- 부칙 영역 끝 -->" in doc else doc

def paragraphs(block: str) -> list[str]:
    return [t for t in (text_of(p) for p in re.findall(r'<p class="pty1_[^"]*"[^>]*>(.*?)</p>', block, re.S)) if t]

# 전문 — 앵커 JP0:0 블록
pre_match = re.search(r'<a name="JP0:0"[^>]*></a>(.*?)<a name="J\d+:0"', body, re.S)
if not pre_match:
    sys.exit("전문 블록을 찾지 못했다")
preamble = "\n\n".join(paragraphs(pre_match.group(1)))
if not preamble.startswith("유구한 역사와 전통에 빛나는"):
    sys.exit(f"전문이 예상과 다르다: {preamble[:40]}")

# 조문 — 앵커 J{n}:0 블록들
anchors = list(re.finditer(r'<a name="J(\d+):0"[^>]*></a>', body))
articles = []
for idx, m in enumerate(anchors):
    number = int(m.group(1))
    end = anchors[idx + 1].start() if idx + 1 < len(anchors) else len(body)
    paras = paragraphs(body[m.end():end])
    if not paras:
        sys.exit(f"제{number}조 본문 없음")
    head = re.sub(rf"^제{number}조\s*", "", paras[0])
    lines = [f"제{number}조 {head}".strip()] + paras[1:]
    articles.append((number, lines))

numbers = [n for n, _ in articles]
assert numbers == list(range(1, 131)), f"조문 번호 불연속 또는 개수 이상: {len(numbers)}개, 앞 {numbers[:3]} 뒤 {numbers[-3:]}"

entries = json.loads(OUT.read_text(encoding="utf-8"))
kept = [e for e in entries if not e["trigger"].startswith("헌법")]
generated = [{"trigger": t, "title": "대한민국 헌법 전문", "body": preamble} for t in ("헌법 전문", "헌법전문")]
for number, lines in articles:
    body_text = "\n".join(lines)
    for t in (f"헌법 {number}조", f"헌법 제{number}조"):
        generated.append({"trigger": t, "title": f"헌법 제{number}조", "body": body_text})

anthem = [e for e in kept if e["trigger"].startswith("애국가")]
flag = [e for e in kept if "국기" in e["trigger"]]
rest = [e for e in kept if e not in anthem and e not in flag]
OUT.write_text(json.dumps(anthem + flag + generated + rest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"법제처 원문: 전문 {len(preamble)}자, 조문 {len(articles)}개 → 항목 {len(generated)}개 (총 {len(anthem)+len(flag)+len(generated)+len(rest)}개)")
print("제2조:", articles[1][1])
print("제10조:", articles[9][1])
