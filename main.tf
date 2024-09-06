# AWS 프로바이더 설정
provider "aws" {
  region = "ap-northeast-2"
}

# VPC 생성
resource "aws_vpc" "eks_vpc" {
  cidr_block           = "200.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "mokonix-lee-vpc"
  }
}

# 인터넷 게이트웨이 생성 및 VPC 연결
resource "aws_internet_gateway" "eks_igw" {
  vpc_id = aws_vpc.eks_vpc.id
  tags = {
    Name = "mokonix-lee-igw"
  }
}

# 퍼블릭 라우트 테이블 생성 및 인터넷 게이트웨이 연결
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eks_igw.id
  }

  tags = {
    Name = "mokonix-lee-public-route-table"
  }
}

# 퍼블릭 서브넷 A (가용영역 ap-northeast-2a)
resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = "200.0.1.0/24"
  availability_zone       = "ap-northeast-2a"
  map_public_ip_on_launch = true
  tags = {
    Name                              = "mokonix-lee-public-subnet-a"
    "kubernetes.io/role/elb"          = "1"          # ELB용 퍼블릭 서브텟 태그
    "kubernetes.io/cluster/eks-cluster" = "shared"   # 클러스터 태그
  }
}

# 퍼블릭 서브넷 C (가용영역 ap-northeast-2c)
resource "aws_subnet" "public_subnet_c" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = "200.0.3.0/24"
  availability_zone       = "ap-northeast-2c"
  map_public_ip_on_launch = true
  tags = {
    Name                              = "mokonix-lee-public-subnet-c"
    "kubernetes.io/role/elb"          = "1"          # ELB용 퍼블릭 서브넷 태그
    "kubernetes.io/cluster/eks-cluster" = "shared"   # 클러스터 태그
  }
}

# 퍼블릭 서브넷 A를 퍼블릭 라우트 테이블에 연결
resource "aws_route_table_association" "public_subnet_a_association" {
  subnet_id      = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.public_route_table.id
}

# 퍼블릭 서브넷 C를 퍼블릭 라우트 테이블에 연결
resource "aws_route_table_association" "public_subnet_c_association" {
  subnet_id      = aws_subnet.public_subnet_c.id
  route_table_id = aws_route_table.public_route_table.id
}

# Application Load Balancer (ALB) 생성 (두 개의 퍼블릭 서브넷 사용)
resource "aws_lb" "example_alb" {
  name               = "mokonix-lee-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]   # ALB용 보안 그룹
  subnets            = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_c.id]

  tags = {
    Name = "mokonix-lee-alb"
  }
}

# ALB Target Group 생성
resource "aws_lb_target_group" "example_tg" {
  name     = "mokonix-lee-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.eks_vpc.id

  health_check {
    protocol = "HTTP"
    path     = "/"
    port     = "traffic-port"
  }

  tags = {
    Name = "mokonix-lee-tg"
  }
}

# ALB Listener 생성
resource "aws_lb_listener" "example_listener" {
  load_balancer_arn = aws_lb.example_alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.example_tg.arn
  }
}

# 보안 그룹 생성 (ALB용 + Jenkins)
resource "aws_security_group" "alb_sg" {
  vpc_id = aws_vpc.eks_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "mokonix-lee-alb-sg"
  }
}

# NAT 게이트웨이 생성
resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet_a.id
  tags = {
    Name = "mokonix-lee-nat-gateway"
  }
}

# 프라이빗 서브넷 A (가용영역 ap-northeast-2a)
resource "aws_subnet" "private_subnet_a" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = "200.0.4.0/24"
  availability_zone       = "ap-northeast-2a"
  map_public_ip_on_launch = false
  tags = {
    Name = "mokonix-lee-private-subnet-a"
  }
}

# 프라이빗 서브넷 C (가용영역 ap-northeast-2c)
resource "aws_subnet" "private_subnet_c" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = "200.0.5.0/24"
  availability_zone       = "ap-northeast-2c"
  map_public_ip_on_launch = false
  tags = {
    Name = "mokonix-lee-private-subnet-c"
  }
}

# 프라이빗 라우트 테이블 생성 (NAT 게이트웨이 연결)
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }

  tags = {
    Name = "mokonix-lee-private-route-table"
  }
}

# 프라이빗 서브넷 A를 프라이빗 라우트 테이블에 연결
resource "aws_route_table_association" "private_subnet_a_association" {
  subnet_id      = aws_subnet.private_subnet_a.id
  route_table_id = aws_route_table.private_route_table.id
}

# 프라이빗 서브넷 C를 프라이빗 라우트 테이블에 연결
resource "aws_route_table_association" "private_subnet_c_association" {
  subnet_id      = aws_subnet.private_subnet_c.id
  route_table_id = aws_route_table.private_route_table.id
}

# 보안 그룹 생성 (EKS 노드 그룹용)
resource "aws_security_group" "eks_security_group" {
  vpc_id = aws_vpc.eks_vpc.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ALB와 통신을 위한 규칙 추가
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    security_groups = [aws_security_group.alb_sg.id]  # ALB 보안 그룹과 연결
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    security_groups = [aws_security_group.alb_sg.id]  # ALB 보안 그룹과 연결
  }
  
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    security_groups = [aws_security_group.alb_sg.id]  # ALB 보안 그룹과 연결
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eks-security-group"
  }
}

# EKS 클러스터 역할 생성
resource "aws_iam_role" "eks_cluster_role" {
  name = "mokonix-lee-eks-cluster-role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      }
    }
  ]
}
EOF

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSServicePolicy",
  ]
}

# EKS 클러스터 생성
resource "aws_eks_cluster" "my_eks_cluster" {
  name     = "mokonix-lee-cluster"
  version  = "1.27"
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids = [
      aws_subnet.private_subnet_a.id,
      aws_subnet.private_subnet_c.id
    ]
    endpoint_public_access = true
    endpoint_private_access = true
    security_group_ids = [aws_security_group.eks_security_group.id]
  }

  tags = {
    Name = "mokonix-lee-eks-cluster"
  }
}

# EKS 노드 그룹 역할 생성
resource "aws_iam_role" "eks_node_role" {
  name = "eks-node-role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      }
    }
  ]
}
EOF

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
  ]
}

# EKS 노드 그룹 생성
resource "aws_eks_node_group" "eks_node_group" {
  cluster_name    = aws_eks_cluster.my_eks_cluster.name
  node_group_name = "eks-node-group"
  node_role_arn   = aws_iam_role.eks_node_role.arn

  subnet_ids = [
    aws_subnet.private_subnet_a.id,
    aws_subnet.private_subnet_c.id
  ]

  scaling_config {
    desired_size = 3
    min_size     = 2
    max_size     = 4
  }

  instance_types = ["t3.small"]
  ami_type       = "AL2_x86_64"

  remote_access {
    ec2_ssh_key = "mokolee"
    source_security_group_ids = [aws_security_group.eks_security_group.id]
  }

  tags = {
    Name        = "chanwoo-node"
    Environment = "development"
    Owner       = "chanwoo"
  }
}

# Jenkins EC2 생성
resource "aws_instance" "jenkins_instance" {
  ami           = "ami-0023481579962abd4"
  instance_type = "t3.large"
  key_name = "mokolee"
  subnet_id     = aws_subnet.public_subnet_a.id
  security_groups = [aws_security_group.alb_sg.id]

  tags = {
    Name = "mokonix-lee-jenkins-instance"
  }

  user_data = <<-EOF
          #!/bin/bash
          dnf upgrade -y

          # Java 17 설치
          dnf install -y java-17-amazon-corretto
          
          # Jenkins 설치
          rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
          dnf config-manager --add-repo http://pkg.jenkins.io/redhat-stable/jenkins.repo

          dnf install jenkins -y
          systemctl start jenkins
          systemctl enable jenkins
          
          # Docker 설치
          dnf install docker -y
          systemctl start docker
          systemctl enable docker
          
          # Jenkins 사용자가 Docker 명령을 사용할 수 있도록 설정
          usermod -aG docker jenkins

          # Git 설치
          dnf install git -y

          # Terraform 설치
          dnf install -y yum-utils
          dnf config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
          dnf install -y terraform

          # Hostname을 jenkins로 변경
          hostnamectl set-hostname jenkins
  EOF
}

# Terraform Cloud 백엔드 설정
terraform {
  backend "remote" {
    organization = "songaji-or"

    workspaces {
      name = "terraform-eks"
    }
  }
}
