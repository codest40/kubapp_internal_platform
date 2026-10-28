# main.py
from fastapi import FastAPI, Request, Form, Depends
from fastapi.templating import Jinja2Templates
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi_utils.tasks import repeat_every
from sre.metrics_service import cpu_percent, memory_percent, disk_percent
from sqlalchemy.orm import Session
import requests
import os
import time
import psutil

import crud, models, schemas
from db import get_db
from sre.system_health import router as system_router
from sre.health import router as health_router
from sre.metrics import router as metrics_router
from sre.metrics_service import (
    weather_requests_total,
    preferences_saved_total,
    failed_weather_requests_total,
    request_latency_seconds,
    active_users
)
from sre.prometheus import PrometheusMiddleware

app = FastAPI()

# ---------------- Routers ----------------
app.include_router(system_router)
app.include_router(health_router)
app.include_router(metrics_router)

# ---------------- Middleware ----------------
app.add_middleware(PrometheusMiddleware)

# ---------------- Static + templates ----------------
app.mount("/static", StaticFiles(directory="static"), name="static")
templates = Jinja2Templates(directory="templates")

API_KEY = os.environ.get("OPENWEATHER_API_KEY")
if not API_KEY:
    raise RuntimeError("OPENWEATHER_API_KEY is missing in container env!")

# ---------------- Routes ----------------
@app.get("/", response_class=HTMLResponse)
async def read_root(request: Request):
    return templates.TemplateResponse("index.html", {"request": request, "weather": None})

@app.get("/health")
async def health_test():
    return {"status": "ok", "code": 200}

@app.get("/live")
async def health_test():
    return {"status": "ok", "code": 200}

@app.get("/ready")
async def health_test():
    return {"status": "ok", "code": 200}

@app.get("/metrics")
async def health_test():
    return {"status": "Succesful Edgepass!", "code": 200}

@app.post("/weather", response_class=HTMLResponse)
async def get_weather(request: Request, city: str = Form(...)):
    start = time.time()
    try:
        url = f"https://api.openweathermap.org/data/2.5/weather?q={city}&appid={API_KEY}&units=metric"
        resp = requests.get(url).json()

        # Ensure the failed_weather_requests_total metric has the right labels
        status_code = resp.get("cod", 500)
        if isinstance(status_code, int):
            status_code_str = str(status_code)
        else:
            status_code_str = status_code

        if status_code != 200:
            # increment failed requests metric safely
            if "labels" in dir(failed_weather_requests_total):
                failed_weather_requests_total.labels(status_code=status_code_str).inc()
            weather_info = {"city": city, "temperature": "N/A", "description": "City not found"}
        else:
            weather_info = {
                "city": city,
                "temperature": resp["main"]["temp"],
                "description": resp["weather"][0]["description"],
            }

        # increment total weather requests metric safely
        if "labels" in dir(weather_requests_total):
            weather_requests_total.labels(status_code=status_code_str).inc()

        return templates.TemplateResponse("index.html", {"request": request, "weather": weather_info})

    finally:
        request_latency_seconds.labels(endpoint="/weather").observe(time.time() - start)


@app.get("/preferences", response_class=HTMLResponse)
async def read_preferences(request: Request):
    return templates.TemplateResponse("preferences.html", {"request": request})


@app.post("/preferences")
async def save_preferences(
    name: str = Form(...),
    email: str = Form(...),
    city: str = Form(...),
    alert_type: str = Form(...),
    db: Session = Depends(get_db),
):
    preferences_saved_total.inc()
    active_users.inc()  # Increment active users

    user = db.query(models.WeatherUser).filter(models.WeatherUser.email == email).first()
    if not user:
        user_in = schemas.UserCreate(name=name, email=email)
        user = crud.create_user(db, user_in)

    pref_in = schemas.PreferenceCreate(user_id=user.id, city=city, alert_type=alert_type)
    crud.create_preference(db, pref_in)
    crud.create_preference(db, pref_in)

    return JSONResponse({"message": "Preferences saved!", "user_id": user.id})


@app.get("/preferences/{user_id}")
async def get_user_preferences(user_id: int, db: Session = Depends(get_db)):
    prefs = crud.get_preferences_by_user(db, user_id)
    return [schemas.PreferenceOut.from_orm(p) for p in prefs]

@app.on_event("startup")
@repeat_every(seconds=5)
def update_system_metrics():
    cpu_percent.set(psutil.cpu_percent())
    mem = psutil.virtual_memory()
    memory_percent.set(mem.percent)
    disk_percent.set(psutil.disk_usage("/tmp").percent)

