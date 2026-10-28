import os, sys
from dotenv import load_dotenv
load_dotenv()
from wait_for_db import DATABASE_URL
import psycopg2

try:
    conn = psycopg2.connect(add_sslmode(DATABASE_URL))
    conn.close()
    print("[SUCCESS] SSL connection to Render DB works!")
except Exception as e:
    print(f"[FAIL] SSL connection failed: {e}")

