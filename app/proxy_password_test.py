import os, json, boto3, pymysql, certifi
from dotenv import load_dotenv

load_dotenv()
REGION = os.getenv("AWS_REGION")
SECRET = os.getenv("DB_SECRET_ARN")
PORT = int(os.getenv("LOCAL_PORT", 3307))

print("starting password test against proxy...")
secret = json.loads(boto3.client("secretsmanager", region_name=REGION)
                    .get_secret_value(SecretId=SECRET)["SecretString"])
print("secret fetched, user:", secret["username"])

try:
    pymysql.connect(host="127.0.0.1", port=PORT, user=secret["username"],
                    password=secret["password"],
                    ssl={"ca": certifi.where(), "check_hostname": False})
    print("RESULT - UNEXPECTED: valid password was ACCEPTED through the proxy")
except pymysql.err.OperationalError as e:
    print(f"RESULT - VALID PASSWORD REFUSED BY PROXY: {e.args[1][:90]}")
except Exception as e:
    print(f"RESULT - other error: {type(e).__name__}: {e}")