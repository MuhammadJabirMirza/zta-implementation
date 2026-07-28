variable "project" {
  type = string
}

variable "evidence_bucket_name" {
  description = "Globally unique bucket for Config + CloudTrail evidence"
  type        = string
}
variable "access_logs_bucket" {
  description = "Bucket receiving S3 server access logs, created in bootstrap"
  type        = string
}