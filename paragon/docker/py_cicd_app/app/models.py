from pydantic import BaseModel, Field


class Note(BaseModel):
    """Input model for creating a note."""

    word: str = Field(min_length=1, max_length=200)


class NoteResponse(BaseModel):
    """Response model for a stored note."""

    id: int
    word: str
