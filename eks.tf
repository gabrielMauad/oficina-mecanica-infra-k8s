# Cluster EKS declarado com aws_eks_cluster/aws_eks_node_group diretamente, e não com o módulo
# terraform-aws-modules/eks — ver README ("Decisões de desenho") para a justificativa: o módulo
# cria IAM roles por padrão, o que esta conta AWS Academy não permite (RFC-002 §6.1).
#
# Nenhum aws_iam_role neste repositório. As duas roles pré-criadas da conta são referenciadas via
# data source e usadas tanto pelo cluster quanto pelo node group, conforme a documentação da
# Academy (RFC-002 §6.1).

data "aws_iam_role" "eks" {
  name = var.eks_cluster_role_name
}

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = data.aws_iam_role.eks.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)
    endpoint_private_access = true
    endpoint_public_access  = true
  }
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-nodes"
  node_role_arn   = data.aws_iam_role.eks.arn
  subnet_ids      = aws_subnet.private[*].id
  instance_types  = var.node_instance_types

  scaling_config {
    desired_size = var.node_group_desired_size
    min_size     = var.node_group_min_size
    max_size     = var.node_group_max_size
  }

  update_config {
    max_unavailable = 1
  }

  # Terraform ignora o EKS até o node group existir — evita a corrida entre o cluster ficar ACTIVE
  # e o node group começar a se registrar.
  depends_on = [aws_eks_cluster.this]
}

# Add-ons geridos pela AWS. metrics-server é o pré-requisito do HPA já usado em k8s/app/22-api-hpa.yaml
# (repositório oficina-mecanica-app); vpc-cni, kube-proxy e coredns são declarados explicitamente
# para fixar versão em vez de depender da versão self-managed default do EKS.
#
# NÃO VALIDADO SEM APPLY: "metrics-server" como aws_eks_addon é um add-on gerenciado relativamente
# recente da AWS; confirmar no primeiro apply que ele está disponível para a versão do cluster
# nesta conta/região. Se não estiver, o fallback é o helm_release usado na Fase 2 (infra/main.tf
# no repositório da aplicação), que exige configurar o provider kubernetes/helm com as credenciais
# do cluster.
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # coredns roda em pods, que só existem depois do node group
  depends_on = [aws_eks_node_group.this]
}

resource "aws_eks_addon" "metrics_server" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "metrics-server"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.this]
}
