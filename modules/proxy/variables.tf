variable "project" {
  type = string
}

variable "vpc_subnet_ids" {
  description = "Private app subnets for the proxy ENIs"
  type        = list(string)
}

variable "proxy_sg_id" {
  description = "Security group for the proxy (app SG works: 3306 within VPC)"
  type        = string
}

variable "db_instance_identifier" {
  type = string
}

variable "db_secret_arn" {
  description = "Secrets Manager ARN holding the RDS master credentials"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key that encrypts the secret"
  type        = string
}

variable "app_role_name" {
  description = "Instance role granted rds-db:connect through the proxy"
  type        = string
}
