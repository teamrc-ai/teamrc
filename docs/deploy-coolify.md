# Deploying teamrc to Production with Coolify

This guide walks you through deploying the teamrc relay server from zero to a working production instance. Every step is explained — no prior Coolify or server admin experience required.

**What you'll end up with**: teamrc running at `https://your-domain.com` with automatic SSL, database backups, and health monitoring.

**How long it takes**: About 30 minutes for a basic deploy (Steps 1–7). The rest is optional optimization.

**Which steps are required?**

| Step | What | Required? |
|------|------|-----------|
| 1–7 | Server, DNS, Coolify, database, app, verify | **Yes** — the minimum to get running |
| 5b | Database tuning | Recommended but not required |
| 5c | Database backups | **Strongly recommended** |
| 8 | Server/kernel tuning | Optional — for performance under load |
| 9 | Auto-deploy | Optional — quality of life |
| 10 | Monitoring | Optional — ongoing maintenance |
| Replication | Database read replicas | Optional — you won't need this unless you have thousands of users |
| Horizontal scaling | Multiple app instances | Optional — a single instance handles massive concurrency already |

**How it works**: Coolify sits on your server and acts as a mini-Heroku. It pulls your code from Git, builds a Docker image, runs it, and puts a reverse proxy (Traefik) in front that handles SSL certificates automatically.

```
Internet → Traefik (SSL, port 443) → teamrc container (port 4000) → PostgreSQL
```

---

## Step 1. Get a Server

You need a Linux VPS. Any provider works — Hetzner, DigitalOcean, Linode, Vultr, etc.

**Minimum specs:**
- 1 vCPU, 2 GB RAM (fine for small teams)
- Ubuntu 22.04 or 24.04
- A public IPv4 address

**Recommended for production:**
- 2 vCPU, 4 GB RAM
- SSD storage

Once your server is running, note its **IP address** — you'll need it in the next step.

---

## Step 2. Point Your Domain to the Server

Go to your DNS provider (Cloudflare, Namecheap, Route 53, etc.) and create an **A record**:

| Type | Name | Value | TTL |
|------|------|-------|-----|
| A | `@` (or `teamrc`) | `YOUR_SERVER_IP` | 300 |

For example, if your domain is `teamrc.ai` and your server IP is `5.78.100.42`:

```
A   teamrc.ai   →   5.78.100.42
```

**Wait 5–10 minutes** for DNS to propagate before continuing. You can check with:

```bash
dig teamrc.ai +short
# Should show your server IP
```

---

## Step 3. Install Coolify

SSH into your server and run the Coolify installer:

```bash
ssh root@YOUR_SERVER_IP
```

Then paste this one-liner:

```bash
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash
```

This takes a few minutes. When it finishes, it prints a URL like:

```
Coolify is ready! Open http://YOUR_SERVER_IP:8000
```

Open that URL in your browser, create your admin account, and you're in.

---

## Step 4. Connect Your Git Repository

Coolify needs access to the teamrc repo to pull and build the code.

1. In Coolify, go to **Sources** in the left sidebar
2. Click **+ Add** and choose **GitHub** (or GitLab, Bitbucket)
3. Follow the OAuth flow to connect your account
4. Make sure the teamrc repository is accessible

---

## Step 5. Create the Database

teamrc needs PostgreSQL to store teams, tokens, and invites.

1. In Coolify, go to **Projects** → click your project (or create one)
2. Click **+ New Resource** → **Database** → **PostgreSQL**
3. Fill in the settings:
   - **Name**: `teamrc-db`
   - **Version**: `18` (default in Coolify — latest stable)
   - **Default Database**: `teamrc`
   - **Username**: `teamrc` (or anything you like)
   - **Password**: click **Generate** to create a strong password
   - **Public Port**: leave **disabled** (the app connects internally, no need to expose it)
4. Click **Deploy**

Wait for the green "Running" status.

### 5a. Find Your Database Connection String

After the database is running:

1. Click on the `teamrc-db` resource
2. Go to the **Connection** tab
3. Copy the **Internal URL** — it looks something like:

```
postgresql://teamrc:generated-password@teamrc-db-abcd1234:5432/teamrc
```

You need to convert this to **Ecto format** for Phoenix. Just change `postgresql://` to `ecto://`:

```
ecto://teamrc:generated-password@teamrc-db-abcd1234:5432/teamrc
```

**Save this string** — you'll paste it into the app's environment variables in Step 6.

### 5b. Tune the Database (Optional but Recommended)

PostgreSQL's defaults are very conservative. For a 2–4 GB RAM server, paste this into the **Custom PostgreSQL Configuration** field in the database's **Advanced** settings:

```ini
# Memory — give Postgres ~25% of your server's RAM
shared_buffers = 512MB
effective_cache_size = 1536MB
work_mem = 4MB
maintenance_work_mem = 128MB

# Connections — Phoenix uses a pool of 10 by default
# Set this higher to leave room for migrations, backups, admin tools
max_connections = 50

# Write performance
checkpoint_completion_target = 0.9
wal_buffers = 16MB

# SSD optimization (almost all VPS providers use SSDs)
random_page_cost = 1.1
effective_io_concurrency = 200

# Replication — enable now so you can add replicas later without downtime
wal_level = replica
max_wal_senders = 3
max_replication_slots = 3

# Logging — log any query that takes more than 500ms
log_min_duration_statement = 500
```

If you're not sure which values to use, here's a quick reference:

| Your Server RAM | shared_buffers | effective_cache_size | work_mem | max_connections |
|-----------------|---------------|---------------------|----------|----------------|
| 1 GB            | 256 MB        | 768 MB              | 2 MB     | 30             |
| 2 GB            | 512 MB        | 1.5 GB              | 4 MB     | 50             |
| 4 GB            | 1 GB          | 3 GB                | 8 MB     | 100            |
| 8 GB            | 2 GB          | 6 GB                | 16 MB    | 200            |

After pasting, **redeploy the database** for the changes to take effect.

### 5c. Set Up Backups

Don't skip this. If your database dies and you have no backup, you lose all your teams.

1. Click on your `teamrc-db` resource
2. Go to the **Backups** tab
3. Configure:
   - **Schedule**: `0 3 * * *` (daily at 3 AM — this is a cron expression)
   - **Retention**: `7` (keep the last 7 backups)
   - **S3 Storage** (optional but recommended): connect an S3-compatible bucket (Backblaze B2, Cloudflare R2, AWS S3) so backups survive even if the whole server dies

---

## Step 6. Deploy the teamrc Application

### 6a. Create the Application in Coolify

1. Go to **Projects** → your project → **+ New Resource** → **Application**
2. Select your Git source and pick the teamrc repository
3. Configure the build settings:
   - **Build Pack**: select **Dockerfile** (not Nixpacks — teamrc has its own Dockerfile)
   - **Branch**: `main` (or whichever branch you deploy from)
   - **Dockerfile Location**: `Dockerfile` (it's at the repo root)
   - **Port Exposes**: `4000`
4. Set your domain:
   - **Domain**: enter your domain with the `https://` prefix, e.g., `https://teamrc.ai`
   - Coolify will automatically provision a Let's Encrypt SSL certificate

### 6b. Generate Your Secrets

You need 4 secret values. These are random strings used to sign cookies, sessions, and LiveView connections. **Each one must be different.**

If you have Elixir installed locally, run this 4 times:

```bash
mix phx.gen.secret
```

If you don't have Elixir, use OpenSSL instead (works on any machine):

```bash
openssl rand -base64 64 | tr -d '\n'
```

Run it 4 times and save each output. Label them:
1. `SECRET_KEY_BASE`
2. `SESSION_SIGNING_SALT`
3. `LIVE_VIEW_SIGNING_SALT`
4. `SESSION_ENCRYPTION_SALT`

### 6c. Set Environment Variables

Go to the **Environment Variables** tab in your Coolify application and add each of these:

| Variable | Value | Notes |
|----------|-------|-------|
| `DATABASE_URL` | `ecto://teamrc:...@teamrc-db-xxxx:5432/teamrc` | The connection string from Step 5a |
| `DATABASE_SSL` | `false` | The database is on the same server, no SSL needed internally |
| `PHX_HOST` | `teamrc.ai` | Your actual domain, **without** `https://` |
| `PHX_SERVER` | `true` | Tells Phoenix to start the web server |
| `SECRET_KEY_BASE` | _(your generated secret)_ | From Step 6b |
| `SESSION_SIGNING_SALT` | _(your generated secret)_ | From Step 6b |
| `LIVE_VIEW_SIGNING_SALT` | _(your generated secret)_ | From Step 6b |
| `SESSION_ENCRYPTION_SALT` | _(your generated secret)_ | From Step 6b |
| `POOL_SIZE` | `10` | How many database connections to keep open |

**Optional** — only needed if you want OAuth-based user accounts (dashboard, machine management, account recovery):

| Variable | Value |
|----------|-------|
| `GITHUB_CLIENT_ID` | From your GitHub OAuth App settings |
| `GITHUB_CLIENT_SECRET` | From your GitHub OAuth App settings |
| `GOOGLE_CLIENT_ID` | From your Google Cloud Console OAuth credentials |
| `GOOGLE_CLIENT_SECRET` | From your Google Cloud Console OAuth credentials |

### 6d. Configure Health Checks

Health checks tell Coolify whether your app is alive. If it stops responding, Coolify will restart it automatically.

In the application settings, go to **Health Checks** and set:

| Setting | Value |
|---------|-------|
| **Path** | `/health` |
| **Port** | `4000` |
| **Interval** | `30` seconds |
| **Timeout** | `10` seconds |
| **Retries** | `3` |
| **Start Period** | `30` seconds (gives the app time to boot and run database migrations) |

### 6e. Deploy

Click **Deploy**. Coolify will:

1. Pull the code from Git
2. Build a Docker image using the `Dockerfile`
3. Start the container
4. Run database migrations automatically (the `docker-entrypoint` script handles this)
5. Wait for the health check to pass
6. Route traffic to the new container

Watch the **Build Logs** tab. A successful build takes 2–5 minutes. Once you see "Container is healthy", you're live.

---

## Step 7. Verify Everything Works

Run these checks to make sure the deployment is healthy:

### 7a. Check SSL

```bash
curl -I https://teamrc.ai
```

You should see:
```
HTTP/2 200
strict-transport-security: max-age=31536000
```

### 7b. Check the Health Endpoint

```bash
curl https://teamrc.ai/health
```

You should see:
```json
{"status":"ok"}
```

### 7c. Test the CLI

From your local machine:

```bash
teamrc whoami
```

The CLI defaults to `https://teamrc.ai`, so it should connect automatically. If you're running a self-hosted relay at a different domain, set it with:

```bash
export TEAMRC_RELAY=https://your-domain.com
teamrc whoami
```

### 7d. Create a Test Team

```bash
teamrc init
```

If this completes without errors, your deployment is fully working.

---

## Step 8. Tune the Server (Optional — Skip If You're Just Getting Started)

> **You can skip this entire step.** The defaults work fine for small teams. Come back to this when you have real traffic or notice performance issues.

teamrc runs on the BEAM (Erlang VM), which is built for massive concurrency — but Linux's default limits are too conservative for it. These tweaks unlock the BEAM's full potential.

### 8a. Tune the Linux Kernel

SSH into your server and create a config file:

```bash
ssh root@YOUR_SERVER_IP
sudo nano /etc/sysctl.d/99-teamrc.conf
```

Paste this:

```ini
# Let the system open more files (BEAM needs lots of file descriptors for connections)
fs.file-max = 1048576
fs.nr_open = 1048576

# Allow more pending connections before the kernel drops them
net.core.somaxconn = 32768
net.core.netdev_max_backlog = 65535

# Recycle TCP connections faster (important for many short-lived API requests)
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15

# Detect dead connections sooner
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5

# Prefer RAM over swap — the BEAM manages its own memory and swap causes latency spikes
vm.swappiness = 1
```

Save the file (Ctrl+X, Y, Enter in nano), then apply it:

```bash
sudo sysctl --system
```

This takes effect immediately, no reboot needed.

### 8b. Raise Container File Descriptor Limits

Docker containers have a default limit on how many files/connections they can open. You need to raise this.

**Option A: Docker daemon config (affects all containers)**

```bash
sudo nano /etc/docker/daemon.json
```

Add (or merge into existing config):

```json
{
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 65536,
      "Soft": 65536
    }
  }
}
```

Then restart Docker:

```bash
sudo systemctl restart docker
```

> **Warning**: This briefly stops all containers. Do this during a maintenance window.

**Option B: Per-app in Coolify (if your Coolify version supports Docker Compose overrides)**

In the application's **Docker Compose** override field:

```yaml
services:
  app:
    ulimits:
      nofile:
        soft: 65536
        hard: 65536
```

### 8c. BEAM VM Flags (Advanced)

These flags optimize how the Erlang VM runs inside a container. They're optional but helpful.

Add this environment variable in Coolify:

| Variable | Value |
|----------|-------|
| `ERL_FLAGS` | `+K true +Q 65536 +P 1048576 +A 32 +sbwt none +sbwtdcpu none +sbwtdio none` |

What these do:

| Flag | What it does |
|------|-------------|
| `+K true` | Use the OS's efficient I/O polling (epoll on Linux). Faster than the default. |
| `+Q 65536` | Allow up to 65k open ports/connections. Match this to your ulimit. |
| `+P 1048576` | Allow up to 1M lightweight BEAM processes. Overkill, but costs nothing. |
| `+A 32` | Use 32 threads for file/network I/O (default is 1). |
| `+sbwt none` | **Important for containers**: Stop the BEAM from busy-waiting when idle. Without this, an idle container wastes CPU. |

> **Heads up**: Don't set `+Q` higher than your `nofile` ulimit. If `nofile` is 65536, set `+Q 65536`.

---

## Step 9. Set Up Auto-Deploy (Optional)

Coolify can automatically redeploy when you push to your branch.

1. Go to your application settings
2. Find **Auto Deploy** and enable it
3. Set the **branch** to watch (e.g., `main`)

Now every `git push origin main` triggers a new deployment. Coolify does rolling deploys — it starts the new container, waits for the health check, then stops the old one. Zero downtime.

---

## Step 10. Monitor and Maintain

### Viewing Logs

Click on your application in Coolify → **Logs** tab. Phoenix logs everything to stdout, and Coolify captures it. Look here when debugging issues.

To increase log detail temporarily, add this environment variable:

| Variable | Value |
|----------|-------|
| `LOGGER_LEVEL` | `debug` |

Change it back to `info` (or remove it) when done — debug logs are very verbose.

### Redeploying

- **Automatic**: Push to your deploy branch (if auto-deploy is on)
- **Manual**: Click **Redeploy** in the Coolify UI
- **Migrations**: Run automatically on every container start. You never need to run them manually.

### Scaling Up

If the server feels slow, the simplest fix is a bigger VPS:

| Team Size | Recommended Server | POOL_SIZE |
|-----------|--------------------|-----------|
| 1–100 users | 1 vCPU, 2 GB RAM | 10 |
| 100–500 users | 2 vCPU, 4 GB RAM | 15 |
| 500–2,000 users | 4 vCPU, 8 GB RAM | 20 |
| 2,000+ users | 4+ vCPU, 8+ GB RAM | 30 |

Remember to also update `POOL_SIZE` and the Postgres `max_connections` if you scale up. Rule of thumb: `max_connections` should be at least `POOL_SIZE * 2 + 20`.

---

## How SSL Works (Behind the Scenes)

You don't need to configure SSL manually. Here's what happens:

1. You set your domain in Coolify with `https://`
2. Coolify's Traefik proxy requests a free SSL certificate from Let's Encrypt
3. All HTTPS traffic hits Traefik on port 443, which terminates SSL
4. Traefik forwards the request to your Phoenix container on port 4000 over plain HTTP (internal Docker network — safe)
5. Traefik adds a header `X-Forwarded-Proto: https` so Phoenix knows the original request was HTTPS
6. Phoenix uses this header to generate correct `https://` URLs for invites, device auth, etc.

If someone visits `http://teamrc.ai`, Phoenix automatically redirects them to `https://teamrc.ai`.

---

## Troubleshooting

### "database connection refused"

**Cause**: The `DATABASE_URL` is wrong, or the database isn't running.

**Fix**:
1. Check that the database resource shows "Running" in Coolify
2. Double-check the internal hostname — go to the database's **Connection** tab and copy the Internal URL
3. Make sure you converted `postgresql://` to `ecto://`

### "SECRET_KEY_BASE is missing"

**Cause**: You forgot to set an environment variable.

**Fix**: Go to the app's **Environment Variables** tab and make sure all 6 required variables are set (DATABASE_URL, PHX_HOST, SECRET_KEY_BASE, and the 3 salts).

### Infinite redirect loop / page won't load

**Cause**: The `force_ssl` config isn't trusting the `X-Forwarded-Proto` header from Traefik.

**Fix**: This is already handled in the codebase (`rewrite_on: [:x_forwarded_proto]`). If you're seeing this, make sure you're running the latest code.

### "certificate verify failed"

**Cause**: `DATABASE_SSL` is set to `true`, but the database is on the same Coolify server (no SSL between containers).

**Fix**: Set `DATABASE_SSL=false` in your environment variables.

### Invite URLs show "example.com" instead of your domain

**Cause**: `PHX_HOST` isn't set.

**Fix**: Set `PHX_HOST=teamrc.ai` (your actual domain, without `https://`).

### CLI says "connection refused" or can't reach the server

**Cause**: The CLI is trying to connect to the wrong URL.

**Fix**: The CLI defaults to `https://teamrc.ai`. If you're self-hosting at a different domain:

```bash
export TEAMRC_RELAY=https://your-domain.com
teamrc whoami
```

Or save it permanently:

```bash
# This gets stored in ~/.teamrc/config.json
teamrc init  # and follow the prompts
```

### High CPU usage when the app is idle

**Cause**: The BEAM VM's scheduler busy-wait is spinning.

**Fix**: Add the `ERL_FLAGS` environment variable from Step 8c. The key flag is `+sbwt none`.

### "emfile" error / BEAM crashes

**Cause**: The container hit its file descriptor limit.

**Fix**: Follow Step 8a and 8b to raise the kernel and container limits.

### LiveView pages disconnect or feel laggy

**Cause**: If running multiple instances, WebSocket connections need sticky sessions.

**Fix**: In Coolify's proxy settings, enable session affinity / sticky sessions. For single-instance deploys, this isn't an issue.

---

## Advanced: PostgreSQL Replication

> You probably don't need this. A single Postgres instance handles thousands of users easily. Only set this up if you need high availability or read scaling.

Coolify doesn't manage replicas automatically, but you can set it up manually:

1. The tuning config from Step 5b already enables `wal_level = replica` — so your primary database is replication-ready
2. Create a second PostgreSQL resource in Coolify (`teamrc-db-replica`)
3. Configure it as a streaming replica pointing to the primary's internal hostname
4. In your Phoenix app, add a read-only Repo module:

```elixir
defmodule Teamrc.ReadRepo do
  use Ecto.Repo, otp_app: :teamrc, adapter: Ecto.Adapters.Postgres, read_only: true
end
```

For most deployments, a simpler alternative is to use a managed database service (Supabase, Neon, or your VPS provider's managed Postgres) and point `DATABASE_URL` at it.

---

## Advanced: Horizontal Scaling

> Again, probably not needed yet. A single BEAM node handles concurrency extremely well. One 4 GB server can serve thousands of concurrent CLI connections.

Phoenix supports clustering via DNS-based service discovery. If you need multiple instances:

1. Add `DNS_CLUSTER_QUERY=teamrc-app.internal` as an environment variable
2. Scale the service to multiple replicas in Coolify
3. Enable sticky sessions in Coolify's proxy config (required for LiveView WebSocket connections)
4. Set a shared Erlang cookie: add `RELEASE_COOKIE=your-shared-secret` as an env var (must be the same across all instances)

---

## Quick Reference: All Environment Variables

| Variable | Required? | Example | Description |
|----------|-----------|---------|-------------|
| `DATABASE_URL` | Yes | `ecto://user:pass@host:5432/db` | PostgreSQL connection string |
| `DATABASE_SSL` | Yes | `false` | Set `false` for same-server DB |
| `PHX_HOST` | Yes | `teamrc.ai` | Your domain (no `https://`) |
| `PHX_SERVER` | Yes | `true` | Enable the web server |
| `SECRET_KEY_BASE` | Yes | _(64+ char random string)_ | Cookie signing key |
| `SESSION_SIGNING_SALT` | Yes | _(random string)_ | Session signing salt |
| `LIVE_VIEW_SIGNING_SALT` | Yes | _(random string)_ | LiveView signing salt |
| `SESSION_ENCRYPTION_SALT` | Yes | _(random string)_ | Session encryption salt |
| `POOL_SIZE` | No | `10` | DB connection pool (default: 10) |
| `ERL_FLAGS` | No | `+K true +sbwt none ...` | BEAM VM tuning flags |
| `LOGGER_LEVEL` | No | `info` | Log verbosity (debug/info/warn) |
| `DNS_CLUSTER_QUERY` | No | `teamrc.internal` | For multi-instance clustering |
| `GITHUB_CLIENT_ID` | No | _(from GitHub OAuth App)_ | GitHub OAuth login |
| `GITHUB_CLIENT_SECRET` | No | _(from GitHub OAuth App)_ | GitHub OAuth login |
| `GOOGLE_CLIENT_ID` | No | _(from Google Cloud Console)_ | Google OAuth login |
| `GOOGLE_CLIENT_SECRET` | No | _(from Google Cloud Console)_ | Google OAuth login |
