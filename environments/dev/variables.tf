variable "project" {
  type    = string
  default = "ztrds"
}

variable "evidence_bucket_name" {
  description = "Globally unique, e.g. ztrds-evidence-mjm-2026"
  type        = string
}

variable "deploy_compliance" {
  description = "Deploy Config + CIS + CloudTrail (Day 10-11 only, cost control)"
  type        = bool
  default     = false
}

variable "deploy_proxy" {
  description = "Deploy RDS Proxy (the PEP demonstration) - Day 11 window"
  type        = bool
  default     = false
}

variable "db_name" {
  description = "Initial database schema name"
  type        = string
  default     = "legacyapp"
}

variable "db_username" {
  description = "Master (admin) username for RDS"
  type        = string
  default     = "admin"
}
