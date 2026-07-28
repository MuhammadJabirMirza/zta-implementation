import boto3, pymysql, time, re
from datetime import datetime, timezone, timedelta

HOST = "ztrds-mysql.cjuk2aew42eu.eu-west-2.rds.amazonaws.com"

token = boto3.client("rds", region_name="eu-west-2").generate_db_auth_token(
    DBHostname=HOST, Port=3306, DBUsername="iam_app")

amz = re.search(r"X-Amz-Date=(\d{8}T\d{6}Z)", token).group(1)
claimed = datetime.strptime(amz, "%Y%m%dT%H%M%SZ").replace(tzinfo=timezone.utc)
now_utc = datetime.now(timezone.utc)
print(f"local clock (UTC): {now_utc:%H:%M:%S}   token claims created: {claimed:%H:%M:%S}   skew: {(now_utc-claimed).total_seconds():+.0f}s")
print(f"server-side expiry therefore: {claimed + timedelta(seconds=900):%H:%M:%S} UTC")

t0 = time.time()
while True:
    mins = (time.time() - t0) / 60
    stamp = datetime.now(timezone.utc).strftime("%H:%M:%S")
    try:
        pymysql.connect(host="127.0.0.1", port=3307, user="iam_app", password=token,
                        ssl={"ca": "global-bundle.pem", "check_hostname": False}).close()
        print(f"{stamp} UTC  t+{mins:4.1f}min: ACCEPTED")
    except pymysql.err.OperationalError as e:
        print(f"{stamp} UTC  t+{mins:4.1f}min: REFUSED - {e.args[1][:50]}")
        break
    if mins > 35:
        print("still accepted past 35min - stop, report this"); break
    time.sleep(120)