-- Run once against RDS (through the tunnel, as admin) to enable the
-- IAM-authenticated database user. No password exists for this user:
-- authentication is a signed 15-minute IAM token.
CREATE USER IF NOT EXISTS iam_app@% IDENTIFIED WITH AWSAuthenticationPlugin AS RDS;
GRANT SELECT ON legacyapp.* TO iam_app@%;
FLUSH PRIVILEGES;
