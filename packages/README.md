# Packages

This folder holds large, vendor-provided artifacts required by some stacks. These files are **not** committed to git (see `.gitignore`).

- **`packages/collibra-dq/`** — Collibra DQ installer package used by the `package-upload` module. See [packages/collibra-dq/README.md](collibra-dq/README.md).

For upload process, S3 bucket naming, and env vars (`COLLIBRA_DQ_SKIP_PACKAGE_UPLOAD`, etc.), see the root [README.md](../README.md) (Package Deployment and Environment Variables sections).
