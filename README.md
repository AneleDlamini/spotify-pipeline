# Spotify Pipeline

An automated data pipeline that captures my Spotify listening history and stores it in AWS, built with Terraform.

Every 6 hours, a scheduled Lambda fetches recently played tracks from the Spotify API and writes the raw JSON to S3. That write triggers a second Lambda, which flattens the nested JSON into a typed Parquet file ready for querying.

Built as a learning project for infrastructure as code, serverless architecture and AWS IAM.

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
```

Both Lambdas run from the same container image held in ECR, with `image_config.command` selecting which handler runs. Each has its own IAM role scoped to only what it needs.

---

## AWS resources

| Resource | Purpose |
| --- | --- |
| S3 bucket | Raw JSON and processed Parquet, in separate prefixes |
| SSM Parameter Store | Spotify client ID, client secret and refresh token, encrypted |
| ECR repository | Holds the container image, keeping the 5 most recent |
| Ingest Lambda | Fetches from Spotify, writes raw JSON |
| Transform Lambda | Flattens JSON to Parquet on S3 event |
| EventBridge rule | Triggers the ingest every 6 hours |
| IAM roles | One per function, least privilege |
| CloudWatch log groups | 14-day retention |
| S3 backend bucket | Terraform state, versioned, created outside Terraform |

---

## Repository layout

```
.
├── Ingest/
│   ├── Dockerfile          # AWS Lambda Python base image
│   ├── handler.py          # Ingest: Spotify API → raw JSON in S3
│   ├── transform.py        # Transform: raw JSON → Parquet
│   └── requirements.txt
├── versions.tf             # Terraform and provider versions, S3 backend
├── variables.tf            # Project name, region, image tag
├── s3.tf                   # Raw data bucket and public access block
├── ssm.tf                  # Encrypted Spotify credentials
├── iam.tf                  # Roles and policies for both Lambdas
├── lambda.tf               # Both functions, log groups, permissions
├── eventbridge.tf          # Schedule rule and target
└── outputs.tf
```

---

## How credentials work

No long-lived AWS access keys exist anywhere in this project.

**For me:** `aws login` signs in through the browser with MFA and issues temporary credentials that refresh themselves. Terraform and the AWS CLI pick these up automatically, so the provider block carries only a region.

**For the Lambdas:** each function assumes its own IAM role at runtime, and AWS supplies fresh credentials on every invocation.

**For Spotify:** the client ID, client secret and refresh token live in SSM Parameter Store as encrypted `SecureString` parameters. Terraform creates each with a placeholder value and `ignore_changes` on `value`; the real values are set separately with `aws ssm put-parameter`. Nothing sensitive reaches the Terraform state file.

The refresh token comes from a one-time browser authorisation. Spotify's client-credentials flow only reaches public data, so reading personal listening history needs the authorisation-code flow, which produces a refresh token that does not expire.

Scopes granted: `user-read-recently-played`, `user-top-read`, `user-read-currently-playing`.

---

## Deploying a change

Terraform state lives in S3, so this works from any machine with AWS access.

**1. Build and push a new image tag**

```bash
cd Ingest
ECR_URL="$(cd .. && terraform output -raw ecr_repository_url)"

DOCKER_BUILDKIT=0 docker build -t "$ECR_URL:v4" .

aws ecr get-login-password | docker login --username AWS --password-stdin "${ECR_URL%%/*}"
docker push "$ECR_URL:v4"
```

`DOCKER_BUILDKIT=0` is required. Modern Docker produces an OCI image index by default, and Lambda accepts only the Docker v2 manifest.

**2. Point Terraform at the new tag**

```bash
terraform apply -var="image_tag=v4"
```

Or change the `image_tag` default in `variables.tf`.

A new tag per deploy is deliberate. Overwriting an existing tag does not update a deployed function, because Lambda pins the image digest at deploy time.

**3. Test**

```bash
aws lambda invoke --function-name spotify-pipeline-ingest /tmp/out.json
cat /tmp/out.json

sleep 20
aws s3 ls "s3://$(terraform output -raw raw_bucket_name)/processed/" --recursive
```

---

## Checking it is running

```bash
# Recent ingest runs
aws logs tail /aws/lambda/spotify-pipeline-ingest --since 12h

# Transform errors
aws logs tail /aws/lambda/spotify-pipeline-transform --since 12h

# Inspect a Parquet file using the container's own pandas
docker run --rm -v /tmp:/data --entrypoint python "$ECR_URL:v4" \
  -c "import pandas as pd; d=pd.read_parquet('/data/out.parquet'); print(d.dtypes); print(d.head())"
```

---

## Output schema

| Column | Type | Notes |
| --- | --- | --- |
| `played_at` | timestamp (UTC) | When the track finished playing |
| `track_name` | string | |
| `track_id` | string | Spotify track ID |
| `artist_names` | string | Comma-separated where a track has several |
| `album_name` | string | |
| `album_release_date` | string | Precision varies by release |
| `duration_sec` | float | |

---

## Notes and constraints

- The recently-played endpoint returns at most the last 50 tracks, which is why the schedule runs every 6 hours rather than daily.
- The S3 event filter is scoped to `recently_played/` and `.json`. Without it, the transform's own output would retrigger the transform in an endless loop, since input and output share a bucket.
- The Terraform backend block cannot use variables, so the state bucket name is hardcoded in `versions.tf`.
- The state bucket is deliberately not managed by Terraform. `terraform destroy` would otherwise try to delete the bucket holding its own state.

---

## Possible extensions

- Query the Parquet files with Athena
- Add `user-top-read` as a weekly snapshot of top artists
- Partition the processed data for more efficient querying
- Move the Terraform files into an `infra/` folder, separating infrastructure from application code
