#!/usr/bin/env python3
"""
build_boards.py — 결과 CSV 를 보드 HTML 안에 <b>구워 넣어</b> 단일 파일로 만듭니다.

  왜 필요한가
    보드 HTML 은 원래 "CSV 를 끌어다 놓는" 방식입니다. 링크로 공유하면
    받는 사람마다 매번 CSV 를 올려야 해서 쓸 수 없습니다.
    이 스크립트가 CSV 를 HTML 안에 넣어 두면 <b>열자마자 바로 보입니다.</b>

  어떻게 동작하나
    각 보드에는 이런 자리가 있습니다.
        const BUILD_ID = '__BUILD_ID__';
        const BAKED = (...)('__BAKED_CSV__');
    여기에 CSV 를 base64 로 넣습니다. 페이지는 <b>자기 파서를 그대로</b> 써서
    읽으므로 파싱 규칙이 두 곳에 갈라지지 않습니다.
    BUILD_ID 가 바뀌면 뷰어의 지난번 업로드 캐시(localStorage)를 버립니다 —
    새로 배포한 데이터가 옛 캐시에 가려지는 사고를 막습니다.

  쓰는 법
    python build_boards.py                       # boards.toml 대로 전부 빌드
    python build_boards.py --only 첫주문율        # 하나만
    python build_boards.py --check               # 빌드 결과 검증만

  입력 규약 (boards.toml 없이 쓰려면 아래 BOARDS 를 고치세요)
"""
from __future__ import annotations
import argparse, base64, datetime as dt, hashlib, json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent

# 보드 정의 : 출력파일 → (템플릿, 넣을 CSV 목록)
# CSV 를 여러 개 주면 이어 붙입니다(30번 + 23번처럼 나눠 뽑았을 때).
BOARDS = {
    "index.html":            ("templates/NSM_리뷰_스코어카드.html", ["data/30_스코어카드.csv"]),
    "growth.html":           ("templates/성장_스코어보드.html",     ["data/40_성장.csv"]),
    "first-order-yoy.html":  ("templates/첫주문율_YoY비교.html",     ["data/42_첫주문율YoY.csv"]),
    # 데이터가 이미 본문에 있는 정적 문서는 그대로 복사만 합니다
    "hipass.html":           ("templates/하이패스_효과검증.html",   []),
}

ALLOW_PII = False
MARK_ID, MARK_CSV = "__BUILD_ID__", "__BAKED_CSV__"

# ── 공개 사이트에 올라가므로, 개인 식별 정보가 섞이면 빌드를 멈춥니다 ──
#    보드는 <b>집계값</b>만 담아야 합니다. 실수로 사람 단위 추출물을 data/ 에
#    떨어뜨리는 사고를 여기서 잡습니다. --allow-pii 로만 넘길 수 있습니다.
PII_COLS = ("user_id", "userid", "회원id", "회원 id", "고객id", "이름", "성명", "name",
            "전화", "휴대폰", "phone", "mdn", "이메일", "email", "주소", "address",
            "생년", "birth", "advertising_id", "idfa", "appsflyer_id", "udid")
PII_PAT = (
    (re.compile(r"01[016789][- ]?\d{3,4}[- ]?\d{4}"), "휴대폰 번호로 보이는 값"),
    (re.compile(r"[\w.+-]+@[\w-]+\.[\w.]+"), "이메일로 보이는 값"),
)


def scan_pii(csv_txt: str, where: str) -> list[str]:
    hits = []
    lines = csv_txt.split("\n")
    header = lines[0].lower() if lines else ""
    for c in PII_COLS:
        if c in header:
            hits.append(f"{where}: 헤더에 '{c}' 컬럼이 있습니다")
    body = "\n".join(lines[1:6000])          # 앞부분만 훑어도 충분합니다
    for pat, why in PII_PAT:
        m = pat.search(body)
        if m:
            hits.append(f"{where}: {why} — '{m.group()[:6]}…'")
    return hits


def merge_csv(paths: list[Path]) -> str:
    """여러 CSV 를 하나로. 두 번째부터는 헤더 줄을 뺍니다."""
    out: list[str] = []
    for i, p in enumerate(paths):
        raw = p.read_bytes()
        for enc in ("utf-8-sig", "cp949"):
            try:
                txt = raw.decode(enc)
                break
            except UnicodeDecodeError:
                continue
        else:
            raise SystemExit(f"[에러] 인코딩을 못 읽었습니다: {p}")
        lines = txt.replace("\r\n", "\n").strip("\n").split("\n")
        if not lines or not lines[0].strip():
            raise SystemExit(f"[에러] 빈 파일: {p}")
        out.extend(lines if i == 0 else lines[1:])
    return "\n".join(out) + "\n"


NAV = [("index.html", "NSM 리뷰"), ("growth.html", "성장"),
       ("first-order-yoy.html", "첫 주문 · 2회차 YoY"), ("hipass.html", "하이패스 검증")]


def add_nav(html: str, cur: str) -> str:
    """보드 사이를 오갈 수 있게 상단에 링크 줄을 넣습니다."""
    if "board-nav" in html:
        return html
    links = "".join(
        '<a href="%s"%s>%s</a>' % (h, ' class="on"' if h == cur else '', t)
        for h, t in NAV)
    block = (
        '<style>.board-nav{display:flex;gap:6px;flex-wrap:wrap;margin:0 0 18px}'
        '.board-nav a{font-size:12.5px;font-weight:600;padding:5px 12px;border-radius:20px;'
        'border:1px solid var(--ring);color:var(--ink2);text-decoration:none;background:var(--surface)}'
        '.board-nav a:hover{border-color:var(--axis);color:var(--ink)}'
        '.board-nav a.on{background:var(--ink);color:var(--page);border-color:var(--ink)}</style>'
        f'<nav class="board-nav">{links}</nav>')
    return html.replace('<div class="wrap">', '<div class="wrap">\n' + block, 1)


def build(out_name: str, tpl_rel: str, csv_rels: list[str], build_id: str) -> dict:
    tpl = ROOT / tpl_rel
    if not tpl.exists():
        raise SystemExit(f"[에러] 템플릿이 없습니다: {tpl}")
    html = tpl.read_text(encoding="utf-8")

    html = add_nav(html, out_name)

    if not csv_rels:                       # 정적 문서 — 복사만
        (ROOT / "dist").mkdir(exist_ok=True)
        (ROOT / "dist" / out_name).write_text(html, encoding="utf-8")
        return {"out": out_name, "rows": None, "bytes": len(html.encode())}

    if MARK_CSV not in html:
        raise SystemExit(
            f"[에러] {tpl_rel} 에 '{MARK_CSV}' 자리가 없습니다.\n"
            f"       보드 HTML 이 구버전입니다 — 훅이 들어간 최신본으로 바꾸세요."
        )
    paths = [ROOT / c for c in csv_rels]
    for p in paths:
        if not p.exists():
            raise SystemExit(f"[에러] CSV 가 없습니다: {p}")
    csv_txt = merge_csv(paths)
    if not ALLOW_PII:
        hits = scan_pii(csv_txt, out_name)
        if hits:
            raise SystemExit(
                "[중단] 개인정보로 보이는 것이 CSV 에 있습니다. 공개 사이트에 올릴 수 없습니다.\n"
                + "\n".join("        " + h for h in hits)
                + "\n        집계 쿼리 결과가 맞는지 확인하세요."
                  " 정말 괜찮다면 --allow-pii 를 붙이세요."
            )
    n_rows = csv_txt.count("\n") - 1
    if n_rows < 1:
        raise SystemExit(f"[에러] 데이터 행이 없습니다: {csv_rels}")

    b64 = base64.b64encode(csv_txt.encode("utf-8")).decode("ascii")
    html = html.replace(MARK_CSV, b64).replace(MARK_ID, build_id)

    (ROOT / "dist").mkdir(exist_ok=True)
    (ROOT / "dist" / out_name).write_text(html, encoding="utf-8")
    return {"out": out_name, "rows": n_rows, "bytes": len(html.encode()),
            "src": [str(p.relative_to(ROOT)) for p in paths]}


def check(out_name: str) -> list[str]:
    """빌드 결과가 실제로 쓸 수 있는 상태인지 확인합니다."""
    p = ROOT / "dist" / out_name
    errs = []
    if not p.exists():
        return [f"{out_name}: 파일이 없습니다"]
    s = p.read_text(encoding="utf-8")
    if MARK_CSV in s:
        errs.append(f"{out_name}: CSV 자리표시자가 그대로 남아 있습니다")
    if MARK_ID in s:
        errs.append(f"{out_name}: BUILD_ID 자리표시자가 그대로 남아 있습니다")
    if "<script" not in s:
        errs.append(f"{out_name}: 스크립트가 없습니다")
    # base64 가 실제로 UTF-8 CSV 로 복원되는지
    m = re.search(r"\}\)\('([A-Za-z0-9+/=]{40,})'\)", s)
    if m:
        try:
            txt = base64.b64decode(m.group(1)).decode("utf-8")
            if txt.count("\n") < 2:
                errs.append(f"{out_name}: 구워 넣은 CSV 의 행이 너무 적습니다")
        except Exception as e:
            errs.append(f"{out_name}: base64 복원 실패 — {e}")
    elif "hipass" not in out_name:
        errs.append(f"{out_name}: 구워 넣은 CSV 를 찾지 못했습니다")
    return errs


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", help="이름 일부가 맞는 보드만 빌드")
    ap.add_argument("--check", action="store_true", help="빌드하지 않고 dist 검증만")
    ap.add_argument("--allow-pii", action="store_true",
                    help="개인정보 가드를 끄고 강행 (공개 사이트에서는 쓰지 마세요)")
    a = ap.parse_args()
    global ALLOW_PII
    ALLOW_PII = a.allow_pii

    if a.check:
        errs = [e for n in BOARDS for e in check(n)]
        print("\n".join(errs) if errs else "검증 통과 — 모든 보드가 데이터를 품고 있습니다")
        return 1 if errs else 0

    build_id = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d-%H%M%S")
    made = []
    for out_name, (tpl, csvs) in BOARDS.items():
        if a.only and a.only not in out_name and a.only not in tpl:
            continue
        info = build(out_name, tpl, csvs, build_id)
        made.append(info)
        rows = "정적" if info["rows"] is None else f'{info["rows"]:,}행'
        print(f'  ✓ dist/{info["out"]:<22} {rows:>10}  {info["bytes"]/1024:6.0f} KB')

    if not made:
        print("빌드할 보드가 없습니다 — --only 값을 확인하세요")
        return 1

    rb = ROOT / "templates" / "robots.txt"      # 검색 노출 가림막 (잠금은 아닙니다)
    if rb.exists():
        (ROOT / "dist" / "robots.txt").write_text(rb.read_text(encoding="utf-8"), encoding="utf-8")

    (ROOT / "dist" / "build.json").write_text(
        json.dumps({"build_id": build_id, "boards": made,
                    "built_at": dt.datetime.now(dt.timezone.utc).isoformat()},
                   ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\nBUILD_ID = {build_id}")
    errs = [e for n in BOARDS for e in check(n)]
    if errs:
        print("\n[검증 실패]\n" + "\n".join("  " + e for e in errs))
        return 1
    print("검증 통과 — dist/ 를 그대로 배포하시면 됩니다")
    return 0


if __name__ == "__main__":
    sys.exit(main())
