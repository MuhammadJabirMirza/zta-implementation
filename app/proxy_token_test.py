import os, boto3, pymysql, certifi
from dotenv import load_dotenv

load_dotenv()
REGION = os.getenv("AWS_REGION")
PROXY = os.getenv("PROXY_ENDPOINT")
PORT = int(os.getenv("PROXY_PORT", 3308))

token = boto3.client("rds", region_name=REGION).generate_db_auth_token(
    DBHostname=PROXY, Port=3306, DBUsername="admin")

conn = pymysql.connect(host="127.0.0.1", port=PORT, user="admin", password=token,
                       ssl={"ca": certifi.where(), "check_hostname": False})
with conn.cursor() as cur:
    cur.execute("SELECT CURRENT_USER(), VERSION()")
    who, ver = cur.fetchone()
    cur.execute("SHOW STATUS LIKE 'Ssl_cipher'")
    cipher = cur.fetchone()[1]
print(f"VIA PROXY - IAM TOKEN ACCEPTED: {who} | MySQL {ver} | TLS cipher: {cipher}")