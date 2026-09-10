# Infraestrutura Kubernetes (Amazon EKS) da Fase 3 — ver README para o desenho completo e
# RFC-002 (repositório oficina-mecanica-app) para o contexto e as restrições da conta AWS
# Academy Learner Lab que moldam este código.
#
# Os recursos estão organizados por arquivo:
#   backend.tf      - configuração parcial do backend remoto (S3)
#   providers.tf     - provider AWS
#   variables.tf     - inputs
#   network.tf       - VPC, subnets públicas/privadas, IGW, NAT
#   eks.tf           - cluster EKS, node group e add-ons (roles pré-criadas da Academy)
#   loadbalancer.tf  - NLB interna + target group (NodePort) que expõe a aplicação na VPC
#   apigateway.tf    - HTTP API + VPC Link, integrando o API Gateway à NLB
#   outputs.tf       - contrato consumido pelos demais repositórios

terraform {
  required_version = ">= 1.5"
}
