# 2026-08-31(2차) — 분자 정의 4단계 재정정 및 Front Axle 부품 카테고리 확정

## 배경

부품 카테고리 분류 착수 전, 분자(고장) 정의를 처음부터 재검증하는 과정에서
연쇄적으로 4개의 정정이 발생했다. 매번 "이름만 보고 판단"한 것을 실제 텍스트
(`DescriptionOfFailure__c`)와 대조하는 과정에서 드러났다.

## 정정 이력

| 단계 | Front Axle | 변경 내용 |
|---|---|---|
| 0 | 3,903 | 원본 단순 집계 (중복 포함) |
| 1 | 2,051 | NA-Global 중복 제거, `ClaimType__c` IN (In Stock/Damaged/Shortage/In House) 제외 |
| 2 | 2,039 | `CauseCode3__c`='Product improvement campaign' 33건(마스터 전체) 추가 제외 확인 |
| 3 | 1,950 | Steering 97건 제외 + Damaged/In House 오분류 10건 복귀 |
| **4 (최종)** | **1,991** | **In Stock 44건 전량 복귀** |

### 결정 1: `CauseCode3__c`='Product improvement campaign' 제외 (33건, 마스터 전체)

선제적 리콜/점검. `DescriptionOfFailure__c` 실측: "Mandatory Product Improvement
campaign TYM SB25-041", "TYM safety inspection". 고장 발생이 아니라 회사가 지시한
예방 조치. 부위별 분포: Chassis 37 > Front Axle 15(적용후 12) > Hydraulic 13 >
Others 10 > Engine 3. **Front Axle 외 부위 분석 시에도 반드시 적용할 것.**

한편 `CauseCode3__c`='Special allowance'(10건)는 이름은 유사하나 텍스트 대조 결과
실제 고장으로 확인되어 포함 유지 ("Both front axles leaking at the wheel shaft",
"FRAME MOUNTS ARE DEFECTIVE... INCORRECT WELDING" 등). **이름만으로 판단 금지의
재확인 사례.**

### 결정 2: Steering 97건 분리 (팀장 확인)

`CauseCode__c`='Front Axle'이나 `CauseCode3__c`='Steering'인 건. 실측 결과 조향
실린더·타이로드·볼조인트의 파손/휨이 대부분("steering cylinder broken", "steering
rod broke"). 위치는 전차축이나 기능적으로 조향 계통이라 차축 자체(구동계) 문제와
성격이 다름. 담당 조직도 다를 수 있어 팀장 확인 후 분리 확정.

### 결정 3: `ClaimType__c`='Damaged'/'In House' 재검증 — 이름만 보고 오판했던 필터 정정

- **Damaged**(4건): 이름은 "운송파손"을 암시하나 실측 결과 3건이 실제 고장
  (와셔 배치 불량으로 바퀴 이탈, 베어링 파손). 진짜 운송파손은 `CauseCode__c`
  자체가 'Shipping Damage'인 1건뿐. → 필터를 `CauseCode__c`='Shipping Damage'로
  정확히 교체.
- **In House**(33건): "처리 장소"를 뜻할 뿐 고장 여부와 무관한 필드였음. 실측
  결과 대다수가 진짜 고장("Knuckle snapped in half", "Factory design of seals
  is faulty" — 자사 설계결함 명시 사례 포함). → 제외 목록에서 완전히 삭제.
- **Shortage**(2건): 실측 결과 진짜 "부품 누락"으로 고장 아님 확인 → 제외 유지.

### 결정 4 (최종): In Stock 전면 재검토 — 사용자 지적으로 발견

**사용자 지적**: "사용 전 발견된 결함이야말로 제조 결함의 가장 확실한 증거인데
왜 빼는가?" 이 지적으로 In Stock 44건(Front Axle)을 재조사.

실측 결과 두 그룹으로 구성:
1. 사용시간 10시간 이하 진짜 판매전 결함 (36건) — "sealing cap... busted from
   factory", "Tie rod boots worn from factory", "MISSING FROM FACTORY" 등.
   **가장 깨끗한 제조결함 증거.**
2. 사용시간이 긴데(최대 1,710시간) `ClaimType__c`만 'In Stock'으로 남은 라벨
   오류 (8건) — 전부 `fm_AssetRetailDate__c`(판매일자) 존재, 판매 후 수년 뒤
   고장 접수된 정상 필드 고장. SFDC 담당자 확인: **옛 데이터 이관(migration)
   시 발생하는 라벨 정정 누락**, 종종 있는 현상.

→ **`ClaimType__c`='In Stock' 필터를 완전히 제거.** 두 그룹 모두 포함이 맞음.
(향후 "판매전 결함 vs 필드 고장" 구분이 필요해지면 UsageTime 기준 별도 플래그로
분리 가능하나, 필터에서는 제외하지 않는다.)

## 최종 분자 정의 (v4)

```sql
WHERE "ClaimType__c" != 'Shortage'
  AND "CauseCode__c" IS NOT NULL
  AND "CauseCode__c" != 'Shipping Damage'
  AND ("CauseCode3__c" IS NULL
       OR "CauseCode3__c" NOT IN ('Product improvement campaign', 'Steering'))
```

검증: 전체 13,213건 / Front Axle 1,991건
(Leakage+Oil Leakage 50.7%, Breakage 41.0% — 4차례 기준 변경에도 안정적으로 90% 유지)

## Front Axle 부품 카테고리 분류 (1,991건 확정 기준)

`causal_parts_no`를 기준 식별자로, `causal_parts_name`(자유 텍스트, 동일 부품이
표기 6종 이상으로 분산되는 사례 확인)은 참고 라벨로 사용. `SUB TO <코드> <이름>`
표기는 뒤쪽 실제 부품명으로 재분류.

| 카테고리 | 건수 | 비고 |
|---|---|---|
| No Part Info(부품정보 없음) | 562 | 한계로 명시 — Breakage 비중이 10%p 높음(선행 감사) |
| **Seal** | 454 | Leakage 83% — 분류 타당성 검증 통과 |
| **Bearing** | 394 | Leakage 56.9%(예상외), Breakage 33.7% — 연쇄고장 가능성(아래 참고) |
| **Gear** | 198 | Breakage 76.9% |
| Washer | 116 | 부품번호 `16709510081` 114건 집중, 서술 전수 확인 결과 베어링 연쇄고장 표지자로 추정(정식 검증 전) |
| Ring(Snap/C/O) | 34 | |
| Cylinder | 34 | Bent(휨) 26.6%로 독보적 — 별도 계통(조향) 성격과 일치 |
| Circlip/Snap Ring | 8 | Reddit VOC의 "서클립→베어링 손상" 이슈와 직결, 별도 분리 |
| 기타 20종 | 191 | 각 20건 미만 |
| 미분류 | 1 | 부품명 정보 자체 없음 |

미분류 1건 제외 전량 분류 완료 (합계 1,991 일치 검증됨).
산출물: `fra_front_axle_categorized_final.csv`

## 다음 단계

- Washer(부품번호 16709510081)가 베어링 연쇄고장 표지자인지 서술 전수 검증
- `part_category` × `CauseCode2__c` 교차표로 카테고리별 고장현상 재확인 (샘플 검증은 완료, 전체 표 작성 필요)
- No Part Info 562건의 Breakage 편중 문제를 결론에 한계로 명시
