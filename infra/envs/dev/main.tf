module "network" {
  source = "../../modules/network"

  environment = "dev"
  vpc_cidr    = var.vpc_cidr
}

module "ecs" {
  source = "../../modules/ecs"

  environment      = "dev"
  vpc_id           = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids
  private_subnet_ids = module.network.private_subnet_ids
  ecs_security_group_id = module.network.ecs_security_group_id
}

module "rds" {
  source = "../../modules/rds"

  environment       = "dev"
  vpc_id            = module.network.vpc_id
  private_subnet_ids = module.network.database_subnet_ids
  ecs_security_group_id = module.network.ecs_security_group_id

  deletion_protection = var.deletion_protection
  backup_retention    = var.backup_retention
}
