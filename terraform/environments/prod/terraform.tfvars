# ─── Preencher antes do primeiro apply ────────────────────────────────────────
aws_region  = "us-east-1"
project     = "togglemaster"
environment = "prod"

# GitHub — substituir pelo seu org/usuário e nome do repo
github_org  = "SEU_GITHUB_ORG"
github_repo = "toggle-master-fase3"

# Networking
vpc_cidr             = "10.10.0.0/16"
public_subnet_cidrs  = ["10.10.1.0/24", "10.10.2.0/24"]
private_subnet_cidrs = ["10.10.10.0/24", "10.10.11.0/24"]
availability_zones   = ["us-east-1a", "us-east-1b"]

# EKS
eks_cluster_version    = "1.29"
eks_node_instance_type = "t3.medium"
eks_node_desired       = 2
eks_node_min           = 1
eks_node_max           = 4

# RDS
rds_instance_class = "db.t3.micro"
rds_username       = "postgres"
