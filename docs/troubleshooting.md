# Troubleshooting

Common issues and solutions.

## Authentication

| Issue                       | Cause                  | Solution                        |
| --------------------------- | ---------------------- | ------------------------------- |
| IMDv2 timeout in container  | Hop limit = 1          | Set hop limit to 2+             |
| Token expired mid-pipeline  | Long job exceeds TTL   | Re-authenticate periodically    |
| Cross-account access denied | Missing trust policy   | Add source role to trust policy |
| OIDC role assumption fails  | Wrong audience/subject | Check OIDC provider conditions  |

## Terraform

| Issue                   | Cause                | Solution                       |
| ----------------------- | -------------------- | ------------------------------ |
| State lock deadlock     | Previous job crashed | `terraform force-unlock <ID>`  |
| Plan artifact too large | Large state file     | Compress with gzip             |
| Init too slow           | No plugin cache      | Enable `TF_PLUGIN_CACHE_DIR`   |
| Format check fails      | Unformatted code     | Run `terraform fmt -recursive` |

## Ansible

| Issue                    | Cause                     | Solution                              |
| ------------------------ | ------------------------- | ------------------------------------- |
| Vault decrypt fails      | Wrong password or newline | Use `printf '%s'` not `echo`          |
| Dynamic inventory fails  | Missing EC2 permissions   | Add ec2:Describe\* permissions        |
| SSH timeout              | Security group or key     | Check SG rules, key permissions (600) |
| Collection download slow | No cache                  | Cache in S3 by requirements.yml hash  |

## Pipeline

| Issue                    | Cause             | Solution                                            |
| ------------------------ | ----------------- | --------------------------------------------------- |
| Concurrent runs conflict | No serialization  | Use resource_group (GitLab) or concurrency (GitHub) |
| Artifact not found       | Name mismatch     | Ensure upload/download names match                  |
| Job timeout              | Long-running task | Increase timeout or split job                       |

## Emergency

**Force unlock state:**

```
terraform force-unlock <LOCK_ID>
```

**State rollback:**

```
aws s3api list-object-versions --bucket <bucket> --prefix <key>
aws s3api get-object --bucket <bucket> --key <key> --version-id <id> terraform.tfstate
```
