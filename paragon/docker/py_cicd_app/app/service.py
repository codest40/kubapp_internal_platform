from app.models import Note, NoteResponse


class NoteService:
    def __init__(self) -> None:
        self._notes: dict[int, NoteResponse] = {}
        self._next_id = 1

    def create_note(self, note: Note) -> NoteResponse:
        word = note.word.strip()

        if not word:
            raise ValueError("Note cannot be empty")

        response = NoteResponse(
            id=self._next_id,
            word=word,
        )

        self._notes[self._next_id] = response
        self._next_id += 1

        return response

    def get_note(self, note_id: int) -> NoteResponse | None:
        return self._notes.get(note_id)
