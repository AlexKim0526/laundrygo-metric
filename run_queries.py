#!/usr/bin/env python3
"""queries/*.sql 을 Snowflake 에서 실행해 data/*.csv 로 저장합니다.

  · 쿼리 맨 위의 `set ...;` 줄을 그대로 세션에 적용한 뒤 본문을 실행합니다.
  · 결과가 0행이면 <b>기존 CSV 를 덮어쓰지 않고 실패</b>시킵니다 —
    빈 파일이 배포되어 보드가 통째로 비는 사고를 막기 위해서입니다.
"""
import os, re, sys
from pathlib import Path
import snowflake.connector
from cryptography.hazmat.primitives import serialization

ROOT = Path(__file__).resolve().parent
JOBS = {                       # 출력 CSV → 쿼리 파일
    "data/30_스코어카드.csv":   "queries/30_스코어카드_통합.sql",
    "data/40_성장.csv":         "queries/40_성장_스코어보드.sql",
    "data/42_첫주문율YoY.csv":  "queries/42_첫주문율_YoY.sql",
}
MIN_ROWS = 10                  # 이보다 적으면 뭔가 잘못된 것으로 봅니다


def pkey():
    raw = os.environ["SF_PRIVATE_KEY"].encode()
    pw = os.environ.get("SF_PRIVATE_KEY_PASSPHRASE") or None
    k = serialization.load_pem_private_key(raw, password=pw.encode() if pw else None)
    return k.private_bytes(serialization.Encoding.DER,
                           serialization.PrivateFormat.PKCS8,
                           serialization.NoEncryption())


def split_sql(text: str):
    """맨 위 `set` 문들과 본문 쿼리를 나눕니다."""
    sets, body = [], []
    for line in text.split("\n"):
        if re.match(r"^\s*set\s+\w+\s*=", line, re.I) and not body:
            sets.append(line.strip().rstrip(";") + ";")
        else:
            body.append(line)
    return sets, "\n".join(body)


def main() -> int:
    con = snowflake.connector.connect(
        account=os.environ["SF_ACCOUNT"], user=os.environ["SF_USER"],
        private_key=pkey(), role=os.environ.get("SF_ROLE"),
        warehouse=os.environ.get("SF_WAREHOUSE"),
        database=os.environ.get("SF_DATABASE"), schema=os.environ.get("SF_SCHEMA"),
        client_session_keep_alive=False,
    )
    bad = 0
    try:
        for out, q in JOBS.items():
            sets, body = split_sql((ROOT / q).read_text(encoding="utf-8"))
            cur = con.cursor()
            for s in sets:
                cur.execute(s)
            cur.execute(body)
            df = cur.fetch_pandas_all()
            cur.close()
            if len(df) < MIN_ROWS:
                print(f"  ✗ {out}: {len(df)}행 — 너무 적습니다. 덮어쓰지 않습니다.")
                bad += 1
                continue
            p = ROOT / out
            p.parent.mkdir(parents=True, exist_ok=True)
            df.to_csv(p, index=False, encoding="utf-8-sig")
            print(f"  ✓ {out}: {len(df):,}행")
    finally:
        con.close()
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
