---------------------------------------------------------------
set y_prev  = 2025;             -- 비교 기준 연도
set y_cur   = 2026;             -- 이번 연도
set d_from  = '01-01';          -- 두 해 공통 시작 (MM-DD)
set d_to    = '08-20';          -- 두 해 공통 종료 (MM-DD)  ← 여기까지만 자릅니다
set cw      = 7;                -- 첫 주문 관측 창(일)
set rw      = 30;               -- <b>2회차</b> 관측 창(일) — 기준일은 가입일이 아니라 <b>첫 주문일</b>
set p_asof  = current_date();   -- 어디까지 관측했는가
---------------------------------------------------------------
/* ============================================================================
   42. 첫 주문율 YoY 비교  —  2025 vs 2026, 1/1 ~ 8/20 같은 자리로 자름
   ----------------------------------------------------------------------------
   [ 무엇을 세는가 ]
     분모 = 그 달에 <b>가입한 회원 전수</b>
            LAUNDRY24(무인세탁소) 계정만 제외. <b>이후 탈퇴한 회원도 그대로 셉니다.</b>
            (deleted=false 로 걸면 분모가 "지금 시점의 생존자" 라, 시간이 지나
             탈퇴가 쌓이면 과거 달의 값이 조용히 바뀝니다 — 32번에서 실측 확인)
     분자 = 그 중 <b>가입일부터 7일 안에 첫 수거신청</b>을 한 <b>사람 수</b>
            요금제(자유/구독) <b>구분 없이</b> 한 사람을 한 번만 셉니다.
            수거신청 건수가 아니라 <b>주문자 수</b>입니다.
     수거 = status not in (4, 17) AND laundry24_pgi is null   (30·40번과 동일)

   [ 2회차 주문율 — <b>시계가 다릅니다</b> ]
     분모 = 위의 <b>첫 주문자</b> (가입자가 아닙니다)
     분자 = 그 중 <b>첫 주문일부터 30일 안에</b> 두 번째 수거신청까지 간 사람
     ★ 기준일이 <b>가입일이 아니라 첫 주문일</b>입니다. 가입일에서 재면
       첫 주문이 늦은 사람일수록 2회차 낼 시간이 줄어, 재주문 능력이 아니라
       <b>첫 주문 속도</b>를 재게 됩니다 (41번에서 확인한 문제입니다).
     같은 날 두 건이면 2회차로 셉니다 — 창 안의 주문 수가 2건 이상이면 도달입니다.
     참고로 <b>가입자를 분모로 본 값</b>도 같이 냅니다. 이건 퍼널 전체
     (가입 → 첫 주문 → 2회차)를 하나로 본 값이라 성격이 다릅니다.

   [ 왜 8/20 인가 — 같은 자리에서 잘라야 비교가 됩니다 ]
     8월을 통째로 넣으면 2026년은 아직 안 끝난 달이라 무조건 작게 나옵니다.
     그래서 <b>두 해 모두 8/1~8/20</b> 로 자릅니다. 나머지 1~7월은 온전한 달입니다.
     결과의 "비고" 칸에 부분 달이 표시됩니다.

   [ 관측 가드 — 두 지표의 <b>관측 종료 시점이 다릅니다</b> ]
     · 첫 주문율 : 8/20 가입자는 8/27 까지 봐야 7일 창이 찹니다.
     · 2회차     : 그 사람이 8/27 에 첫 주문했다면 <b>9/26</b> 까지 봐야 30일이 찹니다.
       → 그래서 <b>2회차는 첫 주문율보다 약 5주 늦게</b> 확정됩니다.
         오늘 돌리면 최근 <b>두 달</b> 정도는 2회차가 비어 있는 것이 정상입니다.
     한 명이라도 창이 안 찬 달은 <b>통째로 비웁니다</b> — 덜 찬 값을 "하락" 으로
     읽는 것을 막기 위해서입니다.

   [ 40번 ② 와의 관계 ]
     같은 정의·같은 창입니다. 40번을 grain='month' 로 돌린 값과
     1~7월은 <b>정확히 같아야</b> 합니다. 다르면 파라미터가 어긋난 것입니다.
     (8월만 다릅니다 — 이 쿼리는 20일까지만 자르기 때문입니다)
   ========================================================================== */
with
prm as (
    select $y_prev as py, $y_cur as cy, $cw as cw, $rw as rw, to_date($p_asof) as asof,
           $d_from as df, $d_to as dt
),
bnd as (
    select py, cy, cw, rw, asof, df, dt,
           to_date(py || '-' || df) as ps_p, to_date(py || '-' || dt) as pe_p,
           to_date(cy || '-' || df) as ps_c, to_date(cy || '-' || dt) as pe_c
    from prm
),
/* ── 분모 : 두 구간의 가입자 전수 ────────────────────────────────── */
jn as (
    select
        u.id                                                        as user_id,
        date(convert_timezone('Asia/Seoul', u.created_at))           as join_d
    from "USER" u
        cross join bnd b
    where ifnull(u.account_type, '') <> 'LAUNDRY24'
      and ( date(convert_timezone('Asia/Seoul', u.created_at)) between b.ps_p and b.pe_p
         or date(convert_timezone('Asia/Seoul', u.created_at)) between b.ps_c and b.pe_c )
),
/* ── 수거신청 : 7일 창을 보려면 p_asof 까지 열어둬야 한다 ─────────── */
w as (
    select
        w.user_id                                                   as user_id,
        w.id                                                        as wash_id,
        date(convert_timezone('Asia/Seoul', w.created_at))           as d
    from wash w
        cross join bnd b
    where w.status not in (4, 17)
      and w.laundry24_pgi is null
      and date(convert_timezone('Asia/Seoul', w.created_at)) between b.ps_p and b.asof
),
/* ── 가입자별 : 7일 안에 첫 주문을 했는가 (사람 단위, 요금제 무관) ── */
u7 as (
    select
        j.user_id,
        j.join_d,
        max(iff(w.d between j.join_d and dateadd(day, b.cw, j.join_d), 1, 0)) as ord7,
        /* 첫 주문일 — 2회차 시계는 <b>가입일이 아니라 여기서</b> 시작합니다 */
        min(iff(w.d between j.join_d and dateadd(day, b.cw, j.join_d), w.d, null)) as first_d
    from jn j
        cross join bnd b
        left join w on w.user_id = j.user_id
    group by 1, 2
),
/* ── 2회차 : 첫 주문일부터 rw(30)일 안에 <b>두 번째</b> 수거신청이 있었나 ──
      같은 날 두 건이면 2회차로 셉니다(41번 재주문 정의와 동일).
      기간 안 주문 수가 2건 이상이면 2회차 도달입니다. */
u2 as (
    select
        a.user_id,
        a.join_d,
        a.first_d,
        count(distinct iff(w.d between a.first_d and dateadd(day, b.rw, a.first_d),
                           w.wash_id, null))                        as n_ord,
        /* 이 사람의 30일 창이 다 찼는가 */
        max(iff(dateadd(day, b.rw, a.first_d) <= b.asof, 1, 0))      as obs2
    from u7 a
        cross join bnd b
        left join w on w.user_id = a.user_id
    where a.ord7 = 1
    group by 1, 2, 3
),
agg as (
    select
        year(u7.join_d)                                             as yr,
        month(u7.join_d)                                            as mo,
        count(*)                                                    as n,
        sum(u7.ord7)                                                as k,
        /* 그 달 마지막 가입자까지 7일이 찼는가 */
        max(iff(dateadd(day, b.cw, u7.join_d) <= b.asof, 0, 1))     as any_open
    from u7
        cross join bnd b
    group by 1, 2
),
agg2 as (
    select
        year(u2.join_d)                                             as yr,
        month(u2.join_d)                                            as mo,
        count(*)                                                    as k,       -- 첫 주문자 수 (검산용)
        count_if(u2.n_ord >= 2)                                     as k2,
        /* 한 명이라도 30일이 안 찼으면 그 달은 통째로 비웁니다 */
        max(iff(u2.obs2 = 1, 0, 1))                                 as any_open2
    from u2 group by 1, 2
)
select
    a.yr                                                            as "연도",
    a.mo                                                            as "월",
    a.yr || '-' || lpad(a.mo, 2, '0')                               as "기간",
    a.n                                                             as "신규 가입자(명)",
    iff(a.any_open = 0, a.k, null)                                  as "첫 주문자 수(명)",
    iff(a.any_open = 0, round(a.k / nullif(a.n, 0) * 100, 2), null) as "첫 주문율(%)",
    /* ── 2회차 : 분모는 <b>첫 주문자</b>, 시계는 <b>첫 주문일</b> ── */
    iff(a2.any_open2 = 0, a2.k2, null)                              as "2회차 주문자 수(명)",
    iff(a2.any_open2 = 0, round(a2.k2 / nullif(a2.k, 0) * 100, 2), null)
                                                                    as "2회차 주문율(%)",
    /* 참고 : 가입자를 분모로 본 값 (퍼널 전체) */
    iff(a.any_open = 0 and a2.any_open2 = 0,
        round(a2.k2 / nullif(a.n, 0) * 100, 2), null)               as "가입자 대비 2회차(%)",
    (case when a.any_open = 1 then '관측 대기(7일 미충족)'
          when a2.any_open2 = 1 and a.mo = month(b.pe_c)
               then '부분 · 1~' || day(b.pe_c) || '일 · 2회차 관측 대기(30일 미충족)'
          when a2.any_open2 = 1 then '2회차 관측 대기(30일 미충족)'
          when a.mo = month(b.pe_c)
               then '부분 · 1~' || day(b.pe_c) || '일'
          else '전월' end)                                           as "비고"
from agg a
    cross join bnd b
    left join agg2 a2 on a2.yr = a.yr and a2.mo = a.mo
order by a.mo, a.yr

/* ----------------------------------------------------------------------------
   [ 결과를 어떻게 읽나 ]

     1) <b>월별 %p 차이</b>를 먼저 봅니다. 비율의 % 변화(YoY(%))가 아니라
        <b>%p 차이</b>가 이 지표의 언어입니다. "34% → 30%" 는 -11.8% 가 아니라
        <b>-4%p</b> 로 읽어야 크기 감각이 맞습니다.

     2) 분자·분모를 <b>같이</b> 봅니다. 비율만 보면 원인을 못 찾습니다.
          · 가입자 ↑ · 첫 주문자 → · 비율 ↓  →  <b>유입의 질</b>이 바뀐 것
          · 가입자 → · 첫 주문자 ↓ · 비율 ↓  →  <b>온보딩</b>이 막힌 것
        첫 주문율은 대량 유입 달에 구조적으로 떨어집니다 (41번에서 자유 재주문도
        코호트 크기와 상관 -0.83 이었습니다). 캠페인 달을 먼저 표시해 두세요.

     3) <b>기간 누계</b>가 최종 판단입니다. 월별은 계절·캠페인으로 흔들립니다.
        누계 = Σ첫 주문자 ÷ Σ가입자 이며, 월별 비율의 단순 평균이 아닙니다
        (달마다 가입자 수가 달라 가중이 다릅니다). HTML 이 이걸 자동 계산합니다.

   [ 표본 감각 ]
     월 가입자가 1만 명 수준이면 첫 주문율(≈33%)의 95% 오차범위는 ±0.9%p 입니다.
     <b>1%p 미만 차이는 노이즈</b>로 보시고, 2%p 이상부터 신호로 읽으세요.
     2회차는 분모가 첫 주문자(≈3,300명)라 오차범위가 <b>±1.7%p</b> 로 두 배 가까이
     넓습니다. 같은 크기의 차이라도 <b>2회차 쪽이 덜 확실</b>합니다.

   [ 두 지표를 같이 보는 법 ]
     · 첫 주문율 ↓ · 2회차 주문율 → : <b>획득</b> 문제 (유입의 질 / 온보딩 마찰)
     · 첫 주문율 → · 2회차 주문율 ↓ : <b>경험</b> 문제 (첫 세탁 만족도 / 가격 / 리드타임)
     · 둘 다 ↓                      : 구조적 문제. 유입 구성 변화를 먼저 확인
     · 첫 주문율 ↑ · 2회차 주문율 ↓ : 한계 고객이 더 들어온 것. 순증은 생각보다 작습니다
   -------------------------------------------------------------------------- */
