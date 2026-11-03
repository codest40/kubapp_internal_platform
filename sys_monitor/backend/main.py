from contextlib import asynccontextmanager
import uvicorn
from fastapi import FastAPI, status
from fastapi.middleware.cors import CORSMiddleware
from services.app_monitor import get_application_status
from services.database_monitor import get_database_status
from config import settings


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Application startup
    yield
    # Application shutdown


app = FastAPI(
    title=settings.app_name,
    version=settings.app_version,
    debug=settings.debug,
    lifespan=lifespan,
)


app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/", tags=["System"])
async def root():
    return {
        "service": settings.app_name,
        "version": settings.app_version,
        "status": "healthy",
    }


@app.get(
    "/health",
    tags=["System"],
    status_code=status.HTTP_200_OK,
)
async def health():
    return {
        "status": "healthy",
        "status_code": status.HTTP_200_OK,
    }

@app.get(
    f"{settings.api_prefix}/applications",
    tags=["Applications"],
)
async def applications():
    return await get_application_status()

@app.get(
    f"{settings.api_prefix}/database",
    tags=["Databases"],
)
async def database_status():
    return await get_database_status()

if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host=settings.host,
        port=settings.port,
        log_level=settings.log_level.lower(),
        reload=settings.debug,
    )
