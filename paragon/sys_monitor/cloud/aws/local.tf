
locals {

  key_name = (var.cluster_mode == "local"
    ? "${var.key_name}"
    : "sys-monitor-key"
  )

}
