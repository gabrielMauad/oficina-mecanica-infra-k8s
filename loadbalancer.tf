# Caminho de exposição escolhido: Network Load Balancer interna, com um listener TCP por serviço
# na mesma porta do NodePort do Service (var.servicos) e um target group tipo "instance" para cada
# NodePort — e o API Gateway integra por VPC Link (apigateway.tf). Ver README ("Decisões de
# desenho") para a comparação com AWS Load Balancer Controller + Ingress e por que ele foi
# descartado (exige IRSA, que exige um IAM role — inviável nesta conta).
#
# Esta NLB é gerenciada 100% pelo Terraform, não pelo Kubernetes: o alvo é o Auto Scaling Group
# criado pelo node group do EKS, via aws_autoscaling_attachment. Isso evita a dependência circular
# de uma NLB provisionada pelo controller do Kubernetes (cujo ARN só existiria depois do deploy
# dos serviços) e não exige nenhuma mudança nos Services — eles continuam NodePort.
#
# É interna (sem IP público): quem expõe os serviços à internet é o API Gateway; a NLB só precisa
# ser alcançável de dentro da VPC — pela VPC Link (API Gateway) e pela Lambda de autenticação por
# CPF, que roda na VPC e chama o serviço de cadastro direto na NLB, na porta do listener dele.

locals {
  # Faixa contígua que cobre todos os NodePorts de var.servicos. As regras de security group
  # abaixo usam a faixa inteira (30080-30084 por padrão) em vez de uma regra por serviço.
  node_port_min = min(values(var.servicos)...)
  node_port_max = max(values(var.servicos)...)
}

resource "aws_security_group" "nlb" {
  name = "${var.cluster_name}-nlb"
  # GroupDescription so aceita ASCII (exigencia da API da AWS) - nao reintroduzir acentos aqui.
  description = "NLB interna que expoe os NodePorts dos servicos ao API Gateway via VPC Link"
  vpc_id      = data.aws_vpc.default.id

  tags = {
    Name = "${var.cluster_name}-nlb"
  }
}

resource "aws_vpc_security_group_ingress_rule" "nlb_from_vpc" {
  security_group_id = aws_security_group.nlb.id
  description       = "Trafego dos listeners de dentro da VPC (VPC Link do API Gateway e Lambda)"
  cidr_ipv4         = data.aws_vpc.default.cidr_block
  from_port         = local.node_port_min
  to_port           = local.node_port_max
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "nlb_to_nodeport" {
  security_group_id = aws_security_group.nlb.id
  description       = "Saida para os NodePorts dos nos do EKS"
  cidr_ipv4         = data.aws_vpc.default.cidr_block
  from_port         = local.node_port_min
  to_port           = local.node_port_max
  ip_protocol       = "tcp"
}

# Libera, no security group compartilhado do cluster/nós, a entrada vinda da NLB nos NodePorts dos
# serviços. cluster_security_group_id é o mesmo SG exportado em outputs.tf para o repositório do
# banco liberar o acesso ao PostgreSQL a partir dele.
resource "aws_vpc_security_group_ingress_rule" "nodeport_from_nlb" {
  security_group_id            = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  description                  = "NodePorts dos servicos, a partir da NLB interna"
  referenced_security_group_id = aws_security_group.nlb.id
  from_port                    = local.node_port_min
  to_port                      = local.node_port_max
  ip_protocol                  = "tcp"
}

resource "aws_lb" "app" {
  name               = "${var.cluster_name}-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = local.subnet_ids
  security_groups    = [aws_security_group.nlb.id]

  tags = {
    Name = "${var.cluster_name}-nlb"
  }
}

resource "aws_lb_target_group" "servico" {
  for_each = var.servicos

  # Nome de target group tem no máximo 32 caracteres: "oficina-mecanica-ordens-servico" tem 31.
  name        = "${var.cluster_name}-${each.key}"
  port        = each.value
  protocol    = "TCP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "instance"

  health_check {
    protocol = "HTTP"
    # /healthz/live, não /healthz: é a liveness pura do serviço (sem os checks de dependências,
    # como o PostgreSQL) — mesma distinção usada nas probes dos Deployments. Um banco fora do ar
    # não deve tirar todos os nós do target group; quem sinaliza indisponibilidade de dependência
    # é a resposta do serviço, não a NLB.
    path                = "/healthz/live"
    port                = tostring(each.value)
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 10
  }

  tags = {
    Name = "${var.cluster_name}-${each.key}"
  }
}

resource "aws_lb_listener" "servico" {
  for_each = var.servicos

  load_balancer_arn = aws_lb.app.arn
  port              = each.value
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.servico[each.key].arn
  }
}

# Registra automaticamente os nós do node group (via seu Auto Scaling Group) em cada target group
# — nós que entram/saem por scaling são adicionados/removidos sem intervenção manual.
resource "aws_autoscaling_attachment" "servico" {
  for_each = var.servicos

  autoscaling_group_name = aws_eks_node_group.this.resources[0].autoscaling_groups[0].name
  lb_target_group_arn    = aws_lb_target_group.servico[each.key].arn
}
