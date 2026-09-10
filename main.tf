# Bootstrap do módulo Terraform de infraestrutura Kubernetes.
#
# Ainda não há provider nem recursos declarados: a nuvem (AWS/GCP/Azure) está
# pendente de decisão em RFC-002, no repositório da aplicação. Este arquivo
# existe só para que `terraform fmt` e `terraform validate` tenham algo
# válido para checar desde o primeiro Pull Request.
#
# Quando a nuvem for decidida, entram aqui (ou em arquivos novos, por
# recurso): bloco de provider com backend remoto (ex.: S3 + DynamoDB lock),
# VPC/subnets, cluster Kubernetes gerenciado (ex.: EKS) com node groups
# escaláveis, add-ons (metrics-server, autoscaler) e Ingress/Load Balancer
# integrado ao API Gateway.

terraform {
  required_version = ">= 1.5"
}
