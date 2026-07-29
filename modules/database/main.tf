# =============================================================================
# MODULE: database  |  The asset everything else exists to protect
# =============================================================================
# THE DEFENCE-IN-DEPTH STACK ON THIS ONE RESOURCE (outside-in):
#   1. Network       - private subnets, publicly_accessible = false (two
#                      independent controls: no route, and no public endpoint).
#   2. Firewall      - db SG accepts 3306 from the app SG only.
#   3. TLS in transit- require_secure_transport = 1 in the parameter group makes
#                      the SERVER reject any unencrypted session. Not client-
#                      dependent - enforced database-side.
#   4. Authentication- three layers: (a) master password generated and stored by
#                      AWS in Secrets Manager via manage_master_user_password, so
#                      it is NEVER in code or Terraform state; (b) IAM database
#                      authentication for a passwordless user using 15-minute
#                      signed tokens; (c) via the proxy, IAM auth REQUIRED.
#   5. Encryption at rest - storage_encrypted with a CUSTOMER-MANAGED KMS key
#                      (not the AWS default) so you control the key policy, see
#                      every decrypt in CloudTrail, and can revoke. A stolen
#                      snapshot is useless ciphertext.
#   6. Availability  - multi_az gives a synchronous standby with automatic
#                      failover. Availability is the forgotten third of the CIA
#                      triad; this is how you evidence it.
#
# WHY manage_master_user_password INSTEAD OF A TERRAFORM VARIABLE
#   If you write the password as a variable, it lands in terraform.tfstate in
#   PLAINTEXT. Anyone with the state file has your database. Letting AWS generate
#   and hold it in Secrets Manager removes the secret from your pipeline entirely
#   - this is the single most common IaC security failure, and avoiding it is a
#   deliberate, defensible design point.
#
# ALTERNATIVES / TRADE-OFFS TO CITE
#   - Aurora MySQL instead of RDS MySQL: better performance and failover, higher
#     cost. The production upgrade path - name it in Recommendations.
#   - RDS default (AWS-managed) KMS key: simpler, but no key-policy control and
#     no cross-account revocation. We chose customer-managed deliberately.
#   - Single-AZ: half the cost. We pay for Multi-AZ because availability is a
#     stated objective and it gives us a failover test to evidence.
# =============================================================================

# Encrypted, private, zero-trust RDS MySQL.
# - Customer-managed KMS key with rotation (CIS-aligned)
# - manage_master_user_password: the password lives in Secrets Manager,
#   never in Terraform state, never in tfvars
# - publicly_accessible = false and DB subnets have no internet route
# - IAM database authentication enabled as a second zero-trust control

#checkov:skip=CKV2_AWS_64:Default key policy (account root) is appropriate for a single-account lab; scoped policy named in Recommendations
resource "aws_kms_key" "db" {
  description         = "${var.project} RDS encryption key"
  enable_key_rotation = true
}

resource "aws_kms_alias" "db" {
  name          = "alias/${var.project}-db"
  target_key_id = aws_kms_key.db.key_id
}

# Proposal commitment: TLS enforced in transit via the parameter group.
resource "aws_db_parameter_group" "mysql" {
  name   = "${var.project}-mysql8"
  family = "mysql8.0"

  parameter {
    name  = "require_secure_transport"
    value = "1"
  }
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.project}-db-subnets"
  subnet_ids = var.private_db_subnet_ids
  tags       = { Name = "${var.project}-db-subnets" }
}

resource "aws_db_instance" "mysql" {
  identifier     = "${var.project}-mysql"
  engine         = "mysql"
  engine_version = "8.0"
  instance_class = "db.t3.micro" # Free Tier

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true
  kms_key_id        = aws_kms_key.db.arn

  db_name  = var.db_name
  username = var.db_username

  # Master password generated and stored by AWS in Secrets Manager.
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.db.arn

  db_subnet_group_name   = aws_db_subnet_group.this.name
  parameter_group_name   = aws_db_parameter_group.mysql.name
  vpc_security_group_ids = [var.db_sg_id]
  publicly_accessible    = false
  multi_az               = var.multi_az

  iam_database_authentication_enabled = true

  backup_retention_period         = 7
  copy_tags_to_snapshot           = true
  auto_minor_version_upgrade      = true
  enabled_cloudwatch_logs_exports = ["error", "slowquery"]
  #checkov:skip=CKV_AWS_293:Deletion protection off by design - the artefact is destroyed after each evidence window (cost control, documented in Methodology)
  #checkov:skip=CKV_AWS_118:Enhanced monitoring omitted for cost; named in Recommendations for production
  skip_final_snapshot = true # dissertation environment only
  deletion_protection = false

  tags = { Name = "${var.project}-mysql" }
}

# Proposal commitment: IAM database authentication demonstrated, least-privilege.
# Grants rds-db:connect for ONE database user (iam_app) on THIS instance only.
variable "app_role_name" {
  description = "IAM role of the app instance, granted rds-db:connect"
  type        = string
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role_policy" "iam_db_auth" {
  name = "${var.project}-rds-iam-connect"
  role = var.app_role_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "rds-db:connect"
      Resource = "arn:aws:rds-db:eu-west-2:${data.aws_caller_identity.current.account_id}:dbuser:${aws_db_instance.mysql.resource_id}/iam_app"
    }]
  })
}
