# --- Existing Data and LB/ASG configs ---

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }
}

# --- ADDED: Bastion Host Instance ---
resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public_1.id # Must be a public subnet
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id] # Need to create this
  associate_public_ip_address = true
  key_name                    = "ofir" # REPLACE WITH YOUR KEY PAIR NAME

  tags = {
    Name = "bastion-host"
  }
}

# --- ADDED: Security Group for Bastion ---
resource "aws_security_group" "bastion_sg" {
  name   = "bastion-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # For dev, limit this to your home IP for better security
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- Your existing LB and ASG resources ---
resource "aws_lb" "web_alb" {
  name               = "web-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]
}

resource "aws_lb_target_group" "web_tg" {
  name     = "web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

resource "aws_launch_template" "app_lt" {
  name_prefix   = "app-lt-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"
  iam_instance_profile { name = aws_iam_instance_profile.ec2_profile.name }
}

resource "aws_autoscaling_group" "app_asg" {
  desired_capacity    = 1
  max_size            = 2
  min_size            = 1
  vpc_zone_identifier = [aws_subnet.private_1.id, aws_subnet.private_2.id]
  
  launch_template {
    id      = aws_launch_template.app_lt.id
    version = "$Latest"
  }
  
  target_group_arns = [aws_lb_target_group.web_tg.arn]
}