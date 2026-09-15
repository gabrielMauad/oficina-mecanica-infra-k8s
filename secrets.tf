# Segredo da aplicação no Secrets Manager. Nada neste repositório criava isso antes: o Secret do
# Kubernetes (k8s/base/02-secret.yaml, removido em oficina-mecanica-app) trazia os valores
# hardcoded em texto puro no manifesto. A partir da migração para a nuvem, a pipeline da aplicação
# lê este secret pelo NOME (nunca pelo ARN) e cria o Secret do Kubernetes em tempo de deploy.
#
# Nome estável e estrutura (username/password-like keys em JSON) seguem o mesmo padrão já usado
# pelo secret do RDS em oficina-mecanica-infra-db (oficina-mecanica/dev/rds/postgresql).

resource "random_password" "jwt_secret" {
  # Segredo HS256 COMPARTILHADO entre esta aplicação e a Lambda (ADR-001, RFC-001 §2) — a Lambda
  # assina o token do cliente, a aplicação valida os dois (assina o da oficina e valida ambos).
  # Sem caracteres especiais: evita problemas de escape quando o valor atravessa variável de
  # ambiente (Jwt__Secret) e o comando de criação do Secret do Kubernetes na pipeline.
  length  = 64
  special = false
}

resource "random_password" "admin_senha" {
  # Login da oficina (Auth:AdminSenha, RFC-001 §4.2). Conjunto de especiais restrito ao que é
  # seguro dentro de aspas duplas num comando de shell (sem $, crase, aspas, barra invertida) —
  # mesmo motivo do jwt_secret acima, este valor também atravessa a pipeline de deploy.
  length           = 24
  special          = true
  override_special = "!#%&*-_=+?"
}

resource "aws_secretsmanager_secret" "app" {
  name        = "oficina-mecanica/dev/app"
  description = "Segredos da aplicacao oficina-mecanica-app: chave JWT compartilhada com a Lambda (ADR-001) e senha do login da oficina."

  # Ambiente descartável (RFC-002 §6.3): permite recriar o secret sem esperar a janela de recovery
  # padrão (7-30 dias) se o ambiente for destruído e reaplicado na mesma sessão de laboratório.
  # Mesmo padrão de oficina-mecanica-infra-db. Em produção real esse valor seria maior que zero.
  recovery_window_in_days = 0

  tags = {
    Name = "oficina-mecanica-app"
  }
}

resource "aws_secretsmanager_secret_version" "app" {
  secret_id = aws_secretsmanager_secret.app.id

  secret_string = jsonencode({
    jwt_secret  = random_password.jwt_secret.result
    admin_senha = random_password.admin_senha.result
  })
}
