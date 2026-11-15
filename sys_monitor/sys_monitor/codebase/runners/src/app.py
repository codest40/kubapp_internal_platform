from flask import Flask, Response, jsonify
import os

METRICS_FILE = os.getenv("METRICS_FILE", "../../evidence/metrics.prom")

app = Flask(__name__)
if METRICS_FILE:
  print(f"Metrics file: {METRICS_FILE}")
  print(f"Exists: {os.path.exists(METRICS_FILE)}")
else:
  print("❌ Metrics File Not Found!")

@app.route("/")
def dashboard():
    return """
    <html>
        <head>
            <title>KubApp SysMonitor[Codebase]</title>
            <style>
                body {
                    font-family: Arial;
                    background: #0f172a;
                    color: #e2e8f0;
                    padding: 40px;
                }
                .box {
                    background: #1e293b;
                    padding: 20px;
                    border-radius: 10px;
                    margin-bottom: 20px;
                }
                h1 { color: #38bdf8; }
                a { color: #60a5fa; }
            </style>
        </head>

        <body>
            <h1> KubApp SysMonitor CodebBase </h1>

            <div class="box">
                <h2>Status</h2>
                <p>System is running</p>
            </div>

            <div class="box">
                <h2>Endpoints</h2>
                <ul>
                    <li><a href="/health">/health</a></li>
                    <li><a href="/metrics">/metrics</a></li>
                </ul>
            </div>
        </body>
    </html>
    """

@app.route("/health")
def health():
    return jsonify({
        "status": "ok",
        "service": "kubapp-sysmonitor [codebase]"
    }), 200

# PROMETHEUS METRICS
@app.route("/metrics")
def metrics():
    try:
        with open(METRICS_FILE) as f:
            data = f.read()

        return Response(data, mimetype="text/plain")

    except Exception as e:
        return Response(
            f"# error reading metrics: {str(e)}\n",
            mimetype="text/plain",
            status=500
        )

if __name__ == "__main__":
    app.run(
        host="0.0.0.0",
        port=8080
    )
