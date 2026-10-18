locals {
  azs            = var.availability_zones
  control_subnet = cidrsubnet(var.vpc_cidr, 8, 0)
  control_ips    = [for index in range(var.control_plane_count) : cidrhost(local.control_subnet, index + 10)]
  control_vip    = cidrhost(local.control_subnet, 20)
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "${var.cluster_name}-vpc" }
}

resource "aws_subnet" "public" {
  count                   = 3
  vpc_id                  = aws_vpc.this.id
  availability_zone       = local.azs[count.index]
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.cluster_name}-public-${count.index + 1}" }
}

resource "aws_internet_gateway" "this" { vpc_id = aws_vpc.this.id }

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
}

resource "aws_route_table_association" "public" {
  count          = 3
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "nodes" {
  name   = "${var.cluster_name}-nodes"
  vpc_id = aws_vpc.this.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidr_blocks
  }
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "api_clients" {
  name   = "${var.cluster_name}-api-clients"
  vpc_id = aws_vpc.this.id
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = var.api_allowed_cidr_blocks
  }
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "vip" {
  name = "${var.cluster_name}-keepalived"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy" "vip" {
  name = "assign-control-plane-vip"
  role = aws_iam_role.vip.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = ["ec2:AssignPrivateIpAddresses"]
      Resource  = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:network-interface/*"
      Condition = { ArnEquals = { "ec2:Subnet" = aws_subnet.public[0].arn } }
    }]
  })
}

resource "aws_iam_instance_profile" "vip" {
  name = "${var.cluster_name}-keepalived"
  role = aws_iam_role.vip.name
}

resource "aws_instance" "control_plane" {
  count                  = var.control_plane_count
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = aws_subnet.public[0].id
  private_ip             = local.control_ips[count.index]
  vpc_security_group_ids = [aws_security_group.nodes.id, aws_security_group.api_clients.id]
  iam_instance_profile   = aws_iam_instance_profile.vip.name
  user_data = join("\n", [
    var.bootstrap_script,
    templatefile("${path.module}/keepalived.sh.tftpl", {
      vip        = local.control_vip
      own_ip     = local.control_ips[count.index]
      peer_ips   = [for ip in local.control_ips : ip if ip != local.control_ips[count.index]]
      priority   = 120 - count.index * 10
      aws_region = var.aws_region
      router_id  = 51
    })
  ])
  tags = { Name = "${var.cluster_name}-control-plane-${count.index + 1}", Role = "control-plane" }
}

resource "aws_instance" "worker" {
  count                  = var.worker_count
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = aws_subnet.public[count.index % 3].id
  vpc_security_group_ids = [aws_security_group.nodes.id]
  user_data              = var.bootstrap_script
  tags                   = { Name = "${var.cluster_name}-worker-${count.index + 1}", Role = "worker" }
}
