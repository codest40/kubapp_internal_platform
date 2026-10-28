data "terraform_remote_state" "database" {
  count = var.allow_kubapp_read_db_state && var.enable_db_cross_account ? 1 : 0

  backend = "s3"
  config = {
    bucket = var.database_state_bucket
    key    = var.database_state_key
    region = var.region

    #profile = "kubapp-reads-db-state-role"
    assume_role = {
      role_arn = var.db_lets_kubapp_read_state_arn
    }
  }
}

