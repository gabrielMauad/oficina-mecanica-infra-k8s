# Configuração parcial: propositalmente sem bucket nem região aqui — nenhum nome de recurso de
# conta fica commitado. Os valores reais entram via `-backend-config` no `terraform init` (ver
# README, seção "Instruções de execução"), tanto localmente quanto no workflow de CI.
#
# Sem lock de state (sem tabela DynamoDB): este repositório e oficina-mecanica-infra-db usam
# chaves distintas no mesmo bucket, e o apply é executado por uma única pessoa — não há
# concorrência a proteger. Ver README, seção "Pré-requisitos".
terraform {
  backend "s3" {}
}
