# Um repositório de imagens por serviço (oficina-mecanica-<serviço>), derivado de var.servicos. A
# pipeline de cada serviço publica no seu próprio repositório; a pipeline de oficina-mecanica-app
# (ordens-servico) publicava antes em um único repositório, oficina-mecanica-api, que deixou de
# existir.

resource "aws_ecr_repository" "servico" {
  for_each = var.servicos

  name = "oficina-mecanica-${each.key}"

  # Sem isso, "terraform destroy" falha com "RepositoryNotEmptyException" se sobrar qualquer
  # imagem publicada pela pipeline dentro do repositório — ambiente descartável (RFC-002 §6.3),
  # não vale a pena reter imagens depois do destroy só para evitar essa falha.
  force_delete = true

  image_scanning_configuration {
    scan_on_push = false # desligado deliberadamente: não gera custo/ruído extra
  }

  tags = {
    Name = "oficina-mecanica-${each.key}"
  }
}

# Mantém só as últimas ~10 imagens de cada repositório — evita acumular imagens de cada push na
# main indefinidamente (custo de armazenamento do ECR é por GB/mês).
resource "aws_ecr_lifecycle_policy" "servico" {
  for_each = aws_ecr_repository.servico

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Mantem somente as ultimas 10 imagens"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
