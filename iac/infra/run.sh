#!/bin/bash

arg="${1:-plan}"
SYS_MONITOR_ENABLED="$(./helpers/check_sys_monitor.sh)" || SYS_MONITOR_ENABLED="false"

if [[ "$arg" == "plan" ]]; then
terraform plan \
  -var="sys_monitor_enabled=$SYS_MONITOR_ENABLED"
elif [[ "$arg" == "apply" ]]; then
terraform apply --auto-approve \
  -var="sys_monitor_enabled=$SYS_MONITOR_ENABLED"
elif [[ "$arg" == "destroy" ]]; then
terraform destroy --auto-approve \
  -var="sys_monitor_enabled=$SYS_MONITOR_ENABLED"
else
  echo "ERROR: INVALID ARG $arg"
  exit 1
fi
