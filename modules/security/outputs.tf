output "app_sg_id" {
  value = aws_security_group.app.id
}

output "db_sg_id" {
  value = aws_security_group.db.id
}

output "vpce_sg_id" {
  value = aws_security_group.vpce.id
}

output "instance_profile_name" {
  value = aws_iam_instance_profile.app.name
}

output "app_role_name" {
  value = aws_iam_role.app_instance.name
}

output "proxy_sg_id" {
  value = aws_security_group.proxy.id
}
