#!/bin/bash
# Fetch the RDS master password from Secrets Manager.
# Usage: ./get-db-password.sh <secret-arn>
aws secretsmanager get-secret-value \
  --secret-id "$1" \
  --query SecretString --output text --region eu-west-2 | python3 -c "import sys,json;print(json.load(sys.stdin)[\"password\"])"
