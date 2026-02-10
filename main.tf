# use aws
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

#use this region
provider "aws" {
  region = var.aws_region
}

#creating vpc
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "terraform-vpc"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

#Subnet
resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name        = "terraform-private-subnet"
    Environment = "dev"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "terraform-private-rt"
    Environment = "dev"
  }
}

#link subnet to route Table
resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

#security group for EC2
resource "aws_security_group" "ec2_sg" {
  name        = "terraform-ec2-sg"
  description = "Security group for EC2 instance"
  vpc_id      = aws_vpc.main.id

  #outbound traffic
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "terraform-ec2-sg"
    Environment = "dev"
  }
}

# security group for VPC
resource "aws_security_group" "vpc_endpoint_sg" {
  name = "vpc-endpoint-sg"
  description = "Security group for VPC endpoints"
  vpc_id = aws_vpc.main.id

  ingress{
    description = "HTTPS from VPC"
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  tags = {
    Name = "vpc-endpoint-sg"
    Environment = "dev"
  }
  
}

#EC2 Instance -  virtual server
resource "aws_instance" "web" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  #move ec2 into vpc subnet
  subnet_id                   = aws_subnet.private.id
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  # key_name                    = aws_key_pair.ec2_key.key_name
  associate_public_ip_address = false

  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name


  #User data to install Apache web server
  user_data = <<-EOF
                #!/bin/bash
                yum update -y
                echo "Instance provisioned successfully" > /tmp/status.txt
                EOF

  root_block_device {
    volume_size = 40
    volume_type = "gp3"
  }

  tags = {
    Name        = "terraform-ec2-instance"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}


resource "aws_iam_role" "ec2_ssm_role"{
  name = "ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_attach"{
  role = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}


resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm_role.name
}


# VPC Endpoint for SSM
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
  private_dns_enabled = true

  tags = {
    Name        = "ssm-endpoint"
    Environment = "dev"
  }
}

# VPC Endpoint for SSM Messages
resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
  private_dns_enabled = true

  tags = {
    Name        = "ssmmessages-endpoint"
    Environment = "dev"
  }
}

# VPC Endpoint for EC2 Messages
resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
  private_dns_enabled = true

  tags = {
    Name        = "ec2messages-endpoint"
    Environment = "dev"
  }
}
