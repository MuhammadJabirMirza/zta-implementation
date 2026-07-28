
terraform {
  backend "s3" {
    bucket       = "zt-rds-tfstate-mjm-2026"
    key          = "dev/terraform.tfstate"
    region       = "eu-west-2"
    use_lockfile = true
    encrypt      = true
  }
}
