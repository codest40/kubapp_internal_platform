from kubernetes import client
import boto3
import os
import base64
import threading
import tempfile
import subprocess
import json
import time


class K8sClientFactory:
    """
    Production-hardened EKS Kubernetes client factory.

    Improvements:
    - exponential backoff on failures
    - RBAC/IAM diagnostics
    - token caching with TTL
    - failure state circuit breaker
    """

    _lock = threading.Lock()

    _api_client = None
    _custom = None
    _core = None

    # ---------------- TOKEN CACHE ----------------
    _cached_token = None
    _token_expiry = 0

    # ---------------- FAILURE CONTROL ----------------
    _failure_count = 0
    _last_failure_time = 0
    _circuit_open_until = 0

    # =========================================================
    # LOGGING
    # =========================================================
    @classmethod
    def _log(cls, msg):
        print(f"[GitOps DEBUG] {msg}")

    # =========================================================
    # ENV
    # =========================================================
    @classmethod
    def _env(cls):
        return {
            "mode": os.getenv("CLUSTER_MODE", "local"),
            "cluster_name": os.getenv("TARGET_CLUSTER_NAME", "kubapp-dev"),
            "region": os.getenv("TARGET_REGION", "us-east-1"),
            "role_arn": os.getenv("TARGET_ROLE_ARN", ""),
            "debug": os.getenv("ENABLE_NODE_DEBUG", "false").lower()
        }

    # =========================================================
    # CIRCUIT BREAKER (ANTI 403 LOOP)
    # =========================================================
    @classmethod
    def _is_circuit_open(cls):
        return time.time() < cls._circuit_open_until

    @classmethod
    def _register_failure(cls, reason):
        cls._failure_count += 1
        cls._last_failure_time = time.time()

        # exponential backoff: 10s → 30s → 60s → 120s (cap 5 min)
        delay = min(300, 10 * (2 ** (cls._failure_count - 1)))

        cls._circuit_open_until = time.time() + delay

        cls._log(f"[FAILURE] {reason}")
        cls._log(f"[FAILURE] Circuit opened for {delay}s")

    @classmethod
    def _reset_failures(cls):
        cls._failure_count = 0
        cls._circuit_open_until = 0

    # =========================================================
    # AWS SESSION
    # =========================================================
    @classmethod
    def _session(cls):
        env = cls._env()

        if env["mode"] == "local":
            session = boto3.Session(region_name=env["region"])
            identity = session.client("sts").get_caller_identity()
            cls._log(f"LOCAL identity: {identity['Arn']}")
            return session

        if not env["role_arn"]:
            raise Exception("TARGET_ROLE_ARN missing in cross mode")

        base = boto3.Session(region_name=env["region"])
        sts = base.client("sts")

        cls._log(f"Base identity: {sts.get_caller_identity()['Arn']}")
        cls._log(f"Assuming role: {env['role_arn']}")

        assumed = sts.assume_role(
            RoleArn=env["role_arn"],
            RoleSessionName="sys-monitor-session"
        )["Credentials"]

        session = boto3.Session(
            aws_access_key_id=assumed["AccessKeyId"],
            aws_secret_access_key=assumed["SecretAccessKey"],
            aws_session_token=assumed["SessionToken"],
            region_name=env["region"]
        )

        cls._log(
            f"Assumed identity: {session.client('sts').get_caller_identity()['Arn']}"
        )

        return session

    # =========================================================
    # CLUSTER INFO
    # =========================================================
    @classmethod
    def _cluster(cls, session):
        env = cls._env()

        eks = session.client("eks", region_name=env["region"])
        c = eks.describe_cluster(name=env["cluster_name"])["cluster"]

        cls._log(f"EKS endpoint: {c['endpoint']}")

        return {
            "endpoint": c["endpoint"],
            "ca": c["certificateAuthority"]["data"]
        }

    # =========================================================
    # TOKEN CACHE (15 min safe TTL)
    # =========================================================
    @classmethod
    def _token(cls):
        env = cls._env()
        now = time.time()

        if cls._cached_token and now < cls._token_expiry:
            cls._log("Using cached EKS token")
            return cls._cached_token

        cmd = [
            "aws", "eks", "get-token",
            "--cluster-name", env["cluster_name"],
            "--region", env["region"]
        ]

        if env["mode"] == "cross":
            cmd += ["--role-arn", env["role_arn"]]

        cls._log("Generating new EKS token")

        out = subprocess.check_output(cmd, stderr=subprocess.STDOUT)
        token = json.loads(out)["status"]["token"]

        # EKS tokens ~15 min → cache for 12 min safe window
        cls._cached_token = token
        cls._token_expiry = now + 720

        return token

    # =========================================================
    # CLIENT BUILD
    # =========================================================
    @classmethod
    def _build(cls):
        if cls._is_circuit_open():
            cls._log("Circuit open → skipping Kubernetes build")
            return

        env = cls._env()
        session = cls._session()
        info = cls._cluster(session)
        token = cls._token()

        configuration = client.Configuration()
        configuration.host = info["endpoint"]
        configuration.verify_ssl = True

        ca = base64.b64decode(info["ca"])
        ca_file = tempfile.NamedTemporaryFile(delete=False)
        ca_file.write(ca)
        ca_file.flush()

        configuration.ssl_ca_cert = ca_file.name

        # proper auth
        configuration.api_key = {"authorization": token}

        api_client = client.ApiClient(configuration)
        api_client.set_default_header("Authorization", f"Bearer {token}")

        cls._api_client = api_client
        cls._custom = client.CustomObjectsApi(api_client)
        cls._core = client.CoreV1Api(api_client)

        cls._log("Kubernetes clients initialized")

        # ---------------- RBAC DIAGNOSTIC ----------------
        try:
            nodes = cls._core.list_node()
            cls._log(f"RBAC OK → nodes={len(nodes.items)}")
            cls._reset_failures()

        except Exception as e:
            cls._log(f"[RBAC FAILURE] {e}")

            # identity diagnostics (VERY IMPORTANT)
            try:
                identity = session.client("sts").get_caller_identity()
                cls._log(f"AWS identity at failure: {identity['Arn']}")
            except:
                pass

            cls._register_failure(str(e))
            raise

    # =========================================================
    # PUBLIC
    # =========================================================
    @classmethod
    def get_clients(cls):
        if cls._api_client:
            return {"custom": cls._custom, "core": cls._core}

        with cls._lock:
            if not cls._api_client:
                cls._log("Building Kubernetes clients")
                cls._build()

        return {"custom": cls._custom, "core": cls._core}
