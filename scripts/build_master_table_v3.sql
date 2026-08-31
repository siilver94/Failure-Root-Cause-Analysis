-- ============================================================================
-- FRA 마스터 테이블 v3 (SQLite)
--
-- v2 대비 변경점:
--   - 클레임 데이터를 8/27 최신본으로 갱신
--   - Part 테이블 결합 (CausalPart__c=True 필터, 북미는 클레임당 정확히 1개 확인됨)
--   - Labor 테이블 집계 결합 (0원 라인 포함해도 SUM 집계는 무해함을 확인)
--
-- 사전 검증 완료 사항 (2026-08-31, decisions/2026-08-31-audit-and-part-labor.md 참고):
--   - 북미 클레임 7,778건 전수 확인 결과 Causal=True가 정확히 1개 (0건 예외)
--     → 북미는 클레임:Part = 1:1로 안전하게 매칭 가능. 한국(126건 다중)과 다름.
--   - Causal=True 2개 이상(128건)은 한국 전용 현상. 북미 마스터에는 영향 없음.
--   - Labor 라인의 22.1%가 승인시간=0/승인비용=0 → 담당자 확인: 시스템 자동 생성
--     빈 레코드. SUM 집계 시 자동 상쇄되어 무해하나, "라인 개수"는 지표로 쓰지 않음.
--
-- 검증 기준값 (8/27 데이터): 북미 모집단 13,482 / Front Axle(분자정의 적용) 2,051
-- ============================================================================


-- ----------------------------------------------------------------------------
-- STEP 0: 인덱스
-- ----------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_id ON "Warrnaty_Claim_Status2_csv" ("Id");
CREATE INDEX IF NOT EXISTS idx_origclaim ON "Warrnaty_Claim_Status2_csv" ("OriginalClaimNumber__c");
CREATE INDEX IF NOT EXISTS idx_recordtype ON "Warrnaty_Claim_Status2_csv" ("RecordType.Name");
CREATE INDEX IF NOT EXISTS idx_claimid_labor ON "Warrnaty_Claim_Status2_csv" ("ClaimId__c.labor");


-- ----------------------------------------------------------------------------
-- STEP 1: 클레임 고유 레코드 추출 (Part/Labor 조인으로 늘어난 행을 원복)
--
-- 원본 CSV는 Case + Parts + Labor가 조인되어 1클레임당 최대 156행까지 늘어나
-- 있음. 먼저 클레임 자체만 Id 기준으로 유일하게 뽑는다.
-- ----------------------------------------------------------------------------

DROP TABLE IF EXISTS fra_claims_raw;

CREATE TABLE fra_claims_raw AS
SELECT DISTINCT
  "Id", "CaseNumber", "OriginalClaimNumber__c", "IsFromNA__c", "IsSentHQ__c", "RecordType.Name",
  "FailureDate__c", "RepairDate__c", "ClosedDate", "CreatedDate",
  "UsageTime__c", "fm_Glo_Kor_ProdDate__c", "fm_AssetRetailDate__c", "fm_Kor_ShippedDate__c",
  "CauseCode__c", "CauseCode2__c", "CauseCode3__c", "ClaimType__c", "Status", "Subject",
  "DescriptionOfFailure__c", "Failure_Cause__c", "Repair__c", "AdminNotes__c",
  "AssetId", "fm_ItemCode__c", "fm_ItemName__c", "fm_ItemNameEng__c", "Asset.Name",
  "AccountId", "Account.Name", "fm_DealerShipName__c",
  "fm_TotalRequestAmount__c", "fm_TotalApprovedAmount__c",
  "ru_TotalApprovedPartsAmount__c", "ru_PartsTotal__c",
  "ru_TotalRequestLaborCost__c", "ru_TotalApprovedLaborCost__c",
  "ru_TotalRequestLaborHour__c", "ru_TotalApprovedLaborHour__c", "ru_CountParts__c",
  "DealerComment__c", "Description"
FROM "Warrnaty_Claim_Status2_csv";

-- 검증: SELECT COUNT(*) FROM fra_claims_raw;  -- 57,901


-- ----------------------------------------------------------------------------
-- STEP 2: 북미 전용 모집단 (fra_claim_event) — v2와 동일 로직, 새 데이터로 재실행
-- ----------------------------------------------------------------------------

DROP TABLE IF EXISTS fra_claim_event;

CREATE TABLE fra_claim_event AS
SELECT
  na."Id" AS na_id, glo."Id" AS global_id,
  COALESCE(glo."Id", na."Id") AS event_key,
  COALESCE(glo."CaseNumber", na."CaseNumber") AS case_number,
  CASE WHEN glo."Id" IS NOT NULL THEN 'Global' ELSE 'NA_standalone' END AS record_source,
  COALESCE(glo."FailureDate__c", na."FailureDate__c") AS failure_date,
  COALESCE(glo."RepairDate__c", na."RepairDate__c") AS repair_date,
  COALESCE(glo."ClosedDate", na."ClosedDate") AS closed_date,
  COALESCE(glo."CreatedDate", na."CreatedDate") AS created_date,
  COALESCE(glo."UsageTime__c", na."UsageTime__c") AS usage_time,
  COALESCE(glo."fm_Glo_Kor_ProdDate__c", na."fm_Glo_Kor_ProdDate__c") AS prod_date,
  COALESCE(glo."fm_AssetRetailDate__c", na."fm_AssetRetailDate__c") AS retail_date,
  COALESCE(glo."fm_Kor_ShippedDate__c", na."fm_Kor_ShippedDate__c") AS shipped_date,
  COALESCE(glo."CauseCode__c", na."CauseCode__c") AS cause_code,
  COALESCE(glo."CauseCode2__c", na."CauseCode2__c") AS cause_code2,
  COALESCE(glo."CauseCode3__c", na."CauseCode3__c") AS cause_code3,
  COALESCE(glo."ClaimType__c", na."ClaimType__c") AS claim_type,
  COALESCE(glo."Status", na."Status") AS status,
  na."Status" AS status_na_stage,
  COALESCE(glo."Subject", na."Subject") AS subject,
  COALESCE(glo."DescriptionOfFailure__c", na."DescriptionOfFailure__c") AS description_of_failure,
  COALESCE(glo."Failure_Cause__c", na."Failure_Cause__c") AS failure_cause,
  COALESCE(glo."Repair__c", na."Repair__c") AS repair_text,
  COALESCE(glo."AdminNotes__c", na."AdminNotes__c") AS admin_notes,
  COALESCE(glo."AssetId", na."AssetId") AS asset_id,
  COALESCE(glo."fm_ItemCode__c", na."fm_ItemCode__c") AS item_code,
  COALESCE(glo."fm_ItemName__c", na."fm_ItemName__c") AS item_name,
  COALESCE(glo."fm_ItemNameEng__c", na."fm_ItemNameEng__c") AS item_name_eng,
  COALESCE(glo."Asset.Name", na."Asset.Name") AS asset_model,
  COALESCE(glo."AccountId", na."AccountId") AS account_id,
  COALESCE(glo."Account.Name", na."Account.Name") AS account_name,
  COALESCE(glo."fm_DealerShipName__c", na."fm_DealerShipName__c") AS dealership_name,
  COALESCE(glo."fm_TotalRequestAmount__c", na."fm_TotalRequestAmount__c") AS amount_requested,
  COALESCE(glo."fm_TotalApprovedAmount__c", na."fm_TotalApprovedAmount__c") AS amount_approved,
  COALESCE(glo."ru_TotalApprovedPartsAmount__c", na."ru_TotalApprovedPartsAmount__c") AS parts_amount_approved,
  COALESCE(glo."ru_PartsTotal__c", na."ru_PartsTotal__c") AS parts_total,
  COALESCE(glo."ru_TotalRequestLaborCost__c", na."ru_TotalRequestLaborCost__c") AS labor_cost_requested,
  COALESCE(glo."ru_TotalApprovedLaborCost__c", na."ru_TotalApprovedLaborCost__c") AS labor_cost_approved,
  COALESCE(glo."ru_TotalRequestLaborHour__c", na."ru_TotalRequestLaborHour__c") AS labor_hour_requested,
  COALESCE(glo."ru_TotalApprovedLaborHour__c", na."ru_TotalApprovedLaborHour__c") AS labor_hour_approved,
  COALESCE(glo."ru_CountParts__c", na."ru_CountParts__c") AS parts_count,
  COALESCE(glo."DealerComment__c", na."DealerComment__c") AS dealer_comment,
  COALESCE(glo."Description", na."Description") AS description,
  na."IsSentHQ__c" AS is_sent_hq,
  glo."IsFromNA__c" AS is_from_na
FROM fra_claims_raw na
LEFT JOIN fra_claims_raw glo
  ON glo."RecordType.Name" = 'Global'
 AND glo."OriginalClaimNumber__c" = na."Id"
WHERE na."RecordType.Name" = 'North America';

-- 22건(NA1:Global2+) dedup
DROP TABLE IF EXISTS fra_claim_event_dedup;
CREATE TABLE fra_claim_event_dedup AS
SELECT * FROM (
  SELECT *, ROW_NUMBER() OVER (
    PARTITION BY na_id
    ORDER BY CASE WHEN status='Closed' THEN 0 ELSE 1 END, created_date DESC
  ) AS rn
  FROM fra_claim_event
) WHERE rn = 1;

-- 검증: SELECT COUNT(*) FROM fra_claim_event_dedup;  -- na_id 고유 건수와 일치


-- ----------------------------------------------------------------------------
-- STEP 3: 분자(고장) 정의 뷰
-- ----------------------------------------------------------------------------

DROP VIEW IF EXISTS fra_failure_only;
CREATE VIEW fra_failure_only AS
SELECT * FROM fra_claim_event_dedup
WHERE claim_type NOT IN ('In Stock', 'Damaged', 'Shortage', 'In House');

-- 검증: SELECT COUNT(*) FROM fra_failure_only WHERE cause_code='Front Axle';  -- 2,051


-- ----------------------------------------------------------------------------
-- STEP 4: Causal Part 테이블 (신규)
--
-- 북미는 CausalPart__c=True가 클레임당 정확히 1개임이 전수 검증됨(7,778건, 예외 0).
-- 따라서 북미에 한해 단순 INNER JOIN으로 클레임:Part = 1:1 매칭이 안전하다.
--
-- 한국은 이 가정이 깨짐(True 2개 이상 126건 확인) — 한국 분석 시 이 STEP을
-- 그대로 재사용하지 말 것. 클레임:Part = 1:N으로 별도 설계 필요.
-- ----------------------------------------------------------------------------

DROP TABLE IF EXISTS fra_causal_part;

CREATE TABLE fra_causal_part AS
SELECT * FROM (
  SELECT
    "ClaimId__c" AS claim_id,
    "fm_PartsNo__c" AS parts_no,
    "fm_PartsName__c" AS parts_name,
    "ProductId__r.Name" AS product_name,
    "Quantity__c" AS quantity,
    "LP__c" AS is_local_purchase,
    "LocalParts__c" AS local_parts_desc,
    ROW_NUMBER() OVER (
      PARTITION BY "ClaimId__c"
      ORDER BY CASE WHEN "fm_PartsNo__c" LIKE '%C' THEN 1 ELSE 0 END  -- 대체품 코드(끝자리 C 등) 후순위
    ) AS rn
  FROM "Warrnaty_Claim_Status2_csv"
  WHERE "CausalPart__c" = 'True'
    AND "fm_PartsNo__c" IS NOT NULL
) WHERE rn = 1;

-- 알려진 예외 (2026-08-31 검증에서 발견, 전수 7,779건 중 1건):
--   CaseNumber 24268 (ClaimId 500J400000BfbbQIAR) — 정품 TA00039979(HOSE)와
--   대체품 TA00039979C(SUB TO TA00039979)가 둘 다 CausalPart__c=True로 존재.
--   부품 대체(재고 부족 등) 이력으로 추정. 위 쿼리는 정품 코드(비-C)를 대표로
--   선택하되, 이런 케이스가 더 있는지는 향후 검증 필요.
-- 검증(북미만): 아래 결과가 0이어야 함 (예외 1건은 위 규칙으로 이미 해소됨)
-- SELECT claim_id, COUNT(*) FROM fra_causal_part
--   WHERE claim_id IN (SELECT Id FROM 클레임_데이터_csv WHERE "RecordType.Name" IN ('North America','Global'))
--   GROUP BY claim_id HAVING COUNT(*) > 1;


-- ----------------------------------------------------------------------------
-- STEP 5: Labor 집계 테이블 (신규, 라인 단위가 아니라 클레임 단위 합계로만 제공)
--
-- 원칙: Labor "라인 개수"는 지표로 쓰지 않는다(0원 자동생성 라인이 22.1% 섞여
-- 있어 건수 기준 집계가 왜곡됨). 오직 SUM(승인시간), SUM(승인비용)만 사용—
-- 0원 라인은 합계에 자연히 0으로 반영되어 무해함.
-- ----------------------------------------------------------------------------

DROP TABLE IF EXISTS fra_labor_summary;

CREATE TABLE fra_labor_summary AS
SELECT
  "ClaimId__c.labor" AS claim_id,
  SUM(CASE WHEN "ApprovedLaborHour__c" IS NOT NULL THEN "ApprovedLaborHour__c" ELSE 0 END) AS total_approved_labor_hour,
  SUM(CASE WHEN "fm_TotalApprovedLaborCost__c" IS NOT NULL THEN "fm_TotalApprovedLaborCost__c" ELSE 0 END) AS total_approved_labor_cost,
  COUNT(DISTINCT "fm_LaborCode__c") AS distinct_labor_code_count  -- 참고용. 라인 개수 아님(코드 종류 수)
FROM "Warrnaty_Claim_Status2_csv"
WHERE "Id.labor" IS NOT NULL
GROUP BY "ClaimId__c.labor";


-- ----------------------------------------------------------------------------
-- STEP 6: 최종 마스터 (fra_master_v3) — 클레임 + Part + Labor 결합
-- ----------------------------------------------------------------------------

DROP TABLE IF EXISTS fra_master_v3;

CREATE TABLE fra_master_v3 AS
SELECT
  ce.*,
  cp.parts_no, cp.parts_name, cp.product_name, cp.quantity, cp.is_local_purchase,
  ls.total_approved_labor_hour, ls.total_approved_labor_cost, ls.distinct_labor_code_count
FROM fra_claim_event_dedup ce
LEFT JOIN fra_causal_part cp ON cp.claim_id = COALESCE(ce.global_id, ce.na_id)
LEFT JOIN fra_labor_summary ls ON ls.claim_id = COALESCE(ce.global_id, ce.na_id);

-- 최종 검증
-- SELECT COUNT(*) FROM fra_master_v3;  -- na_id 고유 건수와 일치해야 함(북미는 Part 1:1이므로 행 안 늘어남)
-- SELECT COUNT(*) FROM fra_master_v3 WHERE cause_code='Front Axle'
--   AND claim_type NOT IN ('In Stock','Damaged','Shortage','In House');  -- 2,051
