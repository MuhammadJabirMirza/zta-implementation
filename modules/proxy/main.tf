# =============================================================================
# MODULE: proxy  |  The Policy Enforcement Point, made real
# =============================================================================
# In NIST zero-trust theory (SP 800-207) every access request passes through a
# Policy Enforcement Point (PEP) that checks it against a Policy Decision Point
# (PDP). RDS Proxy is that PEP for the database, in concrete form:
#   - require_tls = true     -> refuses any unencrypted connection.
#   - iam_auth = REQUIRED     -> the ONLY way through is a short-lived IAM token.
#                               A password will not work even if offered.
#   - It authenticates to the DB using the Secrets Manager secret, so the app
#     never holds database credentials at all - it holds an IAM identity.
#   - It pools connections, so per-request verification scales (the practical
#     objection to zero trust - "verifying every request is slow" - is answered
#     by pooling).
#   Clients connect to the PROXY endpoint and never see the database endpoint.
#
# WHY THIS MATTERS FOR THE DISSERTATION: it converts a control you CLAIM in the
# Background chapter (RDS Proxy = PEP) into one you DEMONSTRATE. That is the
# difference between a literature review and an artefact.
#
# ALTERNATIVE PEPs: an API gateway or a service mesh (Istio) plays the same role
# at the application layer. RDS Proxy is the data-layer PEP. Name the others to
# show you understand the pattern generalises.
# =============================================================================

# Amazon RDS Proxy - the concrete Policy Enforcement Point (PEP) that the
# dissertation Background chapter maps to NIST SP 800-207. The proxy:
#   - authenticates every connection against Secrets Manager / IAM,
#   - enforces TLS (require_tls = true),
#   - pools connections so per-session verification scales,
#   - never exposes the database endpoint to clients.
# Cost: billed per vCPU-hour of the target instance while running.
# Deploy for the demo window, capture evidence, destroy.

data "aws_iam_policy_document" "proxy_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "proxy" {
  name               = "${var.project}-rds-proxy-role"
  assume_role_policy = data.aws_iam_policy_document.proxy_assume.json
}

data "aws_iam_policy_document" "proxy_secrets" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.db_secret_arn]
  }
  statement {
    actions   = ["kms:Decrypt"]
    resources = [var.kms_key_arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.eu-west-2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "proxy_secrets" {
  name   = "${var.project}-proxy-secrets"
  role   = aws_iam_role.proxy.id
  policy = data.aws_iam_policy_document.proxy_secrets.json
}

resource "aws_db_proxy" "this" {
  name                   = "${var.project}-proxy"
  engine_family          = "MYSQL"
  role_arn               = aws_iam_role.proxy.arn
  vpc_subnet_ids         = var.vpc_subnet_ids
  vpc_security_group_ids = [var.proxy_sg_id]
  require_tls            = true
  idle_client_timeout    = 900
  debug_logging          = false

  auth {
    auth_scheme = "SECRETS"
    iam_auth    = "REQUIRED" # zero-trust: token-only through the proxy
    secret_arn  = var.db_secret_arn
  }
}

resource "aws_db_proxy_default_target_group" "this" {
  db_proxy_name = aws_db_proxy.this.name

  connection_pool_config {
    max_connections_percent = 100
  }
}

resource "aws_db_proxy_target" "db" {
  db_proxy_name          = aws_db_proxy.this.name
  target_group_name      = aws_db_proxy_default_target_group.this.name
  db_instance_identifier = var.db_instance_identifier
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role_policy" "iam_db_auth_via_proxy" {
  name = "${var.project}-proxy-iam-connect"
  role = var.app_role_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "rds-db:connect"
      Resource = "arn:aws:rds-db:eu-west-2:${data.aws_caller_identity.current.account_id}:dbuser:${element(split(":", aws_db_proxy.this.arn), 6)}/iam_app"
    }]
  })
}
