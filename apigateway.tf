# HTTP API (API Gateway v2) como porta de entrada única da aplicação (RFC-001 §1). Rotea para a
# aplicação via VPC Link -> NLB interna (loadbalancer.tf). A rota de autenticação por CPF
# (RFC-001 §4.2, POST para a Lambda) NÃO é criada aqui: a Lambda vive em
# oficina-mecanica-lambda-auth, que integra a própria rota a esta API usando os outputs
# api_gateway_id e api_gateway_execution_arn (ver README, "Contrato de outputs").

resource "aws_security_group" "vpc_link" {
  name        = "${var.cluster_name}-vpc-link"
  description = "ENIs da VPC Link do API Gateway"
  vpc_id      = data.aws_vpc.default.id

  tags = {
    Name = "${var.cluster_name}-vpc-link"
  }
}

resource "aws_vpc_security_group_egress_rule" "vpc_link_to_nlb" {
  security_group_id            = aws_security_group.vpc_link.id
  description                  = "Saida para a NLB interna da aplicacao"
  referenced_security_group_id = aws_security_group.nlb.id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "nlb_from_vpc_link" {
  security_group_id            = aws_security_group.nlb.id
  description                  = "Trafego do API Gateway via VPC Link"
  referenced_security_group_id = aws_security_group.vpc_link.id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
}

resource "aws_apigatewayv2_vpc_link" "this" {
  name               = "${var.cluster_name}-vpc-link"
  subnet_ids         = local.subnet_ids
  security_group_ids = [aws_security_group.vpc_link.id]
}

resource "aws_apigatewayv2_api" "this" {
  name          = "${var.cluster_name}-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "app" {
  api_id             = aws_apigatewayv2_api.this.id
  integration_type   = "HTTP_PROXY"
  integration_uri    = aws_lb_listener.app.arn
  integration_method = "ANY"
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.this.id
}

# Rota catch-all: a própria aplicação decide autenticação/autorização por rota (RFC-001 §4.2), o
# API Gateway aqui só roteia e faz o meio de campo de rede via VPC Link.
resource "aws_apigatewayv2_route" "app" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.app.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true
}
