# VPC default da conta, em vez de criar uma nova. A Fase 3 exige EKS com escalabilidade; não exige
# criar VPC. A conta AWS Academy já tem uma VPC default com uma subnet por AZ na região inteira
# (RFC-002 §6.2 — ver README, "Decisões de desenho").
#
# As subnets da VPC default são públicas (rota direta para o Internet Gateway, IP público
# automático) — os nós do EKS ficam em subnet pública, o que elimina a necessidade de NAT Gateway.
# Isso é deliberado: numa conta de produção real, os nós ficariam em subnet privada com NAT
# Gateway; aqui a escolha troca isolamento de rede por custo e simplicidade, dentro do orçamento
# finito da conta AWS Academy. Os security groups dedicados (loadbalancer.tf, apigateway.tf)
# continuam existindo e são o que efetivamente restringe o tráfego — o SG default da VPC (que
# libera tudo entre seus próprios membros) nunca é usado para isso.
#
# NÃO basta "qualquer região tem >= 2 AZs": a quantidade está certa, a elegibilidade não. Várias
# contas AWS têm pelo menos uma AZ sem capacidade para o control plane do EKS (o caso documentado
# mais comum em us-east-1 é a AZ "us-east-1e") — o apply falha com
# "UnsupportedAvailabilityZoneException" só na hora de criar o cluster, sem aviso em validate/plan.
# Por isso as subnets não são usadas todas: var.eks_availability_zones restringe explicitamente a
# um allowlist de AZs elegíveis. Efeito colateral bom: a NLB (loadbalancer.tf) cobra por AZ em que
# tem subnet — restringir a 2-3 em vez de todas as 6 da região também reduz custo.

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_subnet" "default" {
  for_each = toset(data.aws_subnets.default.ids)
  id       = each.value
}

locals {
  # Usadas tanto pelo cluster/node group (eks.tf) quanto pela NLB e pela VPC Link do API Gateway
  # (loadbalancer.tf, apigateway.tf). Mantém o nome "subnet_ids" único porque, com a VPC default,
  # não há mais distinção entre subnet pública e privada.
  eligible_subnets = [
    for s in data.aws_subnet.default : s
    if contains(var.eks_availability_zones, s.availability_zone)
  ]
  subnet_ids = [for s in local.eligible_subnets : s.id]
}

# A validação de que sobram >= 2 AZs elegíveis fica como lifecycle.precondition em
# aws_eks_cluster.this (eks.tf), não como `check` block: `check` só produz warning — não bloqueia
# plan nem apply — e roda depois do Terraform já ter tentado provisionar. `precondition` é avaliado
# antes de criar o recurso e falha o plan de verdade.
