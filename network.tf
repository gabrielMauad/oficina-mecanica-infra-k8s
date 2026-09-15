# VPC default da conta, em vez de criar uma nova. A Fase 3 exige EKS com escalabilidade; não exige
# criar VPC. A conta AWS Academy já tem uma VPC default com uma subnet por AZ na região inteira
# (>= 2 AZs em qualquer região AWS), o que satisfaz o requisito do EKS sem provisionar rede própria
# (RFC-002 §6.2 — ver README, "Decisões de desenho").
#
# As subnets da VPC default são públicas (rota direta para o Internet Gateway, IP público
# automático) — os nós do EKS ficam em subnet pública, o que elimina a necessidade de NAT Gateway.
# Isso é deliberado: numa conta de produção real, os nós ficariam em subnet privada com NAT
# Gateway; aqui a escolha troca isolamento de rede por custo e simplicidade, dentro do orçamento
# finito da conta AWS Academy. Os security groups dedicados (loadbalancer.tf, apigateway.tf)
# continuam existindo e são o que efetivamente restringe o tráfego — o SG default da VPC (que
# libera tudo entre seus próprios membros) nunca é usado para isso.

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

locals {
  # Usadas tanto pelo cluster/node group (eks.tf) quanto pela NLB e pela VPC Link do API Gateway
  # (loadbalancer.tf, apigateway.tf). Mantém o nome "subnet_ids" único porque, com a VPC default,
  # não há mais distinção entre subnet pública e privada.
  subnet_ids = data.aws_subnets.default.ids
}
