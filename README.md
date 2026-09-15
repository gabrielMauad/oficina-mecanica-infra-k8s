# oficina-mecanica-infra-k8s

Terraform do cluster Kubernetes gerenciado do **Sistema de Oficina Mecânica** — Tech Challenge da
pós-graduação em Arquitetura de Software (FIAP/SOAT), Fase 3.

Provisiona, na conta **AWS Academy Learner Lab**, a VPC, o cluster **Amazon EKS**, a exposição da
aplicação e o **API Gateway** — a nuvem escolhida e as restrições da conta estão documentadas em
[RFC-002](https://github.com/gabrielMauad/oficina-mecanica-app/blob/main/docs/arquitetura/rfcs/002-escolha-do-provedor-de-nuvem.md)
e [ADR-006](https://github.com/gabrielMauad/oficina-mecanica-app/blob/main/docs/arquitetura/adrs/006-credenciais-de-nuvem-no-cicd.md),
no repositório [`oficina-mecanica-app`](https://github.com/gabrielMauad/oficina-mecanica-app).

---

## Índice

- [Propósito](#propósito)
- [Tecnologias utilizadas](#tecnologias-utilizadas)
- [Diagrama do componente](#diagrama-do-componente)
- [Pré-requisitos](#pré-requisitos)
- [Instruções de execução](#instruções-de-execução)
- [Passos de deploy](#passos-de-deploy)
- [Explicação da pipeline](#explicação-da-pipeline)
- [Contrato de outputs](#contrato-de-outputs)
- [Decisões de desenho](#decisões-de-desenho)
- [Custo estimado e ordem de destruição](#custo-estimado-e-ordem-de-destruição)
- [O que não foi validado sem apply](#o-que-não-foi-validado-sem-apply)

---

## Propósito

Provisionar, via Terraform, tudo que fica entre a internet e a aplicação
(`oficina-mecanica-app`) rodando em contêiner:

- **Rede**: nenhuma. Usa a VPC default da conta (data sources) — a fase exige EKS, não exige criar
  VPC, e a VPC default já tem subnets em todas as AZs da região.
- **Cluster Kubernetes gerenciado**: Amazon EKS, com node group escalável (2 a 3 nós).
- **Exposição**: NLB interna + API Gateway (HTTP API) na frente do cluster.

O deploy da aplicação em si (imagem, ConfigMap/Secret, Deployment, HPA) continua sendo feito pela
pipeline do repositório `oficina-mecanica-app`, contra o cluster provisionado aqui — este
repositório não aplica manifestos Kubernetes.

## Tecnologias utilizadas

| Tecnologia | Uso |
|---|---|
| **Terraform** ≥ 1.5, provider `hashicorp/aws` ~> 5.0 | IaC de toda a infraestrutura de nuvem |
| **Amazon EKS** | Cluster Kubernetes gerenciado |
| **Amazon API Gateway (HTTP API)** | Porta de entrada única da aplicação |
| **AWS Network Load Balancer** | Expõe o NodePort da aplicação dentro da VPC ao API Gateway |
| **GitHub Actions** | CI de validação (PR) e apply (push/dispatch na `main`) |

## Diagrama do componente

```mermaid
flowchart LR
    Client[Cliente / App externo] -->|HTTPS| GW[API Gateway HTTP API]
    GW -->|CPF: rota de auth| LAMBDA["Lambda de autenticação<br/>oficina-mecanica-lambda-auth<br/>(integra a própria rota nesta API)"]
    GW -->|demais rotas, via VPC Link| VPCLINK[VPC Link]

    subgraph VPC["VPC default da conta (subnets públicas, sem NAT)"]
        VPCLINK --> NLB["NLB interna<br/>target group: instance / NodePort 30080"]
        subgraph EKS["Cluster EKS"]
            NG["Node group (2-3 nós, t3.small)"]
            NLB --> NG
            NG --> PODS["Pods oficina-api<br/>(deploy: oficina-mecanica-app)"]
            HPA["HPA (1-5 pods, 50% CPU)"] -.escala.-> PODS
        end
        NG -.libera 5432 a partir do<br/>cluster_security_group_id.-> RDS[("RDS PostgreSQL<br/>oficina-mecanica-infra-db")]
    end
```

## Pré-requisitos

- [Terraform](https://developer.hashicorp.com/terraform/downloads) ≥ 1.5
- Uma sessão ativa da **AWS Academy Learner Lab**, com as credenciais de sessão
  (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`) exportadas no ambiente para
  rodar `plan`/`apply` localmente
- Um **bucket S3** já existente, criado manualmente uma única vez — é pré-requisito do próprio
  backend, então não pode ser provisionado por este Terraform (RFC-002 §6.4). O mesmo bucket é
  compartilhado com `oficina-mecanica-infra-db`, sob uma chave diferente.

> **Sem lock de state.** Não há tabela DynamoDB para locking. Os dois repositórios de
> infraestrutura usam chaves distintas no mesmo bucket, então não há concorrência entre eles, e o
> `apply` é executado por uma única pessoa. Numa equipe ou com pipelines concorrentes, o lock seria
> obrigatório — aqui ele só acrescentaria custo e uma peça a manter numa conta de crédito finito.

## Instruções de execução

**Validação estática** (não exige credencial — é o que o CI roda em todo PR):

```bash
terraform init -backend=false
terraform fmt -check -recursive
terraform validate
```

**`init` com o backend real** (backend parcial: `backend.tf` declara `backend "s3" {}` vazio, sem
nome de bucket commitado — os valores entram aqui):

```bash
terraform init \
  -backend-config="bucket=<nome-do-bucket-s3>" \
  -backend-config="key=infra-k8s/terraform.tfstate" \
  -backend-config="region=us-east-1"
```

**`plan`/`apply`** exigem as credenciais de sessão da AWS Academy exportadas no ambiente
(`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`):

```bash
terraform plan
terraform apply
```

## Passos de deploy

1. PR contra a `main` deste repositório com o Terraform. CI roda `fmt` + `validate` — status check
   obrigatório.
2. Merge em `main`.
3. Job `apply` do workflow (push na `main` ou `workflow_dispatch`) provisiona a infraestrutura
   contra o backend remoto de state.
4. Com o cluster no ar, a pipeline de `oficina-mecanica-app` faz o deploy da aplicação (imagem +
   manifestos `k8s/`) contra este cluster.
5. `oficina-mecanica-infra-db` e `oficina-mecanica-lambda-auth` consomem os outputs deste
   repositório via `terraform_remote_state` (ver [Contrato de outputs](#contrato-de-outputs)).

Como o ambiente é efêmero (RFC-002 §6.3), o ciclo esperado é provisionar, validar/gravar a
demonstração e destruir (`terraform destroy`) — não manter o cluster no ar indefinidamente.

## Explicação da pipeline

Workflow em [`.github/workflows/ci.yml`](.github/workflows/ci.yml):

- **`validate`** (Pull Request): `terraform fmt -check -recursive`, `terraform init -backend=false`
  e `terraform validate`. Status check obrigatório da `main`.
- **`apply`** (push/`workflow_dispatch` na `main`, depende de `validate`): autentica com
  `aws-actions/configure-aws-credentials`, usando as **credenciais de sessão temporárias** da conta
  AWS Academy — não OIDC/IAM role, que esta conta não permite criar (ADR-006). Requer três secrets
  do repositório, **incluindo obrigatoriamente** `AWS_SESSION_TOKEN`, e a variável do repositório
  `vars.TF_STATE_BUCKET` para o `-backend-config`. Roda
  sob o Environment `aws-academy` do GitHub — crie-o em Settings → Environments e associe os
  secrets a ele (ou aos secrets do repositório, visíveis a qualquer Environment).
- As credenciais de sessão expiram com a sessão do laboratório: se o `apply` falhar na
  autenticação, é preciso renovar os três secrets e reexecutar via `workflow_dispatch` — não é
  pipeline quebrada (ADR-006).

## Contrato de outputs

Consumido por `terraform_remote_state` pelos demais repositórios do projeto.
**`vpc_id`, `private_subnet_ids` e `cluster_security_group_id` são consumidos por
`oficina-mecanica-infra-db` — não renomeie sem avisar quem mantém aquele repositório.**

Desde a adoção da VPC default (ver "Decisões de desenho"), `private_subnet_ids` não aponta mais
para subnets privadas — o nome foi mantido por estabilidade do contrato, mas o conteúdo são as
subnets (públicas) da VPC default. `public_subnet_ids` foi removido: com a VPC default não há mais
distinção entre subnet pública e privada, e nada consumia esse output além de depuração.

| Output | Tipo | Consumido por | Uso |
|---|---|---|---|
| `vpc_id` | string | `infra-db` | VPC (default) do DB subnet group do RDS |
| `private_subnet_ids` | list(string) | `infra-db` | Subnets (da VPC default) do DB subnet group do RDS |
| `cluster_security_group_id` | string | `infra-db` | SG a partir do qual o RDS libera a porta 5432 |
| `cluster_name` | string | — | Nome do cluster EKS |
| `cluster_endpoint` | string | — | Endpoint da API do Kubernetes |
| `cluster_certificate_authority_data` | string | — | CA do cluster, para montar o kubeconfig |
| `app_load_balancer_arn` / `app_load_balancer_dns_name` | string | — | NLB interna que expõe o NodePort da aplicação |
| `api_gateway_id` | string | `lambda-auth` | Id da HTTP API, para criar a integração/rota de autenticação por CPF nesta mesma API |
| `api_gateway_execution_arn` | string | `lambda-auth` | Necessário para a Lambda aceitar invocações vindas deste API Gateway |
| `api_gateway_endpoint` | string | — | URL pública de invocação da API |

## Decisões de desenho

**`aws_eks_cluster`/`aws_eks_node_group` diretamente, não o módulo `terraform-aws-modules/eks`.**
O módulo é ótimo, mas cria IAM roles por padrão (para o cluster, os nós e, se usado, IRSA) — a
conta AWS Academy Learner Lab não permite criar IAM roles (RFC-002 §6.1). Seria possível desligar
essa criação e passar os ARNs das roles pré-criadas (`create_iam_role = false` +
`iam_role_arn = ...`), mas a superfície de variáveis do módulo dedicada a contornar um caso que
aqui é a regra (nenhum IAM role, em lugar nenhum) tornaria a configuração menos legível do que
declarar os dois recursos diretamente com `data "aws_iam_role"`. Optamos pelos recursos diretos.

**Exposição: NLB interna gerenciada pelo Terraform + API Gateway via VPC Link, não AWS Load
Balancer Controller + Ingress.** O AWS Load Balancer Controller normalmente exige um IAM role via
IRSA (o próprio controller precisa de permissões de EC2/ELB não cobertas pela role dos nós) — o que
esta conta não permite criar, então essa alternativa foi descartada antes mesmo de ser tentada, não
por preferência de estilo. A NLB é criada e gerenciada por este Terraform (não pelo Kubernetes):
o alvo é o Auto Scaling Group do node group (`aws_autoscaling_attachment`), no NodePort 30080 já
usado pelo Service da aplicação hoje. Isso evita a dependência circular de uma NLB criada
dinamicamente por um `Service type=LoadBalancer` (cujo ARN só existiria depois do primeiro deploy
da aplicação, numa pipeline diferente) e **não exige nenhuma mudança no repositório da
aplicação** — o Service continua `NodePort`. É o caminho mais simples que funciona.

**Só o add-on `metrics-server` é declarado (`aws_eks_addon`), não Helm.** É pré-requisito do HPA
(escalabilidade é requisito da fase). Declará-lo evita configurar os providers `kubernetes`/`helm`
com autenticação do cluster só para isso — o que, além de mais uma peça, teria uma dependência de
ordem delicada (o provider precisa que o cluster já exista para autenticar, no mesmo apply que o
cria). `vpc-cni`, `kube-proxy` e `coredns` **não** são declarados: o EKS já os instala
automaticamente na criação do cluster, e declará-los só serviria para fixar versão — três pontos de
falha no `apply` sem benefício neste contexto de prazo curto e conta restrita.

**VPC default da conta, sem criar rede própria.** A Fase 3 exige EKS com escalabilidade; não exige
criar VPC. A conta AWS Academy já tem uma VPC default com subnets em todas as AZs da região, o que
elimina VPC, subnets, Internet Gateway, NAT Gateway e route tables deste Terraform — cada um desses
é custo e um ponto de falha a menos no `apply`. As subnets da VPC default são públicas: os nós do
EKS ficam em subnet pública, com IP público automático, o que é o que dispensa o NAT Gateway.
**Isso é uma troca deliberada de isolamento de rede por custo e simplicidade**, aceitável para uma
demonstração acadêmica — numa conta de produção real, os nós ficariam em subnet privada atrás de um
NAT Gateway, e a rede seria criada por este Terraform como antes. O que continua protegendo o
tráfego são os security groups dedicados (`aws_security_group.nlb`, `aws_security_group.vpc_link`,
e o SG do RDS em `infra-db`) — o SG default da VPC (que libera tudo entre seus próprios membros)
nunca é usado para isso.

**Nem todas as subnets da VPC default são usadas — allowlist de AZs.** "Toda região AWS tem ≥ 2
AZs" está certo quanto à quantidade, mas não quanto à elegibilidade: várias contas AWS têm pelo
menos uma AZ sem capacidade para o control plane do EKS (o caso documentado mais comum em
`us-east-1` é a AZ `us-east-1e`), e o erro (`UnsupportedAvailabilityZoneException`) só aparece na
criação do cluster — `validate`/`plan` não o pegam. `var.eks_availability_zones` (`network.tf`,
`variables.tf`) restringe explicitamente as subnets passadas ao cluster/node group/NLB/VPC Link a
um allowlist (`us-east-1a`, `us-east-1b`, `us-east-1c` por padrão), com um `lifecycle.precondition`
em `aws_eks_cluster.this` (`eks.tf`) que falha o `plan` com mensagem clara se sobrar menos de 2 AZs
elegíveis, em vez de deixar o erro só aparecer no `apply`. É `precondition`, não um `check` block:
`check` só produz warning e roda depois do Terraform já ter tentado provisionar — não bloqueia
nada; `precondition` é avaliado antes de criar o recurso e falha o `plan` de verdade. Efeito
colateral bom: a NLB cobra por AZ em que tem subnet — restringir a 3 em vez das 6 da região também
reduz custo.

**Node group `t3.small`, não `t3.micro`/`t3.nano`.** O fator limitante não é CPU, é o limite de
pods por nó do EKS (derivado do número de ENIs/IPs da instância): `t3.micro` suporta só 4 pods, e os
pods de sistema (kube-proxy, coredns, metrics-server, aws-node) já consomem isso, sem sobrar
capacidade para a aplicação. `t3.small` suporta 11; com 2 nós são ~22 slots, menos ~6 de sistema =
~16 livres, suficiente para o HPA escalar até 5 réplicas (`k8s/app/22-api-hpa.yaml`). Se o HPA não
conseguir chegar a 5 réplicas por falta de **memória** (limite mais apertado que os slots de pod
aqui), o próximo degrau é `t3.medium` (ver `variables.tf`).

## Custo estimado e ordem de destruição

O ambiente é efêmero (RFC-002 §6.3): o ciclo esperado é provisionar, validar/gravar a demonstração
e destruir — não manter no ar entre sessões. O que cobra por hora **mesmo com a aplicação parada**
(nenhum destes é gratuito só por existir):

| Recurso | Custo aproximado | Observação |
|---|---|---|
| Control plane do EKS | ~US$ 0,10/h | Cobra desde a criação do cluster até o `destroy`, independente de haver nós ou não. |
| NLB (Network Load Balancer) | ~US$ 0,0225/h + LCU | Cobra enquanto existir, mesmo sem tráfego. |
| Node group (2× `t3.small`) | Instâncias EC2 On-Demand | Cobra por instância, mesmo ociosa. |
| API Gateway (HTTP API) | Por requisição | Não cobra parado, só por uso — não é uma preocupação de "esquecer ligado". |

**Ordem de destruição:** `oficina-mecanica-infra-db` **antes** de `oficina-mecanica-infra-k8s` — na
ordem inversa da criação (ver "Passos de deploy"). O RDS depende da VPC/subnets/security group
exportados por este repositório; destruir este primeiro deixaria o `infra-db` com um
`terraform_remote_state` apontando para recursos que não existem mais, e o próprio RDS órfão (sem
rede válida) na conta. Resumo:

```
destroy: oficina-mecanica-infra-db  →  oficina-mecanica-infra-k8s
apply:   oficina-mecanica-infra-k8s →  oficina-mecanica-infra-db
```

## O que não foi validado sem apply

Este repositório foi validado com `terraform init -backend=false`, `terraform fmt -check
-recursive` e `terraform validate` — nenhum deles fala com a conta AWS. `plan`/`apply` não foram
executados nesta sessão (sem credenciais). Fica para quem rodar o primeiro `apply`, com a sessão do
laboratório ativa, confirmar:

- **Se `LabRole` (usada no lugar de `LabEksClusterRole`, que não existe nesta conta — ver
  `variables.tf`) realmente serve tanto para `aws_eks_cluster.role_arn` quanto para
  `aws_eks_node_group.node_role_arn`.** RFC-002 cita `LabEksClusterRole` para cluster e nós, mas
  essa role não existe na conta usada neste projeto; a policy efetiva anexada a `LabRole` só é
  visível na conta real.
- **Disponibilidade do add-on gerenciado `metrics-server`** (`aws_eks_addon`) para a versão do
  cluster nesta conta/região — é um add-on relativamente recente da AWS. Se `apply` falhar nele
  especificamente, o fallback é instalar via `helm_release` (como na Fase 2, `infra/main.tf` no
  repositório da aplicação), o que exige configurar os providers `kubernetes`/`helm` com a
  autenticação do cluster.
- **Se a versão do Kubernetes (`var.kubernetes_version`, hoje `1.31`) está disponível** na conta —
  contas Academy às vezes atrasam versões suportadas.
- **Se `us-east-1a`, `us-east-1b` e `us-east-1c` (o default de `var.eks_availability_zones`) têm,
  de fato, subnet na VPC default desta conta e suportam o control plane do EKS.** O mapeamento
  nome-de-AZ → AZ física é randomizado por conta AWS, então o nome não garante nada sozinho — é por
  isso que existe o `lifecycle.precondition` em `aws_eks_cluster.this` (`eks.tf`): ele falha o
  `plan` com mensagem clara se sobrar menos de 2 AZs elegíveis, mas só a conta real confirma se o
  allowlist evita a AZ sem capacidade
  para EKS nesta conta especificamente.
- **Health check da NLB em `/healthz/live`** só fica saudável depois que a aplicação estiver de
  fato implantada no cluster (pipeline de `oficina-mecanica-app`) — o `apply` deste repositório cria
  a infraestrutura independente disso, mas o alvo só respondera 200 depois do deploy da app.
- **Limite de 9 instâncias/32 vCPU da conta**: 2 nós `t3.small` (2 vCPU cada) ficam bem dentro do
  limite; não testado contra o painel real da conta.
- **Se o HPA consegue de fato escalar até 5 réplicas em nós `t3.small`** sem esbarrar em memória —
  ver "Decisões de desenho"; se não conseguir, o próximo passo é trocar para `t3.medium`.
- **Nós em subnet pública (VPC default) recebendo IP público automaticamente** — esperado
  (`map_public_ip_on_launch` é o padrão de subnet pública), mas o comportamento efetivo de rede
  (por exemplo, se algum security group da conta interfere) só se confirma no `apply`.
