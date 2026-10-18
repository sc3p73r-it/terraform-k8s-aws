terraform {
  backend "s3" {
    bucket       = "REPLACE_WITH_YOUR_TERRAFORM_STATE_BUCKET"
    key          = "vanilla-k8s/terraform.tfstate"
    region       = "ap-southeast-1"
    encrypt      = true
    use_lockfile = true
  }
}
