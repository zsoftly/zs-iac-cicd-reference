# Jenkins Pipeline

Placeholder directory for Jenkins pipeline configuration.

## Generate Your Pipeline

Use AI to generate pipelines specific to your organization. Provide:

1. **Your org context** - naming conventions, AWS accounts, regions
2. **The patterns from** `docs/pipeline-rules.md`
3. **Your specific tools** - Terraform version, Ansible collections, etc.

## Trigger Rules

Pipelines should ONLY trigger on:

| Event                          | Triggers Pipeline | Why                          |
| ------------------------------ | ----------------- | ---------------------------- |
| Feature branch push            | **NO**            | Wasteful - no value until PR |
| PR opened/updated              | YES               | Ready for review and testing |
| Push to main                   | YES               | Merged code ready for deploy |
| Manual (Build with Parameters) | YES               | Explicit user action         |

## Jenkins Architecture

### Multibranch Pipeline

```
Jenkins Multibranch Pipeline
├── Branch Sources: GitHub/GitLab
├── Build Configuration: Jenkinsfile
└── Scan Triggers: Webhooks or polling

Filter branches:
- main branch: always build
- PR branches: build on PR events
- Feature branches: DO NOT build (filter out)
```

### Shared Library (Optional)

```
jenkins-shared-library/
├── vars/
│   ├── awsAuth.groovy      # Role chaining
│   ├── terraformPlan.groovy
│   └── terraformApply.groovy
└── src/
    └── org/yourorg/
        └── Pipeline.groovy
```

## Example Prompt for AI

```
Generate a Jenkins declarative pipeline for Terraform with:
- Org: <your-org>
- AWS accounts: dev (111111111111), prod (222222222222)
- Regions: ca-central-1 (primary), ca-west-1 (DR)
- State bucket: <org>-tfstate-<account>-<region>
- Role chaining: cicd-oidc-role -> cicd-admin-role

Follow the trigger and deployment rules from docs/pipeline-rules.md:
- Only trigger on PR, main branch, or manual
- Never trigger on feature branch pushes
- Dev deployable from PR, other envs main only
- Prod requires CHANGE_REQUEST parameter
```

## Key Jenkins Concepts

| Concept             | Implementation                                  |
| ------------------- | ----------------------------------------------- |
| Skip feature branch | Branch filter in Multibranch config             |
| PR condition        | `when { changeRequest() }`                      |
| Main condition      | `when { branch 'main' }`                        |
| Manual trigger      | `input` step or Build with Parameters           |
| CR parameter        | `parameters { string(name: 'CHANGE_REQUEST') }` |
| Path filter         | `when { changeset "**/*.tf" }`                  |
| Environment gates   | `input` step with approvers                     |

## Files to Generate

| File              | Purpose                           |
| ----------------- | --------------------------------- |
| `Jenkinsfile`     | Main pipeline (copy to repo root) |
| `shared-library/` | Optional shared library for reuse |

## Branch Filtering

Configure in Multibranch Pipeline:

```groovy
// Discover branches
branchSources {
  github {
    // Only build main and PRs, not feature branches
    traits {
      headRegexFilter {
        regex: 'main|PR-.*'
      }
    }
  }
}
```

Or in Jenkinsfile:

```groovy
pipeline {
  agent any

  // Skip if not PR or main
  when {
    anyOf {
      branch 'main'
      changeRequest()
    }
  }

  stages {
    // ...
  }
}
```
