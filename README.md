# Spotify Pipeline

An automated data pipeline that captures my Spotify listening history and stores it in AWS, built with Terraform.

Every 6 hours a scheduled Lambda fetches recently played tracks from the Spotify API and writes the raw JSON to S3. That write triggers a second Lambda, which flattens the nested JSON into a typed Parquet file. Athena queries the result with SQL.

Built as a learning project for infrastructure as code, serverless architecture, event-driven design and AWS IAM.

---

## Architecture

```
EventBridge (every 6 hours)
        │
        ▼
  Ingest Lambda ──────▶ Spotify API
        │                  ▲
        │                  │ credentials
        │             SSM Parameter Store
        ▼
   S3: recently_played/dt=YYYY-MM-DD/*.json
        │
        │ (S3 ObjectCreated event)
        ▼
 Transform Lambda
        │
        ▼
   S3: processed/recently_played/dt=YYYY-MM-DD/*.parquet
        │
        ▼
   Athena (Glue catalog table, partition projection)
```

Both Lambdas run from the same container image in ECR, with `image_config.command` selecting which handler runs. Each has its own IAM role scoped to only what it needs.

---

## Repository layout

```
.
├── Infrastructure/                  # all Terraform — run commands from here
│   ├── versions.tf         # Terraform and provider versions, S3 backend
│   ├── variables.tf        # project name, region, image tag
│   ├── s3.tf               # raw data bucket, Athena results bucket
│   ├── ssm.tf              # encrypted Spotify credentials
│   ├── iam.tf              # one role per Lambda
│   ├── lambda.tf           # both functions, log groups, permissions
│   ├── eventbridge.tf      # schedule rule and target
│   ├── athena.tf           # Athena workgroup, Glue database and table
│   └── outputs.tf
├── Ingest/
│   ├── Dockerfile          # AWS Lambda Python base image
│   ├── handler.py          # ingest: Spotify API → raw JSON in S3
│   ├── transform.py        # transform: raw JSON → Parquet
│   └── requirements.txt
├── Athena/
│   └── queries/            # analytical queries
└── README.md
```

---

## AWS resources

| Resource | Purpose |
| --- | --- |
| S3 bucket | Raw JSON and processed Parquet, in separate prefixes |
| S3 bucket (Athena) | Query results |
| S3 bucket (state) | Terraform state — created outside Terraform, versioned |
| SSM Parameter Store | Spotify client ID, secret and refresh token, encrypted |
| ECR repository | Container image, keeping the 5 most recent |
| Ingest Lambda | Fetches from Spotify, writes raw JSON |
| Transform Lambda | Flattens JSON to Parquet on S3 event |
| EventBridge rule | Triggers the ingest every 6 hours |
| Glue catalog | Database and table definition for Athena |
| IAM roles | One per function, least privilege |
| CloudWatch log groups | 14-day retention |

---

## Picking the project up again

```bash
aws login                 # browser sign-in with MFA, temporary credentials
cd Infrastructure
terraform init            # reconnects to the S3 backend
terraform plan            # should report no changes
```

State lives in S3, so this works from any machine with AWS access. Nothing is stored locally that matters.

**Where things live, for future reference**

- Terraform state: the `anele-tfstate-*` S3 bucket, versioned
- Container image: ECR repository `spotify-pipeline-ingest`, tagged `v1`, `v2`, …
- Spotify credentials: SSM Parameter Store under `/spotify-pipeline/spotify/`
- Spotify app registration: the Spotify developer dashboard, with redirect URI on port 9090

---

## How credentials work

No long-lived AWS access keys exist anywhere in this project.

**For me:** `aws login` signs in through the browser with MFA and issues temporary credentials that refresh themselves. Terraform and the AWS CLI pick these up automatically, so the provider block carries only a region.

**For the Lambdas:** each function assumes its own IAM role at runtime, and AWS supplies fresh credentials on every invocation.

**For Spotify:** the client ID, secret and refresh token live in SSM Parameter Store as encrypted `SecureString` parameters. Terraform creates each with a placeholder and `ignore_changes` on `value`; the real values are set separately with `aws ssm put-parameter`. Nothing sensitive reaches the Terraform state file.

The refresh token came from a one-time browser authorisation. Spotify's client-credentials flow only reaches public data, so reading personal listening history needs the authorisation-code flow, which produces a refresh token that does not expire.

Scopes granted: `user-read-recently-played`, `user-top-read`, `user-read-currently-playing`.

---

## Deploying a change

**1. Build and push a new image tag**

```bash
cd Ingest
ECR_URL="$(cd ../infra && terraform output -raw ecr_repository_url)"

DOCKER_BUILDKIT=0 docker build -t "$ECR_URL:v4" .

aws ecr get-login-password | docker login --username AWS --password-stdin "${ECR_URL%%/*}"
docker push "$ECR_URL:v4"
```

`DOCKER_BUILDKIT=0` is required. Modern Docker produces an OCI image index by default, and Lambda accepts only the Docker v2 manifest.

**2. Point Terraform at the new tag**

```bash
cd infra
terraform apply -var="image_tag=v4"
```

Or update the `image_tag` default in `variables.tf`.

A new tag per deploy is deliberate. Overwriting an existing tag does not update a deployed function, because Lambda pins the image digest at deploy time.

**3. Test**

```bash
aws lambda invoke --function-name spotify-pipeline-ingest /tmp/out.json
cat /tmp/out.json

sleep 20
aws s3 ls "s3://$(terraform output -raw raw_bucket_name)/processed/" --recursive
```

---

## Querying

The Glue table uses partition projection, so new dates are picked up automatically with no `MSCK REPAIR` step.

Queries live in `athena/queries/` and can be run from the Athena console or the CLI. Example — most played artists:

```sql
SELECT artist_names, COUNT(*) AS plays
FROM (SELECT DISTINCT played_at, track_id, artist_names FROM recently_played)
GROUP BY artist_names
ORDER BY plays DESC
LIMIT 10
```

**Why the `SELECT DISTINCT` wrapper:** the ingest fetches the last 50 tracks every 6 hours, so the same play appears in several files. Without deduplicating on `played_at` and `track_id`, counts come out inflated.

**On timestamps:** `played_at` is stored in UTC. For local time, use `played_at AT TIME ZONE 'Africa/Johannesburg'`.

### Output schema

| Column | Type | Notes |
| --- | --- | --- |
| `played_at` | timestamp (UTC) | When the track finished playing |
| `track_name` | string | |
| `track_id` | string | Spotify track ID |
| `artist_names` | string | Comma-separated where a track has several |
| `album_name` | string | |
| `album_release_date` | string | Precision varies by release |
| `duration_sec` | double | |
| `dt` | string | Partition key, `YYYY-MM-DD` |

---

## Design decisions

**Parquet over CSV.** Parquet stores types, so `played_at` arrives in Athena as a timestamp rather than a string and date comparisons work. It is also columnar, so a query reads only the columns it needs.

**Transform before query, rather than querying raw JSON.** Athena can read the raw nested JSON, but the table definition needs nested structs and `UNNEST` to expand the items array. Flattening first turns that into a flat table with typed columns.

**A role per function.** The transform needs no access to the Spotify credentials, so it holds no path to them. A shared role would have given it one for no reason.

**The S3 event filter is load-bearing.** The transform writes to the same bucket that triggers it. The filter limits triggers to `recently_played/` and `.json` while output goes to `processed/`, which is what stops an endless loop.

**Every 6 hours, not daily.** The recently-played endpoint returns at most the last 50 tracks, so a daily run could miss tracks on a heavy listening day.

**Versioned image tags.** Explicit about which build is deployed, and rollback is a one-line change.

**The state bucket is not managed by Terraform.** `terraform destroy` would otherwise try to delete the bucket holding its own state.

---

## Verifying it actually runs

A scheduled job that deploys cleanly is not the same as a scheduled job that works. Checks worth running after any change:

```bash
# Did it run on its own? Look for runs you did not trigger
aws logs tail /aws/lambda/spotify-pipeline-ingest --since 12h

# Is the schedule attached to anything? An empty target list means it fires into nothing
aws events list-targets-by-rule --rule spotify-pipeline-ingest

# Did the transform error?
aws logs tail /aws/lambda/spotify-pipeline-transform --since 12h
```

An EventBridge rule with no target fires on schedule and silently does nothing — no error, no log entry. The only symptom is the absence of output.

---
 
## Debugging notes
 
Three failure modes worth recording, because each produced silence rather than an error.
 
**1. A schedule that fired into nothing.** Running something on a schedule needs three resources: the rule, a target saying what to invoke, and a permission allowing EventBridge to invoke it. With the target missing, the rule fired every 6 hours and did nothing — no error, nothing in CloudWatch, and the rule reporting as `ENABLED` throughout. The symptom was the absence of files on mornings when nobody had invoked the function by hand. Diagnosed by checking `list-targets-by-rule` and finding an empty list. Lesson: a clean `terraform apply` proves the resources exist, not that they are connected.
 
**2. A backend block that silently fell back to local state.** After moving the Terraform files into `Infrastructure/`, `plan` offered to create all 25 resources from scratch. The cause was a missing `bucket` line in the `backend` block, lost while editing. Terraform does not error on an incomplete backend — it quietly uses local state, finds none in a new folder, and concludes nothing exists. Applying would have tried to recreate live infrastructure. What slowed the diagnosis was checking `.terraform/terraform.tfstate`, which showed the correct bucket: that file caches the *previous* successful init rather than reflecting current config. Recovery was `terraform init -reconfigure`; `-migrate-state` would have copied the empty local state over the real state in S3.
 
**3. An IAM denial that was not a permissions problem.** The Lambda failed with `AccessDenied` on `ssm:GetParameter` for `/spotify-pipeline/spotify/spotify/client_id`. The path contains `spotify` twice: the environment variable already ended in `/spotify` and the code appended it again. The role correctly grants access to three specific parameter ARNs, and the malformed path was not among them. A denial naming a specific resource is often a sign the resource name is wrong rather than the policy.
 
**General pattern.** All three were absences rather than errors — a missing target, a missing config line, a malformed path. Error messages point at themselves; silence has to be looked for. Anything meant to happen unattended needs a check for whether it happened, separate from whether it deployed.
 
---

## Tearing it down

```bash
cd Infrastructure
terraform destroy
```

Not covered by `destroy`, and needing manual removal:

- The Terraform state bucket, deliberately unmanaged
- The IAM group holding the Athena and Glue policies
- The Spotify app in the developer dashboard

---

## Possible extensions

- Add `user-top-read` as a weekly snapshot of top artists
- Replace the broad AWS-managed policies on the IAM user with one customer-managed policy
- A dashboard over the Athena results
