# Infraestrutura Kubernetes (Amazon EKS) compartilhada pelos serviços — ver README para o desenho
# completo e RFC-002 (repositório oficina-mecanica-app) para o contexto e as restrições da conta AWS
# Academy Learner Lab que moldam este código.
#
# Os recursos estão organizados por arquivo:
#   backend.tf      - configuração parcial do backend remoto (S3)
#   providers.tf     - provider AWS
#   variables.tf     - inputs
#   network.tf       - data sources da VPC default da conta e suas subnets (nenhuma rede é criada)
#   eks.tf           - cluster EKS, node group e o add-on metrics-server (roles pré-criadas da Academy)
#   loadbalancer.tf  - NLB interna, com um listener + target group (NodePort) por serviço
#   apigateway.tf    - HTTP API + VPC Link, com integrações e rotas por serviço
#   ecr.tf           - um repositório de imagens (ECR) por serviço
#   secrets.tf       - segredo da aplicação no Secrets Manager (JWT, senha admin, credenciais do mock do Mercado Pago)
#   outputs.tf       - contrato consumido pelos demais repositórios

terraform {
  required_version = ">= 1.5"
}
