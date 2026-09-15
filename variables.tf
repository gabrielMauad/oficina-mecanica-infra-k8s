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

variable "eks_cluster_role_name" {
  description = "Nome da IAM role pré-criada na conta AWS Academy usada pelo cluster e pelo node group do EKS (RFC-002 §6.1). Não é possível criar IAM roles nesta conta."
  type        = string
  default     = "LabEksClusterRole"
}

variable "node_instance_types" {
  description = <<-EOT
    Tipos de instância do node group. Limite da conta AWS Academy: até 'large', 32 vCPU e 9
    instâncias por região (RFC-002 §6.2).

    't3.small', não 't3.micro'/'t3.nano': o fator limitante não é CPU, é o limite de pods por nó
    do EKS (derivado do número de ENIs/IPs da instância) — 't3.micro' suporta só 4 pods, e os pods
    de sistema (kube-proxy, coredns, metrics-server, aws-node) já consomem isso. 't3.small' suporta
    11; com 2 nós são ~22 slots, menos ~6 de sistema = ~16 livres, suficiente para o HPA escalar até
    5 réplicas (k8s/app/22-api-hpa.yaml).

    Se o HPA não conseguir escalar até 5 réplicas por falta de memória (não de slots de pod — é o
    limite mais apertado aqui), o próximo degrau é 't3.medium'.
  EOT
  type        = list(string)
  default     = ["t3.small"]
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
  default = 3
}

variable "app_node_port" {
  description = "NodePort do Service da aplicação (k8s/app/21-api-service.yaml no repositório oficina-mecanica-app), alvo da NLB interna."
  type        = number
  default     = 30080
}
