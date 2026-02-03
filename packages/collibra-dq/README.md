# Collibra DQ Package Storage

Store the Collibra DQ installation package file here.

## Package File

Place the downloaded Collibra DQ package in this directory:
- **File name**: `dq-2025.11-SPARK356-JDK17-package-full.tar`
- **Source**: Download from https://productresources.collibra.com/downloads/data-quality-observability-classic-2025-11/

## S3 Upload

The package is automatically uploaded to S3 during deployment via the `package-upload` module. The EC2 instance downloads it from S3 during boot.

**Process**:
1. Package is uploaded to S3 bucket: `${ACCOUNT_ID}-datashift-${ENV}-packages-${REGION}/collibra-dq/`
2. Upload happens automatically during `package-upload` module deployment
3. EC2 instance downloads from S3 using IAM role permissions

**Upload Time**: ~10-15 minutes for 2.5GB package (depends on network speed)

**Skip Re-upload**: Set `COLLIBRA_DQ_SKIP_PACKAGE_UPLOAD=true` to skip re-uploads if package hasn't changed.

## File Size

The package is typically ~2.5 GB. Package files are automatically ignored by git (see `.gitignore`).
