import time
import threading
from flask import Flask
from prometheus_client import generate_latest, CONTENT_TYPE_LATEST

from collector import collect_metrics

app = Flask(__name__)


@app.route("/")
def home():
    return "GitOps Exporter Running", 200


@app.route("/metrics")
def metrics():
    return generate_latest(), 200, {
        "Content-Type": CONTENT_TYPE_LATEST
    }



def worker_loop():
    while True:
        collect_metrics()
        time.sleep(30)


if __name__ == "__main__":
    thread = threading.Thread(target=worker_loop, daemon=True)
    thread.start()

    app.run(host="0.0.0.0", port=9105)

