#!/bin/bash
# Port-forward to the private RDS instance through SSM. No SSH involved.
# Usage: ./connect-db.sh <instance-id> <rds-endpoint>
INSTANCE_ID=$1
RDS_ENDPOINT=$2
aws ssm start-session \
  --target "$INSTANCE_ID" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"$RDS_ENDPOINT\"],\"portNumber\":[\"3306\"],\"localPortNumber\":[\"3306\"]}" \
  --region eu-west-2
