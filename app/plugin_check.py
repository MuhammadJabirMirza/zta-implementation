import os, json, boto3, pymysql
from dotenv import load_dotenv

load_dotenv()
print("cwd:", os.getcwd())
print("bundle:", os.path.isfile("global-bundle.pem"), os.path.getsize("global-bundle.pem") if os.path.isfile("global-bundle.pem") else 0, "bytes")
REGION = os.getenv("AWS_REGION", "eu-west-2")
SECRET = os.getenv("DB_SECRET_ARN")
PORT = int(os.getenv("LOCAL_PORT", 3307))

s = json.loads(boto3.client("secretsmanager", region_name=REGION)
               .get_secret_value(SecretId=SECRET)["SecretString"])

conn = pymysql.connect(host="127.0.0.1", port=PORT, user=s["username"],
                       password=s["password"],
                       ssl={"ca": "global-bundle.pem", "check_hostname": False})

with conn.cursor() as cur:
    cur.execute("SELECT VERSION()")
    print("engine version:", cur.fetchone()[0])
    cur.execute("SELECT user, host, plugin FROM mysql.user WHERE user IN ('admin','iam_app')")
    print(f"{'user':10} {'host':6} plugin")
    for user, host, plugin in cur.fetchall():
        print(f"{user:10} {host:6} {plugin}")
conn.close()