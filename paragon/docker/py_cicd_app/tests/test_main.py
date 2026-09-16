import unittest

from fastapi.testclient import TestClient

from app.main import app


class TestNotesAPI(unittest.TestCase):
    def setUp(self) -> None:
        self.client = TestClient(app)

    def test_health_check(self) -> None:
        response = self.client.get("/health")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"status": "ok"})

    def test_create_note(self) -> None:
        response = self.client.post(
            "/notes",
            json={"word": "hello"},
        )

        self.assertEqual(response.status_code, 201)

        data = response.json()

        self.assertEqual(data["word"], "hello")
        self.assertIn("id", data)

    def test_create_empty_note(self) -> None:
        response = self.client.post(
            "/notes",
            json={"word": ""},
        )

        self.assertEqual(response.status_code, 422)

    def test_get_missing_note(self) -> None:
        response = self.client.get("/notes/999999")

        self.assertEqual(response.status_code, 404)


if __name__ == "__main__":
    unittest.main()
