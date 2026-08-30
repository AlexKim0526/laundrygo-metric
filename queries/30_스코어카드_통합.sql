---------------------------------------------------------------
set p_start    = '2025-01-01';   -- 리뷰 시작 (이 날짜가 속한 주/월부터)
set p_end      = '2026-07-31';   -- 리뷰 종료
set grain      = 'month';        -- 'month' 또는 'week'  ← 이 한 줄만 바꾸면 주간 리뷰
set care_lag   = 15;             -- 안심케어 요청이 다 들어오기까지 기다릴 일수
set qc_cov_min = 20;             -- QC 진행률(%)이 이 값 미만인 (기간·공장)은 QC 지표를 비웁니다
set p_asof     = current_date(); -- ★ 전환·요청을 "어디까지 관측했는가" (보통 오늘)
                                 --   p_end 이후에 들어온 전환도 그 코호트에 붙여 셉니다.
                                 --   p_end 로 두면 예전처럼 마지막 기간이 비워집니다.
---------------------------------------------------------------
/* ============================================================================
   30. NSM 리뷰 스코어카드 (통합)  —  이것 하나만 돌리면 됩니다 · ★ 없음
   ----------------------------------------------------------------------------
   20(핵심·구성·구독·금액·품질·캐파·신규) 과 23(QC·스파팅·안심케어·공장별) 을
   <b>한 쿼리로 합친 것</b>입니다. 결과 CSV 하나를 스코어카드 HTML 에 올리면 끝입니다.

   [ 쓰는 법 ]
     · 월간 리뷰 : grain = 'month'   · 주간 리뷰 : grain = 'week'   (그 줄만 교체)
     · 전년 동기는 자동 계산됩니다 — 월은 12개월 전, 주는 364일 전(요일 정렬 유지)
     · 결과는 세로형(long) 이라 그대로 피벗해서 붙이면 리뷰 자료가 됩니다
     · p_start 를 13개월 전으로 잡으면 추이 스파크라인이 채워집니다

   [ 출력 — 기간 · 구분 · 지표 · 값 · 전년동기 · YoY · 기준선 · 판정 ]
     ① 핵심   NSM · 활성 고객 · 고객당 물량 · 수거신청
     ② 구성   구독 비중 · 세그먼트별 물량        ③ 구독   구독-개월 · 낙전
     ④ 금액   결제금액 · 실질 매출 · 무상포인트   ⑤ 품질   준수율 · P90 · 세탁불가 ·
                                                          부속품 · QC 부적합 · 못지움 · 안심케어
     ⑥ 캐파   일평균 · 일 최대                    ⑦ 신규   가입자 · 7일 첫 이용
     ⑧ 공장   ⑤ 품질 3종의 공장별 분해            ⑨ 진단   화면에서는 숨김. 해석용

   [ 시간축이 지표마다 다릅니다 — 이것만 기억하세요 ]
     · ①②③④⑥⑦ 과 ⑤의 준수율·P90·세탁불가·부속품 → <b>수거 신청월</b>
     · ⑤의 QC 부적합률 · 못지움율 · 안심케어 인입률 · ⑧ 공장 → <b>출고월(세탁 완료월)</b>
       품질 사건은 "그 옷이 나간 달" 에 붙여야 원인을 짚을 수 있기 때문입니다.

   [ 자동으로 비는 칸이 있습니다 — 버그가 아닙니다 ]
     · ⑦ 신규        : 가입 후 7일이 <b>p_asof 기준으로</b> 안 찬 기간
     · 안심케어 인입률 : 출고 후 care_lag(15일)이 <b>p_asof 기준으로</b> 안 지난 기간
     · QC · 스파팅    : QC 진행률이 qc_cov_min(20%) 미만인 (기간·공장)
       비운 칸은 <b>판정도 하지 않습니다</b> — 거짓 이탈 경보를 막기 위해서입니다.

   [ ★ p_asof — 마지막 달이 늘 비던 문제를 없앱니다 ]
     리뷰는 보통 <b>다음 달에</b> 합니다. 8월 26일에 7월 리뷰를 하면 7월 가입자의
     7일 창은 이미 8월 7일에 다 찼는데, 예전 판은 p_end(7/31)까지만 보느라
     7월을 통째로 비웠습니다. p_asof 를 오늘로 두면 <b>p_end 이후에 들어온 전환도
     그 코호트에 붙여</b> 세므로 7월이 채워집니다.
     · 본문 지표(물량·매출·품질)는 <b>여전히 p_end 로 묶여 있습니다.</b> 확장되는 것은
       "가입 후 7일" · "출고 후 15일" 처럼 <b>코호트를 뒤따라가는 관측</b>뿐입니다.
     · 예전 동작이 필요하면 p_asof 를 p_end 로 두세요.

   [ 정의 ] — 지금까지 확정한 것 그대로
     · NSM   = wash_item(accepted=1) 중 <b>세탁 부속품·세탁 불가 제외</b>
     · 매출  = (실결제 + 충전포인트 + 매출성포인트) − 취소분   ← 현업 쿼리와 동일
     · 이연  = 플러스 구독료를 약정 개월로 나눠 배분한 실질 매출
     · 수거  = status not in (4,17) · laundry24_pgi is null
     · 준수  = 세탁 완료일 ≤ 출고 기한 (배송일 아님)
     · 출고  = wash.washed_at (세탁 완료)   · 공장 = wash.lsf_factory_info_id
   ========================================================================== */
with
prm as (
    select to_date($p_start) as ps, to_date($p_end) as pe, lower($grain) as g,
           $care_lag as lag, $qc_cov_min as covmin, to_date($p_asof) as asof
),
/* 전년 동기까지 스캔해야 하므로 시작을 1년 앞으로 당긴다 */
win as (
    select ps, pe, g, lag, covmin, asof,
           case when g = 'week' then dateadd(day, -371, ps) else add_months(ps, -12) end as ws
    from prm
),
/* ── 요금제 세그먼트 ─────────────────────────────────────────────── */
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
/* ── 바코드 (NSM 정의 반영) ──────────────────────────────────────── */
wi as (
    select
        wi.wash_id,
        count(distinct case when lc.name not in ('세탁 부속품', '세탁 불가') then wi.id end) as bc,
        count(distinct case when lc.name = '세탁 부속품' then wi.id end)                     as bc_acc,
        count(distinct case when lc.name = '세탁 불가'   then wi.id end)                     as bc_bad,
        count(distinct wi.id)                                                                as bc_all
    from wash_item             wi
        left join laundry_category lc on lc.id = wi.laundry_category_id
    where wi.accepted = 1
    group by 1
),
/* ── 수거신청 기준 원장 ──────────────────────────────────────────── */
wb as (
    select
        w.id                                                       as wash_id,
        w.user_id,
        date(convert_timezone('Asia/Seoul', w.created_at))          as d,
        (case when win.g = 'week' then date_trunc('week',  date(convert_timezone('Asia/Seoul', w.created_at)))
              else                     date_trunc('month', date(convert_timezone('Asia/Seoul', w.created_at))) end) as p,
        ifnull(os.seg, '미분류')                                    as seg,
        w.subscription_order_id,
        ifnull(wi.bc, 0)                                            as bc,
        ifnull(wi.bc_acc, 0)                                        as bc_acc,
        ifnull(wi.bc_bad, 0)                                        as bc_bad,
        ifnull(wi.bc_all, 0)                                        as bc_all,
        convert_timezone('Asia/Seoul', w.washed_at)                 as t_wash,
        convert_timezone('Asia/Seoul', w.delivered_at)              as t_del,
        w.release_deadline_date                                     as t_due
    from wash w
        cross join win
        left join wi        on wi.wash_id = w.id
        left join order_seg os on os.subscription_order_id = w.subscription_order_id
    where w.status not in (4, 17)
      and w.laundry24_pgi is null
      and date(convert_timezone('Asia/Seoul', w.created_at)) between win.ws and win.pe
),
/* ── 결제 ────────────────────────────────────────────────────────── */
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
        (case when sp.payment_type = 0 then sp.wash_id else sp2.wash_id end) as wash_id,
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
                 then case lpl.log_type when 'U' then lpl.amount when 'P' then -lpl.amount else 0 end else 0 end)     as sales_point,
        sum(case when lp.provision_type_id not in (10001, 20032, 30000)
                  and (pt.type is null or pt.type not in ('SALES', 'SALES_CASH_RECEIPT'))
                 then case lpl.log_type when 'U' then lpl.amount when 'P' then -lpl.amount else 0 end else 0 end)     as free_point
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
            - (b.cancel + ifnull(g.cp_cancel, 0))                  as amt,
        case when b.wash_id is null then
             (b.paid + ifnull(g.cp_paid, 0) + ifnull(g.sales_point, 0)) - (b.cancel + ifnull(g.cp_cancel, 0))
             else 0 end                                            as plan_amt,
        os.plus_term,
        ifnull(g.free_point, 0)                                    as free_point
    from pay_base b
        left join point_agg g  on g.payment_id = b.payment_id
        left join order_seg os on os.subscription_order_id = b.soid
),
/* ── 구독-개월 (낙전) ────────────────────────────────────────────── */
sm as (
    select
        (case when win.g = 'week' then date_trunc('week',  date(convert_timezone('Asia/Seoul', so.created_at)))
              else                     date_trunc('month', date(convert_timezone('Asia/Seoul', so.created_at))) end) as p,
        so.id                                                      as soid,
        ifnull(wc.wash_cnt, 0)                                     as wash_cnt
    from subscription_order so
        cross join win
        join      subscription s on s.id = so.subscription_id and s.laundry_plan_type = 0
        left join (select subscription_order_id, count(*) as wash_cnt
                   from wash where status not in (4, 17) and laundry24_pgi is null
                   group by 1) wc on wc.subscription_order_id = so.id
    where date(convert_timezone('Asia/Seoul', so.created_at)) between win.ws and win.pe
),
/* ── 신규 가입 코호트 ────────────────────────────────────────────── */
jn as (
    select
        (case when win.g = 'week' then date_trunc('week',  date(convert_timezone('Asia/Seoul', u.created_at)))
              else                     date_trunc('month', date(convert_timezone('Asia/Seoul', u.created_at))) end) as p,
        u.id                                                       as user_id,
        date(convert_timezone('Asia/Seoul', u.created_at))          as join_d,
        /* ★ 관측 완결성 — 그 기간의 마지막 가입자까지 7일이 확보됐는가.
           확보되지 않은 기간은 지표를 NULL 로 비웁니다. 안 그러면 마지막 주/달이
           항상 "이탈"로 찍혀 거짓 경보가 됩니다.
           ※ 창을 30일이 아니라 7일로 잡은 이유 — 주간 리뷰 때문입니다.
             30일이면 최근 4~5주가 통째로 비어 주간 리뷰에서 신규 지표를 볼 수 없습니다.
             7일이면 비는 구간이 마지막 1주뿐입니다. 전환의 대부분이 첫 주에 일어나
             (30일 39.2% vs 60일 40.7%) 신호 손실도 크지 않습니다. */
        (case when dateadd(day, 7,
                   case when win.g = 'week'
                        then dateadd(day, 6, date_trunc('week',  date(convert_timezone('Asia/Seoul', u.created_at))))
                        else last_day(       date_trunc('month', date(convert_timezone('Asia/Seoul', u.created_at)))) end
                 ) <= win.asof then 1 else 0 end)                   as obs_ok,
        iff(u.deleted, 1, 0)                                          as is_gone
    from "USER" u
        cross join win
    /* ★ 모수 = 가입 전수. 탈퇴 회원도 뺐다가 <b>다시 넣었습니다.</b>
       deleted=false 로 걸면 분모가 "지금 시점의 생존자" 라, 시간이 지나 탈퇴가
       쌓이면 <b>과거 달의 값이 조용히 바뀝니다.</b> 실측으로 최대 1.45%p 였습니다.
       가입 코호트 지표는 분모가 고정돼야 하고, 현업 쿼리도 전수 기준입니다. */
    where ifnull(u.account_type, '') <> 'LAUNDRY24'      -- 무인세탁소 계정만 제외
      and date(convert_timezone('Asia/Seoul', u.created_at)) between win.ws and win.pe
),
/* 코호트 전환 조회 전용 — 본문 지표(wb)는 p_end 로 묶여 있어야 하지만,
   "가입 후 7일" 은 p_end 를 넘어 들어온 신청도 세야 코호트가 완성됩니다 */
wcv as (
    select w.user_id                                              as user_id,
           date(convert_timezone('Asia/Seoul', w.created_at))      as d
    from wash w
        cross join win
    where w.status not in (4, 17)
      and w.laundry24_pgi is null
      and date(convert_timezone('Asia/Seoul', w.created_at)) between win.ws and win.asof
),
jn_first as (
    select
        j.p,
        j.user_id,
        max(j.obs_ok)                                                                        as obs_ok,
        max(j.is_gone)                                                                       as is_gone,
        max(case when w.d between j.join_d and dateadd(day, 7, j.join_d) then 1 else 0 end) as used7,
        count(case when w.d between j.join_d and dateadd(day, 7, j.join_d) then 1 end)      as n7
    from jn j
        left join wcv w on w.user_id = j.user_id
    group by 1, 2
),
/* ── 일별 (캐파) ─────────────────────────────────────────────────── */
daily as (
    select p, d, sum(bc) as bc from wb group by 1, 2
),
/* ── ⓪ QC·스파팅을 하지 않는 공장 ───────────────────────────────────
      여기 적힌 공장은 QC 지표에서 제외되고, 커버리지 분모에서도 빠집니다.
      QC 를 시작하면 이 줄을 지우세요. 안심케어에는 영향이 없습니다. */
qc_scope as (
    select column1 as factory from values
        ('부산공장')
),

/* ── ① 출고(세탁 완료)된 수거신청 + 공장 ─────────────────────────── */
relw as (
    select
        w.id                                                            as wash_id,
        date(convert_timezone('Asia/Seoul', w.washed_at))               as rel_d,
        (case when win.g = 'week'
              then date_trunc('week',  date(convert_timezone('Asia/Seoul', w.washed_at)))
              else date_trunc('month', date(convert_timezone('Asia/Seoul', w.washed_at))) end) as p,
        ifnull(f.name, '(미지정)')                                       as factory,
        (case when ifnull(f.name, '(미지정)') in (select factory from qc_scope)
              then 0 else 1 end)                                        as qc_ok
    from wash w
        left join lsf_factory_info f on f.id = w.lsf_factory_info_id
        cross join win
    where w.status not in (4, 17)
      and w.laundry24_pgi is null
      and w.washed_at is not null
      and date(convert_timezone('Asia/Seoul', w.washed_at)) between win.ws and win.pe
),

/* ── ② 분모 : 출고 의류 수 (기간 × 공장, 전체는 rollup) ──────────── */
relx as (
    select b.p                                                       as p,
           coalesce(b.factory, '전체')                                as factory,
           count(wi.id)                                              as rel_items,
           /* QC 진행률의 분모 — QC 를 하는 공장의 출고분만 */
           sum(case when b.qc_ok = 1 then 1 else 0 end)               as rel_qc_items,
           max(b.qc_ok)                                              as fac_qc_ok
    from relw b
        join wash_item wi on wi.wash_id = b.wash_id and wi.accepted = 1
    group by b.p, rollup(b.factory)
),

/* ── ③ LSF 의류 → 출고월·공장 (확인된 유일한 다리) ──────────────── */
lsf_id as (
    select lsf_wash_item_id as item_id from qc_inspection_result
    where delete_yn = 'N' and lsf_wash_item_id is not null
    union
    select lsf_wash_item_id from wash_item_complain
    where delete_yn = 'N' and lsf_wash_item_id is not null
),
lnk as (
    select l.item_id, max(lph.wash_id) as wash_id
    from lsf_id l
        join laundry_progress_history lph on lph.lsf_wash_item_id = l.item_id
    where lph.wash_id is not null
    group by 1
),
qitem as (
    select k.item_id, b.p, b.factory, b.rel_d, b.qc_ok
    from lnk k
        join relw b on b.wash_id = k.wash_id
),

/* ── ④ 의류별 QC · 스파팅 판정 ──────────────────────────────────── */
qres as (
    select
        q.lsf_wash_item_id                                                as item_id,
        min(date(q.created_datetime))                                     as qc_d,
        max(case when q.qc_inspection_menu = 'QC_INSPECTION_NONCONFORMITY_ROUND'
                 then 1 else 0 end)                                       as qc_done,
        max(case when q.qc_inspection_menu = 'QC_INSPECTION_NONCONFORMITY_ROUND'
                  and q.result_common_code = 'PRFT082' then 1 else 0 end) as qc_bad,
        /* 스파팅 진행 = 결과가 입력된 건만. PRFT086(태그만 하고 미입력)은 제외 */
        max(case when q.qc_inspection_menu = 'QC_INSPECTION_SPOTTING_ROUND'
                  and q.result_common_code in ('PRFT083', 'PRFT084', 'PRFT089')
                 then 1 else 0 end)                                       as sp_done,
        max(case when q.qc_inspection_menu = 'QC_INSPECTION_SPOTTING_ROUND'
                  and q.result_common_code = 'PRFT084' then 1 else 0 end) as sp_unremoved,
        max(case when q.qc_inspection_menu = 'QC_INSPECTION_SPOTTING_ROUND'
                  and q.result_common_code = 'PRFT089' then 1 else 0 end) as sp_rewash,
        /* 태그는 했으나 결과 미입력 — 품질이 아니라 현장 입력 누락 신호 */
        max(case when q.qc_inspection_menu = 'QC_INSPECTION_SPOTTING_ROUND'
                  and q.result_common_code = 'PRFT086' then 1 else 0 end) as sp_blank
    from qc_inspection_result q
    where q.delete_yn = 'N'
      and q.lsf_wash_item_id in (select item_id from qitem)
    group by 1
),
careq as (
    select wic.lsf_wash_item_id            as item_id,
           min(date(wic.created_datetime)) as req_d
    from wash_item_complain wic
    where wic.delete_yn = 'N'
      and wic.lsf_wash_item_id in (select item_id from qitem)
    group by 1
),

/* ── ⑤ 기간 × 공장 집계 (전체는 rollup) ─────────────────────────── */
qagg as (
    select
        i.p                                                            as p,
        coalesce(i.factory, '전체')                                     as factory,
        sum(case when i.qc_ok = 1 then ifnull(q.qc_done, 0) else 0 end)                                      as qc_done,
        sum(case when i.qc_ok = 1 then ifnull(q.qc_bad, 0) else 0 end)                                       as qc_bad,
        sum(case when i.qc_ok = 1 then ifnull(q.sp_done, 0) else 0 end)                                      as sp_done,
        sum(case when i.qc_ok = 1 then ifnull(q.sp_unremoved, 0) else 0 end)                                 as sp_unremoved,
        sum(case when i.qc_ok = 1 then ifnull(q.sp_rewash, 0) else 0 end)                                    as sp_rewash,
        sum(case when i.qc_ok = 1 then ifnull(q.sp_blank, 0) else 0 end)                                     as sp_blank,
        count(c.item_id)                                               as care_items,
        percentile_cont(0.9) within group (order by datediff('day', i.rel_d, c.req_d)) as lag_p90,
        percentile_cont(0.5) within group (order by
            case when i.qc_ok = 1 then datediff('day', q.qc_d, i.rel_d) end)               as qc_gap
    from qitem i
        left join qres   q on q.item_id = i.item_id
        left join careq c on c.item_id = i.item_id
    group by i.p, rollup(i.factory)
),

/* ── ⑥ 셀 = 분모 + 분자 ────────────────────────────────────────── */
care_all as (          -- 요청일 기준 접수 건수 — 다리(progress_history) 손실 상시 점검용
    select
        (case when win.g = 'week' then date_trunc('week',  date(wic.created_datetime))
              else                     date_trunc('month', date(wic.created_datetime)) end) as p,
        count(distinct wic.lsf_wash_item_id) as req_items
    from wash_item_complain wic
        cross join win
    where wic.delete_yn = 'N'
      and wic.lsf_wash_item_id is not null
      and date(wic.created_datetime) between win.ws and win.asof
    group by 1
),
qcell as (
    select
        r.p, r.factory, r.rel_items, r.rel_qc_items, r.fac_qc_ok,
        ifnull(a.qc_done, 0)      as qc_done,
        ifnull(a.qc_bad, 0)       as qc_bad,
        ifnull(a.sp_done, 0)      as sp_done,
        ifnull(a.sp_unremoved, 0) as sp_unremoved,
        ifnull(a.sp_rewash, 0)    as sp_rewash,
        ifnull(a.sp_blank, 0)     as sp_blank,
        ifnull(a.care_items, 0)   as care_items,
        a.lag_p90, a.qc_gap,
        /* 관측 완결성 — 출고 후 care_lag 일이 지났는가 */
        (case when dateadd(day, win.lag,
                   case when win.g = 'week' then dateadd(day, 6, r.p) else last_day(r.p) end
                 ) <= win.asof then 1 else 0 end)                      as obs_ok,
        /* 커버리지 완결성 — QC 롤아웃 중인 (기간·공장)은 부적합률이 편향됩니다 */
        (case when ifnull(a.qc_done, 0) / nullif(r.rel_qc_items, 0) * 100 >= win.covmin
              then 1 else 0 end)                                       as cov_ok
    from relx r
        cross join win
        left join qagg a on a.p = r.p and a.factory = r.factory
),

/* ── 지표를 세로형으로 ───────────────────────────────────────────── */
m as (
    /* ① 핵심 */
    select p, '① 핵심' as grp, 'NSM · 세탁 물량(점)' as metric, sum(bc) as v from wb group by 1
    union all select p, '① 핵심', '활성 고객 수(순, 명)', count(distinct user_id) from wb group by 1
    union all select p, '① 핵심', '고객당 물량(점)',
               sum(bc) / nullif(count(distinct user_id), 0) from wb group by 1
    union all select p, '① 핵심', '수거신청 수(건)', count(distinct wash_id) from wb group by 1
    /* ② 구성 */
    union all select p, '② 구성', '구독 고객 비중(%)',
               count(distinct case when seg in ('월구독', '플러스') then user_id end)
               / nullif(count(distinct user_id), 0) * 100 from wb group by 1
    union all select p, '② 구성', '구독 고객당 물량(점)',
               sum(case when seg in ('월구독', '플러스') then bc else 0 end)
               / nullif(count(distinct case when seg in ('월구독', '플러스') then user_id end), 0) from wb group by 1
    union all select p, '② 구성', '자유 고객당 물량(점)',
               sum(case when seg = '자유' then bc else 0 end)
               / nullif(count(distinct case when seg = '자유' then user_id end), 0) from wb group by 1
    union all select p, '② 구성', '월 구독 물량(점)', sum(case when seg = '월구독' then bc else 0 end) from wb group by 1
    union all select p, '② 구성', '플러스 물량(점)',   sum(case when seg = '플러스' then bc else 0 end) from wb group by 1
    union all select p, '② 구성', '자유 물량(점)',     sum(case when seg = '자유'   then bc else 0 end) from wb group by 1
    /* ③ 구독 건전성 */
    union all select p, '③ 구독', '구독-개월 수(건)', count(*) from sm group by 1
    union all select p, '③ 구독', '낙전 비율(%)',
               sum(case when wash_cnt = 0 then 1 else 0 end) / nullif(count(*), 0) * 100 from sm group by 1
    /* ④ 금액 */
    union all select p, '④ 금액', '결제금액(원)', sum(amt) from pay group by 1
    union all select p, '④ 금액', '실질 매출(선수금 이연, 원)',
               sum(case when seg = '플러스' and plus_term > 0 then plan_amt / plus_term + (amt - plan_amt) else amt end)
               from pay group by 1
    union all select p, '④ 금액', '무상포인트 할인율(%)',
               sum(free_point) / nullif(sum(amt) + sum(free_point), 0) * 100 from pay group by 1
    /* ⑤ 품질·운영 */
    union all select p, '⑤ 품질', '출고 기한 준수율(%)',
               avg(case when t_wash is null or t_due is null then null
                        when date(t_wash) <= t_due then 1 else 0 end) * 100 from wb group by 1
    union all select p, '⑤ 품질', '전체 리드타임 P90(일)',
               percentile_cont(0.9) within group (order by datediff('hour', d, t_del) / 24.0) from wb group by 1
    union all select p, '⑤ 품질', '세탁 불가(만건당)',
               sum(bc_bad) / nullif(sum(bc_all), 0) * 10000 from wb group by 1
    union all select p, '⑤ 품질', '세탁 부속품 비중(%)',
               sum(bc_acc) / nullif(sum(bc_all), 0) * 100 from wb group by 1
    /* 진단용 — 스코어카드 화면에서는 숨기고 "미완결" 경고 판단에만 씁니다.
       3% 를 넘으면 그 기간은 아직 배송이 진행 중이라 품질 지표를 신뢰할 수 없습니다. */
    union all select p, '⑨ 진단', '배송시각 결측(%)',
               avg(case when t_del is null then 1 else 0 end) * 100 from wb group by 1
    /* ⑥ 캐파 */
    union all select p, '⑥ 캐파', '일평균 물량(점)', avg(bc) from daily group by 1
    union all select p, '⑥ 캐파', '일 최대 물량(점)', max(bc) from daily group by 1
    /* ⑦ 신규 */
    union all select p, '⑦ 신규', '신규 가입자(명)', count(*) from jn_first group by 1
    union all select p, '⑦ 신규', '가입 → 7일 내 첫 이용(%)',
               case when max(obs_ok) = 1 then avg(used7) * 100 end from jn_first group by 1
    union all select p, '⑦ 신규', '가입자당 7일 주문(건)',
               case when max(obs_ok) = 1 then avg(n7) end from jn_first group by 1
    /* 모수 구성 진단 — 탈퇴 비중이 크게 흔들리면 전환율 해석도 흔들립니다 */
    union all select p, '⑨ 진단', '가입자 중 탈퇴(%)',
               avg(is_gone) * 100                        from jn_first group by 1


    /* ⑤ 품질 — 23번의 품질 3종 (출고월 기준) */
    union all select p, '⑤ 품질', 'QC 부적합률(%)',
           case when cov_ok = 1 then qc_bad / nullif(qc_done, 0) * 100 end        as v
    from qcell where factory = '전체'
    union all select p, '⑤ 품질', '스파팅 못지움율(%)',
           case when cov_ok = 1 then sp_unremoved / nullif(sp_done, 0) * 100 end
    from qcell where factory = '전체'
    union all select p, '⑤ 품질', '안심케어 인입률(%)',
           case when obs_ok = 1 then care_items / nullif(rel_items, 0) * 100 end
    from qcell where factory = '전체'

    /* ⑧ 공장 — 같은 지표를 공장별로 */
    union all select p, '⑧ 공장', 'QC 부적합률(%) · ' || factory,
           case when cov_ok = 1 then qc_bad / nullif(qc_done, 0) * 100 end
    from qcell where factory <> '전체' and fac_qc_ok = 1
    union all select p, '⑧ 공장', '스파팅 못지움율(%) · ' || factory,
           case when cov_ok = 1 then sp_unremoved / nullif(sp_done, 0) * 100 end
    from qcell where factory <> '전체' and fac_qc_ok = 1
    union all select p, '⑧ 공장', '안심케어 인입률(%) · ' || factory,
           case when obs_ok = 1 then care_items / nullif(rel_items, 0) * 100 end
    from qcell where factory <> '전체'

    /* ⑨ 진단 — 화면에는 안 나오지만 해석에 반드시 필요합니다 */
    union all select p, '⑨ 진단', 'QC 진행률(%)',
           qc_done / nullif(rel_qc_items, 0) * 100     from qcell where factory = '전체'
    union all select p, '⑨ 진단', '스파팅 진행률(%)',
           sp_done / nullif(rel_qc_items, 0) * 100     from qcell where factory = '전체'
    union all select p, '⑨ 진단', 'QC 미실시 공장 출고 비중(%)',
           (rel_items - rel_qc_items) / nullif(rel_items, 0) * 100
                                                       from qcell where factory = '전체'
    union all select p, '⑨ 진단', '스파팅 결과 미입력률(%)',
           sp_blank / nullif(sp_done + sp_blank, 0) * 100 from qcell where factory = '전체'
    union all select p, '⑨ 진단', '스파팅 재세탁율(%)',
           sp_rewash / nullif(sp_done, 0) * 100        from qcell where factory = '전체'
    union all select p, '⑨ 진단', '출고 의류 수(건)',    rel_items   from qcell where factory = '전체'
    union all select p, '⑨ 진단', '안심케어 인입(건)',   care_items  from qcell where factory = '전체'
    union all select p, '⑨ 진단', '안심케어 요청 지연 P90(일)', lag_p90 from qcell where factory = '전체'
    union all select p, '⑨ 진단', '안심케어 접수(요청일, 건)', req_items from care_all
    union all select p, '⑨ 진단', '출고 − QC 시행 간격 중앙값(일)',
           /* 커버리지 미달 기간은 재세탁 등으로 과거 출고건에 뒤늦게 붙은 QC 만
              잡혀 음수가 나옵니다. 지표와 같은 가드를 걸어 비웁니다 */
           case when cov_ok = 1 then qc_gap end        from qcell where factory = '전체'
    /* 공장별 커버리지 — 어떤 공장의 값이 왜 비었는지 여기서 확인 */
    union all select p, '⑨ 진단', 'QC 진행률(%) · ' || factory,
           qc_done / nullif(rel_qc_items, 0) * 100
    from qcell where factory <> '전체' and fac_qc_ok = 1
),
joined as (
    select
        c.p, c.grp, c.metric, c.v,
        pr.v                                                       as v_prev
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
    case metric
        when '구독 고객 비중(%)'                then '40% 이상'
        when '출고 기한 준수율(%)'              then '95% 이상'
        when '무상포인트 할인율(%)'             then '전년比 +0.5%p 이내'
        when '낙전 비율(%)'                     then '전년比 상승 금지'
        when '세탁 불가(만건당)'                then '2건 이하'
        when '전체 리드타임 P90(일)'            then '전년比 상승 금지'
        when '가입 → 7일 내 첫 이용(%)'         then '전년比 하락 금지'
        when '가입자당 7일 주문(건)'            then '전년比 -5% 이내'
        when '고객당 물량(점)'                  then '전년比 -3% 이내'
        when 'NSM · 세탁 물량(점)'              then '전년比 0% 이상'
        when 'QC 부적합률(%)'                   then '전년比 상승 금지'
        when '스파팅 못지움율(%)'                then '전년比 상승 금지'
        when '안심케어 인입률(%)'                then '전년比 상승 금지'
        else case when grp = '⑧ 공장' then '전년比 상승 금지' end
        end                                                        as "기준선",
    case
        /* v 가 비어 있으면 판정하지 않는다 — 관측·커버리지 가드로 비운 칸을
           '이탈'로 잘못 찍는 것을 막습니다 */
        when v is null                           then null
        when metric = '구독 고객 비중(%)'        then case when v >= 40 then '양호' else '이탈' end
        when metric = '출고 기한 준수율(%)'      then case when v >= 95 then '양호' else '이탈' end
        when metric = '세탁 불가(만건당)'        then case when v <= 2  then '양호' else '이탈' end
        when v_prev is null or v_prev = 0        then null
        when metric = '무상포인트 할인율(%)'     then case when v - v_prev <= 0.5 then '양호' else '이탈' end
        when metric = '낙전 비율(%)'             then case when v <= v_prev then '양호' else '이탈' end
        when metric = '전체 리드타임 P90(일)'    then case when v <= v_prev then '양호' else '이탈' end
        when metric = '가입 → 7일 내 첫 이용(%)'  then case when v >= v_prev then '양호' else '이탈' end
        when metric = '가입자당 7일 주문(건)'    then case when v >= v_prev * 0.95 then '양호' else '이탈' end
        when metric = '고객당 물량(점)'          then case when v >= v_prev * 0.97 then '양호' else '이탈' end
        when metric = 'NSM · 세탁 물량(점)'      then case when v >= v_prev then '양호' else '이탈' end
        when metric in ('QC 부적합률(%)', '스파팅 못지움율(%)', '안심케어 인입률(%)')
                                                 then case when v <= v_prev then '양호' else '이탈' end
        when grp = '⑧ 공장'                      then case when v <= v_prev then '양호' else '이탈' end
        else null end                                              as "판정"
from joined
order by "기간", grp, metric

/* ----------------------------------------------------------------------------
   [ 리뷰 진행 요령 — 15분 ]
     1) "판정" = 이탈 인 줄만 먼저 훑습니다.
     2) NSM 이 빠졌다면 ①의 <b>활성 고객 수</b>와 <b>고객당 물량</b> 중 어느 쪽인지 봅니다.
        고객당 물량이면 ②의 <b>구독 비중</b>을 봅니다 — 지금까지 원인은 거의 항상 여기였습니다.
     3) ⑤가 이탈이면 NSM 이 아직 멀쩡해도 <b>몇 달 뒤 물량으로 돌아옵니다.</b>
        어느 공장인지는 ⑧에서 좁힙니다.
     4) ⑥ 캐파 일평균이 역대 최대의 80% 를 넘기 시작하면 물량 목표에 상한을 겁니다.

   [ ⑨ 진단 — 지표를 믿어도 되는지 먼저 확인 ]
     · 배송시각 결측(%)          3% 초과 → 그 기간은 미완결. 준수율·P90 해석 금지
     · QC 진행률(%)              흔들리면 부적합률·못지움율의 추세 해석 금지
                                 (분모가 바뀐 것이지 품질이 바뀐 게 아닙니다)
     · 스파팅 결과 미입력률(%)   오르면 품질 악화가 아니라 <b>현장 입력 누락</b>
                                 (태그만 찍고 적합/못지움/재세탁 미입력 = PRFT086)
     · 안심케어 접수 vs 인입      두 값의 기간 합이 5% 넘게 벌어지면 다리에서 건이 샌 것
     · 안심케어 요청 지연 P90     care_lag(15일)에 가까워지면 값을 올리세요
     · QC 미실시 공장 출고 비중   흔들리면 공장 배정이 바뀐 것. 커버리지도 같이 보세요

   [ 알아두실 것 ]
     · 부산공장은 QC·스파팅을 하지 않습니다. QC 지표에서 빠지고 <b>커버리지 분모에서도</b>
       빠집니다(qc_scope CTE). 시작하면 그 한 줄만 지우면 됩니다. 안심케어는 그대로 냅니다.
     · QC 데이터는 2026-03 부터만 있고 커버리지가 아직 오르는 중이라,
       QC·스파팅은 <b>2026-06 이후</b>부터만 값이 나옵니다. 전년 대비는 2027년부터입니다.
     · 주간(week)으로 볼 때 구독-개월·낙전은 월 단위 개념이라 해석이 어렵습니다.

   [ 무겁다고 느껴지면 ]
     20(핵심 지표) 과 23(품질 3종) 을 따로 돌려도 결과는 같습니다.
     두 CSV 를 스코어카드에 함께 끌어다 놓으면 하나의 표로 합쳐집니다.
   -------------------------------------------------------------------------- */
