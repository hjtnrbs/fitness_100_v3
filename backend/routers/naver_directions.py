# routers/naver_directions.py
from fastapi import APIRouter, HTTPException, Query
import requests
import os

router = APIRouter(
    prefix="/naver",
    tags=["naver-directions"],
)

NAVER_CLIENT_ID = os.getenv("NAVER_CLIENT_ID")
NAVER_CLIENT_SECRET = os.getenv("NAVER_CLIENT_SECRET")

BASE_URL = "https://maps.apigw.ntruss.com/map-direction/v1/driving"


@router.get("/directions")
def get_directions(
    start: str = Query(..., description="경도,위도 (예: 126.9780,37.5665)"),
    goal: str = Query(..., description="경도,위도 (예: 126.9920,37.5700)"),
    option: str = Query("traoptimal", description="경로 옵션 (traoptimal / trafast / tracomfort 등)"),
):
    """
    네이버 Directions V1 Driving API 프록시 엔드포인트.
    Flutter → (내 서버) → Naver API 구조로 사용.
    """
    if not NAVER_CLIENT_ID or not NAVER_CLIENT_SECRET:
        # .env 안 읽힌 경우
        raise HTTPException(
            status_code=500,
            detail="NAVER_CLIENT_ID / NAVER_CLIENT_SECRET 환경변수가 설정되지 않았습니다.",
        )

    headers = {
        "X-NCP-APIGW-API-KEY-ID": NAVER_CLIENT_ID,
        "X-NCP-APIGW-API-KEY": NAVER_CLIENT_SECRET,
    }

    params = {
        "start": start,
        "goal": goal,
        "option": option,
    }

    try:
        resp = requests.get(BASE_URL, headers=headers, params=params, timeout=5)
    except requests.RequestException as e:
        raise HTTPException(
            status_code=502,
            detail=f"Naver Directions 호출 실패: {e}",
        )

    # 네이버 응답 코드 그대로 체크
    if resp.status_code != 200:
        raise HTTPException(
            status_code=resp.status_code,
            detail=f"Naver API error: {resp.text}",
        )

    data = resp.json()

    # 네이버 JSON 내부 code 체크 (0이 정상)
    if isinstance(data, dict) and data.get("code") != 0:
        # 네이버가 내부 에러코드를 줄 때
        raise HTTPException(
            status_code=400,
            detail={"naver_code": data.get("code"), "naver_message": data.get("message")},
        )

    # 정상일 때 네이버 JSON 그대로 프론트에 전달
    return data
