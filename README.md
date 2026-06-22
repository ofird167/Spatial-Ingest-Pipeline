# ASTERRA DevOps Technical Assignment - Spatial Ingest Pipeline

This repository contains the complete event-driven spatial data ingestion pipeline and containerized application suite built for the ASTERRA DevOps technical assignment.

---

## 1. Repository Architecture

```text
├── .github/workflows/
│   └── deploy.yml          # GitHub Actions CI/CD pipeline
├── helm/
│   ├── backend/            # Kubernetes Helm Chart for Flask API
│   ├── database/           # Kubernetes Helm Chart for PostgreSQL
│   └── frontend/           # Kubernetes Helm Chart for Frontend
├── src/
│   └── backend/
│       ├── app.py          # Dual-Mode Spatial Processor (Flask & Lambda)
│       ├── requirements.txt
│       └── Dockerfile
├── terraform/              # Infrastructure as Code templates
│   ├── compute.tf          # Bastion host, target groups, launch templates, ASG
│   ├── database.tf         # RDS subnet groups, DB instances
│   ├── iam.tf              # IAM Roles and policies
│   ├── lambda.tf           # Private VPC Lambda deployment
│   ├── main.tf             # Providers and S3 Backend
│   ├── s3.tf               # Ingest S3 Bucket & Trigger Notification
│   ├── security.tf         # Authorization Security Groups (DB, Lambda, Bastion)
│   ├── variables.tf
│   └── vpc.tf              # Networking, Subnets, Routing, and S3 Gateway Endpoint
├── sample.geojson          # Test GeoJSON data
├── SUBMISSION.md           # Submission Candidate Half-Pager
└── README.md               # Setup and Deployment Instructions
```

---

## 2. Infrastructure & Ingest Architecture

This pipeline implements a secure, highly-available event-driven spatial processing architecture:
1. **Private Subnets:** Both the database (RDS PostgreSQL + PostGIS) and the ingestion Lambda function are strictly located inside **VPC Private Subnets** with zero direct public internet routing.
2. **S3 Gateway VPC Endpoint:** Because the Lambda is inside the private VPC network, it accesses your S3 Ingest Bucket securely and internally using an **S3 Gateway VPC Endpoint**, completely avoiding costly NAT Gateways.
3. **Dual-Mode Codebase:** The application (`src/backend/app.py`) can run as an AWS Lambda function triggered on S3 uploads, or as a containerized Flask REST API listening on port `8080` (for Helm/Kubernetes clusters).

---

## 3. Getting Started & Deployment

### Prerequisites
* Terraform `~> 1.0`
* AWS CLI installed and configured
* PostgreSQL client (`psql`) installed

### Deployment Steps
1. Navigate to the `terraform/` directory:
   ```bash
   cd terraform
   ```
2. Initialize Terraform:
   ```bash
   terraform init
   ```
3. Configure your database password inside `terraform.tfvars`:
   ```hcl
   db_password = "your-secure-password"
   ```
4. Deploy the infrastructure:
   ```bash
   terraform apply -auto-approve
   ```
   *This will output the `bastion_public_ip` and `db_endpoint` once complete!*

---

## 4. End-to-End Ingestion Verification

Once deployed, follow these steps to test the automatic trigger and inspect the PostGIS geometries:

### Step A: Upload GeoJSON to S3
Upload the provided test `sample.geojson` file to your newly created S3 Ingest Bucket:
```bash
aws s3 cp sample.geojson s3://<your-s3-bucket-name>/sample.geojson
```
*This instantly fires the S3 ObjectCreated trigger, executes the Lambda, enables PostGIS, and parses/inserts features.*

### Step B: Open the SSH Tunnel
Establish a secure SQL port-forwarding bridge through the public Bastion host to access the private database:
```bash
ssh -o StrictHostKeyChecking=no -L 5432:<db-endpoint>:5432 -i ofir.pem ec2-user@<bastion-public-ip> -N
```

### Step C: Query Loaded Features via psql
In a new terminal window, connect to your AWS RDS database:
```bash
psql -h localhost -p 5432 -U dbadmin -d postgres
```
When prompted, type your `db_password` (e.g. `15975312300`). Run this SQL query to verify the ingested spatial geometries:
```sql
SELECT id, properties->>'city' AS city, ST_AsText(geom) AS geometry FROM geojson_features;
```

---

## 5. CI/CD Deployment Pipeline

The project includes an automated GitHub Actions pipeline in [.github/workflows/deploy.yml](file:///home/ofird/projects/Spatial-Ingest-Pipeline/.github/workflows/deploy.yml).

### Configuring GitHub Secrets
Add these secrets to your GitHub repository under **Settings -> Secrets and variables -> Actions**:
* `AWS_ACCESS_KEY_ID`: Your AWS access key ID.
* `AWS_SECRET_ACCESS_KEY`: Your AWS secret access key.
* `DB_PASSWORD`: The database password for Terraform variables.

Every push or PR merge to the `main` branch will automatically lint your Python code (`flake8`), package/push your Docker container to AWS ECR, and execute `terraform apply`.
