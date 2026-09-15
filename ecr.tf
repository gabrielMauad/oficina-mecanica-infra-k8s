# Repositório de imagens da aplicação. Nada neste repositório criava isso antes: a pipeline de
# oficina-mecanica-app publicava no Docker Hub (Fase 2). A partir da migração para a nuvem, ela
# publica aqui.

resource "aws_ecr_repository" "app" {
  name = "oficina-mecanica-api"

  # Sem isso, "terraform destroy" falha com "RepositoryNotEmptyException" se sobrar qualquer
  # imagem publicada pela pipeline dentro do repositório — ambiente descartável (RFC-002 §6.3),
  # não vale a pena reter imagens depois do destroy só para evitar essa falha.
  force_delete = true

  image_scanning_configuration {
    scan_on_push = false # desligado deliberadamente: não gera custo/ruído extra nesta fase
  }

  tags = {
    Name = "oficina-mecanica-api"
  }
}

# Mantém só as últimas ~10 imagens — evita acumular imagens de cada push na main indefinidamente
# (custo de armazenamento do ECR é por GB/mês).
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

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
