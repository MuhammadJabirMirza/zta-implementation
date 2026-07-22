# Implementation Pathway — Zero-Trust RDS Re-platforming Artefact

Follow this file top to bottom. Every phase ends with an **EVIDENCE** box:
capture it immediately — do not plan to redeploy later just for screenshots.
Region is eu-west-2 (London) everywhere. Deadline discipline: Phases 0–3 in
one sitting if possible; Phases 4–5 are the paid evidence windows.

**Final-review fixes already applied in this version (cite these in the
Development chapter as defects found by static/manual review):**
1. App SG now has an egress rule to the **S3 gateway endpoint prefix list**
   (gateway endpoints route to S3 public IPs, so the old VPC-CIDR-only rule
   silently blocked dnf).
2. A **secretsmanager interface endpoint** was added — RDS Proxy in private
   subnets cannot fetch the DB secret without it (targets stay UNAVAILABLE).
3. The proxy now has a **dedicated security group** (it previously reused the
   zero-ingress app SG, so the app could never have reached it on 3306), and
   the DB SG accepts 3306 from the proxy SG.
4. `db_check.py` SQL bug fixed (`SHOW STATUS LIKE 'Ssl_cipher'` was unquoted).
5. Checkov waiver register added (`.checkov.yaml`) — 184 passed / 0 failed;
   tfsec clean; Bandit clean. The register doubles as your Testing-chapter
   waiver table.

---

## Phase 0 — Prerequisites (workstation, ~45 min, £0)

1. AWS account with an IAM admin user (not root). MFA on.
2. **Billing → Budgets → Create budget: £50/month, alerts at 50% and 80%.**
   Non-negotiable first action. Paid services are in scope; the Cost Explorer
   total is your SME-affordability finding.
3. Install: Terraform ≥ 1.7, AWS CLI v2, **Session Manager plugin** for the
   AWS CLI, Python 3.11+ with `pip install pymysql boto3`.
4. `aws configure` with your IAM user keys, region `eu-west-2`.
5. Download the RDS CA bundle into `app/`:
   `curl -o app/global-bundle.pem https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem`
6. Download the CIS conformance pack template (needed before Phase 4):
   from the `awslabs/aws-config-rules` GitHub repo, folder
   `aws-config-conformance-packs`, file
   `Operational-Best-Practices-for-CIS-AWS-v1.4-Level1.yaml`, save as
   `modules/compliance/templates/cis-level1.yaml`.
7. Choose two globally unique bucket names and write them down:
   state bucket (e.g. `zt-rds-tfstate-mjm-2026`) and evidence bucket
   (e.g. `ztrds-evidence-mjm-2026`). Put the evidence bucket name in
   `environments/dev/terraform.tfvars` (replace CHANGE-ME).

**EVIDENCE:** screenshot of the budget alert configuration.

---

## Phase 1 — Bootstrap the state backend (~15 min, pennies)

```
cd bootstrap
terraform init
terraform apply -var "state_bucket_name=<your-state-bucket>"
```

Copy the printed bucket name into `environments/dev/backend.tf`
(replace REPLACE-WITH-YOUR-STATE-BUCKET).

**EVIDENCE:** terminal output of the apply; S3 console showing the
versioned, encrypted state bucket.

---

## Phase 2 — Deploy the core artefact (~40 min incl. RDS creation, ~£1–2/day while up)

```
cd ../environments/dev
terraform init
terraform fmt -check -recursive ../..
terraform validate
terraform plan -out tfplan
terraform apply tfplan
```

Multi-AZ RDS takes 15–25 minutes. While waiting, run the local scans and
save the output files — this is Testing-chapter primary evidence:

```
pip install checkov bandit
checkov -d ../.. --framework terraform --compact > ../../evidence-checkov.txt
bandit -r ../../app -ll > ../../evidence-bandit.txt
```

Expected: Checkov 184 passed / 0 failed, Bandit 0 issues.

**EVIDENCE:** `terraform apply` completion output showing the three outputs
(rds_endpoint, db_secret_arn, app_instance_id); both scan text files;
screenshot of the VPC console resource map (three tiers, no IGW route on
private tables).

---

## Phase 3 — Functional zero-trust verification (~1 hr, £0 extra)

### 3.1 Prove SSM-only access (no SSH exists)
```
aws ssm start-session --target <app_instance_id> --region eu-west-2
```
Inside the session: `mysql --version` — proves the S3 gateway endpoint fix
worked (dnf installed the client with no internet route).

**Negative test:** attempt `ssh ec2-user@<private-ip>` from anywhere — it
must fail (no key pair, no ingress, no route). Screenshot the failure.

### 3.2 Create the IAM database user
Get the admin password (never displayed on the instance, fetched at runtime):
```
./scripts/get-db-password.sh <db_secret_arn>
```
Open the tunnel in one terminal:
```
./scripts/connect-db.sh <app_instance_id> <rds_endpoint>
```
In another terminal connect as admin via 127.0.0.1 and run
`app/create-iam-user.sql` to create `iam_app`.

### 3.3 Run the two-path demonstrator
```
cd app
python db_check.py secret <db_secret_arn>
python db_check.py iam <rds_endpoint>
```
Both must print the connected user, MySQL version, and a TLS cipher.

**Negative tests (screenshot each):**
- `mysql -h 127.0.0.1 -u admin -p --ssl-mode=DISABLED` → refused
  (require_secure_transport).
- Wait 16 minutes after generating an IAM token, then try it → rejected
  (15-minute credential lifetime — your headline zero-trust metric).

**EVIDENCE:** session transcript, both db_check outputs, both negative-test
failures, CloudWatch log group `/ztrds/ssm-sessions` showing the session
transcript.

---

## Phase 4 — Compliance evidence window (Day 10 pattern, ~3–4 hrs, ~£2–4)

Confirm `modules/compliance/templates/cis-level1.yaml` exists (Phase 0.6),
then:
```
terraform apply -var deploy_compliance=true
```
Note: if your account has ever had a Config recorder or an SSM session
preferences document named `SSM-SessionManagerRunShell`, import them first:
`terraform import 'module.compliance[0].aws_ssm_document.session_prefs' SSM-SessionManagerRunShell`

Wait 1–2 hours for Config to evaluate, then capture:
1. Config console → Conformance packs → ztrds-cis → **compliance score**.
2. GuardDuty console → findings (generate a sample finding:
   Settings → Sample findings).
3. CloudTrail → event history filtered to the RDS instance.
4. Security Hub → enable 30-day free trial → CIS AWS Foundations
   Benchmark v3.0 → capture the score (v1.4 via Config + v3.0 via Security
   Hub is your dual-benchmark coverage claim).
5. Well-Architected Tool → define workload → Security pillar review →
   export the PDF.

**EVIDENCE:** all five screenshots/exports above.

---

## Phase 5 — RDS Proxy PEP window (Day 11 pattern, ~2 hrs, ~£1–2)

```
terraform apply -var deploy_compliance=true -var deploy_proxy=true
```
Wait for the proxy target to show AVAILABLE (RDS console → Proxies →
Targets). If it stays unavailable, the secretsmanager endpoint or proxy SG
is the suspect — both are fixed in this version, so expect AVAILABLE.

Re-run the tunnel pointing at the **proxy endpoint** instead of the RDS
endpoint, then:
```
python db_check.py iam <proxy_endpoint>
```
**Negative test:** `python db_check.py secret <db_secret_arn>` against the
proxy → must FAIL (iam_auth = REQUIRED means passwords are refused even
when valid — the PEP enforcing policy, not the database).

**EVIDENCE:** proxy target AVAILABLE screenshot; IAM-token success through
the proxy; password rejection through the proxy (this pair is your NIST
SP 800-207 PEP demonstration).

---

## Phase 6 — Cost evidence and teardown (~30 min)

1. Cost Explorer → filter to the project period → screenshot the total and
   the per-service breakdown. This number goes in Conclusions against the
   $45,000 enterprise barrier.
2. Destroy in reverse order:
```
terraform apply -var deploy_compliance=false -var deploy_proxy=false   # drops paid stack
terraform destroy
cd ../../bootstrap && terraform destroy   # optional: keep until dissertation submitted
```
3. Next day: confirm Cost Explorer shows ~£0 daily spend. Screenshot.

**EVIDENCE:** cost total, per-service breakdown, post-destroy zero-spend day.

---

## Testing-chapter evidence table (fill as you go)

| # | Control (Terraform) | NIST SP 800-207 principle | Validation method | Evidence ref |
|---|---------------------|---------------------------|-------------------|--------------|
| 1 | RDS Proxy, iam_auth=REQUIRED, require_tls | Policy Enforcement Point | Phase 5 pass/fail pair | |
| 2 | IAM DB auth, 15-min token | Ephemeral credentials / verify explicitly | Phase 3.3 + expiry negative test | |
| 3 | SG-to-SG references, zero-ingress app SG | Microsegmentation | Phase 3 negative tests | |
| 4 | require_secure_transport parameter group | Encrypt in transit | TLS-disabled refusal | |
| 5 | KMS CMK with rotation, storage_encrypted | Encrypt at rest | Console + Checkov pass | |
| 6 | manage_master_user_password | No static secrets in code/state | get-db-password.sh runtime fetch | |
| 7 | SSM-only admin, session transcripts | Continuous monitoring / audit | CloudWatch log group | |
| 8 | Config CIS v1.4 pack + Security Hub v3.0 | Continuous diagnostics (CDM) | Compliance scores | |
| 9 | GuardDuty + CloudTrail | Threat detection / audit | Sample finding + event history | |
| 10 | Checkov/tfsec/Bandit in CI, waiver register | Policy as code, shift-left | evidence-*.txt + green CI run | |

## External review pack (after Phases 0–6)

Give reviewers: the GitHub repo link (push this folder; CI must be green),
this file, the evidence table, and three questions — (1) would you deploy
this pattern at an SME, (2) which NIST mapping is weakest, (3) what would
you add first in production. Their written answers are your expert-
evaluation evidence under Design Science Research.

## Troubleshooting quick hits

- `dnf` hangs on the instance → S3 gateway endpoint or its SG rule missing
  (fixed here; verify with `aws ec2 describe-vpc-endpoints`).
- Proxy target UNAVAILABLE → secretsmanager endpoint absent or proxy SG
  wrong (both fixed here); check proxy CloudWatch logs.
- Conformance pack fails to create → cis-level1.yaml missing from
  templates/, or Config recorder not yet ENABLED (wait 2 min, re-apply).
- `terraform apply` AlreadyExists on Config recorder / SSM document →
  pre-existing account resources; import as shown in Phase 4.
