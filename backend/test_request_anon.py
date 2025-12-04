from dotenv import load_dotenv
from pathlib import Path
import os
import requests

BASE_DIR = Path(__file__).resolve().parent
load_dotenv(dotenv_path=BASE_DIR / ".env")

SUPABASE_URL = os.getenv("SUPABASE_URL")
ANON_KEY = os.getenv("SUPABASE_ANON_KEY")

url = f"{SUPABASE_URL}/rest/v1/physical_age_assessments"

headers = {
    "apikey": ANON_KEY,
    "Authorization": f"Bearer {ANON_KEY}",
    "Content-Type": "application/json",
    "Prefer": "return=representation",
}

payload = {
    "user_id": "1fd95601-f3ac-4cb0-b492-747c0c5b7cc7",
    "sex": "M",
    "lo_age_value": 28,
}

resp = requests.post(url, headers=headers, json=payload)
print("STATUS:", resp.status_code)
print("BODY:", resp.text)
