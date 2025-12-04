# server/routers/auth.py
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, EmailStr
from passlib.hash import bcrypt
from datetime import datetime

router = APIRouter()

# 실제로는 DB 세션 주입해서 써야 함
fake_users = {}  # <- 일단 프론트 연동 테스트용

class SignUpIn(BaseModel):
    nickname: str
    email: EmailStr
    password: str

class LoginIn(BaseModel):
    email: EmailStr
    password: str

@router.post("/signup")
def signup(payload: SignUpIn):
    if payload.email in fake_users:
        raise HTTPException(status_code=400, detail="이미 존재하는 이메일입니다.")
    password_hash = bcrypt.hash(payload.password)
    fake_users[payload.email] = {
        "nickname": payload.nickname,
        "password_hash": password_hash,
        "created_at": datetime.utcnow(),
    }
    return {"ok": True}

@router.post("/login")
def login(payload: LoginIn):
    user = fake_users.get(payload.email)
    if not user or not bcrypt.verify(payload.password, user["password_hash"]):
        raise HTTPException(status_code=401, detail="이메일 또는 비밀번호가 올바르지 않습니다.")
    # 나중에 JWT 토큰으로 교체
    return {"token": "dummy-session-token"}
