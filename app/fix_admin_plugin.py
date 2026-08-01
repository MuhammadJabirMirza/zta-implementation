import os, json, boto3, pymysql
from dotenv import load_dotenv

load_dotenv()

REGION = os.getenv("AWS_REGION", "eu-west-2")
SECRET = os.getenv("DB_SECRET_ARN")
PORT = int(os.getenv("LOCAL_PORT", 3307))

s = json.loads(boto3.client("secretsmanager", region_name=REGION)
               .get_secret_value(SecretId=SECRET)["SecretString"])

conn = pymysql.connect(host="127.0.0.1", port=PORT, user=s["username"],
                       password=s["password"],
                       ssl={"ca": "global-bundle.pem", "check_hostname": False})

with conn.cursor() as cur:
    cur.execute(
        "ALTER USER 'admin'@'%%' IDENTIFIED WITH caching_sha2_password BY %s",
        (s["password"],)
    )
    cur.execute("FLUSH PRIVILEGES")
    cur.execute("SELECT user, host, plugin FROM mysql.user WHERE user IN ('admin','iam_app')")
    for row in cur.fetchall():
        print(row)
conn.close()
print("done")