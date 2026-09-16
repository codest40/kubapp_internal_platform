
module "alerts" {
  count  = var.enable_alerts ? 1 : 0
  source = "./alerts"

}

