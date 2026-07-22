variable "project" {
  type = string
}

variable "private_db_subnet_ids" {
  type = list(string)
}

variable "db_sg_id" {
  type = string
}

variable "db_name" {
  type    = string
  default = "legacyapp"
}

variable "db_username" {
  type    = string
  default = "admin"
}

variable "multi_az" {
  description = "Multi-AZ deployment (Well-Architected aligned; ~2x instance-hours cost)"
  type        = bool
  default     = true
}
