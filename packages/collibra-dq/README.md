# Collibra DQ Package Storage

Store the Collibra DQ installation package file here.

## Package File

Place the downloaded Collibra DQ package in this directory:
- **File name**: `dq-2025.11-SPARK356-JDK17-package-full.tar.gz` (or `.zip` if you compress it)
- **Source**: Download from https://productresources.collibra.com/downloads/data-quality-observability-classic-2025-11/

## Usage

After placing the package file here, you can upload it to the EC2 instance manually via SSM Session Manager or any other method you prefer.

The installation script will automatically detect if the package file already exists in `/opt/collibra-dq/` and skip the download step.

## File Size

The package is typically several GB in size. Package files are automatically ignored by git.
