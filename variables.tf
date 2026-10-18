variable "aws_region" {
  type    = string
  default = "ap-southeast-1"
}
variable "cluster_name" {
  type    = string
  default = "vanilla-k8s"
}
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}
variable "availability_zones" {
  type    = list(string)
  default = ["ap-southeast-1a", "ap-southeast-1b", "ap-southeast-1c"]
}
variable "instance_type" {
  type    = string
  default = "t3.medium"
}
variable "ami_id" {
  type    = string
  default = "ami-0933f1385008d33c4"
}
variable "key_name" {
  type    = string
  default = "agdevops"
}
variable "ssh_allowed_cidr_blocks" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}
variable "api_allowed_cidr_blocks" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}
