# CI/CD Caching Strategy

Caching dependencies dramatically reduces pipeline execution time.

## The Problem

| Task                         | Without Cache | With Cache | Savings |
| ---------------------------- | ------------- | ---------- | ------- |
| Download Terraform providers | 30-60s        | 2-5s       | ~90%    |
| Install Ansible collections  | 20-40s        | 1-3s       | ~92%    |
| pip install                  | 45-90s        | 3-8s       | ~91%    |
| npm install                  | 60-120s       | 5-15s      | ~88%    |
| go mod download              | 30-60s        | 2-5s       | ~92%    |
| docker pull base images      | 60-120s       | 5-10s      | ~92%    |

**A 5-minute pipeline becomes 1-2 minutes with proper caching.**

## Cache Locations

### Artifact Bucket (PLT Account)

```
s3://${ORG}-cicd-artifacts-${PLT_ACCOUNT_ID}-${REGION}/
├── terraform-providers/{hash}/     # 7 day TTL
├── terraform-plugins/{os}-{arch}/  # 7 day TTL
├── ansible-collections/{hash}/     # 3 day TTL
├── pip-cache/{hash}/               # 3 day TTL
├── node-modules/{hash}/            # 3 day TTL
├── go-mod/{hash}/                  # 7 day TTL
├── docker-layers/{hash}/           # 1 day TTL
└── terraform-plans/{run-id}/       # 1 day TTL
```

### Platform-Native Cache

| Platform       | Cache Type    | Limit   | Scope      |
| -------------- | ------------- | ------- | ---------- |
| GitHub Actions | actions/cache | 10 GB   | Repository |
| GitLab CI      | CI/CD cache   | Per-job | Runner     |
| Jenkins        | Workspace     | Local   | Node       |

## Cache Keys

Use content-based hashing for cache keys:

```bash
# Terraform providers
terraform-providers-$(sha256sum .terraform.lock.hcl | cut -d' ' -f1)

# Ansible collections
ansible-collections-$(sha256sum requirements.yml | cut -d' ' -f1)

# Python pip
pip-cache-$(sha256sum requirements.txt | cut -d' ' -f1)

# Node.js
node-modules-$(sha256sum package-lock.json | cut -d' ' -f1)

# Go
go-mod-$(sha256sum go.sum | cut -d' ' -f1)
```

## Expiration Policy (CRITICAL)

**Caches MUST expire to receive security updates.**

| Cache Type          | TTL    | Reason                              |
| ------------------- | ------ | ----------------------------------- |
| Terraform providers | 7 days | Large, versioned, less frequent CVE |
| Go modules          | 7 days | Versioned, less frequent updates    |
| Ansible collections | 3 days | May have security fixes             |
| Python packages     | 3 days | Frequent security patches           |
| Node modules        | 3 days | Frequent security patches           |
| Container layers    | 1 day  | Base images get CVE fixes daily     |
| Plan artifacts      | 1 day  | Job-specific, no reuse value        |

### Why Not Longer TTLs?

| Risk              | Impact                         |
| ----------------- | ------------------------------ |
| CVE in cached dep | Vulnerable until cache expires |
| Stale versions    | Missing bug fixes              |
| Cache poisoning   | Longer exposure window         |
| Storage costs     | Unbounded growth               |

## Terraform Caching

### Plugin Cache Directory

```bash
# Set environment variable
export TF_PLUGIN_CACHE_DIR="$HOME/.terraform.d/plugin-cache"

# Or use CLI config
cat > ~/.terraformrc <<EOF
plugin_cache_dir = "$HOME/.terraform.d/plugin-cache"
EOF
```

### S3 Backend Cache

```bash
#!/bin/bash
# scripts/terraform-cache.sh

set -euo pipefail

CACHE_BUCKET="${ARTIFACT_BUCKET:-}"
LOCK_FILE=".terraform.lock.hcl"

if [[ -z "$CACHE_BUCKET" ]]; then
  echo "[WARN] ARTIFACT_BUCKET not set, skipping cache"
  exit 0
fi

CACHE_KEY="terraform-providers-$(sha256sum "$LOCK_FILE" | cut -d' ' -f1)"

download_cache() {
  echo "[INFO] Downloading Terraform cache..."
  aws s3 cp "s3://${CACHE_BUCKET}/${CACHE_KEY}.tar.gz" /tmp/tf-cache.tar.gz 2>/dev/null || {
    echo "[INFO] No cache found, will create after init"
    return 1
  }
  mkdir -p ~/.terraform.d/plugin-cache
  tar -xzf /tmp/tf-cache.tar.gz -C ~/.terraform.d/
  echo "[OK] Cache restored"
}

upload_cache() {
  if [[ ! -d ~/.terraform.d/plugin-cache ]]; then
    echo "[WARN] No plugin cache to upload"
    return 0
  fi
  echo "[INFO] Uploading Terraform cache..."
  tar -czf /tmp/tf-cache.tar.gz -C ~/.terraform.d/ plugin-cache/
  aws s3 cp /tmp/tf-cache.tar.gz "s3://${CACHE_BUCKET}/${CACHE_KEY}.tar.gz"
  echo "[OK] Cache uploaded"
}

case "${1:-download}" in
  download) download_cache ;;
  upload)   upload_cache ;;
  *)        echo "Usage: $0 {download|upload}" >&2; exit 1 ;;
esac
```

### Provider Mirror (Air-Gapped)

```hcl
# For air-gapped or restricted environments
provider_installation {
  filesystem_mirror {
    path    = "/opt/terraform/providers"
    include = ["registry.terraform.io/*/*"]
  }
  direct {
    exclude = ["registry.terraform.io/*/*"]
  }
}
```

## Ansible Caching

### Collection Cache

```bash
# Install to cacheable path
export ANSIBLE_COLLECTIONS_PATH=~/.ansible/collections
ansible-galaxy collection install -r requirements.yml -p "$ANSIBLE_COLLECTIONS_PATH"
```

### S3 Backend Cache

```bash
#!/bin/bash
# scripts/ansible-cache.sh

set -euo pipefail

CACHE_BUCKET="${ARTIFACT_BUCKET:-}"
REQ_FILE="requirements.yml"

if [[ -z "$CACHE_BUCKET" ]]; then
  echo "[WARN] ARTIFACT_BUCKET not set, skipping cache"
  exit 0
fi

CACHE_KEY="ansible-collections-$(sha256sum "$REQ_FILE" | cut -d' ' -f1)"

download_cache() {
  aws s3 cp "s3://${CACHE_BUCKET}/${CACHE_KEY}.tar.gz" /tmp/ansible-cache.tar.gz 2>/dev/null || return 1
  mkdir -p ~/.ansible/collections
  tar -xzf /tmp/ansible-cache.tar.gz -C ~/.ansible/
  echo "[OK] Ansible cache restored"
}

upload_cache() {
  if [[ ! -d ~/.ansible/collections ]]; then
    return 0
  fi
  tar -czf /tmp/ansible-cache.tar.gz -C ~/.ansible/ collections/
  aws s3 cp /tmp/ansible-cache.tar.gz "s3://${CACHE_BUCKET}/${CACHE_KEY}.tar.gz"
  echo "[OK] Ansible cache uploaded"
}

case "${1:-download}" in
  download) download_cache ;;
  upload)   upload_cache ;;
  *)        echo "Usage: $0 {download|upload}" >&2; exit 1 ;;
esac
```

## GitHub Actions

### Terraform Cache

```yaml
jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Cache Terraform providers
        uses: actions/cache@v4
        with:
          path: ~/.terraform.d/plugin-cache
          key: terraform-${{ runner.os }}-${{ hashFiles('**/.terraform.lock.hcl') }}
          restore-keys: |
            terraform-${{ runner.os }}-

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3

      - name: Terraform Init
        run: terraform init
        env:
          TF_PLUGIN_CACHE_DIR: ~/.terraform.d/plugin-cache
```

### Ansible Cache

```yaml
jobs:
  ansible:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Cache Ansible collections
        uses: actions/cache@v4
        with:
          path: ~/.ansible/collections
          key: ansible-${{ hashFiles('**/requirements.yml') }}
          restore-keys: |
            ansible-

      - name: Install collections
        run: ansible-galaxy collection install -r requirements.yml
        env:
          ANSIBLE_COLLECTIONS_PATH: ~/.ansible/collections
```

### S3 Backend Cache

```yaml
jobs:
  terraform:
    runs-on: ubuntu-latest
    env:
      ARTIFACT_BUCKET: ${{ vars.ARTIFACT_BUCKET }}
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.RUNNER_ROLE_ARN }}
          aws-region: ca-central-1

      - name: Download cache from S3
        run: |
          CACHE_KEY="terraform-$(sha256sum .terraform.lock.hcl | cut -d' ' -f1)"
          aws s3 cp "s3://${ARTIFACT_BUCKET}/${CACHE_KEY}.tar.gz" /tmp/cache.tar.gz || true
          if [[ -f /tmp/cache.tar.gz ]]; then
            mkdir -p ~/.terraform.d/plugin-cache
            tar -xzf /tmp/cache.tar.gz -C ~/.terraform.d/
          fi

      - name: Terraform Init
        run: terraform init
        env:
          TF_PLUGIN_CACHE_DIR: ~/.terraform.d/plugin-cache

      - name: Upload cache to S3
        if: always()
        run: |
          CACHE_KEY="terraform-$(sha256sum .terraform.lock.hcl | cut -d' ' -f1)"
          tar -czf /tmp/cache.tar.gz -C ~/.terraform.d/ plugin-cache/ 2>/dev/null || true
          aws s3 cp /tmp/cache.tar.gz "s3://${ARTIFACT_BUCKET}/${CACHE_KEY}.tar.gz" || true
```

## GitLab CI

### Terraform Cache

```yaml
variables:
  TF_PLUGIN_CACHE_DIR: ${CI_PROJECT_DIR}/.terraform-cache

.terraform-cache:
  cache:
    key:
      files:
        - .terraform.lock.hcl
      prefix: terraform
    paths:
      - .terraform-cache/
    policy: pull-push

terraform-init:
  extends: .terraform-cache
  script:
    - mkdir -p ${TF_PLUGIN_CACHE_DIR}
    - terraform init
```

### Ansible Cache

```yaml
.ansible-cache:
  cache:
    key:
      files:
        - ansible/requirements.yml
      prefix: ansible
    paths:
      - .ansible-collections/
    policy: pull-push

ansible-playbook:
  extends: .ansible-cache
  variables:
    ANSIBLE_COLLECTIONS_PATH: ${CI_PROJECT_DIR}/.ansible-collections
  script:
    - ansible-galaxy collection install -r requirements.yml
    - ansible-playbook playbooks/site.yml
```

## Jenkins

### Pipeline Cache

```groovy
pipeline {
    agent any

    environment {
        TF_PLUGIN_CACHE_DIR = "${WORKSPACE}/.terraform-cache"
        ANSIBLE_COLLECTIONS_PATH = "${WORKSPACE}/.ansible-collections"
    }

    stages {
        stage('Restore Cache') {
            steps {
                sh '''
                    mkdir -p ${TF_PLUGIN_CACHE_DIR}
                    mkdir -p ${ANSIBLE_COLLECTIONS_PATH}
                '''
                // Use shared library or S3 for persistent cache
            }
        }

        stage('Terraform Init') {
            steps {
                sh 'terraform init'
            }
        }
    }

    post {
        always {
            // Save cache to S3 or shared storage
        }
    }
}
```

## Cache Invalidation

### Force Refresh

```yaml
# GitHub Actions - add date to key
key: terraform-${{ runner.os }}-${{ hashFiles('**/.terraform.lock.hcl') }}-${{ github.run_id }}

# Or use workflow input
on:
  workflow_dispatch:
    inputs:
      refresh_cache:
        description: "Force cache refresh"
        type: boolean
        default: false

jobs:
  build:
    steps:
      - uses: actions/cache@v4
        if: ${{ !inputs.refresh_cache }}
        # ...
```

### Scheduled Refresh

```yaml
# Weekly cache refresh for security
on:
  schedule:
    - cron: "0 0 * * 0" # Every Sunday at midnight

jobs:
  refresh-cache:
    runs-on: ubuntu-latest
    steps:
      - name: Clear GitHub cache
        run: |
          gh cache delete --all
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## Storage Options

| Provider          | Pros                     | Cons               | Cost       |
| ----------------- | ------------------------ | ------------------ | ---------- |
| **AWS S3**        | Native IAM, low latency  | Egress fees        | ~$0.023/GB |
| **Cloudflare R2** | Zero egress, global edge | Separate auth      | ~$0.015/GB |
| **GitHub Cache**  | Built-in, no setup       | 10GB limit, 7d TTL | Free       |
| **GitLab Cache**  | Built-in                 | Runner-scoped      | Free       |
| **Self-hosted**   | Full control             | Maintenance burden | Varies     |

## Cloudflare R2 Setup

```bash
# Install wrangler
npm install -g wrangler

# Create R2 bucket
wrangler r2 bucket create cicd-artifacts

# Generate API token with R2 permissions
# Store in CI/CD secrets: CF_ACCOUNT_ID, CF_R2_ACCESS_KEY_ID, CF_R2_SECRET_ACCESS_KEY
```

```yaml
# GitHub Actions with R2
- name: Configure R2
  run: |
    aws configure set aws_access_key_id ${{ secrets.CF_R2_ACCESS_KEY_ID }}
    aws configure set aws_secret_access_key ${{ secrets.CF_R2_SECRET_ACCESS_KEY }}
    aws configure set region auto

- name: Download cache from R2
  run: |
    aws s3 cp s3://cicd-artifacts/terraform-cache.tar.gz /tmp/ \
      --endpoint-url https://${{ secrets.CF_ACCOUNT_ID }}.r2.cloudflarestorage.com || true
```

## Best Practices

1. **Use content-based keys** - Hash lockfiles, not branches
2. **Set appropriate TTLs** - Balance speed vs security
3. **Clean up regularly** - Lifecycle rules or scheduled jobs
4. **Monitor cache hit rates** - Track effectiveness
5. **Test cache restoration** - Verify cached content works
6. **Document cache keys** - Make invalidation predictable
