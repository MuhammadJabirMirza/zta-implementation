import os, json, boto3, pymysql
from dotenv import load_dotenv

load_dotenv()
s = json.loads(boto3.client("secretsmanager", region_name=os.getenv("AWS_REGION"))
               .get_secret_value(SecretId=os.getenv("DB_SECRET_ARN"))["SecretString"])

conn = pymysql.connect(host="127.0.0.1", port=int(os.getenv("LOCAL_PORT", 3307)),
                       user=s["username"], password=s["password"],
                       ssl={"ca": "global-bundle.pem", "check_hostname": False})

with conn.cursor() as cur:
    cur.execute("SELECT table_name, definer FROM information_schema.views WHERE table_schema='employees'")
    print("views before:", cur.fetchall())
    cur.execute("DROP VIEW IF EXISTS employees.current_dept_emp")
    cur.execute("DROP VIEW IF EXISTS employees.dept_emp_latest_date")
    cur.execute("SELECT table_name FROM information_schema.views WHERE table_schema='employees'")
    print("views after:", cur.fetchall())
conn.commit()
conn.close()
print("done")