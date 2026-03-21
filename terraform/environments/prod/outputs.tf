output "vpc_id" {
  value = module.networking.vpc_id
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "ecr_repositories" {
  value = module.ecr.repository_urls
}

output "rds_endpoints" {
  value     = { for db in module.rds.db_instances : db.name => db.endpoint }
  sensitive = true
}

output "redis_endpoint" {
  value     = module.elasticache.redis_endpoint
  sensitive = true
}

output "sqs_queue_url" {
  value = module.sqs.queue_url
}

output "dynamodb_table_name" {
  value = module.dynamodb.table_name
}

output "github_actions_role_arn" {
  description = "ARN da role usada pelo GitHub Actions (adicionar como secret GHA_ROLE_ARN)"
  value       = module.iam_oidc.github_actions_role_arn
}

output "argocd_server_ip" {
  description = "IP do LoadBalancer do ArgoCD (pode demorar alguns minutos)"
  value       = try(helm_release.argocd.status, "pending")
}

output "kubeconfig_command" {
  description = "Comando para atualizar kubeconfig localmente"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}
