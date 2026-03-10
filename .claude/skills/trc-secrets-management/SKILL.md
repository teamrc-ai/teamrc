---
name: trc-secrets-management
title: "Secrets Management"
description: "Never store secrets in code, logs, or environment variables in production"
---

## Secret Storage
- Never commit secrets (API keys, passwords, tokens, certificates, private
  keys) to version control — not in code, config files, test fixtures, or
  example files. Use a secrets manager (Vault, AWS Secrets Manager, GCP
  Secret Manager, 1Password) with rotation support.
- Never store production secrets in environment variables directly — they
  leak into process listings, crash dumps, and child processes. Inject
  secrets at runtime from a secrets manager or mounted secret volume.
- Never hardcode secrets in Docker images, CI configs, or infrastructure
  templates — use build-time secret injection that does not persist in
  layers or artifacts.

## Secret Handling
- Never log, print, or include secrets in error messages — redact all
  credential material in application logs, HTTP request logs, and error
  reporting. Structured logging should have a secret-aware formatter.
- Hash secrets before storing them in databases — API keys, tokens, and
  passwords must be stored as cryptographic hashes (bcrypt, argon2id, or
  scrypt for passwords; SHA-256 for tokens). A database compromise must
  not yield usable credentials.
- Show secrets only once at creation time — after initial display, the
  plaintext should never be retrievable. Provide regeneration, not recovery.

## Secret Lifecycle
- Every secret must have a defined owner, expiration date, and rotation
  schedule — secrets without expiration accumulate as permanently valid
  attack surface.
- Rotate secrets immediately on any suspected compromise — do not wait for
  the scheduled rotation. Automate rotation where possible.
- Audit secret access — log who accessed which secret and when. Alert on
  unusual access patterns or access from unexpected sources.
- Use short-lived credentials where possible — 15-minute access tokens are
  safer than 90-day API keys. Prefer temporary credentials over permanent
  ones.

