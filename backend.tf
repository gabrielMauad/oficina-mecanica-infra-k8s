# Configuração parcial: propositalmente sem bucket/região/tabela de lock aqui — nenhum nome de
# recurso de conta fica commitado. Os valores reais entram via `-backend-config` no `terraform
# init` (ver README, seção "Instruções de execução"), tanto localmente quanto no workflow de CI.
terraform {
  backend "s3" {}
}
