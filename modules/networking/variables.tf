variable "project" {
  description = "Project name used for tagging"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones (two required)"
  type        = list(string)
  default     = ["eu-west-2a", "eu-west-2b"]
}

variable "enable_ssm_endpoints" {
  description = "Create VPC interface endpoints for SSM (true zero-trust, ~$0.03/hr while running)"
  type        = bool
  default     = true
}

variable "endpoint_security_group_id" {
  description = "Security group allowing HTTPS from app subnets to the SSM endpoints"
  type        = string
}

variable "app_security_group_id" {
  description = "App SG id - receives the S3 gateway-endpoint egress rule"
  type        = string
}
