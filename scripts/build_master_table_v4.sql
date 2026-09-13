-- ============================================================================
-- FRA 마스터 테이블 v4 (SQLite)
--
-- v3(build_master_table_v3.sql) 대비 변경점 — 분자(고장) 정의 4단계 재검증
-- 결과 반영. STEP 3의 필터가 완전히 교체됨. 상세 근거:
-- decisions/2026-08-31c-numerator-final-revision-and-categorization.md
--
--   1) ClaimType__c='In Stock' 필터 삭제
--      → 판매전 발견 결함은 가장 강력한 제조결함 증거(사용 안 했는데 고장났다면
--        고객 과실일 수 없음). 사용시간이 긴데 라벨만 In Stock으로 남은 8건은
--        SFDC 담당자 확인 결과 시스템 이관 시 흔한 라벨 정정 누락. 전량 포함.
--   2) ClaimType__c='Damaged' 필터를 CauseCode__c='Shipping Damage'로 교체
--      → 'Damaged' 4건 중 3건이 실제 고장(와셔 불량으로 바퀴 이탈, 베어링 파손
--        등)이었음. 진짜 운송파손은 CauseCode__c 자체가 'Shipping Damage'인
--        1건뿐이므로 이 값으로 정확히 지정해야 함.
--   3) ClaimType__c='In House' 필터 삭제
--      → "처리 장소"를 뜻할 뿐 고장 여부와 무관한 필드였음. 실측 결과 대다수가
--        진짜 고장("Factory design of seals is faulty" 등 자사설계결함 명시
--        사례 포함).
--   4) ClaimType__c='Shortage' 필터는 유지
--      → 실측 확인 결과 진짜 "부품 누락"으로 고장 아님.
--   5) CauseCode3__c='Product improvement campaign' 제외 추가 (마스터 전체 33건)
--      → 선제적 리콜/점검. 부위별: Chassis 37 > Front Axle 15 > Hydraulic 13 >
--        Others 10 > Engine 3. 'Special allowance'는 이름은 유사하나 실제
--        고장으로 확인되어 포함 유지.
--   6) CauseCode3__c='Steering' 제외 추가 (Front Axle 내 97건, 팀장 확인)
--      → 물리적으로 조향 계통이며 차축 자체(구동계) 문제와 성격이 다름.
--
-- 추가로 STEP 6-2에서 Branson(단종 브랜드, fm_ItemName__c에 'Branson' 포함)
-- 133건을 제외하는 단계를 신설함 — 현재 판매 중인 제품 분석이 목적이므로.
--
-- 검증 기준값 (8/27 데이터, 2026-09-07 기준 최종):
--   전체 고장정의 적용 후 13,213건 / Front Axle 1,991건
--   → Branson 제외 후 Front Axle 최종 1,858건
--   (Leakage+Oil Leakage 50.7%, Breakage 41.0%)
-- ============================================================================


-- ----------------------------------------------------------------------------
-- STEP 0~2: v3와 동일 (인덱스, 클레임 고유 추출, NA-Global 병합)
-- 이미 fra_master_v3 테이블이 존재한다면 이 단계는 생략하고 바로 STEP 3부터
-- 실행해도 됨. 처음부터 재현하려면 build_master_table_v3.sql의 STEP 0~2를
-- 그대로 실행한 뒤 이어서 진행할 것.
-- ----------------------------------------------------------------------------


-- ----------------------------------------------------------------------------
-- STEP 3 (v4로 교체): 분자(고장) 정의 뷰
-- ----------------------------------------------------------------------------

DROP VIEW IF EXISTS fra_failure_only_v4;

CREATE VIEW fra_failure_only_v4 AS
SELECT *
FROM fra_master_v3
WHERE "ClaimType__c" != 'Shortage'
  AND "CauseCode__c" IS NOT NULL
  AND "CauseCode__c" != 'Shipping Damage'
  AND ("CauseCode3__c" IS NULL
       OR "CauseCode3__c" NOT IN ('Product improvement campaign', 'Steering'));

-- 검증
-- SELECT COUNT(*) FROM fra_failure_only_v4;
-- 기대값: 13,213

-- SELECT COUNT(*) FROM fra_failure_only_v4 WHERE "CauseCode__c" = 'Front Axle';
-- 기대값: 1,991 (Branson 포함 상태)


-- ----------------------------------------------------------------------------
-- STEP 6-2 (신규): Front Axle 확정 — Branson(단종 브랜드) 제외
--
-- fm_ItemName__c에 'Branson'이 포함된 건은 TYM이 과거 북미에서 운영했던
-- 별도 브랜드이며 현재 단종됨(사용자 확인). 현재 판매 중인 제품의 설계·조립
-- 문제를 규명하는 것이 목적이므로 분석 대상에서 제외한다.
-- ----------------------------------------------------------------------------

DROP VIEW IF EXISTS fra_front_axle_final;

CREATE VIEW fra_front_axle_final AS
SELECT *
FROM fra_failure_only_v4
WHERE "CauseCode__c" = 'Front Axle'
  AND ("fm_ItemName__c" IS NULL OR "fm_ItemName__c" NOT LIKE '%Branson%');

-- 검증
-- SELECT COUNT(*) FROM fra_front_axle_final;
-- 기대값: 1,858 (최종 분석 대상)

-- SELECT "CauseCode2__c", COUNT(*) AS n,
--        ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS pct
-- FROM fra_front_axle_final
-- GROUP BY "CauseCode2__c"
-- ORDER BY n DESC;
-- 기대값: Leakage+Oil Leakage 약 50.7%, Breakage 약 41.0%
