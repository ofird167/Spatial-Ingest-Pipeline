# 1. Declare the subnet group FIRST
resource "aws_db_subnet_group" "db_subnets" {
  name       = "main-db-subnet-group"
  # Ensure these subnets exist in your vpc.tf
  subnet_ids = [aws_subnet.private_1.id, aws_subnet.private_2.id]
  
  tags = {
    Name = "Main DB subnet group"
  }
}

# 2. Declare the DB instance, referencing the group declared above
resource "aws_db_instance" "default" {
  allocated_storage      = 20
  engine                 = "postgres"
  engine_version         = "15"
  instance_class         = "db.t3.micro"
  username               = "dbadmin" # Changed from "admin" to "dbadmin"
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.db_subnets.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  skip_final_snapshot    = true
}