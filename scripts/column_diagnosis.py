import openpyxl, json
from collections import defaultdict

wb = openpyxl.load_workbook('/mnt/user-data/uploads/Warrnaty_Claim_Status.xlsx',
                            data_only=True, read_only=True)
ws = wb['Claim Raw']

rows = ws.iter_rows(values_only=True)
header = list(next(rows))
n = len(header)

filled      = [0]*n                      # 전체 채움
filled_kor  = [0]*n                      # 한국 채움
filled_na   = [0]*n
filled_glo  = [0]*n
uniq        = [set() for _ in range(n)]  # 고유값(상한 두고 수집)
uniq_over   = [False]*n                  # 고유값 5000 초과 여부
samples     = [[] for _ in range(n)]     # 샘플값
types       = [defaultdict(int) for _ in range(n)]

tot_kor = tot_na = tot_glo = 0
total = 0
IDX_RT = 1

for row in rows:
    total += 1
    rt = row[IDX_RT]
    if rt == 'Korea': tot_kor += 1
    elif rt == 'North America': tot_na += 1
    elif rt == 'Global': tot_glo += 1

    for i in range(n):
        v = row[i] if i < len(row) else None
        if v is None or (isinstance(v, str) and v.strip() == ''):
            continue
        filled[i] += 1
        if rt == 'Korea': filled_kor[i] += 1
        elif rt == 'North America': filled_na[i] += 1
        elif rt == 'Global': filled_glo[i] += 1

        types[i][type(v).__name__] += 1

        if not uniq_over[i]:
            uniq[i].add(str(v)[:100])
            if len(uniq[i]) > 5000:
                uniq_over[i] = True
                uniq[i] = set()
        if len(samples[i]) < 3:
            s = str(v).replace('\n',' ')[:60]
            if s not in samples[i]:
                samples[i].append(s)

out = []
for i in range(n):
    out.append(dict(
        idx=i, name=str(header[i]),
        filled=filled[i], rate=round(filled[i]/total*100,1),
        kor=filled_kor[i], na=filled_na[i], glo=filled_glo[i],
        kor_rate=round(filled_kor[i]/tot_kor*100,1) if tot_kor else 0,
        na_rate=round(filled_na[i]/tot_na*100,1) if tot_na else 0,
        glo_rate=round(filled_glo[i]/tot_glo*100,1) if tot_glo else 0,
        nuniq=(-1 if uniq_over[i] else len(uniq[i])),
        dtype=max(types[i], key=types[i].get) if types[i] else 'empty',
        samples=samples[i]
    ))

json.dump(dict(total=total, tot_kor=tot_kor, tot_na=tot_na, tot_glo=tot_glo, cols=out),
          open('diag.json','w'), ensure_ascii=False)
print(f"완료: {total}행 × {n}컬럼 진단")
print(f"한국 {tot_kor} / 북미 {tot_na} / 글로벌 {tot_glo}")
