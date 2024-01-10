terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }

  required_version = ">= 1.2.0"
}

variable "region" {
  type = string
  description = "The AWS region to deploy resources into. Pre-requisites must exist in same region"
}

variable "vpc_cidr" {
  type = string
  description = "A CIDR address range to use for the VPC, must not conflict with existing VPC ranges"
}

variable "rstudio_server_ami" {
  type = string
  description = "The AMI id for the custom image built by Packer"
}

variable "rstudio_server_instance_type" {
  type = string
  description = "The EC2 instance type to use for the RStudio Server"
}

variable "instance_key_name" {
  type = string
  description = "The name of the key pair to associate with the EC2 instance"
}

provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc.git?ref=e4768508a17f79337f9f1e48ebf47ee885b98c1f"

  name = "rstudio-server-vpc"
  cidr = var.vpc_cidr

  azs             = data.aws_availability_zones.available.names
  private_subnets = slice(cidrsubnets(var.vpc_cidr, 6, 6),0,1)
  public_subnets  = slice(cidrsubnets(var.vpc_cidr, 6, 6),1,2)

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

resource "aws_security_group" "intra_sg" {
  name        = "intra-sg"
  description = "Self referencing security group"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
    description = "Allow access on any protocol form sources associated with same security group"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all egress"
  }
}

resource "aws_vpc_endpoint" "ec2_messages_endpoint" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.region}.ec2messages"
  vpc_endpoint_type = "Interface"

  security_group_ids = [
    aws_security_group.intra_sg.id,
  ]

  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ssm_endpoint" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.region}.ssm"
  vpc_endpoint_type = "Interface"

  security_group_ids = [
    aws_security_group.intra_sg.id,
  ]

  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ssm_messages_endpoint" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.region}.ssmmessages"
  vpc_endpoint_type = "Interface"

  security_group_ids = [
    aws_security_group.intra_sg.id,
  ]

  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "s3_endpoint" {
  vpc_id       = module.vpc.vpc_id
  service_name = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
}

resource "aws_iam_role" "rstudio_server_role" {
  name = "rstudio-server-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]
}

resource "aws_iam_instance_profile" "rstudio_server_profile" {
  name = "rstudio-server-profile"
  role = aws_iam_role.rstudio_server_role.name
}

resource "aws_instance" "rstudio_server" {
  ami                  = var.rstudio_server_ami
  instance_type        = var.rstudio_server_instance_type
  security_groups      = ["${aws_security_group.intra_sg.id}"]
  subnet_id            = element(module.vpc.private_subnets, 0)
  iam_instance_profile = aws_iam_instance_profile.rstudio_server_profile.name
  key_name             = var.instance_key_name
  metadata_options {
    http_tokens = "required"
  }
  ebs_optimized = true

  root_block_device {
    encrypted = true
  }

  tags = {
    Name = "rstudio-shiny-server"
    Role = "rstudio-server"
  }
}
