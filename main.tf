terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region     = "ap-northeast-2"
  access_key = "<AWS IAM 액세스 키>"
  secret_key = "<AWS IAM 시크릿 키>"
}

# 1. VPC 만들기
resource "aws_vpc" "vpc-01" {
  cidr_block = "10.0.0.0/16"
}

# 2. 인터넷 게이트웨이 만들기
resource "aws_internet_gateway" "igw-01" {
  vpc_id = aws_vpc.vpc-01.id
}

# 3. 라우팅 테이블 만들기
resource "aws_route_table" "route-table-01" {
  vpc_id = aws_vpc.vpc-01.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw-01.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.igw-01.id
  }
}

# 4. 서브넷 만들기
resource "aws_subnet" "subnet-01" {
  vpc_id            = aws_vpc.vpc-01.id
  cidr_block        = "10.0.1.0/25"
  availability_zone = "ap-northeast-2a"

  tags = {
    Name = "subnet-01"
  }
}

# 5. 서브넷과 라우트 테이블 연결하기
resource "aws_route_table_association" "association-a" {
  subnet_id      = aws_subnet.subnet-01.id
  route_table_id = aws_route_table.route-table-01.id
}

# 6. SG 만들기
resource "aws_security_group" "allow-web-traffic" {
  name        = "allow_web_traffic"
  description = "Allow Web inbound traffic"
  vpc_id      = aws_vpc.vpc-01.id

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # 모든 프로토콜을 의미함
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_Web_traffic"
  }
}

# 7. 네트워크 인터페이스 만들기
resource "aws_network_interface" "web-server-01-eni" {
  subnet_id       = aws_subnet.subnet-01.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow-web-traffic.id]
}

# 8. eni에 elastic IP 부여하기
resource "aws_eip" "one" {
  vpc                       = true
  network_interface         = aws_network_interface.web-server-01-eni.id
  associate_with_private_ip = "10.0.1.50"
  depends_on                = [aws_internet_gateway.igw-01]
}

# 9. 우분투 서버 생성 및 apache2 설치 & 설정
resource "aws_instance" "web-server-instance" {
  ami           = "ami-0454bb2fefc7de534"
  instance_type = "t2.nano"
  # 반드시 서브넷의 AZ와 동일하게 설정해야 함.
  # 설정하지 않을 시 무작위 AZ가 배정된다.
  availability_zone = "ap-northeast-2a"
  key_name          = "terraform-project-key"

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.web-server-01-eni.id
  }

  user_data = <<-EOF
                #!/bin/bash
                sudo apt update -y
                sudo apt install apache2 -y
                sudo systemctl start apache2
                sudo bash -c 'echo your very first web server > /var/www/html/index.html'
                EOF

  tags = {
    Name = "web-server-instance-01"
  }
}
