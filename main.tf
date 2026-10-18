terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}
provider "aws" { region = var.aws_region }
module "k8s_cluster" {
  source                  = "./modules/k8s-cluster"
  cluster_name            = var.cluster_name
  vpc_cidr                = var.vpc_cidr
  availability_zones      = var.availability_zones
  ami_id                  = var.ami_id
  instance_type           = var.instance_type
  key_name                = var.key_name
  control_plane_count     = 3
  worker_count            = 3
  ssh_allowed_cidr_blocks = var.ssh_allowed_cidr_blocks
  api_allowed_cidr_blocks = var.api_allowed_cidr_blocks
  bootstrap_script        = file("${path.module}/install_k8s.sh")
  aws_region              = var.aws_region
}
