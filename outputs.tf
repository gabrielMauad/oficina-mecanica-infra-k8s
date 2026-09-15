# Contrato consumido pelos demais repositórios via terraform_remote_state. Documentado em detalhe
# no README ("Contrato de outputs"). Não renomeie vpc_id, private_subnet_ids ou
# cluster_security_group_id sem avisar quem mantém oficina-mecanica-infra-db — são consumidos de
# lá em paralelo.

output "vpc_id" {
  description = "Id da VPC default da conta. Consumido por oficina-mecanica-infra-db para o RDS."
  value       = data.aws_vpc.default.id
}

output "private_subnet_ids" {
  description = <<-EOT
    Ids das subnets da VPC default usadas pelo cluster/NLB/VPC Link. Nome mantido por
    compatibilidade com o contrato de oficina-mecanica-infra-db (DB subnet group do RDS), mas
    desde a adoção da VPC default (ver README) estas subnets são públicas, não privadas.
  EOT
  value       = local.subnet_ids
}

output "cluster_security_group_id" {
  description = "Security group compartilhado do cluster/nós EKS. Consumido por oficina-mecanica-infra-db para liberar a porta 5432 a partir dele."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "cluster_name" {
  description = "Nome do cluster EKS."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "Endpoint da API do Kubernetes (control plane EKS)."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "CA (base64) do cluster, necessária para montar o kubeconfig (ex.: aws eks update-kubeconfig ou geração manual)."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "app_load_balancer_arn" {
  description = "ARN da NLB interna que expõe o NodePort da aplicação."
  value       = aws_lb.app.arn
}

output "app_load_balancer_dns_name" {
  description = "DNS name da NLB interna (somente resolvível de dentro da VPC)."
  value       = aws_lb.app.dns_name
}

output "api_gateway_id" {
  description = "Id da HTTP API. Consumido por oficina-mecanica-lambda-auth para criar a integração/rota de autenticação por CPF nesta mesma API."
  value       = aws_apigatewayv2_api.this.id
}

output "api_gateway_execution_arn" {
  description = "Execution ARN da HTTP API. Necessário para a permissão da Lambda (aws_lambda_permission) aceitar invocações vindas deste API Gateway."
  value       = aws_apigatewayv2_api.this.execution_arn
}

output "api_gateway_endpoint" {
  description = "URL pública de invocação da API (stage $default) — entrada única da aplicação."
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "ecr_repository_url" {
  description = "URL do repositório ECR (registry/repositório) para a pipeline de oficina-mecanica-app fazer build e push da imagem."
  value       = aws_ecr_repository.app.repository_url
}

output "ecr_repository_name" {
  description = "Nome do repositório ECR — usado por aws ecr get-login-password / describe-repositories para resolver a URL sem hardcode de conta."
  value       = aws_ecr_repository.app.name
}

output "app_secret_name" {
  description = <<-EOT
    Nome (não o ARN) do secret com os segredos da aplicação (jwt_secret, admin_senha). As
    pipelines lêem por NOME — aws secretsmanager get-secret-value --secret-id <nome> —, nunca pelo
    ARN: o nome é estável entre recriações do ambiente, o ARN não é.
  EOT
  value       = aws_secretsmanager_secret.app.name
}

output "app_secret_arn" {
  description = "ARN do secret da aplicação. Exposto para quem precisar de referência formal (ex.: policy IAM); as pipelines usam app_secret_name, não este valor."
  value       = aws_secretsmanager_secret.app.arn
}
