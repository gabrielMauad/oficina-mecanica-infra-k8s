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

variable "eks_availability_zones" {
  description = <<-EOT
    Allowlist de AZs cujas subnets da VPC default (network.tf) são passadas ao cluster/node
    group/NLB/VPC Link. Não é "pegue todas as subnets da VPC default": pelo menos uma AZ comum em
    us-east-1 (historicamente 'us-east-1e') não tem capacidade para o control plane do EKS em
    várias contas AWS — o apply falha com UnsupportedAvailabilityZoneException só na criação do
    cluster. Restringir também reduz custo: a NLB (loadbalancer.tf) cobra por AZ.

    Se var.aws_region mudar para 'us-west-2' (a outra região permitida pela conta AWS Academy,
    RFC-002), esta lista precisa mudar junto — os nomes de AZ são específicos da região.
  EOT
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "eks_cluster_role_name" {
  description = <<-EOT
    Nome da IAM role pré-criada na conta AWS Academy usada pelo cluster e pelo node group do EKS
    (RFC-002 §6.1). Não é possível criar IAM roles nesta conta.

    A lista oficial de serviços da AWS Academy indica que o EKS assume a role
    "LabEksClusterRole created for Cluster and Node", mas essa role não existe na conta usada
    neste projeto: o terraform plan falhou com
    "reading IAM Role (LabEksClusterRole): couldn't find resource". A checagem com
    `aws iam list-roles` mostrou que a única role "Lab*" disponível na conta é `LabRole` — a mesma
    indicada na orientação em aula. O default abaixo foi ajustado para `LabRole` e validado com
    plan e apply reais.

    Numa conta AWS Academy onde `LabEksClusterRole` exista, basta sobrescrever esta variável com
    o nome dela.
  EOT
  type        = string
  default     = "LabRole"
}

variable "node_instance_types" {
  description = <<-EOT
    Tipos de instância do node group. Limite da conta AWS Academy: até 'large', 32 vCPU e 9
    instâncias por região (RFC-002 §6.2).

    't3.medium' (2 vCPU, 4 GiB): o fator limitante é o limite de pods por nó do EKS (derivado do
    número de ENIs/IPs da instância) e a memória. 't3.medium' suporta 17 pods por nó. Conta de
    pods com 3 nós: 51 slots, menos os pods de sistema (aws-node e kube-proxy em cada nó, coredns,
    metrics-server) e os do 'nri-bundle' (New Relic), sobram bem mais que os 15 pods que os 5
    serviços ocupam no pico (HPA com máximo de 3 réplicas por serviço). Em memória, 15 réplicas
    com request de 256Mi somam 3,75 GiB, distribuídos entre 3 nós de 4 GiB; em CPU, 15 × 100m =
    1,5 vCPU de 6 vCPU.
  EOT
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_group_desired_size" {
  description = "Quantidade desejada de nós. 3 nós acomodam os 5 serviços com as réplicas do HPA (1 a 3 por serviço) mais os pods de sistema e o nri-bundle; ver node_instance_types."
  type        = number
  default     = 3
}

variable "node_group_min_size" {
  description = "Mínimo de nós do node group."
  type        = number
  default     = 2
}

variable "node_group_max_size" {
  description = "Máximo de nós do node group (a conta permite até 9 instâncias e 32 vCPU)."
  type        = number
  default     = 4
}

variable "servicos" {
  description = <<-EOT
    Mapa serviço -> NodePort do Service do serviço no cluster. É a fonte única da qual derivam,
    via for_each, o repositório ECR (oficina-mecanica-<serviço>), o listener e o target group da
    NLB (listener TCP na mesma porta do NodePort), as integrações do API Gateway e as regras de
    security group (faixa de portas = menor e maior NodePort do mapa). A chave é também o nome do
    Deployment/Service no namespace oficina-mecanica e o prefixo da rota técnica
    /<serviço>/{proxy+} do API Gateway.
  EOT
  type        = map(number)
  default = {
    "ordens-servico" = 30080
    autenticacao     = 30081
    cadastro         = 30082
    "pecas-insumos"  = 30083
    pagamento        = 30084
  }

  validation {
    condition     = length(distinct(values(var.servicos))) == length(var.servicos)
    error_message = "Cada serviço precisa de um NodePort distinto."
  }

  validation {
    condition     = alltrue([for porta in values(var.servicos) : porta >= 30000 && porta <= 32767])
    error_message = "NodePorts do Kubernetes ficam na faixa 30000-32767."
  }

  validation {
    condition     = contains(keys(var.servicos), "ordens-servico")
    error_message = "O serviço ordens-servico é o destino da rota padrão (ANY /{proxy+}) e precisa existir no mapa."
  }
}
