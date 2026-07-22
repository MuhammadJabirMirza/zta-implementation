output "rds_endpoint" {
  value = module.database.endpoint
}

output "db_secret_arn" {
  value = module.database.master_user_secret_arn
}

output "app_instance_id" {
  value = module.compute.instance_id
}

output "proxy_endpoint" {
  value = var.deploy_proxy ? module.proxy[0].proxy_endpoint : null
}
