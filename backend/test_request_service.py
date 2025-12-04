from dotenv import load_dotenv
from pathlib import Path
import os
import uuid
import requests

BASE_DIR = Path(__file__).resolve().parent
load_dotenv(dotenv_path=BASE_DIR / ".env")

SUPABASE_URL = os.getenv("SUPABASE_URL")
SERVICE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY")

url = f"{SUPABASE_URL}/rest/v1/physical_age_assessments"

headers = {
    "apikey": SERVICE_KEY,
    "Authorization": f"Bearer {SERVICE_KEY}",
    "Content-Type": "application/json",
    "Prefer": "return=representation",
}

payload = {
    "user_id": "1fd95601-f3ac-4cb0-b492-747c0c5b7cc7",  # 임시 uuid
    "sex": "M",
    "lo_age_value": 33,
}

resp = requests.post(url, headers=headers, json=payload)
print("STATUS:", resp.status_code)
print("BODY:", resp.text)
