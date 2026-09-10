variable "aws_region" {
  description = "Região AWS. A conta AWS Academy Learner Lab só permite us-east-1 e us-west-2 (RFC-002)."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Nome do cluster EKS e prefixo dos demais recursos."
  type        = string
  default     = "oficina-mecanica"
}

variable "kubernetes_version" {
  description = "Versão do Kubernetes do control plane EKS."
  type        = string
  default     = "1.31"
}

variable "vpc_cidr" {
  description = "CIDR block da VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDRs das subnets públicas, uma por AZ (NAT Gateway e a NLB, se algum dia se tornar internet-facing)."
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs das subnets privadas, uma por AZ (node group do EKS e a NLB interna)."
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "eks_cluster_role_name" {
  description = "Nome da IAM role pré-criada na conta AWS Academy usada pelo cluster e pelo node group do EKS (RFC-002 §6.1). Não é possível criar IAM roles nesta conta."
  type        = string
  default     = "LabEksClusterRole"
}

variable "node_instance_types" {
  description = "Tipos de instância do node group. Limite da conta AWS Academy: até 'large', 32 vCPU e 9 instâncias por região (RFC-002 §6.2)."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_group_desired_size" {
  description = "Quantidade desejada de nós. 2 nós é suficiente para demonstrar o HPA, que escala pods (1 a 5), não nós."
  type        = number
  default     = 2
}

variable "node_group_min_size" {
  type    = number
  default = 2
}

variable "node_group_max_size" {
  type    = number
  default = 4
}

variable "app_node_port" {
  description = "NodePort do Service da aplicação (k8s/app/21-api-service.yaml no repositório oficina-mecanica-app), alvo da NLB interna."
  type        = number
  default     = 30080
}
