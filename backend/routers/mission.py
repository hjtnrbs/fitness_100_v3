# backend/routers/mission.py
from fastapi import APIRouter

router = APIRouter()

@router.get("/ping")
def ping_mission():
    return {"message": "mission ok"}
