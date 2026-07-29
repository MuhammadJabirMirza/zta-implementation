"""
Performance comparison of three authentication paths.

Measures connection establishment time for:
  1. Direct to RDS, password authentication (baseline)
  2. Direct to RDS, IAM token authentication
  3. Via RDS Proxy (the Policy Enforcement Point), IAM token authentication

All three run through SSM port-forwarding tunnels, so the figures include
tunnel latency and compare authentication mechanisms relative to each other.
They are not absolute application performance measurements.

Requires two tunnels open before running:
  RDS   -> localPortNumber=3307
  Proxy -> localPortNumber=3308
"""

import json
import os
import statistics
import time

import boto3
import certifi
import pymysql
from dotenv import load_dotenv

load_dotenv()

REGION = os.getenv("AWS_REGION", "eu-west-2")
RDS_HOST = os.getenv("RDS_ENDPOINT")
PROXY_HOST = os.getenv("PROXY_ENDPOINT")
SECRET_ARN = os.getenv("DB_SECRET_ARN")
RDS_PORT = int(os.getenv("LOCAL_PORT", 3307))
PROXY_PORT = int(os.getenv("PROXY_PORT", 3308))
RUNS = 20

rds = boto3.client("rds", region_name=REGION)
secret = json.loads(
    boto3.client("secretsmanager", region_name=REGION)
    .get_secret_value(SecretId=SECRET_ARN)["SecretString"]
)


def measure(label, port, user, credential_fn, ca_bundle):
    """Open and close RUNS connections, reporting timings in milliseconds."""
    timings = []
    for _ in range(RUNS):
        started = time.perf_counter()
        conn = pymysql.connect(
            host="127.0.0.1",
            port=port,
            user=user,
            password=credential_fn(),
            ssl={"ca": ca_bundle, "check_hostname": False},
        )
        with conn.cursor() as cur:
            cur.execute("SELECT 1")
            cur.fetchone()
        conn.close()
        timings.append((time.perf_counter() - started) * 1000)

    print(
        f"{label:34} mean {statistics.mean(timings):7.1f}  "
        f"median {statistics.median(timings):7.1f}  "
        f"min {min(timings):7.1f}  max {max(timings):7.1f}"
    )
    return timings


def main():
    print(f"Connection establishment time, {RUNS} runs each, milliseconds\n")

    baseline = measure(
        "1. direct, password auth",
        RDS_PORT,
        secret["username"],
        lambda: secret["password"],
        "global-bundle.pem",
    )

    token_direct = measure(
        "2. direct, IAM token auth",
        RDS_PORT,
        "iam_app",
        lambda: rds.generate_db_auth_token(
            DBHostname=RDS_HOST, Port=3306, DBUsername="iam_app"
        ),
        "global-bundle.pem",
    )

    via_proxy = measure(
        "3. via proxy, IAM token auth",
        PROXY_PORT,
        secret["username"],
        lambda: rds.generate_db_auth_token(
            DBHostname=PROXY_HOST, Port=3306, DBUsername=secret["username"]
        ),
        certifi.where(),
    )

    base = statistics.median(baseline)
    print("\nOverhead relative to password authentication, median")
    print(f"  IAM token auth      {statistics.median(token_direct) - base:+7.1f} ms")
    print(f"  IAM token via proxy {statistics.median(via_proxy) - base:+7.1f} ms")


if __name__ == "__main__":
    main()