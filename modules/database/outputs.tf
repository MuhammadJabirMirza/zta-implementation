output "endpoint" {
  value = aws_db_instance.mysql.address
}

output "master_user_secret_arn" {
  value = aws_db_instance.mysql.master_user_secret[0].secret_arn
}

output "db_instance_identifier" {
  value = aws_db_instance.mysql.identifier
}

output "kms_key_arn" {
  value = aws_kms_key.db.arn
}
