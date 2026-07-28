module "security" {
  source   = "../../modules/security"
  project  = var.project
  vpc_id   = module.networking.vpc_id
  vpc_cidr = module.networking.vpc_cidr
}

module "networking" {
  source                     = "../../modules/networking"
  project                    = var.project
  endpoint_security_group_id = module.security.vpce_sg_id
  app_security_group_id      = module.security.app_sg_id
}

module "database" {
  source                = "../../modules/database"
  project               = var.project
  private_db_subnet_ids = module.networking.private_db_subnet_ids
  db_sg_id              = module.security.db_sg_id
  app_role_name         = module.security.app_role_name
  db_name               = var.db_name
  db_username           = var.db_username
}

module "compute" {
  source                = "../../modules/compute"
  project               = var.project
  private_app_subnet_id = module.networking.private_app_subnet_ids[0]
  app_sg_id             = module.security.app_sg_id
  instance_profile_name = module.security.instance_profile_name
  network_ready         = module.networking.s3_prefix_list_id
}

module "compliance" {
  source               = "../../modules/compliance"
  count                = var.deploy_compliance ? 1 : 0
  project              = var.project
  evidence_bucket_name = var.evidence_bucket_name
  access_logs_bucket   = var.access_logs_bucket
}

module "proxy" {
  source                 = "../../modules/proxy"
  count                  = var.deploy_proxy ? 1 : 0
  project                = var.project
  vpc_subnet_ids         = module.networking.private_app_subnet_ids
  proxy_sg_id            = module.security.proxy_sg_id
  db_instance_identifier = module.database.db_instance_identifier
  db_secret_arn          = module.database.master_user_secret_arn
  kms_key_arn            = module.database.kms_key_arn
  app_role_name          = module.security.app_role_name
}

