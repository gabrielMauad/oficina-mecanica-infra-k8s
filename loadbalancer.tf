# Caminho de exposição escolhido: Network Load Balancer interna, com target group tipo
# "instance" apontando para o NodePort do Service da aplicação (k8s/app/21-api-service.yaml no
# repositório oficina-mecanica-app, hoje NodePort 30080) — e o API Gateway integra por VPC Link
# (apigateway.tf). Ver README ("Decisões de desenho") para a comparação com AWS Load Balancer
# Controller + Ingress e por que ele foi descartado (exige IRSA, que exige um IAM role — inviável
# nesta conta).
#
# Esta NLB é gerenciada 100% pelo Terraform, não pelo Kubernetes: o alvo é o Auto Scaling Group
# criado pelo node group do EKS, via aws_autoscaling_attachment. Isso evita a dependência circular
# de uma NLB provisionada pelo controller do Kubernetes (cujo ARN só existiria depois do deploy da
# aplicação) e não exige nenhuma mudança no Service da aplicação — ele continua NodePort.
#
# É interna (sem IP público): quem expõe a aplicação à internet é o API Gateway; a NLB só precisa
# ser alcançável a partir das subnets privadas pela VPC Link.

resource "aws_security_group" "nlb" {
  name        = "${var.cluster_name}-nlb"
  description = "NLB interna que expõe o NodePort da aplicação ao API Gateway via VPC Link"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.cluster_name}-nlb"
  }
}

resource "aws_vpc_security_group_ingress_rule" "nlb_from_vpc" {
  security_group_id = aws_security_group.nlb.id
  description       = "Trafego HTTP de dentro da VPC (VPC Link do API Gateway)"
  cidr_ipv4         = aws_vpc.this.cidr_block
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "nlb_to_nodeport" {
  security_group_id = aws_security_group.nlb.id
  description       = "Saida para o NodePort dos nos do EKS"
  cidr_ipv4         = aws_vpc.this.cidr_block
  from_port         = var.app_node_port
  to_port           = var.app_node_port
  ip_protocol       = "tcp"
}

# Libera, no security group compartilhado do cluster/nós, a entrada vinda da NLB no NodePort da
# aplicação. cluster_security_group_id é o mesmo SG exportado em outputs.tf para o repositório do
# banco liberar 5432 a partir dele.
resource "aws_vpc_security_group_ingress_rule" "nodeport_from_nlb" {
  security_group_id            = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  description                  = "NodePort da aplicacao, a partir da NLB interna"
  referenced_security_group_id = aws_security_group.nlb.id
  from_port                    = var.app_node_port
  to_port                      = var.app_node_port
  ip_protocol                  = "tcp"
}

resource "aws_lb" "app" {
  name               = "${var.cluster_name}-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = aws_subnet.private[*].id
  security_groups    = [aws_security_group.nlb.id]

  tags = {
    Name = "${var.cluster_name}-nlb"
  }
}

resource "aws_lb_target_group" "app" {
  name        = "${var.cluster_name}-app"
  port        = var.app_node_port
  protocol    = "TCP"
  vpc_id      = aws_vpc.this.id
  target_type = "instance"

  health_check {
    protocol            = "HTTP"
    path                = "/healthz"
    port                = tostring(var.app_node_port)
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 10
  }

  tags = {
    Name = "${var.cluster_name}-app"
  }
}

resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# Registra automaticamente os nós do node group (via seu Auto Scaling Group) no target group —
# nós que entram/saem por scaling são adicionados/removidos sem intervenção manual.
resource "aws_autoscaling_attachment" "app" {
  autoscaling_group_name = aws_eks_node_group.this.resources[0].autoscaling_groups[0].name
  lb_target_group_arn    = aws_lb_target_group.app.arn
}
