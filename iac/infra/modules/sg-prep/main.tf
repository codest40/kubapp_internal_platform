locals {
  sg_definitions = merge(

    {

      ingress = {
        description = "Network entry point (ingress)"
        workload    = "ingress"

        ingress = [
          {
            from_port   = 80
            to_port     = 80
            protocol    = "tcp"
            cidr_blocks = [var.vpc_cidr]
          },
          {
            from_port   = 443
            to_port     = 443
            protocol    = "tcp"
            cidr_blocks = [var.vpc_cidr]
          }
        ]

        egress = [
          {
            from_port   = 0
            to_port     = 0
            protocol    = "-1"
            cidr_blocks = ["0.0.0.0/0"]
          }
        ]
      }

      ec2_app = {
        description = "For EKS EC2 Node apps"
        workload    = "ec2 nodes"

        ingress = [
          {
            from_port  = var.from_port_ec2_app
            to_port    = var.to_port_ec2_app
            protocol   = "tcp"
            source_sgs = ["ingress"]
          }
        ]

        egress = [
          {
            from_port   = 0
            to_port     = 0
            protocol    = "-1"
            cidr_blocks = ["0.0.0.0/0"]
          }
        ]
      }

      fargate_app = {
        description = "For EKS Fargate workload apps"
        workload    = "Fargaet"

        ingress = [
          {
            from_port  = var.from_port_fargate_app
            to_port    = var.to_port_fargate_app
            protocol   = "tcp"
            source_sgs = ["ingress"]
          }
        ]

        egress = [
          {
            from_port   = 0
            to_port     = 0
            protocol    = "-1"
            cidr_blocks = ["0.0.0.0/0"]
          }
        ]
      }

      db_access = {
        description = "Db access Boundary service"
        workload    = "security"

        ingress = [
          {
            from_port  = var.from_port_db_access
            to_port    = var.to_port_db_access
            protocol   = "tcp"
            source_sgs = ["ec2_app", "fargate_app"]
          }
        ]

        egress = [
          {
            from_port   = 0
            to_port     = 0
            protocol    = "-1"
            cidr_blocks = ["0.0.0.0/0"]
          }
        ]
      }
    },

    var.custom_sg_definitions
  )
}

output "sg_definitions" {
  value = local.sg_definitions
}
