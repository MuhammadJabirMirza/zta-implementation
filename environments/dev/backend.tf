# Fill in the bucket name printed by the bootstrap step, then:
#   terraform init
terraform {
  backend "s3" {
    bucket         = "REPLACE-WITH-YOUR-STATE-BUCKET"
    key            = "dev/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "zt-rds-tflock"
    encrypt        = true
  }
}
