"""Zero-trust connectivity demonstrator (proposal Objective 3).

Proves two access paths to the private RDS MySQL instance, both over
enforced TLS, run from the operator workstation through the SSM tunnel:

  1. Managed-secret auth: password fetched at runtime from AWS Secrets
     Manager (never stored on disk or in code).
  2. IAM database authentication: a short-lived (15 min) signed token
     replaces the password entirely - the zero-trust ephemeral
     credential model.

Usage:
  python db_check.py secret <secret_arn>
  python db_check.py iam <rds_endpoint>
Requires the SSM port-forward tunnel on 127.0.0.1:3306 and the RDS CA
bundle saved as global-bundle.pem in this directory.
"""
import json
import sys

import boto3
import pymysql

REGION = "eu-west-2"
LOCAL_HOST, LOCAL_PORT = "127.0.0.1", 3306
CA_BUNDLE = "global-bundle.pem"


def connect(user: str, password: str) -> None:
    conn = pymysql.connect(
        host=LOCAL_HOST,
        port=LOCAL_PORT,
        user=user,
        password=password,
        ssl={"ca": CA_BUNDLE},  # TLS enforced server-side too
    )
    with conn.cursor() as cur:
        cur.execute("SELECT CURRENT_USER(), VERSION()")
        who, version = cur.fetchone()
        cur.execute("SHOW STATUS LIKE 'Ssl_cipher'")
        cipher = cur.fetchone()
    conn.close()
    print(f"connected as {who} | MySQL {version} | TLS cipher: {cipher[1]}")


def main() -> None:
    mode = sys.argv[1]
    if mode == "secret":
        sm = boto3.client("secretsmanager", region_name=REGION)
        secret = json.loads(
            sm.get_secret_value(SecretId=sys.argv[2])["SecretString"]
        )
        connect("admin", secret["password"])
    elif mode == "iam":
        rds = boto3.client("rds", region_name=REGION)
        token = rds.generate_db_auth_token(
            DBHostname=sys.argv[2], Port=3306, DBUsername="iam_app"
        )
        connect("iam_app", token)
    else:
        raise SystemExit("mode must be: secret | iam")


if __name__ == "__main__":
    main()
