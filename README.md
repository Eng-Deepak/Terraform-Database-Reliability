Terraform + Database Reliability Assessment

PURPOSE
This project has two parts:
1. Run PostgreSQL on your Ubuntu computer using Docker.
2. Write Terraform files that describe AWS infrastructure.

IMPORTANT
You can test the database on your computer.
You can check Terraform files using terraform plan.
Do not run terraform apply unless you really want to create AWS resources. AWS resources such as NAT Gateway, ECS and RDS can cost money.

--------------------------------------------------
PART 1 - OPEN YOUR PROJECT
--------------------------------------------------

Open Ubuntu and run:

cd ~/projects/devops-terraform-db-reliability

This is your main project folder. Run the commands below from this folder unless the guide says otherwise.

--------------------------------------------------
PART 2 - START POSTGRESQL
--------------------------------------------------

Create a file named docker-compose.yml in the main project folder.

Put this text inside it:

services:
  postgres:
    image: postgres:16
    container_name: assessment-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: devops
      POSTGRES_PASSWORD: localpass123
      POSTGRES_DB: bookings
    ports:
      - "127.0.0.1:5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

volumes:
  postgres_data:

Start the database:

docker compose up -d

Check the container:

docker ps

If Docker permission is denied, use sudo before the docker command.

--------------------------------------------------
PART 3 - CREATE DATABASE TABLES
--------------------------------------------------

Create the folder and file:

mkdir -p database/migrations

Create this file:
database/migrations/001_create_tables.sql

Put this SQL inside:

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS hotel_bookings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID NOT NULL,
    hotel_id VARCHAR(100) NOT NULL,
    city VARCHAR(100) NOT NULL,
    checkin_date DATE NOT NULL,
    checkout_date DATE NOT NULL,
    amount NUMERIC(12,2) NOT NULL,
    status VARCHAR(50) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS booking_events (
    id BIGSERIAL PRIMARY KEY,
    booking_id UUID NOT NULL REFERENCES hotel_bookings(id),
    event_type VARCHAR(100) NOT NULL,
    payload JSONB,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

Run the SQL file:

docker exec -i assessment-postgres psql -U devops -d bookings < database/migrations/001_create_tables.sql

Check the tables:

docker exec assessment-postgres psql -U devops -d bookings -c "\\dt"

--------------------------------------------------
PART 4 - ADD SAMPLE DATA
--------------------------------------------------

Create the folder:

mkdir -p database/seeds

Create this file:
database/seeds/seed.sql

Put this SQL inside:

INSERT INTO hotel_bookings (
    org_id, hotel_id, city, checkin_date, checkout_date,
    amount, status, created_at
)
SELECT
    ('00000000-0000-0000-0000-' ||
     LPAD((i % 5 + 1)::TEXT, 12, '0'))::UUID,
    'HOTEL-' || i,
    CASE
        WHEN i % 3 = 0 THEN 'delhi'
        WHEN i % 3 = 1 THEN 'mumbai'
        ELSE 'jaipur'
    END,
    CURRENT_DATE + 10,
    CURRENT_DATE + 12,
    (1000 + i * 100)::NUMERIC(12,2),
    CASE
        WHEN i % 3 = 0 THEN 'confirmed'
        WHEN i % 3 = 1 THEN 'cancelled'
        ELSE 'pending'
    END,
    NOW() - (i || ' days')::INTERVAL
FROM generate_series(1, 120) AS i;

INSERT INTO booking_events (booking_id, event_type, payload)
SELECT id, 'booking_created',
       '{"source":"web","payment":"pending"}'::JSONB
FROM hotel_bookings
ORDER BY created_at DESC
LIMIT 30;

Run the seed file ONCE on a fresh database:

docker exec -i assessment-postgres psql -U devops -d bookings < database/seeds/seed.sql

Check the number of bookings:

docker exec assessment-postgres psql -U devops -d bookings -c "SELECT COUNT(*) FROM hotel_bookings;"

Expected result: 120

Check the number of events:

docker exec assessment-postgres psql -U devops -d bookings -c "SELECT COUNT(*) FROM booking_events;"

Expected result: 30

Do not run the seed file again unless you want to add more rows.

--------------------------------------------------
PART 5 - CREATE AN INDEX AND RUN THE QUERY
--------------------------------------------------

Create an index. This helps PostgreSQL search by city and date:

docker exec assessment-postgres psql -U devops -d bookings -c "CREATE INDEX IF NOT EXISTS idx_bookings_city_created ON hotel_bookings (city, created_at) INCLUDE (org_id, status, amount);"

Run the report query:

docker exec assessment-postgres psql -U devops -d bookings -c "SELECT org_id, status, COUNT(*), SUM(amount) FROM hotel_bookings WHERE city = 'delhi' AND created_at >= NOW() - INTERVAL '30 days' GROUP BY org_id, status;"

See how PostgreSQL runs the query:

docker exec assessment-postgres psql -U devops -d bookings -c "EXPLAIN (ANALYZE, BUFFERS) SELECT org_id, status, COUNT(*), SUM(amount) FROM hotel_bookings WHERE city = 'delhi' AND created_at >= NOW() - INTERVAL '30 days' GROUP BY org_id, status;"

Simple explanation:
- city is the first index column because we search for one city.
- created_at is the second column because we search within a date range.
- INCLUDE stores other columns that the query needs.
- With only 120 rows, PostgreSQL may choose a normal table scan. That is okay.

--------------------------------------------------
PART 6 - BACKUP THE DATABASE
--------------------------------------------------

Create the folder:

mkdir -p scripts backups

Create this file:
scripts/backup.sh

Put this text inside:

#!/bin/bash
set -euo pipefail

mkdir -p backups
BACKUP_FILE="backups/bookings_$(date +%Y%m%d_%H%M%S).dump"

docker exec assessment-postgres pg_dump -U devops -d bookings -Fc > "$BACKUP_FILE"

echo "Backup completed: $BACKUP_FILE"

Make the script executable:

chmod +x scripts/backup.sh

Run the backup:

./scripts/backup.sh

Check the backup file:

ls -lh backups/

--------------------------------------------------
PART 7 - RESTORE THE BACKUP
--------------------------------------------------

Create this file:
scripts/restore.sh

Put this text inside:

#!/bin/bash
set -euo pipefail

BACKUP_FILE="${1:-}"

if [ -z "$BACKUP_FILE" ] || [ ! -f "$BACKUP_FILE" ]; then
    echo "Usage: ./scripts/restore.sh backups/backup-file.dump"
    exit 1
fi

docker exec assessment-postgres dropdb --if-exists -U devops bookings_restore
docker exec assessment-postgres createdb -U devops bookings_restore

docker exec -i assessment-postgres pg_restore \
    -U devops -d bookings_restore \
    --no-owner --no-privileges < "$BACKUP_FILE"

echo "Restore completed."

docker exec assessment-postgres psql -U devops -d bookings_restore \
    -c "SELECT COUNT(*) FROM hotel_bookings;"

Make it executable:

chmod +x scripts/restore.sh

Find your backup filename:

ls backups/

Run restore. Replace the example filename with your real filename:

./scripts/restore.sh backups/bookings_20261111_150000.dump

Check the original database:

docker exec assessment-postgres psql -U devops -d bookings -c "SELECT COUNT(*) FROM hotel_bookings;"

Check the restored database:

docker exec assessment-postgres psql -U devops -d bookings_restore -c "SELECT COUNT(*) FROM hotel_bookings;"

Both should show 120.

--------------------------------------------------
PART 8 - TERRAFORM MODULES
--------------------------------------------------

Create these folders:

mkdir -p infra/modules/network
mkdir -p infra/modules/ecs
mkdir -p infra/modules/rds

Each folder needs three files:

Network module:
infra/modules/network/main.tf
infra/modules/network/variables.tf
infra/modules/network/outputs.tf

ECS module:
infra/modules/ecs/main.tf
infra/modules/ecs/variables.tf
infra/modules/ecs/outputs.tf

RDS module:
infra/modules/rds/main.tf
infra/modules/rds/variables.tf
infra/modules/rds/outputs.tf

What does each file mean?

main.tf:
Contains the AWS resources for that module.

variables.tf:
Contains the input values. For example, VPC CIDR, subnet IDs and database username.

outputs.tf:
Returns useful values to another Terraform module. For example, VPC ID and database endpoint.

What each module does:

NETWORK:
Creates the VPC, public subnets, private subnets, Internet Gateway and routing.

ECS:
Creates the ECS Fargate cluster, application load balancer, task, service and security groups.

RDS:
Creates a PostgreSQL database in private subnets. It allows database access only from the ECS security group.

The module code is separate from the environment configuration. Later, the dev and prod folders call these modules and provide different values.

IMPORTANT SECURITY POINTS:
- ALB is in public subnets.
- ECS is in private subnets.
- RDS is in private database subnets.
- RDS must not be publicly accessible.
- Allow PostgreSQL port 5432 only from the ECS security group.
- Never put real passwords or AWS keys in GitHub.

--------------------------------------------------
PART 9 - DEV AND PROD ENVIRONMENTS
--------------------------------------------------

Create these folders:

mkdir -p infra/envs/dev
mkdir -p infra/envs/prod

Each environment needs a root Terraform configuration that calls the network, ECS and RDS modules.

Keep different values for each environment.

DEV example:
- ECS desired count: 1
- Smaller CPU and memory
- Smaller database instance
- Short backup retention
- Deletion protection can be disabled for a disposable test environment

PROD example:
- ECS desired count: 2 or more
- More CPU and memory
- Larger database instance
- Longer backup retention
- Deletion protection enabled

Use separate Terraform state for dev and prod. Do not share one state file between both environments.

--------------------------------------------------
PART 10 - CHECK TERRAFORM FILES
--------------------------------------------------

From the project root, format the module files:

terraform fmt -recursive infra/modules

Check formatting:

terraform fmt -check -recursive infra/modules

After the dev and prod root configuration files are complete, go into each environment folder and run:

terraform init
terraform validate
terraform plan -refresh=false

These commands check and plan the configuration. They do not create AWS resources.

For plan-only testing without AWS credentials, the provider must be configured for offline planning, and the configuration must not use live AWS data sources. Dummy credentials are not real AWS credentials.

Do not run terraform apply for this local assessment.

--------------------------------------------------
PART 11 - GITHUB ACTIONS
--------------------------------------------------

Create a workflow under:

.github/workflows/

The workflow should run when a pull request is opened or updated.

It should:
1. Check Terraform formatting.
2. Initialize Terraform without a remote backend.
3. Validate Terraform.
4. Run a plan-only check.
5. Save the plan output as an artifact if required.

Do not add an apply step. Do not store AWS access keys in the repository.

--------------------------------------------------
PART 12 - GIT AND GITHUB
--------------------------------------------------

Create a .gitignore file in the project root:

.terraform/
*.tfstate
*.tfstate.*
*.tfplan
backups/
*.dump
.env

Check your files:

git status

Create a Git commit:

git init
git add .
git commit -m "Complete Terraform database reliability assessment"
git branch -M main

Connect your GitHub repository. Replace YOUR_USERNAME with your GitHub username:

git remote add origin https://github.com/YOUR_USERNAME/devops-terraform-db-reliability.git
git push -u origin main

If a remote already exists, check it first with:

git remote -v

Never push passwords, AWS keys, database backups or Terraform state files.

--------------------------------------------------
FINAL CHECKLIST
--------------------------------------------------

[ ] PostgreSQL container is running.
[ ] hotel_bookings table exists.
[ ] booking_events table exists.
[ ] At least 100 bookings are inserted.
[ ] Booking events are inserted.
[ ] Index is created.
[ ] Report query works.
[ ] EXPLAIN ANALYZE output is checked.
[ ] Backup file is created.
[ ] Restore database is created.
[ ] Original and restored booking counts match.
[ ] Network Terraform module has all three files.
[ ] ECS Terraform module has all three files.
[ ] RDS Terraform module has all three files.
[ ] Dev and prod root configurations call the modules.
[ ] Terraform fmt, validate and plan checks pass.
[ ] GitHub repository contains the project.
[ ] No secrets, backups or Terraform state are committed.

--------------------------------------------------
SIMPLE DEMO EXPLANATION
--------------------------------------------------

"I created a PostgreSQL database using Docker Compose. I created two tables for hotel bookings and booking events. I inserted 120 sample bookings and created an index to help the city and date search. I tested the query using EXPLAIN ANALYZE.

I also created a backup script and a restore script. I restored the backup into a separate database and checked that both databases had the same number of bookings.

For AWS infrastructure, I separated Terraform code into network, ECS and RDS modules. The design puts the load balancer in public subnets, the application in private subnets, and the database in private subnets. I prepared separate dev and prod configurations and checked the Terraform code without deploying AWS resources."

END OF GUIDE
"""
out="/mnt/data/DevOps_Project_Simple_Guide.txt"
pypandoc.convert_text(content, "plain", format="md", outputfile=out, extra_args=["--standalone"])
print(out, os.path.getsize(out))

