# Scripts Directory

This directory contains deployment, destruction, and utility scripts organized by purpose.

## Structure

```
scripts/
├── deploy/              # Deployment scripts
│   ├── deploy-collibra-dq.sh
│   └── ...
├── destroy/             # Destruction scripts
│   └── ...
├── utils/               # Utility and helper scripts
│   ├── check-deployment-status.sh
│   └── ...
└── README.md           # This file
```

## Usage

### Deployment Scripts

**Collibra DQ Standalone**:
```bash
./scripts/deploy/deploy-collibra-dq.sh <env>
```

### Destruction Scripts

**Collibra DQ Standalone**:
```bash
./scripts/destroy/destroy-collibra-dq.sh <env>
```

### Utility Scripts

**Check Deployment Status**:
```bash
./scripts/utils/check-deployment-status.sh <env>
```

## Root-Level Scripts

The following scripts remain in the root directory for convenience:

- `bootstrap.sh` - One-time environment bootstrap
- `deploy.sh` - Main Soda Agent deployment
- `destroy.sh` - Main Soda Agent destruction
- `destroy-bootstrap.sh` - Bootstrap destruction

These are the primary entry points and are kept in root for easy access.
