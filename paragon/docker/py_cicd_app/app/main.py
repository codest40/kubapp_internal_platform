import logging

from fastapi import FastAPI, HTTPException, status

from app.config import settings
from app.models import Note, NoteResponse
from app.service import NoteService

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title=settings.app_name,
    version=settings.app_version,
)

note_service = NoteService()


@app.get("/health")
def health_check() -> dict[str, str]:
    """Return the application health status."""
    return {"status": "ok"}


@app.post(
    "/notes",
    response_model=NoteResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_note(note: Note) -> NoteResponse:
    """Create a new note."""
    logger.info("Creating note")

    try:
        created_note = note_service.create_note(note)
    except ValueError as exc:
        logger.warning("Unable to create note: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from exc

    return created_note


@app.get("/notes/{note_id}", response_model=NoteResponse)
def get_note(note_id: int) -> NoteResponse:
    """Retrieve a note by ID."""
    note = note_service.get_note(note_id)

    if note is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Note not found",
        )

    return note

