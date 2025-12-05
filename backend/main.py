from typing import Optional, Dict, List

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, field_validator

import numpy as np
import pandas as pd
import joblib
from pathlib import Path
import math
import os
import requests
from datetime import datetime
from dotenv import load_dotenv

# =========================================
# 환경변수 로드
# =========================================
load_dotenv()  # 기본 .env 로드

BASE_DIR = Path(__file__).resolve().parent
load_dotenv(dotenv_path=BASE_DIR / ".env")

# =========================================
# Supabase 연동 헬퍼
# =========================================
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_SERVICE_ROLE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY")

print("[DEBUG] SUPABASE_URL:", SUPABASE_URL)
print("[DEBUG] SUPABASE_KEY 시작 10글자:", SUPABASE_SERVICE_ROLE_KEY[:10] if SUPABASE_SERVICE_ROLE_KEY else None)

def _sb_json_headers(prefer_return: bool = False) -> Dict[str, str]:
  """Supabase REST 호출용 공통 헤더"""
  if not SUPABASE_SERVICE_ROLE_KEY:
      raise RuntimeError("SUPABASE_SERVICE_ROLE_KEY 가 설정되지 않았습니다.")
  headers = {
      "apikey": SUPABASE_SERVICE_ROLE_KEY,
      "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
      "Content-Type": "application/json",
  }
  if prefer_return:
      headers["Prefer"] = "return=representation"
  return headers

def _sb_table_url(table: str) -> str:
  if not SUPABASE_URL:
      raise RuntimeError("SUPABASE_URL 이 설정되지 않았습니다.")
  return f"{SUPABASE_URL}/rest/v1/{table}"

# =========================================
# Naver Directions API 키 사용안함! 없어도 되는 부분
# =========================================
NAVER_CLIENT_ID = os.getenv("NAVER_CLIENT_ID")      # X-NCP-APIGW-API-KEY-ID

print("[DEBUG] NAVER_CLIENT_ID:", NAVER_CLIENT_ID)


# =========================================
# Supabase insert / select 함수 (physical_age_assessments)
# =========================================
def insert_physical_age_assessment(row: dict) -> Optional[dict]:
    """
    Supabase physical_age_assessments 테이블에 1건 insert 후
    삽입된 row를 반환 (또는 None).
    """
    if not SUPABASE_URL or not SUPABASE_SERVICE_ROLE_KEY:
        print("[WARN] Supabase 환경변수가 없어 insert를 건너뜁니다.")
        return None

    try:
        url = f"{SUPABASE_URL}/rest/v1/physical_age_assessments"
        headers = _sb_json_headers(prefer_return=True)
        resp = requests.post(url, headers=headers, json=row, timeout=5)

        if resp.status_code >= 400:
            print("[ERROR] Supabase 응답:", resp.status_code, resp.text)
            resp.raise_for_status()

        data = resp.json()
        if isinstance(data, list) and data:
            return data[0]
        return data
    except Exception as e:
        print(f"[ERROR] Supabase insert 실패: {e}")
        return None


def query_physical_age_assessments(user_id: str, limit: int = 1) -> List[dict]:
    """
    Supabase physical_age_assessments 에서 user_id 기준으로
    최근 measured_at 순으로 limit건 조회.
    """
    if not SUPABASE_URL or not SUPABASE_SERVICE_ROLE_KEY:
        raise RuntimeError("Supabase 환경변수가 설정되어 있지 않습니다.")

    try:
        url = f"{SUPABASE_URL}/rest/v1/physical_age_assessments"
        headers = {
            "apikey": SUPABASE_SERVICE_ROLE_KEY,
            "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
        }
        params = {
            "user_id": f"eq.{user_id}",
            "order": "measured_at.desc",
            "limit": str(limit),
        }
        resp = requests.get(url, headers=headers, params=params, timeout=5)
        resp.raise_for_status()
        data = resp.json()
        if not isinstance(data, list):
            raise TypeError("Supabase 응답 형식이 리스트가 아닙니다.")
        return data
    except Exception as e:
        print(f"[ERROR] Supabase select 실패: {e}")
        raise


# =========================================
# 1. 신체나이 17등급 라벨 정의
# =========================================
AGE_GRADES = [
    "19세 이하",      # 0
    "20대 초반",      # 1
    "20대 중반",      # 2
    "20대 후반",      # 3
    "30대 초반",      # 4
    "30대 중반",      # 5
    "30대 후반",      # 6
    "40대 초반",      # 7
    "40대 중반",      # 8
    "40대 후반",      # 9
    "50대 초반",      # 10
    "50대 중반",      # 11
    "50대 후반",      # 12
    "60대 초반",      # 13
    "60대 중반",      # 14
    "60대 후반",      # 15
    "70대 이상",      # 16
]


def grade_idx_to_label(idx: int) -> str:
    """등급 인덱스(0~16)를 한글 라벨로 변환."""
    idx = max(0, min(idx, len(AGE_GRADES) - 1))
    return AGE_GRADES[idx]


def quantile_to_grade(q: float) -> Dict[str, object]:
    """
    평균 quantile(0~1)을 17등급으로 변환.
    """
    q = float(np.clip(q, 0.0, 1.0))
    n_grades = len(AGE_GRADES)

    idx_from_low = int(q * n_grades)
    if idx_from_low == n_grades:
        idx_from_low -= 1

    grade_idx = (n_grades - 1) - idx_from_low
    grade_idx = max(0, min(grade_idx, n_grades - 1))
    label = grade_idx_to_label(grade_idx)

    return {
        "grade_index": grade_idx,
        "grade_label": label,
    }


def grade_index_to_lo_age_value(idx: int) -> int:
    """
    17등급 인덱스를 대략적인 '숫자 신체나이'로 매핑.
    """
    idx = max(0, min(idx, len(AGE_GRADES) - 1))
    mapping = {
        0: 18,  # 19세 이하
        1: 22,  # 20대 초반
        2: 25,  # 20대 중반
        3: 28,  # 20대 후반
        4: 32,  # 30대 초반
        5: 35,  # 30대 중반
        6: 38,  # 30대 후반
        7: 42,  # 40대 초반
        8: 45,  # 40대 중반
        9: 48,  # 40대 후반
        10: 52,  # 50대 초반
        11: 55,  # 50대 중반
        12: 58,  # 50대 후반
        13: 62,  # 60대 초반
        14: 65,  # 60대 중반
        15: 68,  # 60대 후반
        16: 72,  # 70대 이상
    }
    return mapping.get(idx, 40)


# =========================================
# 2. 입력/출력 Pydantic 모델 정의
# =========================================
class PhysicalAgeRequest(BaseModel):
    user_id: Optional[str] = None   # Supabase auth.users.id (uuid) / 없으면 None
    sex: str                        # "M"/"F", "남"/"여" 등
    flexibility: float              # 유연성
    jump_power: float               # 제자리멀리뛰기
    cardio_endurance: float         # 심폐지구력
    sit_ups: float                  # 윗몸일으키기

    @field_validator("sex")
    @classmethod
    def normalize_sex(cls, v: str) -> str:
        s = v.strip().lower()
        if s in ["f", "female", "여", "여자", "woman", "girl"]:
            return "Female"
        if s in ["m", "male", "남", "남자", "man", "boy"]:
            return "Male"
        raise ValueError("sex 는 남/여(M/F) 형태로 입력해야 합니다.")


class PhysicalAgeResponse(BaseModel):
    # Flutter에서 바로 쓸 핵심 값들
    lo_age_value: int                   # 숫자 신체나이 (예: 33)
    lo_age_tier_label: str              # "30대 후반" 등급 라벨
    percentile: float                   # avg_quantile * 100
    weak_point: str                     # 가장 취약한 항목 (예: "sit_ups")
    tier_index: int                     # 등급 인덱스(=grade_index)

    # 세부 정보
    detail_quantiles: Dict[str, float]  # 항목별 quantile (0~1)
    avg_quantile: float                 # 4개 종목 평균 quantile

    # 디버깅/부가 정보
    grade_index: int                    # 0 ~ 16
    grade_label: str                    # "40대 중반" 등
    assessment_id: Optional[int] = None # Supabase physical_age_assessments.id


class PhysicalAgeRecord(BaseModel):
    id: int
    user_id: str
    measured_at: datetime

    # 등급/지표
    grade_index: Optional[int] = None
    grade_label: Optional[str] = None
    percentile: Optional[float] = None
    weak_point: Optional[str] = None
    avg_quantile: Optional[float] = None

    # 숫자 신체나이 + 라벨
    lo_age_value: Optional[int] = None
    lo_age_tier_label: Optional[str] = None

    # 세부 quantile 정보
    detail_quantiles: Optional[Dict[str, float]] = None


class PhysicalAgeHistoryResponse(BaseModel):
    user_id: str
    records: List[PhysicalAgeRecord]


# =========================================
# 3. 엔진(model.pkl) 로딩 및 quantile 계산 함수
# =========================================
ENGINE_PATH = Path(__file__).parent / "models" / "model.pkl"
_engine_cache: Optional[Dict[str, pd.DataFrame]] = None


def load_engine() -> Dict[str, pd.DataFrame]:
    """
    model.pkl(dict) 로딩.
    키: 'sit_ups', 'flexibility', 'jump_power', 'cardio_endurance'
    값: pandas.DataFrame (index = quantile, columns = ['Female', 'Male'])
    """
    global _engine_cache
    if _engine_cache is not None:
        return _engine_cache

    if not ENGINE_PATH.exists():
        raise FileNotFoundError(f"엔진 파일을 찾을 수 없습니다: {ENGINE_PATH}")

    obj = joblib.load(str(ENGINE_PATH))
    if not isinstance(obj, dict):
        raise TypeError("엔진 파일 내용이 dict 형식이 아닙니다.")

    for key in ["sit_ups", "flexibility", "jump_power", "cardio_endurance"]:
        if key not in obj:
            raise KeyError(f"엔진에 '{key}' 키가 없습니다.")
        if not isinstance(obj[key], pd.DataFrame):
            raise TypeError(f"엔진의 '{key}' 값이 DataFrame 이 아닙니다.")

    _engine_cache = obj
    return _engine_cache


def get_quantile_from_table(df: pd.DataFrame, sex_col: str, value: float) -> float:
    """
    DataFrame(quantile table)과 입력값(value)으로부터 quantile 추정.
    """
    if sex_col not in df.columns:
        raise KeyError(f"엔진 테이블에 '{sex_col}' 컬럼이 없습니다.")

    q = df.index.to_numpy(dtype=float)
    v = df[sex_col].to_numpy(dtype=float)

    order = np.argsort(v)
    v_sorted = v[order]
    q_sorted = q[order]

    q_est = np.interp(value, v_sorted, q_sorted, left=0.0, right=1.0)
    return float(q_est)


def compute_physical_age_quantiles(req: PhysicalAgeRequest) -> Dict[str, float]:
    """
    4개 운동 항목 각각에 대해 quantile 계산 후 dict 로 반환.
    """
    engine = load_engine()
    sex_col = req.sex  # "Female" or "Male"

    q_situps = get_quantile_from_table(engine["sit_ups"], sex_col, req.sit_ups)
    q_flex   = get_quantile_from_table(engine["flexibility"], sex_col, req.flexibility)
    q_jump   = get_quantile_from_table(engine["jump_power"], sex_col, req.jump_power)
    q_cardio = get_quantile_from_table(engine["cardio_endurance"], sex_col, req.cardio_endurance)

    return {
        "sit_ups": q_situps,
        "flexibility": q_flex,
        "jump_power": q_jump,
        "cardio_endurance": q_cardio,
    }


# =========================================
# 4. 공공체육시설 Supabase + 근처 조회 로직
# =========================================
FACILITIES_TABLE = os.getenv("FACILITIES_TABLE", "facilities")
_facilities_df: Optional[pd.DataFrame] = None


def load_facilities() -> pd.DataFrame:
    """
    Supabase facilities 테이블 전체를 페이징으로 읽어와
    하나의 DataFrame으로 캐싱해서 반환.
    """
    global _facilities_df
    if _facilities_df is not None:
        return _facilities_df

    if not SUPABASE_URL or not SUPABASE_SERVICE_ROLE_KEY:
        raise RuntimeError("Supabase 환경변수가 설정되지 않았습니다.")

    table_name = FACILITIES_TABLE
    base_url = f"{SUPABASE_URL}/rest/v1/{table_name}"

    common_headers = {
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
        "Range-Unit": "items",
        "Prefer": "count=exact",
    }

    page_size = 1000
    start = 0
    frames: List[pd.DataFrame] = []

    while True:
        end = start + page_size - 1

        headers = {
            **common_headers,
            "Range": f"{start}-{end}",
        }

        params = {
            "select": (
                "id,name,lat,lon,address,detail_equip,type,"
                "is_muscular_endurance,is_flexibility,is_cardio,quickness"
            )
        }

        resp = requests.get(base_url, headers=headers, params=params, timeout=30)
        print(f"[DEBUG] facilities page {start}-{end} status:", resp.status_code)

        resp.raise_for_status()
        data = resp.json()

        if not data:
            break

        df_page = pd.DataFrame(data)
        frames.append(df_page)

        if len(data) < page_size:
            break

        start += page_size

    if not frames:
        raise RuntimeError("Supabase에서 시설 데이터를 가져오지 못했습니다.")

    df = pd.concat(frames, ignore_index=True)

    df = df.dropna(subset=["lat", "lon"])
    df["lat"] = df["lat"].astype(float)
    df["lon"] = df["lon"].astype(float)

    print("[DEBUG] Supabase에서 시설 로딩 완료, 전체 시설 수:", len(df))
    _facilities_df = df
    return _facilities_df


def haversine_km(lat1, lon1, lat2, lon2) -> float:
    R = 6371.0
    d_lat = math.radians(lat2 - lat1)
    d_lon = math.radians(lon2 - lon1)
    a = math.sin(d_lat/2)**2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(d_lon/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    return R * c


def infer_category(row) -> str:
    """
    facilities 테이블 기준 운동 카테고리 추론
    - is_cardio             : 심폐지구력
    - is_muscular_endurance : 근지구력
    - is_flexibility        : 유연성
    - quickness             : (선택) 순발력/기타
    """
    if row.get("is_cardio", 0) == 1:
        return "심폐지구력"

    if row.get("is_muscular_endurance", 0) == 1:
        return "근지구력"

    if row.get("is_flexibility", 0) == 1:
        return "유연성"

    if row.get("quickness", 0) == 1:
        return "기타"

    return "기타"


def weak_point_to_category(weak_point: str) -> str:
    """
    weak_point 문자열을 시설 카테고리로 매핑.
    예: 'cardio_endurance' -> '심폐지구력'
    """
    w = weak_point.lower()
    if "cardio" in w or "심폐" in w:
        return "심폐지구력"
    if "sit" in w or "muscular" in w or "endurance" in w or "근지구" in w:
        return "근지구력"
    if "flex" in w or "유연" in w:
        return "유연성"
    if "jump" in w or "strength" in w or "근력" in w:
        return "근력"
    return "기타"


class FacilityOut(BaseModel):
    id: int
    name: str
    lat: float
    lon: float
    address: str
    mission: str
    category: str


class RecommendedFacility(FacilityOut):
    distance_km: float           # 사용자와의 거리
    match_category: bool         # 취약영역 카테고리와 맞는지 여부


# =========================================
# 5. FastAPI 앱 및 엔드포인트
# =========================================
app = FastAPI(title="Fitness100 Physical Age 17-Grade API")


@app.on_event("startup")
def on_startup():
    try:
        load_engine()
        print(f"[INFO] 엔진 로딩 완료: {ENGINE_PATH}")
    except Exception as e:
        print(f"[ERROR] 엔진 로딩 실패: {e}")

    try:
        load_facilities()
        print(f"[INFO] 시설 데이터 로딩 완료 (Supabase)")
    except Exception as e:
        print(f"[ERROR] 시설 데이터 로딩 실패 (Supabase): {e}")


@app.get("/health")
def health_check():
    return {"status": "ok"}


@app.post("/predict/physical-age", response_model=PhysicalAgeResponse)
def predict_physical_age(req: PhysicalAgeRequest):
    """
    신체나이 17등급 예측 + Supabase insert 엔드포인트.
    """
    try:
        q_dict = compute_physical_age_quantiles(req)
    except (KeyError, TypeError, FileNotFoundError) as e:
        raise HTTPException(status_code=500, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"예측 중 오류가 발생했습니다: {e}")

    q_values = list(q_dict.values())
    avg_q = float(np.mean(q_values))
    grade_info = quantile_to_grade(avg_q)
    grade_index = int(grade_info["grade_index"])
    grade_label = str(grade_info["grade_label"])

    lo_age_value = grade_index_to_lo_age_value(grade_index)
    lo_age_tier_label = grade_label
    tier_index = grade_index
    percentile = avg_q * 100.0
    weak_point = min(q_dict.items(), key=lambda kv: kv[1])[0]

    saved_row = None
    if req.user_id is not None:
        row = {
            "user_id": req.user_id,
            "sex": req.sex,
            "sit_ups": req.sit_ups,
            "flexibility": req.flexibility,
            "jump_power": req.jump_power,
            "cardio_endurance": req.cardio_endurance,
            "lo_age_value": lo_age_value,
            "lo_age_tier_label": lo_age_tier_label,
            "tier_index": tier_index,
            "percentile": percentile,
            "weak_point": weak_point,
            "detail_quantiles": q_dict,
        }

        saved_row = insert_physical_age_assessment(row)

    assessment_id = None
    if isinstance(saved_row, dict) and "id" in saved_row:
        assessment_id = saved_row["id"]

    return PhysicalAgeResponse(
        lo_age_value=lo_age_value,
        lo_age_tier_label=lo_age_tier_label,
        percentile=percentile,
        weak_point=weak_point,
        tier_index=tier_index,
        detail_quantiles=q_dict,
        avg_quantile=avg_q,
        grade_index=grade_index,
        grade_label=grade_label,
        assessment_id=assessment_id,
    )


@app.get("/users/{user_id}/physical-age/latest", response_model=PhysicalAgeRecord)
def get_latest_physical_age(user_id: str):
    """
    특정 사용자(user_id)의 최근 신체나이 측정 1건 조회.
    """
    try:
        rows = query_physical_age_assessments(user_id, limit=1)
    except RuntimeError as e:
        raise HTTPException(status_code=500, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Supabase 조회 중 오류: {e}")

    if not rows:
        raise HTTPException(status_code=404, detail="해당 사용자의 신체나이 기록이 없습니다.")

    row = rows[0]
    return PhysicalAgeRecord(
        id=row["id"],
        user_id=row["user_id"],
        measured_at=row["measured_at"],
        grade_index=row.get("grade_index"),
        grade_label=row.get("grade_label"),
        percentile=row.get("percentile"),
        weak_point=row.get("weak_point"),
        avg_quantile=row.get("avg_quantile"),
        lo_age_value=row.get("lo_age_value"),
        lo_age_tier_label=row.get("lo_age_tier_label"),
        detail_quantiles=row.get("detail_quantiles"),
    )


@app.get("/users/{user_id}/physical-age/history", response_model=PhysicalAgeHistoryResponse)
def get_physical_age_history(user_id: str, limit: int = 20):
    """
    특정 사용자(user_id)의 최근 신체나이 측정 히스토리 조회.
    """
    if limit <= 0:
        raise HTTPException(status_code=400, detail="limit 은 1 이상이어야 합니다.")

    try:
        rows = query_physical_age_assessments(user_id, limit=limit)
    except RuntimeError as e:
        raise HTTPException(status_code=500, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Supabase 조회 중 오류: {e}")

    records = [
        PhysicalAgeRecord(
            id=row["id"],
            user_id=row["user_id"],
            measured_at=row["measured_at"],
            grade_index=row.get("grade_index"),
            grade_label=row.get("grade_label"),
            percentile=row.get("percentile"),
            weak_point=row.get("weak_point"),
            avg_quantile=row.get("avg_quantile"),
            lo_age_value=row.get("lo_age_value"),
            lo_age_tier_label=row.get("lo_age_tier_label"),
            detail_quantiles=row.get("detail_quantiles"),
        )
        for row in rows
    ]

    return PhysicalAgeHistoryResponse(
        user_id=user_id,
        records=records,
    )


@app.get("/facilities/near", response_model=List[FacilityOut])
def get_near_facilities(lat: float, lon: float, radius_km: float = 2.0):
    """
    lat/lon 기준 반경 radius_km 이내 공공체육시설 조회
    """
    try:
        df = load_facilities()
        print("[DEBUG] 시설 개수:", len(df))
        print("[DEBUG] lat range:", df["lat"].min(), " ~ ", df["lat"].max())
        print("[DEBUG] lon range:", df["lon"].min(), " ~ ", df["lon"].max())
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    results: List[FacilityOut] = []

    for _, row in df.iterrows():
        d = haversine_km(lat, lon, float(row["lat"]), float(row["lon"]))

        if d <= radius_km:
            category = infer_category(row)
            equip = row.get("detail_equip", "")
            mission = str(equip) if (isinstance(equip, str) and equip.strip() != "") else f"{category} 운동"
            results.append(
                FacilityOut(
                    id=int(row["id"]),
                    name=str(row["name"]),
                    lat=float(row["lat"]),
                    lon=float(row["lon"]),
                    address=str(row["address"]),
                    mission=mission,
                    category=category,
                )
            )

    return results


@app.get("/route")
def get_route(
    start_lat: float,
    start_lon: float,
    end_lat: float,
    end_lon: float,
):
    """
    네이버 Driving Directions API 를 통해
    start -> end까지 도로 기반 경로를 받아와 polyline 좌표만 반환
    (현재 앱에서는 실제 길찾기 UI는 사용하지 않고, 경로 polyline만 사용 가능)
    """
    if not NAVER_CLIENT_ID or not NAVER_CLIENT_SECRET:
        raise HTTPException(status_code=500, detail="NAVER API 키가 설정되어 있지 않습니다.")

    url = "https://maps.apigw.ntruss.com/map-direction/v1/driving"

    # 네이버는 "경도,위도" 순서!
    params = {
        "start": f"{start_lon},{start_lat}",
        "goal": f"{end_lon},{end_lat}",
        "option": "traoptimal",
    }

    headers = {
        "X-NCP-APIGW-API-KEY-ID": NAVER_CLIENT_ID,
        "X-NCP-APIGW-API-KEY": NAVER_CLIENT_SECRET,
    }

    try:
        res = requests.get(url, params=params, headers=headers, timeout=10)
        if res.status_code != 200:
            print("[ERROR] Navermap Directions response:", res.text)
            raise HTTPException(status_code=500, detail="네이버 길찾기 API 오류")

        data = res.json()

        routes = data.get("route", {}).get("traoptimal")
        if not routes:
            raise HTTPException(status_code=404, detail="경로를 찾을 수 없습니다.")

        path = routes[0].get("path", [])  # [[lon, lat], ...]

        return {"path": path}
    except HTTPException:
        raise
    except Exception as e:
        print("[ERROR] Navermap Directions exception:", e)
        raise HTTPException(status_code=500, detail="경로 요청 실패")


@app.get("/recommend/facilities", response_model=List[RecommendedFacility])
def recommend_facilities(
    lat: float,
    lon: float,
    radius_km: float = 2.0,
    weak_point: Optional[str] = None,
):
    """
    위치 + 취약영역(weak_point)을 기준으로 시설 추천.
    """
    try:
        df = load_facilities()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    target_category = None
    if weak_point:
        target_category = weak_point_to_category(weak_point)

    facilities: List[RecommendedFacility] = []

    for _, row in df.iterrows():
        d = haversine_km(lat, lon, row["lat"], row["lon"])
        if d > radius_km:
            continue

        category = infer_category(row)
        equip = row.get("detail_equip", "")
        mission = str(equip) if (isinstance(equip, str) and equip.strip() != "") else f"{category} 운동"

        match = (target_category is not None) and (category == target_category)

        facilities.append(
            RecommendedFacility(
                id=int(row["id"]),
                name=str(row["name"]),
                lat=float(row["lat"]),
                lon=float(row["lon"]),
                address=str(row["address"]),
                mission=mission,
                category=category,
                distance_km=round(d, 3),
                match_category=match
            )
        )

    facilities.sort(key=lambda f: (not f.match_category, f.distance_km))

    return facilities


# =========================================
# 7. 이지팟 즐겨찾기 & 미션 완료 API
# =========================================
class FavoriteToggleRequest(BaseModel):
    user_id: str          # auth.users.id (uuid)
    facility_id: int      # facilities.id
    is_favorite: bool     # true면 추가, false면 제거


class MissionCompleteRequest(BaseModel):
    user_id: str          # auth.users.id
    facility_id: int      # facilities.id
    mission_id: Optional[str] = None   # ✅ 없으면 None 으로 처리
    status: str = "completed"          # "started" / "arrived" / "completed"
    started_at: Optional[datetime] = None
    arrived_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    is_favorite: bool = False          # 완료 시 즐겨찾기 표시 여부(선택)


@app.post("/favorites/toggle")
def toggle_favorite(req: FavoriteToggleRequest):
    """
    즐겨찾기 ON/OFF 토글
    - is_favorite=True  → favorite_facilities 에 upsert(단순 insert, PK 충돌 시 무시)
    - is_favorite=False → favorite_facilities 에서 delete
    """
    if not SUPABASE_URL or not SUPABASE_SERVICE_ROLE_KEY:
        raise HTTPException(status_code=500, detail="Supabase 환경변수가 설정되지 않았습니다.")

    table = "favorite_facilities"

    if req.is_favorite:
        # ✅ 즐겨찾기 추가
        url = _sb_table_url(table)
        payload = {
            "user_id": req.user_id,
            "facility_id": req.facility_id,
        }
        try:
            r = requests.post(url, headers=_sb_json_headers(), json=payload, timeout=5)
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"즐겨찾기 추가 요청 실패: {e}")

        if r.status_code not in (200, 201, 204):
            raise HTTPException(
                status_code=500,
                detail=f"즐겨찾기 추가 실패: {r.status_code} {r.text}",
            )
        return {"status": "ok", "is_favorite": True}

    else:
        # ❌ 즐겨찾기 해제
        url = (
            _sb_table_url(table)
            + f"?user_id=eq.{req.user_id}&facility_id=eq.{req.facility_id}"
        )
        try:
            r = requests.delete(url, headers=_sb_json_headers(), timeout=5)
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"즐겨찾기 삭제 요청 실패: {e}")

        if r.status_code not in (200, 204):
            raise HTTPException(
                status_code=500,
                detail=f"즐겨찾기 삭제 실패: {r.status_code} {r.text}",
            )
        return {"status": "ok", "is_favorite": False}


@app.get("/favorites/by-user", response_model=List[FacilityOut])
def get_favorite_facilities(user_id: str):
    """
    특정 유저의 즐겨찾기 이지팟 리스트
    - favorite_facilities(user_id, facility_id) + facilities 캐시 DataFrame 활용
    """
    if not SUPABASE_URL or not SUPABASE_SERVICE_ROLE_KEY:
        raise HTTPException(status_code=500, detail="Supabase 환경변수가 설정되지 않았습니다.")

    # 1) favorite_facilities 에서 facility_id 리스트 조회
    fav_url = (
        _sb_table_url("favorite_facilities")
        + f"?user_id=eq.{user_id}&select=facility_id"
    )
    try:
        r = requests.get(fav_url, headers=_sb_json_headers(), timeout=5)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"즐겨찾기 조회 실패: {e}")

    if r.status_code != 200:
        raise HTTPException(
            status_code=500,
            detail=f"즐겨찾기 조회 실패: {r.status_code} {r.text}",
        )

    rows = r.json()
    facility_ids = [row["facility_id"] for row in rows]
    if not facility_ids:
        return []

    # 2) 캐시된 facilities DataFrame 에서 해당 id들만 필터링
    try:
        df = load_facilities()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    df_sel = df[df["id"].isin(facility_ids)]

    results: List[FacilityOut] = []
    for _, row in df_sel.iterrows():
        category = infer_category(row)
        equip = row.get("detail_equip", "")
        mission = str(equip) if (isinstance(equip, str) and equip.strip() != "") else f"{category} 운동"
        results.append(
            FacilityOut(
                id=int(row["id"]),
                name=str(row["name"]),
                lat=float(row["lat"]),
                lon=float(row["lon"]),
                address=str(row["address"]),
                mission=mission,
                category=category,
            )
        )

    return results


@app.post("/mission/complete")
def complete_mission(req: MissionCompleteRequest):
    """
    미션 완료(또는 진행 상태) 기록 저장용 엔드포인트
    - mission_logs 테이블에 1행 insert
    """
    if not SUPABASE_URL or not SUPABASE_SERVICE_ROLE_KEY:
        raise HTTPException(status_code=500, detail="Supabase 환경변수가 설정되지 않았습니다.")

    url = _sb_table_url("mission_logs")

    # ✅ mission_id 는 일단 빼고 기본 필드만 넣기
    payload = {
        "user_id": req.user_id,
        "facility_id": req.facility_id,
        "status": req.status,
        "is_favorite": req.is_favorite,
    }

    # ✅ mission_id 가 넘어온 경우에만 넣기
    if req.mission_id is not None:
        payload["mission_id"] = req.mission_id

    if req.started_at is not None:
        payload["started_at"] = req.started_at.isoformat()
    if req.arrived_at is not None:
        payload["arrived_at"] = req.arrived_at.isoformat()
    if req.completed_at is not None:
        payload["completed_at"] = req.completed_at.isoformat()

    try:
        r = requests.post(
            url,
            headers=_sb_json_headers(prefer_return=True),
            json=payload,
            timeout=5,
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"미션 로그 저장 요청 실패: {e}")

    if r.status_code not in (200, 201):
        raise HTTPException(
            status_code=500,
            detail=f"미션 로그 저장 실패: {r.status_code} {r.text}",
        )

    return {"status": "ok", "data": r.json()}



# =========================================
# 8. 로컬 실행용
# =========================================
if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
