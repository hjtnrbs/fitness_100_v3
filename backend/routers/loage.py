# backend/routers/loage.py
# 신체나이 계산 API (나이 예측 모델 + Quantile 엔진)

from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
import math



router = APIRouter()

# =========================
# 1. 경로 설정
# =========================

BASE_DIR = Path(__file__).resolve().parents[1]  # backend/
MODEL_DIR = BASE_DIR / "models"

# 🔹 단일 회귀 모델 (RandomForest 등)
MODEL_PATH = MODEL_DIR / "age_model.pkl"

# 🔹 Quantile 엔진 (lai_v6_quantile_engine → model.pkl 이름으로 저장된 버전)
QUANTILE_PATH = MODEL_DIR / "model.pkl"

# 🔹 모델이 기대하는 입력 컬럼 (학습 시 사용한 순서와 동일)
FEATURE_COLUMNS = [
    "flexibility",
    "grip_strength",
    "jump_power",
    "sex_M",
    "cardio_endurance",
    "sit_ups",
    "body_fat_pct",
    "sex_F",
    "rhr",
]

# 🔹 퍼센타일 계산에 사용하는 운동 항목
METRICS = ["sit_ups", "flexibility", "jump_power", "cardio_endurance"]
LOWER_IS_BETTER = ["cardio_endurance"]  # 숫자가 낮을수록 좋은 지표


print("[DEBUG] loage.py loaded from:", __file__)
print("[DEBUG] MODEL_PATH:", MODEL_PATH)
print("[DEBUG] QUANTILE_PATH:", QUANTILE_PATH)

# =========================
# 2. 모델 / Quantile 로드
# =========================

try:
    age_model = joblib.load(MODEL_PATH)
    print("✅ age_model 로드 완료")
except Exception as e:
    print(f"[경고] age_model 로드 실패: {e}")
    age_model = None

try:
    quantile_table = joblib.load(QUANTILE_PATH)
    print("✅ quantile_table 로드 완료")
except Exception as e:
    print(f"[경고] quantile_table 로드 실패: {e}")
    quantile_table = None


# =========================
# 3. 요청 바디 스키마
# =========================

class PhysicalAgeRequest(BaseModel):
    # 온보딩에서 필수로 받을 4개 + 유연성
    flexibility: float
    jump_power: float
    cardio_endurance: float
    sit_ups: float

    # 성별은 회원가입 데이터에서 가져와서 넣는다고 가정
    sex: str  # "M" 또는 "F"

    # 아래 3개는 선택 입력 (없으면 기본값으로 자동 대체)
    grip_strength: float | None = None
    body_fat_pct: float | None = None
    rhr: float | None = None


# =========================
# 4. 기본값 세팅 + 결측치 보완
# =========================

# 성별별 평균/대표 값 (필요하면 나중에 데이터 기반으로 보정)
DEFAULTS = {
    "M": {"grip_strength": 30.0, "body_fat_pct": 20.0, "rhr": 75.0},
    "F": {"grip_strength": 20.0, "body_fat_pct": 27.0, "rhr": 78.0},
}


def fill_missing_features(data: PhysicalAgeRequest) -> dict:
    """
    grip_strength, body_fat_pct, rhr 가 None 이면
    성별별 기본값으로 채워서 모델 입력용 dict 생성
    """
    sex = data.sex.upper()

    base = DEFAULTS.get(sex)
    if base is None:
        # 이 부분은 compute_physical_age에서 한 번 더 체크하지만 안전장치로 한 번 더
        raise HTTPException(status_code=400, detail="sex는 'M' 또는 'F'여야 합니다.")

    return {
        "flexibility": data.flexibility,
        "grip_strength": data.grip_strength if data.grip_strength is not None else base["grip_strength"],
        "jump_power": data.jump_power,
        "cardio_endurance": data.cardio_endurance,
        "sit_ups": data.sit_ups,
        "body_fat_pct": data.body_fat_pct if data.body_fat_pct is not None else base["body_fat_pct"],
        "rhr": data.rhr if data.rhr is not None else base["rhr"],
        "sex_M": 1 if sex == "M" else 0,
        "sex_F": 1 if sex == "F" else 0,
    }


# =========================
# 5. 퍼센타일 / 보정 유틸 함수
# =========================

def _is_true(x):
    if isinstance(x, (bool, np.bool_)):
        return bool(x)
    if isinstance(x, (int, np.integer)):
        return x == 1
    if isinstance(x, str):
        return x.upper() == "TRUE"
    return False


def get_sex_from_row(row: pd.Series) -> str:
    val_f = row.get("sex_F", None)
    val_m = row.get("sex_M", None)

    if _is_true(val_f):
        return "Female"
    if _is_true(val_m):
        return "Male"
    return "Male"


def get_percentile_score_v6(metric: str, value: float, sex: str, q_model: dict) -> float:
    """
    Quantile 엔진에서 metric별 값 분포를 가져와
    해당 값이 몇 % 위치인지 0~100 점수로 변환
    """
    try:
        series = q_model[metric][sex]  # index: 0~100, values: 기준값
        idx = int(np.searchsorted(series.values, value, side="right"))  # 0~100
        score = float(idx)
        if metric in LOWER_IS_BETTER:
            score = 100.0 - score
        return max(0.0, min(100.0, score))
    except Exception:
        return 0.0


def get_percentile(user_row: pd.Series, quantile_model: dict) -> float:
    """
    METRICS 항목들(sit_ups, flexibility, jump_power, cardio_endurance)을
    각각 0~100 점수로 바꾸고 평균낸 값을 최종 퍼센타일로 사용
    """
    sex = get_sex_from_row(user_row)
    scores = []

    for m in METRICS:
        if m not in user_row.index:
            continue
        v = user_row[m]
        if pd.isna(v):
            continue
        s = get_percentile_score_v6(m, v, sex, quantile_model)
        scores.append(s)

    if not scores:
        return 50.0

    return float(np.mean(scores))


def adjust_age(age_pred: float, percentile: float) -> float:
    """
    예측 나이(age_pred)와 퍼센타일(percentile)을 이용한 보정 규칙
    퍼센타일 구간에 따라 ± 몇 살 보정할지 결정
    """
    if percentile < 20:
        return age_pred + 5
    elif percentile < 40:
        return age_pred + 2
    elif percentile < 60:
        return age_pred
    elif percentile < 80:
        return age_pred - 2
    else:
        return age_pred - 4


# =========================
# 6. 메인 엔드포인트
# =========================

@router.post("/compute")
def compute_physical_age(payload: PhysicalAgeRequest):
    # 모델/Quantile이 로드되지 않았다면 바로 500 에러
    if age_model is None or quantile_table is None:
        raise HTTPException(status_code=500, detail="모델이 로드되지 않았습니다.")

    sex = payload.sex.upper()
    if sex not in ["M", "F"]:
        raise HTTPException(status_code=400, detail="sex는 'M' 또는 'F'여야 합니다.")

    # 🔹 부족한 입력은 성별별 기본값으로 채우기
    row_dict = fill_missing_features(payload)
    row = pd.Series(row_dict)

    # 🔹 Stage A: 회귀 모델로 예측 나이 계산
    X = pd.DataFrame([row_dict])[FEATURE_COLUMNS]
    age_pred = float(age_model.predict(X)[0])

    # 🔹 Stage B: Quantile 기반 퍼센타일 계산
    percentile = float(get_percentile(row, quantile_table))

    # 🔹 Stage C: 퍼센타일 기반 신체나이 보정
    physical_age = float(adjust_age(age_pred, percentile))

    return {
        "age_pred": age_pred,
        "percentile": percentile,
        "physical_age": physical_age,
    }
