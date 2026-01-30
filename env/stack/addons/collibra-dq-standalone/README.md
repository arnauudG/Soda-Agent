# Collibra DQ Standalone add-on (EC2 + ALB + RDS)

This add-on deploys Collibra DQ in "standalone" mode on an EC2 instance behind an Application Load Balancer. It also relies on an RDS PostgreSQL database as the metastore.

## What it deploys

Under `env/stack/addons/collibra-dq-standalone`:

- `alb/sg-alb`: security group for the ALB
- `sg-collibra-dq`: security group for the Collibra DQ EC2 instance
- `package-upload`: uploads the Collibra DQ installer package from `packages/collibra-dq/` to S3
- `terragrunt.hcl`: the EC2 instance running Collibra DQ
- `alb`: ALB resources and target group
- `alb/target-group-attachment`: attaches the EC2 instance to the ALB target group

The EC2 module also creates an IAM role/instance profile for the instance. The role name is suffixed with the stack VPC id suffix to avoid colliding with legacy roles from previous runs.
The ALB and target group names are also VPC-suffixed for the same reason.

Related database layer (not in this folder, but part of the full Collibra stack):

- `env/stack/database/rds-collibra-dq/sg-rds`
- `env/stack/database/rds-collibra-dq/rds`

## Prerequisites

For a full deploy:

- `env/stack/network/vpc`
- `env/stack/network/vpc-endpoints`
- `env/stack/database/rds-collibra-dq/sg-rds`
- `env/stack/database/rds-collibra-dq/rds`

## Environment variables

Required (unless you deploy core-only with `--skip-addons`):

- `COLLIBRA_DQ_ADMIN_PASSWORD`
- `COLLIBRA_DQ_LICENSE_KEY`

Optional:

- `COLLIBRA_DQ_OWL_BASE` (default: `/opt/collibra-dq`)
- `COLLIBRA_DQ_SPARK_PACKAGE` (default: `spark-3.5.6-bin-hadoop3.tgz`)
- `COLLIBRA_DQ_PACKAGE_FILENAME` (default: `dq-2025.11-SPARK356-JDK17-package-full.tar`)
- `COLLIBRA_DQ_PACKAGE_URL` (optional override; default is the S3 path created by `package-upload`)
- `COLLIBRA_DQ_LICENSE_NAME` (default: `collibra-partners`)
- `COLLIBRA_DQ_ENABLE_S3_ACCELERATION` (default: `false`)
- `COLLIBRA_DQ_SKIP_PACKAGE_UPLOAD` (default: `false`)

Database optional:

- `COLLIBRA_DQ_RDS_PASSWORD` (if unset, the RDS module generates a random password)

## User data and 16KB limit

EC2 user data is limited to 16 KB. The full Collibra DQ install script exceeds this, so the stack uses a **bootstrap**: user data only contains a short script that downloads the full install script from S3 (`s3://<packages-bucket>/collibra-dq/install_collibra_dq.sh`) and runs it. The full script is uploaded to the same package bucket when you apply the Collibra DQ EC2 layer. The instance role already has S3 read access for the package bucket.

## Package workflow

1) Place the installer file in `packages/collibra-dq/`.
2) Ensure the file name matches `COLLIBRA_DQ_PACKAGE_FILENAME`.
3) The `package-upload` module uploads it to an S3 bucket named like:

- `<account>-<org>-<env>-packages-<region>`

If the bucket already exists (e.g., from a previous test run / legacy infrastructure), the stack will **reuse** it and will **not** try to create or manage the bucket (to avoid accidental deletion and S3 CreateBucket `BucketAlreadyOwnedByYou` errors). The upload step will still put the package object in the bucket.

## Deploy

Recommended (orchestrated):

```bash
./deploy-stack.sh collibra-dq
```

Core-only (skips Collibra app layer and database):

```bash
./deploy-stack.sh collibra-dq --skip-addons
```

Direct (advanced):

```bash
cd env/stack/addons/collibra-dq-standalone
terragrunt apply
```

## Destroy

```bash
./destroy-stack.sh collibra-dq
```

Core-only (keeps add-ons intact):

```bash
./destroy-stack.sh collibra-dq --skip-addons
```

## Verify

Get instance id:

```bash
cd env/stack/addons/collibra-dq-standalone
terragrunt output -raw instance_id
```

Get ALB DNS:

```bash
cd env/stack/addons/collibra-dq-standalone/alb
terragrunt output -raw load_balancer_dns_name
```

Check service status via SSM:

```bash
aws ssm start-session --target <instance_id> --region "$TF_VAR_region"
# on the instance:
sudo systemctl status collibra-dq.service --no-pager -l
```

End-to-end checks:

```bash
./scripts/test-collibra-dq-deployment.sh "$TF_VAR_environment" "$TF_VAR_region"
```

## RDS connectivity model

The RDS security group for Collibra DQ (`env/stack/database/rds-collibra-dq/sg-rds`) currently allows inbound Postgres (5432) from:

- the Collibra DQ EC2 instance security group only

This matches the "minimal Collibra DQ" footprint (no EKS / ops required).

If you later want RDS reachable from EKS nodes or an ops box, do it as an optional allowlist of additional SG IDs (without adding an EKS dependency).

## Troubleshooting

- Package not found: verify `packages/collibra-dq/<COLLIBRA_DQ_PACKAGE_FILENAME>` exists and is readable.
- SSM unavailable: ensure VPC endpoints for SSM are deployed and the instance has the SSM managed policy.
- ALB target unhealthy: check security groups and confirm the service listens on the expected port (default target group backend port is 9000).
- **ALB 502 Bad Gateway or request timed out**: The instance is in a private subnet; the ALB connects to its private IP. The DQ Web app must listen on `0.0.0.0:9000`, not only `127.0.0.1`. The install script sets `OWL_WEB_HTTP_ADDRESS=0.0.0.0` and `-Dhttp.address=0.0.0.0` in `owl-env.sh` and in the systemd unit. For an **existing** instance deployed before this fix, either re-deploy (replace instance so user data runs again) or run the following **on the EC2 instance** (connect first via `aws ssm start-session --target <instance-id> --region <region>`; do not run these on your Mac). On the instance, set `OWL_BASE` (e.g. `OWL_BASE=/opt/collibra-dq` or `OWL_BASE=/opt/collibra-dq/owl` if the package extracted to `owl/`), then: `OWL_ENV="$OWL_BASE/owl-env.sh"; [ -f "$OWL_BASE/owl/owl-env.sh" ] && OWL_ENV="$OWL_BASE/owl/owl-env.sh"; grep -q OWL_WEB_HTTP_ADDRESS "$OWL_ENV" || echo 'export OWL_WEB_HTTP_ADDRESS=0.0.0.0' >> "$OWL_ENV"; grep -q "http.address" "$OWL_ENV" || echo 'export OWL_WEB_OPTS="${OWL_WEB_OPTS:-} -Dhttp.address=0.0.0.0"' >> "$OWL_ENV"; cd "$OWL_BASE" || cd "$OWL_BASE/owl"; ./owlmanage.sh stop=owlweb; sleep 3; ./owlmanage.sh start=owlweb`. Check with `ss -tlnp | grep 9000` (Linux; on the instance) that the process listens on `0.0.0.0:9000`.
- **`/opt/config/owl-env.sh: No such file or directory`** (from `owlmanage.sh`): The package may have extracted with a nested layout (e.g. `owl/config/owl-env.sh`) while `owlmanage.sh` expects `/opt/config` to point to the directory that contains `owl-env.sh`. The install script now links `/opt/config` to the directory where `owl-env.sh` was found and persists paths in `/etc/collibra-dq/opt-paths.conf` so restarts keep the correct symlinks. Re-deploy (replace instance) to get the fix, or on an existing instance: find the real config dir (e.g. `REAL_CONFIG=$(find /opt/collibra-dq -name owl-env.sh -type f | head -1 | xargs dirname)`), then `sudo ln -sfn "$REAL_CONFIG" /opt/config` and ensure `/etc/collibra-dq/opt-paths.conf` has `OWL_CONFIG_DIR` and `OWL_INSTALL_ROOT` set so the systemd service recreates the symlinks on restart.

### RDS: subnet group / parameter group already exists

If a previous attempt created the DB subnet group / parameter group but Terraform state is missing, apply can fail with:

- `DBSubnetGroupAlreadyExists`
- `DBParameterGroupAlreadyExists`

Fix by importing them into state and re-running the deploy:

```bash
cd env/stack/database/rds-collibra-dq/rds
terragrunt init -upgrade

terragrunt import aws_db_subnet_group.this datashift-dev-dqmetastore-collibra-dq-subnet-group
terragrunt import aws_db_parameter_group.this datashift-dev-dqmetastore-collibra-dq-parameter-group
```
