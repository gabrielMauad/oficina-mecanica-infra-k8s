# HTTP API (API Gateway v2) como porta de entrada única dos serviços (RFC-001 §1). Rotea para cada
# serviço via VPC Link -> listener do serviço na NLB interna (loadbalancer.tf). A rota de
# autenticação por CPF (RFC-001 §4.2, POST /auth/cpf para a Lambda) NÃO é criada aqui: a Lambda
# vive em oficina-mecanica-lambda-auth, que integra a própria rota a esta API usando os outputs
# api_gateway_id e api_gateway_execution_arn (ver README, "Contrato de outputs").

locals {
  # Rotas de negócio de cada serviço: chegam ao pod sem reescrita de caminho. A própria aplicação
  # decide autenticação/autorização por rota; o API Gateway só roteia e faz o meio de campo de
  # rede via VPC Link. Serviços de var.servicos que não aparecem aqui só têm a rota técnica.
  rotas_negocio = {
    autenticacao = ["ANY /api/v1/auth/{proxy+}"]
    cadastro = [
      "ANY /api/v1/clientes",
      "ANY /api/v1/clientes/{proxy+}",
      "ANY /api/v1/veiculos",
      "ANY /api/v1/veiculos/{proxy+}",
      "ANY /api/v1/servicos",
      "ANY /api/v1/servicos/{proxy+}",
    ]
    "pecas-insumos" = [
      "ANY /api/v1/pecas-insumos",
      "ANY /api/v1/pecas-insumos/{proxy+}",
    ]
    "ordens-servico" = [
      "ANY /api/v1/ordens-servico",
      "ANY /api/v1/ordens-servico/{proxy+}",
    ]
    pagamento = ["ANY /api/v1/pagamentos/{proxy+}"]
  }

  # Uma entrada por rota de negócio, com a chave única "<serviço> <route_key>".
  rotas_negocio_planas = {
    for rota in flatten([
      for servico in keys(var.servicos) : [
        for route_key in lookup(local.rotas_negocio, servico, []) : {
          servico   = servico
          route_key = route_key
        }
      ]
    ]) : "${rota.servico} ${rota.route_key}" => rota
  }

  # Serviço que recebe o que nenhuma rota mais específica captura (ANY /{proxy+}).
  servico_padrao = "ordens-servico"
}

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
  description                  = "Saida para os listeners dos servicos na NLB interna"
  referenced_security_group_id = aws_security_group.nlb.id
  from_port                    = local.node_port_min
  to_port                      = local.node_port_max
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "nlb_from_vpc_link" {
  security_group_id            = aws_security_group.nlb.id
  description                  = "Trafego do API Gateway via VPC Link"
  referenced_security_group_id = aws_security_group.vpc_link.id
  from_port                    = local.node_port_min
  to_port                      = local.node_port_max
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

# Integração de negócio: o caminho da requisição chega ao pod como veio.
resource "aws_apigatewayv2_integration" "servico" {
  for_each = var.servicos

  api_id             = aws_apigatewayv2_api.this.id
  integration_type   = "HTTP_PROXY"
  integration_uri    = aws_lb_listener.servico[each.key].arn
  integration_method = "ANY"
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.this.id
}

# Integração técnica, para a rota /<serviço>/{proxy+}: reescreve o caminho removendo o prefixo do
# serviço, de modo que GET /cadastro/healthz/ready chegue ao pod como GET /healthz/ready. O
# $request.path.proxy vem sem a barra inicial, por isso ela é acrescentada no valor.
resource "aws_apigatewayv2_integration" "servico_reescrita" {
  for_each = var.servicos

  api_id             = aws_apigatewayv2_api.this.id
  integration_type   = "HTTP_PROXY"
  integration_uri    = aws_lb_listener.servico[each.key].arn
  integration_method = "ANY"
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.this.id

  request_parameters = {
    "overwrite:path" = "/$request.path.proxy"
  }
}

resource "aws_apigatewayv2_route" "negocio" {
  for_each = local.rotas_negocio_planas

  api_id    = aws_apigatewayv2_api.this.id
  route_key = each.value.route_key
  target    = "integrations/${aws_apigatewayv2_integration.servico[each.value.servico].id}"
}

resource "aws_apigatewayv2_route" "tecnica" {
  for_each = var.servicos

  api_id    = aws_apigatewayv2_api.this.id
  route_key = "ANY /${each.key}/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.servico_reescrita[each.key].id}"
}

# Rota padrão: tudo que não casa com uma rota mais específica vai para o ordens-servico (o
# monólito original, cujas rotas já eram atendidas por este catch-all).
resource "aws_apigatewayv2_route" "padrao" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.servico[local.servico_padrao].id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true
}
