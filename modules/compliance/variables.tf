variable "project" {
  type = string
}

variable "evidence_bucket_name" {
  description = "Globally unique bucket for Config + CloudTrail evidence"
  type        = string
}
