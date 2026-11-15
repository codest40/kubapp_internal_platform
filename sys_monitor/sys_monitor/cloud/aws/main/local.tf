data "aws_iam_role" "sys_monitor" {
  name = "sys-monitor-ec2-role"
}

locals {
  eks_account_id = var.kubapp_account_id

  domain_name  = data.terraform_remote_state.kubapp_infra.outputs.domain
  cluster_name = data.terraform_remote_state.kubapp_infra.outputs.cluster_name

}

data "http" "public_ip" {
  count = var.access_mode == "ssh" ? 1 : 0
  url   = "https://ifconfig.me/ip"
}

locals {
  public_ip = (
    var.access_mode == "ssh"
    ? chomp(data.http.public_ip[0].response_body)
    : null
  )
}

