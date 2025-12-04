from fastapi import APIRouter
router = APIRouter()

@router.get("/ping")
def ping_user():
    return {"message": "user router ok"}
