terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Projeto       = "oficina-mecanica"
      Fase          = "3"
      Repositorio   = "oficina-mecanica-infra-k8s"
      GerenciadoPor = "terraform"
    }
  }
}
