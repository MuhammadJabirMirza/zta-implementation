# =============================================================================
# MODULE: compliance  |  Continuous proof that the config stays correct
# =============================================================================
# Security is not a one-time state - it drifts. Someone flips a setting in the
# console, a new resource appears misconfigured. This module WATCHES.
#   - AWS Config      -> records the configuration of every resource over time
#                        and evaluates it against rules. include_global_resource_
#                        types = true so it captures IAM (needed for CIS rules).
#   - CIS conformance  -> a pack of ~40+ Config rules encoding the Center for
#     pack                Internet Security Benchmark. Turns "are we compliant?"
#                        into a measured score you can put in a table.
#   - CloudTrail      -> the audit log: WHO did WHAT, WHEN, from WHERE. With log
#                        file validation on, the log itself is tamper-evident.
#   - GuardDuty       -> ML-based threat detection watching for anomalies
#                        (crypto-mining, credential exfiltration, recon).
#   - Session logging  -> full transcripts of SSM sessions to CloudWatch, so even
#                        legitimate admin access to the data path is recorded.
#
# COST DISCIPLINE: Config bills per rule evaluation. This whole module is behind
#   a deploy_compliance toggle - deploy it, capture evidence, destroy it. Never
#   leave it running overnight. This is itself a documented cost-control method.
#
# ALTERNATIVE: AWS Security Hub aggregates Config + GuardDuty + more into one
#   dashboard and scores against CIS v3.0 - we enable it alongside for the newer
#   benchmark version, since Config packs only reach CIS v1.4.
# =============================================================================

# AWS Config recorder + CIS conformance pack + CloudTrail.
# COST NOTE: Config bills per rule evaluation. Deploy this module,
# capture evidence, then destroy. Do not leave it running overnight.

data "aws_caller_identity" "current" {}

#checkov:skip=CKV_AWS_145:SSE-S3 default encryption applies; a dedicated KMS CMK for evidence adds cost without security benefit in a single-account lab
#checkov:skip=CKV_AWS_144:Cross-region replication out of scope (single-region artefact, cost control)
#checkov:skip=CKV_AWS_18:Access logging omitted - the bucket already receives CloudTrail/Config delivery; server access logs add cost noise
#checkov:skip=CKV2_AWS_62:Event notifications not required for an evidence archive
#tfsec:ignore:aws-s3-encryption-customer-key -- SSE-S3 applied below; CMK waived per register
#tfsec:ignore:aws-s3-enable-bucket-logging -- waived per register
resource "aws_s3_bucket" "evidence" {
  bucket        = var.evidence_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_logging" "evidence" {
  bucket        = aws_s3_bucket.evidence.id
  target_bucket = var.access_logs_bucket
  target_prefix = "evidence-access-logs/"
}

resource "aws_s3_bucket_versioning" "evidence" {
  bucket = aws_s3_bucket.evidence.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "evidence" {
  bucket = aws_s3_bucket.evidence.id
  rule {
    id     = "expire-old-evidence"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "evidence" {
  bucket = aws_s3_bucket.evidence.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # SSE-S3; CMK waived, see .checkov.yaml register
    }
  }
}

resource "aws_s3_bucket_public_access_block" "evidence" {
  bucket                  = aws_s3_bucket.evidence.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "bucket_policy" {
  statement {
    sid       = "AWSConfigBucketCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.evidence.arn]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com", "cloudtrail.amazonaws.com"]
    }
  }

  statement {
    sid       = "AWSConfigWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.evidence.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com", "cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "evidence" {
  bucket = aws_s3_bucket.evidence.id
  policy = data.aws_iam_policy_document.bucket_policy.json
}

# ----- Config recorder -----
data "aws_iam_policy_document" "config_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "config" {
  name               = "${var.project}-config-role"
  assume_role_policy = data.aws_iam_policy_document.config_assume.json
}

resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_config_configuration_recorder" "this" {
  name     = "${var.project}-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true # required for CIS IAM rules
  }
}

resource "aws_config_delivery_channel" "this" {
  name           = "${var.project}-delivery"
  s3_bucket_name = aws_s3_bucket.evidence.bucket
  depends_on     = [aws_config_configuration_recorder.this]
}

resource "aws_config_configuration_recorder_status" "this" {
  name       = aws_config_configuration_recorder.this.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.this]
}

# ----- CIS conformance pack -----
# The CIS template exceeds the PutConformancePack inline body limit
# (~51KB), so it is uploaded to S3 and referenced by URI.
# Day 10: download it into templates/cis-level1.yaml first.
resource "aws_s3_object" "cis_template" {
  bucket = aws_s3_bucket.evidence.id
  key    = "conformance/cis-level1.yaml"
  source = "${path.module}/templates/cis-level1.yaml"
  etag   = filemd5("${path.module}/templates/cis-level1.yaml")
}

resource "aws_config_conformance_pack" "cis" {
  name            = "${var.project}-cis"
  template_s3_uri = "s3://${aws_s3_bucket.evidence.bucket}/${aws_s3_object.cis_template.key}"
  depends_on      = [aws_config_configuration_recorder_status.this, aws_s3_object.cis_template]
}

# ----- CloudTrail -----
#checkov:skip=CKV_AWS_67:Single-region trail by design - the artefact is single-region; multi-region named in Recommendations
#checkov:skip=CKV_AWS_35:Trail KMS CMK omitted for cost; log file validation is enabled instead
#checkov:skip=CKV_AWS_252:SNS notification out of scope for the evidence window
#checkov:skip=CKV2_AWS_10:CloudWatch Logs integration omitted for cost; S3 delivery with validation suffices for evidence
resource "aws_cloudtrail" "this" {
  name                          = "${var.project}-trail"
  s3_bucket_name                = aws_s3_bucket.evidence.bucket
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  depends_on                    = [aws_s3_bucket_policy.evidence]
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.trail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.trail_logs.arn
}

# ----- GuardDuty (30-day free trial covers the sprint) -----
#checkov:skip=CKV2_AWS_3:Standalone account - organisation-level GuardDuty does not apply
resource "aws_guardduty_detector" "this" {
  enable = true
}

# ----- Session Manager content logging (closes the audit limitation) -----

resource "aws_cloudwatch_log_group" "sessions" {
  #checkov:skip=CKV_AWS_158:Default SSE encryption applies; a CMK for a demo session log adds cost without benefit
  name              = "/${var.project}/ssm-sessions"
  retention_in_days = 365
}
resource "aws_cloudwatch_log_group" "trail" {
  #checkov:skip=CKV_AWS_158:Default SSE encryption applies; a dedicated CMK for trail logs adds cost without benefit in a single-account lab
  name              = "/${var.project}/cloudtrail"
  retention_in_days = 365
}

resource "aws_ssm_document" "session_prefs" {
  name            = "SSM-SessionManagerRunShell"
  document_type   = "Session"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Session Manager preferences - transcript logging"
    sessionType   = "Standard_Stream"
    inputs = {
      cloudWatchLogGroupName      = aws_cloudwatch_log_group.sessions.name
      cloudWatchEncryptionEnabled = false
      cloudWatchStreamingEnabled  = true
    }
  })
}
resource "aws_cloudwatch_log_group" "trail" {
  name              = "/${var.project}/cloudtrail"
  retention_in_days = 365
}

resource "aws_iam_role" "trail_logs" {
  name = "${var.project}-cloudtrail-logs-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "trail_logs" {
  name = "${var.project}-cloudtrail-logs"
  role = aws_iam_role.trail_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.trail.arn}:*"
    }]
  })
}