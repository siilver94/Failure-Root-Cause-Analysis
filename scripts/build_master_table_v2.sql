-- ============================================================================
-- FRA 마스터 테이블 v2 (SQLite)
--
-- v1(build_master_table.sql) 대비 변경점:
--   v1은 쌍이 있는 경우 UNION ALL로 Global 레코드만 채택 → NA의 Id,
--   ResponsibilityID__c, TM_Code__c 등이 통째로 소실됨.
--   v2는 LEFT JOIN + COALESCE로 두 레코드를 병합 → 정보 손실 없음.
--
--   이 변경이 필요한 이유: 향후 수신할 Parts/Causal/Labor 데이터가
--   NA의 Id를 조인키로 쓸지 Global의 Id를 쓸지 아직 알 수 없음.
--   양쪽 Id를 모두 보존해야 어느 키로 오든 조인이 가능하다.
--
-- 검증 기준값 (v1과 동일해야 함): 총 12,856(중복 22건 수정 후 12,834) /
--   NA단독 4,457 / Global재클레임 8,377(고유) / Front Axle 1,972(분자 정의 적용)
-- ============================================================================


-- ----------------------------------------------------------------------------
-- STEP 0: 인덱스 (v1과 동일, 필수)
-- ----------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_id
  ON "Warrnaty_Claim_Status_csv" ("Id");
CREATE INDEX IF NOT EXISTS idx_origclaim
  ON "Warrnaty_Claim_Status_csv" ("OriginalClaimNumber__c");
CREATE INDEX IF NOT EXISTS idx_recordtype
  ON "Warrnaty_Claim_Status_csv" ("RecordType.Name");


-- ----------------------------------------------------------------------------
-- STEP 1: NA-Global 쌍 병합 (fra_claim_event)
--
-- "1행 = 1고장사건"을 만족하는 최소 단위 테이블.
-- 쌍이 있는 경우 두 레코드를 병합, 값이 갈리면 Global 우선(COALESCE).
-- NA 전용 컬럼(ResponsibilityID, TM_Code 등)과 Global 전용 컬럼
-- (ServiceManager 등)을 모두 보존.
--
-- 알려진 잔여 이슈 (2026-08-27 감사에서 발견, 아직 미해결):
--   - NA 1건에 Global이 2건 붙는 케이스 22건 존재 → 이 쿼리는 미해결.
--     정확히 하려면 Global 쪽에서 대표 1건을 고르는 규칙이 별도로 필요.
--     (예: 가장 최근 수정된 것, 또는 Status가 Closed인 것 우선)
--   - IsSentHQ__c=True인데 Global 짝이 없는 NA 2,667건 → 담당자 확인 대기.
--     이 쿼리에서는 "짝 없음"으로 자동 분류되어 NA 단독 취급됨.
-- ----------------------------------------------------------------------------

DROP TABLE IF EXISTS fra_claim_event;

CREATE TABLE fra_claim_event AS
SELECT
  -- 두 체계의 Id를 모두 보존 — 향후 Parts 데이터 조인 대비
  na."Id"                              AS na_id,
  glo."Id"                             AS global_id,
  COALESCE(glo."Id", na."Id")          AS event_key,   -- 대표키(조인 실패 시 폴백)
  COALESCE(glo."CaseNumber", na."CaseNumber") AS case_number,

  -- 어느 쪽이 최종 판정인지 명시 (분석 시 근거 추적용)
  CASE WHEN glo."Id" IS NOT NULL THEN 'Global' ELSE 'NA_standalone' END AS record_source,

  -- 날짜/시간 — Global 우선, 없으면 NA (fm_Glo_Kor_ProdDate__c 등은 NA에서
  -- 결측률이 높으므로(26.9%) COALESCE로 보완됨)
  COALESCE(glo."FailureDate__c", na."FailureDate__c")             AS failure_date,
  COALESCE(glo."RepairDate__c", na."RepairDate__c")               AS repair_date,
  COALESCE(glo."ClosedDate", na."ClosedDate")                     AS closed_date,
  COALESCE(glo."CreatedDate", na."CreatedDate")                   AS created_date,
  COALESCE(glo."UsageTime__c", na."UsageTime__c")                 AS usage_time,
  COALESCE(glo."fm_Glo_Kor_ProdDate__c", na."fm_Glo_Kor_ProdDate__c") AS prod_date,
  COALESCE(glo."fm_AssetRetailDate__c", na."fm_AssetRetailDate__c")   AS retail_date,
  COALESCE(glo."fm_Kor_ShippedDate__c", na."fm_Kor_ShippedDate__c")   AS shipped_date,

  -- 고장/원인 — Global 우선 (CauseCode3__c는 Global 62.7% vs NA 24.8%)
  COALESCE(glo."CauseCode__c", na."CauseCode__c")                 AS cause_code,
  COALESCE(glo."CauseCode2__c", na."CauseCode2__c")               AS cause_code2,
  COALESCE(glo."CauseCode3__c", na."CauseCode3__c")               AS cause_code3,
  COALESCE(glo."ClaimType__c", na."ClaimType__c")                 AS claim_type,
  COALESCE(glo."Status", na."Status")                             AS status,          -- 최종 판정(Global 있으면 Global이 항상 최종)
  na."Status"                                                     AS status_na_stage, -- NA 1단계 판정 별도 보존(참고용)
  COALESCE(glo."Subject", na."Subject")                           AS subject,
  COALESCE(glo."DescriptionOfFailure__c", na."DescriptionOfFailure__c") AS description_of_failure,
  COALESCE(glo."Failure_Cause__c", na."Failure_Cause__c")         AS failure_cause,
  COALESCE(glo."Repair__c", na."Repair__c")                       AS repair_text,
  COALESCE(glo."AdminNotes__c", na."AdminNotes__c")               AS admin_notes,

  -- 제품/조직
  COALESCE(glo."AssetId", na."AssetId")                           AS asset_id,
  COALESCE(glo."fm_ItemCode__c", na."fm_ItemCode__c")             AS item_code,
  COALESCE(glo."fm_ItemName__c", na."fm_ItemName__c")             AS item_name,
  COALESCE(glo."fm_ItemNameEng__c", na."fm_ItemNameEng__c")       AS item_name_eng,
  COALESCE(glo."Asset.Name", na."Asset.Name")                     AS asset_model,      -- 실제로는 모델명(고유 173) — 기대 표시명 아님, 필드정의서 오류 정정
  COALESCE(glo."AccountId", na."AccountId")                       AS account_id,
  COALESCE(glo."Account.Name", na."Account.Name")                 AS account_name,
  COALESCE(glo."fm_DealerShipName__c", na."fm_DealerShipName__c") AS dealership_name,

  -- 금액/심각도
  COALESCE(glo."fm_TotalRequestAmount__c", na."fm_TotalRequestAmount__c")   AS amount_requested,
  COALESCE(glo."fm_TotalApprovedAmount__c", na."fm_TotalApprovedAmount__c") AS amount_approved,
  COALESCE(glo."ru_TotalApprovedPartsAmount__c", na."ru_TotalApprovedPartsAmount__c") AS parts_amount_approved,
  COALESCE(glo."ru_PartsTotal__c", na."ru_PartsTotal__c")         AS parts_total,
  COALESCE(glo."ru_TotalRequestLaborCost__c", na."ru_TotalRequestLaborCost__c") AS labor_cost_requested,
  COALESCE(glo."ru_TotalApprovedLaborCost__c", na."ru_TotalApprovedLaborCost__c") AS labor_cost_approved,
  COALESCE(glo."ru_TotalRequestLaborHour__c", na."ru_TotalRequestLaborHour__c") AS labor_hour_requested,
  COALESCE(glo."ru_TotalApprovedLaborHour__c", na."ru_TotalApprovedLaborHour__c") AS labor_hour_approved,
  COALESCE(glo."ru_CountParts__c", na."ru_CountParts__c")         AS parts_count,

  -- 보조 텍스트
  COALESCE(glo."DealerComment__c", na."DealerComment__c")         AS dealer_comment,
  COALESCE(glo."Description", na."Description")                  AS description,

  -- v1에서 제거했던 것 중 마스터 취지에 맞게 복원 — NA 전용이라 COALESCE 무의미,
  -- 그대로 NA 값 사용 (담당자 편향 체크, 처리유형 분석용)
  na."ResponsibilityID__c"     AS responsibility_id_na,
  na."TM_Code__c"              AS tm_code_na,
  na."CreditMemoAmount__c"     AS credit_memo_amount_na,

  -- Global 전용 — 향후 처리속도 분석(FRA/Method 예정 사례)을 위해 보존
  glo."Glo_ServiceManager__c"  AS service_manager_global,
  glo."Glo_SubmittedDate__c"   AS submitted_date_global,

  -- 구조 추적용 (감사 로그)
  na."IsSentHQ__c"             AS is_sent_hq,
  glo."IsFromNA__c"            AS is_from_na

FROM "Warrnaty_Claim_Status_csv" na
LEFT JOIN "Warrnaty_Claim_Status_csv" glo
  ON glo."RecordType.Name" = 'Global'
 AND glo."OriginalClaimNumber__c" = na."Id"
WHERE na."RecordType.Name" = 'North America';

-- 참고: Global 단독 레코드(OriginalClaimNumber가 어떤 NA와도 매칭 안 되는 것)는
-- 전부 비북미로 확인됨(2026-08-14 감사, BAD BOY INC/MCCORMICK/RURAL KING 등
-- 해외 파트너사). 따라서 이 마스터(북미 전용)에는 포함하지 않는다.
-- 전 지역 마스터가 필요해지면 별도 테이블(fra_claim_event_global_only)로 분리해
-- UNION하되, 이 SELECT의 컬럼 구조를 그대로 맞춰서 만들 것 — NULL 나열 방식은
-- 컬럼이 늘어날 때마다 깨지므로 쓰지 않는다.


-- 검증
-- SELECT COUNT(*) FROM fra_claim_event;                                -- 12,834 (NA 4,457 + Global고유 8,377)
-- SELECT record_source, COUNT(*) FROM fra_claim_event GROUP BY record_source;
-- SELECT COUNT(*) FROM fra_claim_event WHERE global_id IS NULL AND is_sent_hq='True';  -- 2,667 (미해결 이슈 재확인용)


-- ----------------------------------------------------------------------------
-- STEP 2: 22건 중복 처리 (NA 1건 : Global 2건인 케이스)
--
-- 위 LEFT JOIN은 이 22건에 대해 행이 2개 생성된다(한 NA가 두 Global과 매칭).
-- 대표 1건만 남기는 규칙: Status가 'Closed'인 것 우선, 둘 다 같으면 최근
-- CreatedDate 우선. (담당자 확인 전까지의 임시 규칙 — 확정 아님)
-- ----------------------------------------------------------------------------

DROP TABLE IF EXISTS fra_claim_event_dedup;

CREATE TABLE fra_claim_event_dedup AS
SELECT *
FROM (
  SELECT *,
    ROW_NUMBER() OVER (
      PARTITION BY na_id
      ORDER BY
        CASE WHEN status = 'Closed' THEN 0 ELSE 1 END,
        created_date DESC
    ) AS rn
  FROM fra_claim_event
)
WHERE rn = 1;

-- 검증
-- SELECT COUNT(*) FROM fra_claim_event_dedup;   -- 12,834 (정확히 일치해야 함)


-- ----------------------------------------------------------------------------
-- STEP 3: 분자(고장) 정의 적용 뷰
--
-- 마스터 테이블 자체에는 필터를 걸지 않는다(원칙: 필터는 뷰에서).
-- 분석 시 이 뷰를 사용한다.
-- ----------------------------------------------------------------------------

DROP VIEW IF EXISTS fra_failure_only;

CREATE VIEW fra_failure_only AS
SELECT *
FROM fra_claim_event_dedup
WHERE claim_type NOT IN ('In Stock', 'Damaged', 'Shortage', 'In House');

-- 검증
-- SELECT COUNT(*) FROM fra_failure_only;                                  -- 약 12,600대 (In Stock 등 제외분)
-- SELECT COUNT(*) FROM fra_failure_only WHERE cause_code = 'Front Axle';  -- 1,972 (기존 확정치와 일치해야 함)
