# Run this FIRST, once, with local state. It creates the S3 bucket and
# DynamoDB table that hold remote state for the main project.
terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = "eu-west-2"
}

variable "state_bucket_name" {
  description = "Globally unique S3 bucket name, e.g. zt-rds-tfstate-mjm-2026"
  type        = string
}

#tfsec:ignore:aws-s3-enable-bucket-logging -- access logging waived, see .checkov.yaml register
resource "aws_s3_bucket" "tfstate" {
  bucket = var.state_bucket_name
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

#tfsec:ignore:aws-s3-encryption-customer-key -- SSE-KMS with the AWS-managed key; dedicated CMK waived per register
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "lock" {
  name         = "zt-rds-tflock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
  point_in_time_recovery {
    enabled = true
  }
  #tfsec:ignore:aws-dynamodb-table-customer-key -- lock table holds no sensitive data; AWS-managed key suffices
  server_side_encryption {
    enabled = true
  }
}

output "state_bucket" {
  value = aws_s3_bucket.tfstate.bucket
}
