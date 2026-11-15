from flask import Flask
from routes.github import github_bp
from prometheus_client import generate_latest, CONTENT_TYPE_LATEST

app = Flask(__name__)

app.register_blueprint(github_bp)


@app.route("/")
def home():
    return "GitHub Exporter Running", 200


@app.route("/metrics")
def metrics():
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=3000)
