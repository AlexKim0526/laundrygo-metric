# 런드리고 지표 보드

Snowflake 결과 CSV 를 HTML 안에 **구워 넣어** GitHub Pages 로 배포합니다.
받는 사람은 **링크만 열면 됩니다** — CSV 업로드가 필요 없습니다.

```
templates/   보드 HTML 원본 (데이터 없음)
data/        Snowflake 결과 CSV        ← 이것만 갈아끼우면 됩니다
queries/     그 CSV 를 만드는 SQL
dist/        빌드 결과 (자동 생성 · git 에 올리지 않음)
```

---

## 처음 한 번만 — 3분

1. 이 폴더를 새 리포지토리에 push
2. **Settings → Pages → Source** 를 **GitHub Actions** 로 변경
3. 첫 배포가 끝나면 `https://<org>.github.io/<repo>/` 로 공유

끝입니다. 이후로는 CSV 만 갈아끼우면 됩니다.

## 매번 갱신 — 30초

1. `queries/*.sql` 을 Snowflake 에서 실행
2. 결과를 CSV 로 내려 `data/` 의 **같은 이름으로 덮어쓰기**
3. ```bash
   git add data && git commit -m "data: 2026-09-01" && git push
   ```

push 하면 Actions 가 다시 굽고 배포합니다. 2~3분 걸립니다.

손으로 미리 확인하려면:

```bash
python build_boards.py          # dist/ 생성
open dist/index.html
```

---

## ⚠️ 이 사이트는 공개입니다

**GitHub Pages 사이트는 리포지토리를 private 으로 두어도 공개됩니다.**
URL 을 아는 사람은 누구나 봅니다. 비공개로 하려면 GitHub Enterprise Cloud 의
Pages access control 이 필요합니다 — Pro·Team 으로는 안 됩니다.

그래서 두 가지 장치를 넣어 두었습니다.

**1. 검색 노출 차단** — `robots.txt` 로 크롤러를 막습니다.
검색에는 안 걸리지만 **잠금은 아닙니다.** 링크가 새면 그대로 열립니다.

**2. 개인정보 가드** — 빌드할 때 CSV 를 훑어서 `user_id` · 이름 · 전화번호 ·
이메일 같은 것이 있으면 **빌드를 중단**합니다. 사람 단위 추출물을 실수로
`data/` 에 떨어뜨리는 사고를 막습니다.

```
[중단] 개인정보로 보이는 것이 CSV 에 있습니다. 공개 사이트에 올릴 수 없습니다.
        first-order-yoy.html: 헤더에 'user_id' 컬럼이 있습니다
```

정말 괜찮은 경우에만 `--allow-pii` 로 넘길 수 있습니다.
**공개 배포에서는 쓰지 마세요.**

> 나중에 비공개가 필요해지면 `dist/` 를 사내 호스팅이나 S3+SSO 에 올리는 것으로
> 바꾸면 됩니다. **빌드 방식은 그대로**이고 배포처만 달라집니다.

---

## 나중에 자동화하고 싶다면

`.github/workflows/refresh-from-snowflake.yml` 이 들어 있습니다.
지금은 **수동 실행 전용**(Actions 탭에서 버튼)으로 꺼 두었고,
파일 안의 `schedule` 두 줄 주석을 풀면 매주 월요일 아침(KST)에 자동으로 돕니다.

필요한 Secrets — **키페어 인증을 쓰세요. 비밀번호는 넣지 마세요.**

```
SNOWFLAKE_ACCOUNT  SNOWFLAKE_USER  SNOWFLAKE_ROLE
SNOWFLAKE_WAREHOUSE  SNOWFLAKE_DATABASE  SNOWFLAKE_SCHEMA
SNOWFLAKE_PRIVATE_KEY  SNOWFLAKE_PRIVATE_KEY_PASSPHRASE
```

**읽기 전용 롤**을 따로 만들어 쓰세요. 이 워크플로에 쓰기 권한은 필요 없습니다.
결과가 10행 미만이면 덮어쓰지 않고 실패합니다 — 빈 CSV 가 배포되어 보드가
통째로 비는 사고를 막기 위해서입니다.

---

## 알아 두실 것

- **BUILD_ID** — 새로 배포하면 뷰어의 지난번 업로드 캐시(localStorage)를 버립니다.
  옛 데이터가 새 배포를 가리는 일이 없습니다.
- **업로드 기능은 그대로 남아 있습니다.** 배포본에서도 CSV 를 끌어다 놓으면
  그 사람 화면에서만 바뀝니다. 임시로 다른 기간을 볼 때 편합니다.
- **보드 파서를 그대로 씁니다.** 빌드 스크립트는 CSV 를 해석하지 않고 통째로
  넣기만 합니다 — 파싱 규칙이 두 곳으로 갈라지지 않습니다.
- **CSV 는 base64 로 들어갑니다.** 파일이 원본 CSV 의 약 1.33배만큼 커집니다.
  지금(43~76KB)은 신경 쓸 수준이 아닙니다.
- **보드 사이 이동**은 상단 링크로 됩니다. 링크는 빌드할 때 자동으로 붙습니다.

## 파일별 대응

| 보드 | 쿼리 | 데이터 |
|---|---|---|
| `index.html` NSM 리뷰 | `30_스코어카드_통합.sql` | `data/30_스코어카드.csv` |
| `growth.html` 성장 | `40_성장_스코어보드.sql` | `data/40_성장.csv` |
| `first-order-yoy.html` 첫 주문·2회차 YoY | `42_첫주문율_YoY.sql` | `data/42_첫주문율YoY.csv` |
| `hipass.html` 하이패스 검증 | — (본문에 결과가 들어 있는 정적 문서) | — |
