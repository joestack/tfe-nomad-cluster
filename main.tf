provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {}

locals {
  mod_az = length(data.aws_availability_zones.available.names)
  #mod_az = length(split(",", join(", ",data.aws_availability_zones.available.names)))
}


data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}


resource "aws_vpc" "hashicorp_vpc" {
  cidr_block           = var.network_address_space
  enable_dns_hostnames = "true"

  tags = {
    Name = "${var.name}-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.hashicorp_vpc.id

}

resource "aws_route_table" "rtb" {
  vpc_id = aws_vpc.hashicorp_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.name}-IGW"
  }

}

resource "aws_route_table_association" "nomad-subnet" {
  count          = var.server_count
  subnet_id      = element(aws_subnet.nomad_subnet.*.id, count.index)
  route_table_id = aws_route_table.rtb.id
}


resource "aws_subnet" "nomad_subnet" {
  count                   = var.server_count
  vpc_id                  = aws_vpc.hashicorp_vpc.id
  cidr_block              = cidrsubnet(var.network_address_space, 8, count.index + 1)
  map_public_ip_on_launch = "true"
  availability_zone       = data.aws_availability_zones.available.names[count.index % local.mod_az]

  tags = {
    Name = "${var.name}-subnet"
  }
}

resource "aws_security_group" "primary" {
  name   = var.name
  vpc_id = aws_vpc.hashicorp_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.whitelist_ip]
  }


  # Nomad
  ingress {
    from_port   = 4646
    to_port     = 4648
    protocol    = "tcp"
    cidr_blocks = [var.whitelist_ip]
  }

  # Consul
  ingress {
    from_port   = 8500
    to_port     = 8500
    protocol    = "tcp"
    cidr_blocks = [var.whitelist_ip]
  }

  # Consul
  ingress {
    from_port   = 20000
    to_port     = 29999
    protocol    = "tcp"
    cidr_blocks = [var.whitelist_ip]
  }
  # Consul
  ingress {
    from_port   = 30000
    to_port     = 39999
    protocol    = "tcp"
    cidr_blocks = [var.whitelist_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}





resource "aws_iam_instance_profile" "nomad_join" {
  name = var.name
  role = aws_iam_role.nomad_join.name
}
resource "aws_iam_policy" "nomad_join" {
  name = var.name
  description = "Allows Nomad nodes to describe instances for joining."
  policy = data.aws_iam_policy_document.nomad-server.json
}
resource "aws_iam_role" "nomad_join" {
  name = var.name
  assume_role_policy = data.aws_iam_policy_document.instance_role.json
}
resource "aws_iam_policy_attachment" "nomad_join" {
  name = var.name
  roles      = [aws_iam_role.nomad_join.name]
  policy_arn = aws_iam_policy.nomad_join.arn
}
data "aws_iam_policy_document" "nomad-server" {
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "instance_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

output "nomad_server_private_ips" {
  value = aws_instance.nomad_server.*.private_ip
}

output "nomad_server_public_ips" {
  value = aws_instance.nomad_server[*].public_ip
}

output "nomad_client_private_ips" {
  value = aws_instance.nomad_client.*.private_ip
}

output "nomad_client_public_ips" {
  value = aws_instance.nomad_client[*].public_ip
}