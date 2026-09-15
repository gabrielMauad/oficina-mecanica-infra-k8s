# Infraestrutura Kubernetes (Amazon EKS) da Fase 3 — ver README para o desenho completo e
# RFC-002 (repositório oficina-mecanica-app) para o contexto e as restrições da conta AWS
# Academy Learner Lab que moldam este código.
#
# Os recursos estão organizados por arquivo:
#   backend.tf      - configuração parcial do backend remoto (S3)
#   providers.tf     - provider AWS
#   variables.tf     - inputs
#   network.tf       - data sources da VPC default da conta e suas subnets (nenhuma rede é criada)
#   eks.tf           - cluster EKS, node group e o add-on metrics-server (roles pré-criadas da Academy)
#   loadbalancer.tf  - NLB interna + target group (NodePort) que expõe a aplicação na VPC
#   apigateway.tf    - HTTP API + VPC Link, integrando o API Gateway à NLB
#   ecr.tf           - repositório de imagens da aplicação (ECR)
#   secrets.tf       - segredo da aplicação no Secrets Manager (JWT compartilhado + senha admin)
#   outputs.tf       - contrato consumido pelos demais repositórios

terraform {
  required_version = ">= 1.5"
}
