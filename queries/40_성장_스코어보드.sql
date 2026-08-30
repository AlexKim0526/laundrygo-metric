---------------------------------------------------------------
set p_start   = '2025-01-01';     -- 리뷰 시작
set p_end     = '2026-07-31';     -- 리뷰 종료
set grain     = 'month';          -- 'month' 또는 'week'  ← 이 한 줄만 바꾸면 주간
set p_asof    = current_date();   -- 코호트를 어디까지 관측했는가 (보통 오늘)
set cw_first  = 7;                -- 첫 주문 관측 창(일) — 30번과 같게 유지
set cw_cohort = 28;               -- 1~3회차 코호트 관측 창(일)
set ret_lag   = 35;               -- 구독 다음 회차를 기다리는 일수 (리텐션 관측 가드)
set re_early  = 28;               -- 자유 재주문 <b>조기</b> 창(일) — 빨리 나오지만 최종의 절반만 잡음
set re_main   = 90;               -- 자유 재주문 <b>본</b> 창(일)   — 최종(180일)의 83% 를 잡음
---------------------------------------------------------------
/* ============================================================================
   40. 성장 스코어보드  —  신규 획득 · 구독 유입 · 리텐션 · 단가
   ----------------------------------------------------------------------------
   30번(NSM 리뷰)에서 성장 쪽만 떼어내고, 요청하신 항목을 더한 별도 보드입니다.
   출력은 30번과 <b>같은 세로형</b>이라 전용 HTML(성장_스코어보드.html)에 그대로 올립니다.

   [ 그룹 ]
     ① 신규      신규 가입자
     ② 첫 주문   가입 → 7일 내 <b>첫 주문자 수와 첫 주문율</b> (요금제 구분 없음)
     ③ 코호트    가입 → 28일 내 1·2·3회차 도달률, 회차 간 간격
     ④ 구독 유입 구독 가입자와 그 <b>유입 경로 3분류</b> + 플러스 약정별
     ⑤ 리텐션    구독 결제 회차 1→2 · 2→3 · 1→3 (전체 / 월구독 / 플러스)
     ⑥ 금액      결제금액
     ⑦ 단가      수거당 단가 (전체 / 자유 / 구독)
     ⑧ 자유 재주문  <b>첫 주문일 앵커</b> — 재주문율 · 3회차 · 구독 전환
     ⑨ 진단      화면에서는 숨김. 해석과 경고에만 사용

   [ 확정한 정의 — 이번에 정한 것 ]
     · 코호트 창 = <b>28일</b>. 4주라 주간 리뷰와 자리가 맞습니다.
     · 구독 유입 3분류 (서로 배타적이고 합이 100%)
         바로 구독   : 이번이 <b>첫 구독</b>이고, 그 전에 <b>수거신청도 없던</b> 사람
         써보고 구독 : 이번이 첫 구독이지만 <b>이미 수거신청 이력이 있던</b> 사람
         재가입      : <b>구독이 두 번째 이상</b>인 사람 (해지 후 복귀)
     · 리텐션 회차 = <b>구독 결제 회차</b> (subscription_order.sequence)
     · 구독 = laundry_plan_type = 0 (월구독 + 플러스). 자유는 구독으로 세지 않습니다.

   [ ⑧ 자유 재주문은 왜 앵커가 다른가 — 41번 실측 결과 ]
     ③ 코호트는 <b>가입일</b> 기준이라 첫 주문이 늦은 사람일수록 2회차를 낼 시간이
     줄어듭니다. 재주문 능력이 아니라 첫 주문 속도를 재게 되므로,
     자유 재주문은 <b>첫 주문일</b>에서 시계를 다시 겁니다.

     창은 41번 실측(완결 코호트 14개)에서 정했습니다.
       창      최종(180일) 대비    평균 재주문율
       ─────────────────────────────────────
        28일        50.6%            24.18%     ← 조기 신호로만
        56일        70.2%            33.53%
        <b>90일        83.3%            39.83%</b>     ← 본 지표
       180일       100.0%            47.80%
     첫 재주문 간격은 P50 27.9일 · P75 67.4일 · P90 117.6일 입니다.
     28일은 정확히 <b>중앙값 지점</b>이라 재주문하는 사람의 절반을 놓칩니다.
     그래서 28일은 남기되 "조기" 라고 이름 붙이고, 판단은 90일로 합니다.

   [ 자동으로 비는 칸 — 버그가 아닙니다 ]
     · ② 첫 주문  : 가입 후 7일이 p_asof 기준 안 찬 기간
     · ③ 코호트   : 가입 후 28일이 안 찬 기간
     · ⑤ 리텐션   : 2회차는 ret_lag(35일), 3회차는 70일이 안 지난 기간
     · ⑧ 자유     : 28일 조기는 28일, 나머지는 90일이 안 지난 기간
     비운 칸은 판정도 하지 않습니다.

   [ ★ ⑧ 자유 재주문을 <b>주간</b>으로 보는 법 — grain = 'week' ]

     자주 나오는 오해부터 정리합니다. <b>"90일 창이니 3개월에 한 번밖에 못 본다"
     는 틀렸습니다.</b> 창의 길이는 <b>지연</b>을 만들 뿐 <b>빈도</b>를 만들지 않습니다.
     주간 코호트로 돌리면 <b>매주 한 개의 새 코호트가 90일을 채워 확정</b>되므로,
     시계열에는 매주 새 점이 하나씩 찍힙니다. 추정도 보정도 필요 없습니다.

       이번 주 리뷰에서 새로 확정되는 것 = <b>13주 전 주에 첫 주문한 코호트</b>
       화면 오른쪽 끝 <b>13주</b>는 항상 비어 있습니다 (관측 중)

     그래서 ⑧은 "지금 무슨 일이 일어나는가" 가 아니라 <b>"한 분기 전에 들어온
     고객이 어떻게 됐는가"</b> 를 매주 갱신해 보는 지표입니다. 캠페인을 이번 주에
     틀었다면 그 답은 13주 뒤에 나옵니다. 그 사이를 메우려면 <b>28일 조기</b>를
     보되, 조기값은 최종의 50.6% 만 잡는다는 것을 잊지 마세요.

     [ 주간은 표본이 얇습니다 — 반드시 같이 볼 것 ]
       자유 첫 주문 고객이 주당 1,000~3,000명이라, 90일 재주문율(≈40%)의
       95% 오차범위가 <b>±2~3%p</b> 입니다 (n=1,000 → ±3.0%p / n=3,000 → ±1.8%p).
       실측한 전년 대비 하락폭이 4~7%p 였으니 <b>전년 동주 비교는 유효</b>하지만,
       <b>전주 대비는 대부분 노이즈</b>입니다.
       → 주간에서는 이 두 개를 먼저 보세요.
           ⑧ 재주문율 · 90일 · <b>4기간 평균(%)</b>   ← 주간 추세는 이걸로 읽습니다
           ⑨ 자유 90일 재주문율 <b>오차범위(±%p)</b>  ← 이 폭 안의 움직임은 무시
       4기간 평균은 앞 3기간이 모두 확정일 때만 값을 냅니다 (섞어 평균 내지 않음).

     [ 월간으로 볼 때 ]
       grain = 'month' 면 마지막 <b>3~4개월</b>이 비고, 매달 한 개씩 확정됩니다.
       계절옷 영향이 커서 <b>전월 대비가 아니라 전년 동월 대비</b>로 읽어야 합니다.
   ========================================================================== */
with
prm as (
    select to_date($p_start) as ps, to_date($p_end) as pe, lower($grain) as g,
           to_date($p_asof) as asof, $cw_first as cw1, $cw_cohort as cw2, $ret_lag as rlag,
           $re_early as re1, $re_main as re2
),
win as (
    select ps, pe, g, asof, cw1, cw2, rlag, re1, re2,
           case when g = 'week' then dateadd(day, -371, ps) else add_months(ps, -12) end as ws
    from prm
),

/* ── 요금제 세그먼트 (30번과 동일) ───────────────────────────────── */
plus_span as (
    select so.subscription_id, so.sequence as start_seq,
           max(try_to_number(regexp_substr(mmr.laundry_plan_name, '([0-9]+)개월', 1, 1, 'e', 1))) as term_months
    from marketing_monthly_retention        mmr
        join marketing_monthly_retention_policy mmrp on mmr.marketing_monthly_retention_policy_id = mmrp.id
        join subscription_order                 so   on mmr.subscription_order_id = so.id
    where mmrp.id in (5, 6, 7, 8, 9) and mmr.user_id not in (700340786, 700865223)
    group by 1, 2
),
order_plus as (
    select so.id as subscription_order_id, max(ps.term_months) as plus_term
    from subscription_order so
        join plus_span ps on ps.subscription_id = so.subscription_id
                         and so.sequence between ps.start_seq and ps.start_seq + ps.term_months - 1
    group by 1
),
order_seg as (
    select so.id as subscription_order_id,
           (case when s.laundry_plan_type = 1 then '자유'
                 when s.laundry_plan_type = 0 and op.plus_term is null then '월구독'
                 when s.laundry_plan_type = 0 then '플러스'
                 else '미분류' end)                                as seg,
           op.plus_term
    from subscription_order so
        join      subscription s  on so.subscription_id = s.id
        left join order_plus   op on op.subscription_order_id = so.id
),

/* ── 수거신청 : 본문용(p_end) · 코호트용(p_asof) ─────────────────── */
wb as (        -- 기간 지표용 — p_end 로 묶인다
    select
        w.id                                                       as wash_id,
        w.user_id                                                  as user_id,
        (case when win.g = 'week' then date_trunc('week',  date(convert_timezone('Asia/Seoul', w.created_at)))
              else                     date_trunc('month', date(convert_timezone('Asia/Seoul', w.created_at))) end) as p,
        ifnull(os.seg, '미분류')                                    as seg
    from wash w
        cross join win
        left join order_seg os on os.subscription_order_id = w.subscription_order_id
    where w.status not in (4, 17)
      and w.laundry24_pgi is null
      and date(convert_timezone('Asia/Seoul', w.created_at)) between win.ws and win.pe
),
wcv as (       -- 코호트 추적용 — p_asof 까지 열어둔다
    select
        w.user_id                                                  as user_id,
        w.id                                                       as wash_id,
        date(convert_timezone('Asia/Seoul', w.created_at))          as d,
        ifnull(os.seg, '미분류')                                    as seg
    from wash w
        cross join win
        left join order_seg os on os.subscription_order_id = w.subscription_order_id
    where w.status not in (4, 17)
      and w.laundry24_pgi is null
      and date(convert_timezone('Asia/Seoul', w.created_at)) between win.ws and win.asof
),

/* ── ① 가입자 (전수 · LAUNDRY24 만 제외 — 30번과 동일 기준) ──────── */
jn as (
    select
        (case when win.g = 'week' then date_trunc('week',  date(convert_timezone('Asia/Seoul', u.created_at)))
              else                     date_trunc('month', date(convert_timezone('Asia/Seoul', u.created_at))) end) as p,
        u.id                                                       as user_id,
        date(convert_timezone('Asia/Seoul', u.created_at))          as join_d,
        (case when dateadd(day, win.cw1,
                   case when win.g = 'week' then dateadd(day, 6, date_trunc('week',  date(convert_timezone('Asia/Seoul', u.created_at))))
                        else                      last_day(       date_trunc('month', date(convert_timezone('Asia/Seoul', u.created_at)))) end
                 ) <= win.asof then 1 else 0 end)                   as obs1,
        (case when dateadd(day, win.cw2,
                   case when win.g = 'week' then dateadd(day, 6, date_trunc('week',  date(convert_timezone('Asia/Seoul', u.created_at))))
                        else                      last_day(       date_trunc('month', date(convert_timezone('Asia/Seoul', u.created_at)))) end
                 ) <= win.asof then 1 else 0 end)                   as obs2
    from "USER" u
        cross join win
    where ifnull(u.account_type, '') <> 'LAUNDRY24'
      and date(convert_timezone('Asia/Seoul', u.created_at)) between win.ws and win.pe
),
/* 가입자별 : 첫 주문(7일) · 1~3회차(28일) */
jn_u as (
    select
        j.p, j.user_id, max(j.obs1) as obs1, max(j.obs2) as obs2,
        /* 7일 창 — 첫 주문 여부와 그 요금제 */
        max(iff(w.d between j.join_d and dateadd(day, win.cw1, j.join_d), 1, 0))                       as u7,
        max(iff(w.d between j.join_d and dateadd(day, win.cw1, j.join_d)
                and w.seg = '자유', 1, 0))                                                             as u7_free,
        max(iff(w.d between j.join_d and dateadd(day, win.cw1, j.join_d)
                and w.seg in ('월구독', '플러스'), 1, 0))                                              as u7_sub,
        /* 28일 창 — 몇 회차까지 갔나 */
        count(distinct iff(w.d between j.join_d and dateadd(day, win.cw2, j.join_d), w.wash_id, null)) as n28,
        /* 회차별 날짜 — 간격 진단용 */
        min(iff(w.d between j.join_d and dateadd(day, win.cw2, j.join_d), w.d, null))                  as d1
    from jn j
        cross join win
        left join wcv w on w.user_id = j.user_id
    group by 1, 2
),
/* 2·3회차 도달일 — 간격 중앙값 진단용 */
ord_rk as (
    select j.user_id, w.d,
           row_number() over (partition by j.user_id order by w.d, w.wash_id) as rn,
           j.join_d
    from jn j
        cross join win
        join wcv w on w.user_id = j.user_id
                  and w.d between j.join_d and dateadd(day, win.cw2, j.join_d)
),
gap as (
    select user_id,
           max(iff(rn = 1, datediff('day', join_d, d), null)) as g1,
           max(iff(rn = 2, datediff('day', join_d, d), null)) as g2,
           max(iff(rn = 3, datediff('day', join_d, d), null)) as g3
    from ord_rk group by 1
),

/* ── ④ 구독 유입 ─────────────────────────────────────────────────
      구독(plan_type=0) 하나하나를 "구독 가입 건" 으로 보고,
      그 시작 회차(min sequence)의 생성일이 속한 기간에 집계합니다. */
sub_start as (
    select
        s.id                                                       as sub_id,
        s.user_id                                                  as user_id,
        min(so.sequence)                                           as first_seq,
        min(date(convert_timezone('Asia/Seoul', so.created_at)))    as start_d
    from subscription s
        join subscription_order so on so.subscription_id = s.id
    where s.laundry_plan_type = 0
    group by 1, 2
),
sub_seq as (
    select ss.sub_id, ss.user_id, ss.start_d,
           row_number() over (partition by ss.user_id order by ss.start_d, ss.sub_id) as sub_no
    from sub_start ss
),
sub_plus as (      -- 그 구독의 플러스 약정 개월 (없으면 월구독)
    select so.subscription_id as sub_id, max(op.plus_term) as plus_term
    from subscription_order so
        join order_plus op on op.subscription_order_id = so.id
    group by 1
),
/* 전 기간 수거신청 — "역대 첫 주문" 판정은 기간 창에 묶이면 안 된다 */
w_all as (
    select
        w.user_id                                                  as user_id,
        w.id                                                       as wash_id,
        date(convert_timezone('Asia/Seoul', w.created_at))          as d,
        ifnull(os.seg, '미분류')                                    as seg
    from wash w
        cross join win
        left join order_seg os on os.subscription_order_id = w.subscription_order_id
    where w.status not in (4, 17)
      and w.laundry24_pgi is null
      and date(convert_timezone('Asia/Seoul', w.created_at)) <= win.asof
),
uw_first as (      -- 유저별 역대 첫 수거신청일
    select user_id, min(d) as first_w from w_all group by 1
),
fseg as (          -- 그 첫 주문의 요금제 (같은 날 여러 건이면 wash_id 가 작은 쪽)
    select f.user_id, f.first_w as d1, min_by(a.seg, a.wash_id) as seg1
    from uw_first f
        join w_all a on a.user_id = f.user_id and a.d = f.first_w
    group by 1, 2
),
sub_prior as (     -- 구독 시작 <b>전에</b> 수거신청 이력이 있었는가
    select q.sub_id,
           iff(f.first_w is not null and f.first_w < q.start_d, 1, 0) as had_wash
    from sub_seq q
        left join uw_first f on f.user_id = q.user_id
),
sub_base as (
    select
        (case when win.g = 'week' then date_trunc('week',  q.start_d)
              else                     date_trunc('month', q.start_d) end) as p,
        q.sub_id,
        q.sub_no,
        ifnull(pr.had_wash, 0)                                     as had_wash,
        pl.plus_term
    from sub_seq q
        cross join win
        left join sub_prior pr on pr.sub_id = q.sub_id
        left join sub_plus  pl on pl.sub_id = q.sub_id
    where q.start_d between win.ws and win.pe
),

/* ── ⑤ 리텐션 : 구독 결제 회차 도달 ─────────────────────────────── */
sub_reach as (
    select
        b.p, b.sub_id, b.plus_term,
        count(distinct so.sequence)                                as n_seq
    from sub_base b
        join subscription_order so on so.subscription_id = b.sub_id
        cross join win
    where date(convert_timezone('Asia/Seoul', so.created_at)) <= win.asof
    group by 1, 2, 3
),
ret as (
    select
        r.p, r.plus_term, r.n_seq,
        (case when dateadd(day, win.rlag,
                   case when win.g = 'week' then dateadd(day, 6, r.p) else last_day(r.p) end
                 ) <= win.asof then 1 else 0 end)                  as obs_r2,
        (case when dateadd(day, win.rlag * 2,
                   case when win.g = 'week' then dateadd(day, 6, r.p) else last_day(r.p) end
                 ) <= win.asof then 1 else 0 end)                  as obs_r3
    from sub_reach r
        cross join win
),

/* ── ⑧ 자유 재주문 : 첫 주문일에서 시계를 다시 건다 ──────────────
      ③ 코호트는 <b>가입일</b> 앵커라, 첫 주문이 늦은 사람일수록 2회차를 낼
      시간이 줄어 재주문 능력이 아니라 첫 주문 속도를 재게 됩니다.
      자유 재주문은 반드시 <b>첫 주문일</b>에서 다시 재야 합니다. */
fcoh as (
    select (case when win.g = 'week' then date_trunc('week',  fs.d1)
                 else                     date_trunc('month', fs.d1) end) as p,
           fs.user_id, fs.d1
    from fseg fs
        cross join win
    where fs.seg1 = '자유'
      and fs.d1 between win.ws and win.pe
),
fseq as (
    select c.p, c.user_id, c.d1, a.d, a.seg,
           row_number() over (partition by c.user_id order by a.d, a.wash_id) as rn
    from fcoh c
        join w_all a on a.user_id = c.user_id and a.d >= c.d1
),
fu as (
    select p, user_id, d1,
           max(iff(rn = 2, datediff('day', d1, d), null)) as g2,
           max(iff(rn = 3, datediff('day', d1, d), null)) as g3,
           max(iff(rn = 2, seg, null))                    as seg2
    from fseq group by 1, 2, 3
),
fagg as (
    select
        fu.p                                                       as p,
        count(*)                                                   as n,
        count_if(fu.g2 <= win.re1)                                 as r2a,
        count_if(fu.g2 <= win.re2)                                 as r2b,
        count_if(fu.g3 <= win.re2)                                 as r3b,
        count_if(fu.g2 <= win.re2 and fu.seg2 in ('월구독', '플러스')) as r2sub,
        percentile_cont(0.50) within group (order by iff(fu.g2 <= win.re2, fu.g2, null)) as gq50,
        percentile_cont(0.75) within group (order by iff(fu.g2 <= win.re2, fu.g2, null)) as gq75,
        max(iff(dateadd(day, win.re1,
                case when win.g = 'week' then dateadd(day, 6, fu.p) else last_day(fu.p) end)
                <= win.asof, 1, 0))                                as obs_a,
        max(iff(dateadd(day, win.re2,
                case when win.g = 'week' then dateadd(day, 6, fu.p) else last_day(fu.p) end)
                <= win.asof, 1, 0))                                as obs_b
    from fu
        cross join win
    group by 1
),
/* ── ⑧ 주간용 : 4기간 이동평균 ────────────────────────────────────
      주간 코호트는 표본이 얇아 전주 대비가 대부분 노이즈입니다.
      추세는 이 값으로 읽습니다. <b>앞 3기간이 모두 확정일 때만</b> 값을 냅니다 —
      관측이 덜 찬 기간을 섞어 평균 내면 값이 조용히 낮아집니다. */
fma as (
    select p,
           iff(obs_b = 1, r2b / nullif(n, 0) * 100, null)              as v90
    from fagg
),
fma4 as (
    select p,
           iff(count(v90) over (order by p rows between 3 preceding and current row) = 4,
               avg(v90)   over (order by p rows between 3 preceding and current row),
               null)                                                   as v90_ma4
    from fma
),

/* ── ⑥⑦ 결제 · 단가 ─────────────────────────────────────────────── */
pay_base as (
    select
        sp.id                                                      as payment_id,
        (case
             when sp.payment_type =  0 and sp.order_name in (
                '할인 혜택 반환금', '미배출로 인한 회수불가 방문비용', '보관서비스 기간연장 결제'
                ) then sp.old_subscription_order_id
             when sp.payment_type =  0 and sp.wash_id is null      then sp.new_subscription_order_id
             when sp.payment_type =  0 and sp.wash_id is not null  then sp.old_subscription_order_id
             when sp.payment_type != 0 and sp2.order_name in (
                '할인 혜택 반환금', '미배출로 인한 회수불가 방문비용', '보관서비스 기간연장 결제'
                ) then sp2.old_subscription_order_id
             when sp.payment_type != 0 and sp2.wash_id is null     then sp2.new_subscription_order_id
             when sp.payment_type != 0 and sp2.wash_id is not null then sp2.old_subscription_order_id
             else null end)                                        as soid,
        (case when win.g = 'week'
              then date_trunc('week',  date(convert_timezone('Asia/Seoul', ifnull(sp.approved_at, sp.created_at))))
              else date_trunc('month', date(convert_timezone('Asia/Seoul', ifnull(sp.approved_at, sp.created_at)))) end) as p,
        case sp.payment_type when 0 then sp.paid_price else 0 end  as paid,
        case sp.payment_type when 0 then 0 else sp.paid_price end  as cancel
    from subscription_payment sp
        cross join win
        left join subscription_payment sp2 on sp.parent_payment_id = sp2.id
    where sp.succeeded = 1
      and date(convert_timezone('Asia/Seoul', ifnull(sp.approved_at, sp.created_at))) between win.ws and win.pe
),
point_agg as (
    select
        lpl.subscription_payment_id                                as payment_id,
        sum(case when lp.provision_type_id in (10001, 20032, 30000) and lpl.log_type = 'U' then lpl.amount else 0 end) as cp_paid,
        sum(case when lp.provision_type_id in (10001, 20032, 30000) and lpl.log_type = 'P' then lpl.amount else 0 end) as cp_cancel,
        sum(case when lp.provision_type_id not in (10001, 20032, 30000) and pt.type in ('SALES', 'SALES_CASH_RECEIPT')
                 then case lpl.log_type when 'U' then lpl.amount when 'P' then -lpl.amount else 0 end else 0 end)     as sales_point
    from laundrygo_point_log lpl
        join      laundrygo_point lp on lpl.laundrygo_point_id = lp.id
        left join provision_type   pt on lp.provision_type_id  = pt.id
    where lpl.subscription_payment_id in (select payment_id from pay_base)
    group by 1
),
pay as (
    select
        b.p,
        ifnull(os.seg, '미분류')                                    as seg,
        (b.paid + ifnull(g.cp_paid, 0) + ifnull(g.sales_point, 0))
            - (b.cancel + ifnull(g.cp_cancel, 0))                  as amt
    from pay_base b
        left join point_agg g  on g.payment_id = b.payment_id
        left join order_seg os on os.subscription_order_id = b.soid
),
pay_agg as (
    select p,
           sum(amt)                                                as amt_all,
           sum(iff(seg = '자유', amt, 0))                           as amt_free,
           sum(iff(seg in ('월구독', '플러스'), amt, 0))            as amt_sub
    from pay group by 1
),
wash_agg as (
    select p,
           count(distinct wash_id)                                 as w_all,
           count(distinct iff(seg = '자유', wash_id, null))         as w_free,
           count(distinct iff(seg in ('월구독', '플러스'), wash_id, null)) as w_sub
    from wb group by 1
),

/* ── 지표 ────────────────────────────────────────────────────────── */
m as (
    /* ① 신규 */
    select p, '① 신규' as grp, '신규 가입자(명)' as metric, count(*) as v from jn_u group by 1

    /* ② 첫 주문 (7일) — 요금제 구분 없이 <b>주문자 수와 주문율</b> 두 개만 노출.
       자유/구독 분해는 ⑨ 진단으로 내렸습니다. 한 사람이 7일 안에 두 요금제를
       모두 쓰면 양쪽에 잡혀 합이 전체보다 커지므로, 화면에 나란히 두면
       "합이 안 맞는다" 는 오해가 생깁니다. */
    union all select p, '② 첫 주문', '첫 주문자 수(명)',
           iff(max(obs1) = 1, sum(u7), null)                       from jn_u group by 1
    union all select p, '② 첫 주문', '첫 주문율(%)',
           iff(max(obs1) = 1, avg(u7) * 100, null)                 from jn_u group by 1

    /* ③ 코호트 (28일) */
    union all select p, '③ 코호트', '28일 내 1회차 도달(%)',
           iff(max(obs2) = 1, avg(iff(n28 >= 1, 1, 0)) * 100, null) from jn_u group by 1
    union all select p, '③ 코호트', '28일 내 2회차 도달(%)',
           iff(max(obs2) = 1, avg(iff(n28 >= 2, 1, 0)) * 100, null) from jn_u group by 1
    union all select p, '③ 코호트', '28일 내 3회차 도달(%)',
           iff(max(obs2) = 1, avg(iff(n28 >= 3, 1, 0)) * 100, null) from jn_u group by 1
    union all select p, '③ 코호트', '1회차 → 2회차 잔존(%)',
           iff(max(obs2) = 1,
               sum(iff(n28 >= 2, 1, 0)) / nullif(sum(iff(n28 >= 1, 1, 0)), 0) * 100, null)
                                                                   from jn_u group by 1
    union all select p, '③ 코호트', '2회차 → 3회차 잔존(%)',
           iff(max(obs2) = 1,
               sum(iff(n28 >= 3, 1, 0)) / nullif(sum(iff(n28 >= 2, 1, 0)), 0) * 100, null)
                                                                   from jn_u group by 1

    /* ④ 구독 유입 */
    union all select p, '④ 구독 유입', '구독 가입(건)', count(*) from sub_base group by 1
    union all select p, '④ 구독 유입', '바로 구독(%)',
           avg(iff(sub_no = 1 and had_wash = 0, 1, 0)) * 100       from sub_base group by 1
    union all select p, '④ 구독 유입', '써보고 구독(%)',
           avg(iff(sub_no = 1 and had_wash = 1, 1, 0)) * 100       from sub_base group by 1
    union all select p, '④ 구독 유입', '재가입(%)',
           avg(iff(sub_no > 1, 1, 0)) * 100                        from sub_base group by 1
    union all select p, '④ 구독 유입', '플러스 · 전체(%)',
           avg(iff(plus_term is not null, 1, 0)) * 100             from sub_base group by 1
    union all select p, '④ 구독 유입', '플러스 · 3개월(%)',
           avg(iff(plus_term = 3, 1, 0)) * 100                     from sub_base group by 1
    union all select p, '④ 구독 유입', '플러스 · 6개월(%)',
           avg(iff(plus_term = 6, 1, 0)) * 100                     from sub_base group by 1
    union all select p, '④ 구독 유입', '플러스 · 12개월(%)',
           avg(iff(plus_term = 12, 1, 0)) * 100                    from sub_base group by 1

    /* ⑤ 리텐션 — 구독 결제 회차 */
    union all select p, '⑤ 리텐션', '결제 1→2회차(%)',
           iff(max(obs_r2) = 1, avg(iff(n_seq >= 2, 1, 0)) * 100, null)   from ret group by 1
    union all select p, '⑤ 리텐션', '결제 2→3회차(%)',
           iff(max(obs_r3) = 1,
               sum(iff(n_seq >= 3, 1, 0)) / nullif(sum(iff(n_seq >= 2, 1, 0)), 0) * 100, null)
                                                                          from ret group by 1
    union all select p, '⑤ 리텐션', '결제 1→3회차(%)',
           iff(max(obs_r3) = 1, avg(iff(n_seq >= 3, 1, 0)) * 100, null)   from ret group by 1
    union all select p, '⑤ 리텐션', '결제 1→2회차 · 월구독(%)',
           iff(max(obs_r2) = 1,
               sum(iff(plus_term is null and n_seq >= 2, 1, 0))
               / nullif(sum(iff(plus_term is null, 1, 0)), 0) * 100, null) from ret group by 1
    union all select p, '⑤ 리텐션', '결제 1→2회차 · 플러스(%)',
           iff(max(obs_r2) = 1,
               sum(iff(plus_term is not null and n_seq >= 2, 1, 0))
               / nullif(sum(iff(plus_term is not null, 1, 0)), 0) * 100, null) from ret group by 1
    union all select p, '⑤ 리텐션', '결제 1→3회차 · 월구독(%)',
           iff(max(obs_r3) = 1,
               sum(iff(plus_term is null and n_seq >= 3, 1, 0))
               / nullif(sum(iff(plus_term is null, 1, 0)), 0) * 100, null) from ret group by 1
    union all select p, '⑤ 리텐션', '결제 1→3회차 · 플러스(%)',
           iff(max(obs_r3) = 1,
               sum(iff(plus_term is not null and n_seq >= 3, 1, 0))
               / nullif(sum(iff(plus_term is not null, 1, 0)), 0) * 100, null) from ret group by 1

    /* ⑥ 금액 */
    union all select p, '⑥ 금액', '결제금액(원)',        amt_all  from pay_agg
    union all select p, '⑥ 금액', '결제금액 · 자유(원)',  amt_free from pay_agg
    union all select p, '⑥ 금액', '결제금액 · 구독(원)',  amt_sub  from pay_agg

    /* ⑦ 단가 */
    union all select a.p, '⑦ 단가', '수거당 단가 · 전체(원)',
           a.amt_all  / nullif(w.w_all, 0)   from pay_agg a join wash_agg w on w.p = a.p
    union all select a.p, '⑦ 단가', '수거당 단가 · 자유(원)',
           a.amt_free / nullif(w.w_free, 0)  from pay_agg a join wash_agg w on w.p = a.p
    union all select a.p, '⑦ 단가', '수거당 단가 · 구독(원)',
           a.amt_sub  / nullif(w.w_sub, 0)   from pay_agg a join wash_agg w on w.p = a.p

    /* ⑧ 자유 재주문 — 첫 주문일 앵커 */
    union all select p, '⑧ 자유 재주문', '자유 첫 주문 고객(명)', n from fagg
    union all select p, '⑧ 자유 재주문', '재주문율 · 28일 조기(%)',
           iff(obs_a = 1, r2a / nullif(n, 0) * 100, null)          from fagg
    union all select p, '⑧ 자유 재주문', '재주문율 · 90일(%)',
           iff(obs_b = 1, r2b / nullif(n, 0) * 100, null)          from fagg
    union all select p, '⑧ 자유 재주문', '3회차 도달률 · 90일(%)',
           iff(obs_b = 1, r3b / nullif(n, 0) * 100, null)          from fagg
    union all select p, '⑧ 자유 재주문', '2회차 구독 전환(%)',
           iff(obs_b = 1, r2sub / nullif(n, 0) * 100, null)        from fagg
    /* 주간 추세 판독용 — 전주 대비 노이즈를 눌러 놓은 값 */
    union all select p, '⑧ 자유 재주문', '재주문율 · 90일 · 4기간 평균(%)',
           v90_ma4                                                 from fma4

    /* ⑨ 진단 */
    union all select p, '⑨ 진단', '첫 주문율 · 자유(%)',
           iff(max(obs1) = 1, avg(u7_free) * 100, null)            from jn_u group by 1
    union all select p, '⑨ 진단', '첫 주문율 · 구독(%)',
           iff(max(obs1) = 1, avg(u7_sub) * 100, null)             from jn_u group by 1
    union all select p, '⑨ 진단', '수거신청 수(건)',       w_all  from wash_agg
    union all select p, '⑨ 진단', '수거신청 · 자유(건)',   w_free from wash_agg
    union all select p, '⑨ 진단', '수거신청 · 구독(건)',   w_sub  from wash_agg
    union all select p, '⑨ 진단', '구독 시작 건수(건)',    count(*) from sub_base group by 1
    union all select p, '⑨ 진단', '1회차 도달 소요 중앙값(일)',
           percentile_cont(0.5) within group (order by g1) from gap
        join jn on jn.user_id = gap.user_id group by 1
    union all select p, '⑨ 진단', '1→2회차 간격 중앙값(일)',
           percentile_cont(0.5) within group (order by g2 - g1) from gap
        join jn on jn.user_id = gap.user_id group by 1
    union all select p, '⑨ 진단', '자유 첫 재주문 간격 P50(일)',
           iff(obs_b = 1, gq50, null)                              from fagg
    union all select p, '⑨ 진단', '자유 첫 재주문 간격 P75(일)',
           iff(obs_b = 1, gq75, null)                              from fagg
    union all select p, '⑨ 진단', '자유 재주문 중 구독 비중(%)',
           iff(obs_b = 1, r2sub / nullif(r2b, 0) * 100, null)      from fagg
    /* 이 폭 안의 움직임은 해석하지 마세요 — 이항분포 95% 오차범위 */
    union all select p, '⑨ 진단', '자유 90일 재주문율 오차범위(±%p)',
           iff(obs_b = 1,
               1.96 * sqrt( (r2b / nullif(n, 0)) * (1 - r2b / nullif(n, 0))
                            / nullif(n, 0) ) * 100, null)          from fagg
    union all select p, '⑨ 진단', '2→3회차 간격 중앙값(일)',
           percentile_cont(0.5) within group (order by g3 - g2) from gap
        join jn on jn.user_id = gap.user_id group by 1
),
joined as (
    select c.p, c.grp, c.metric, c.v, pr.v as v_prev
    from m c
        cross join win
        left join m pr
          on pr.metric = c.metric
         and pr.p = (case when win.g = 'week' then dateadd(day, -364, c.p) else add_months(c.p, -12) end)
    where c.p >= (case when win.g = 'week' then date_trunc('week', win.ps) else date_trunc('month', win.ps) end)
      and c.p <= win.pe
)
select
    to_char(p, 'YYYY-MM-DD')                                       as "기간",
    grp                                                            as "구분",
    metric                                                         as "지표",
    round(v, 2)                                                    as "값",
    round(v_prev, 2)                                               as "전년 동기",
    case when v_prev is null or v_prev = 0 then null
         else round((v - v_prev) / abs(v_prev) * 100, 1) end       as "YoY(%)",
    case when grp in ('② 첫 주문', '③ 코호트', '⑤ 리텐션', '⑧ 자유 재주문')
              and endswith(metric, '(%)') and metric <> '2회차 구독 전환(%)'
              then '전년比 하락 금지'
         when grp = '⑦ 단가' then '전년比 하락 금지'
         else null end                                             as "기준선",
    case when v is null then null
         when v_prev is null or v_prev = 0 then null
         when grp in ('② 첫 주문', '③ 코호트', '⑤ 리텐션', '⑧ 자유 재주문')
              and endswith(metric, '(%)') and metric <> '2회차 구독 전환(%)'
              then iff(v >= v_prev, '양호', '이탈')
         when grp = '⑦ 단가'
              then iff(v >= v_prev, '양호', '이탈')
         else null end                                             as "판정"
from joined
order by "기간", grp, metric

/* ----------------------------------------------------------------------------
   [ 읽는 순서 ]
     1) ① 신규 가입자와 ② 첫 주문율을 함께 봅니다.
        가입자가 늘었는데 첫 주문율이 떨어졌다면 <b>유입의 질</b>이 바뀐 것입니다.
     2) ③ 코호트의 "1→2회차 잔존" 이 진짜 관문입니다.
        1회차는 프로모션으로 만들 수 있지만 2회차는 서비스가 만듭니다.
     3) ④ 구독 유입 3분류는 <b>합이 100%</b> 입니다.
        "써보고 구독" 비중이 오르면 자유 → 구독 파이프가 살아나는 것이고,
        "바로 구독" 만 오르면 프로모션 의존일 수 있습니다.
     4) ⑤ 리텐션은 결제 회차 기준이라 <b>낙전(⑨ 30번)</b>과 함께 보세요.
        결제는 유지되는데 안 쓰는 상태가 가장 위험합니다.
     5) ⑦ 단가는 자유·구독을 나눠 보세요. 전체 단가는 두 세그먼트의
        <b>구성비 변화만으로도</b> 움직입니다.

   [ 정의 메모 ]
     · ② 첫 주문은 <b>7일</b>, ③ 코호트는 <b>28일</b> 창입니다. 서로 다른 질문입니다.
       (7일 = 온보딩 마찰 / 28일 = 습관 형성)
     · ④ 구독 유입의 기준일은 그 구독의 <b>첫 결제 회차 생성일</b>입니다.
     · ⑦ 구독 단가는 구독료를 그 기간 수거신청 수로 나눈 값이라,
       낙전이 늘면 <b>단가가 올라갑니다.</b> 좋아진 게 아닐 수 있습니다.
   -------------------------------------------------------------------------- */
