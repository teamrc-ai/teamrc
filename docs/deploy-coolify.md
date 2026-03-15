# Deploying teamrc to Production with Coolify

This guide covers deploying the teamrc relay server from scratch. No prior Coolify or server admin experience required.

**End result**: teamrc running at `https://your-domain.com` with automatic SSL, database backups, and health monitoring.

**Time**: ~30 minutes for a basic deploy (Steps 1-7). The rest is optional.

**Which steps are required?**

| Step | What | Required? |
|------|------|-----------|
| 1-7 | Server, DNS, Coolify, Git, database, app, verify | **Yes** |
| 5b | Database backups | **Strongly recommended** |
| 5c | Database tuning | Recommended |
| 8 | Database access (SSH tunnel + DBeaver) | **Recommended** |
| 9 | Server and kernel tuning | Optional. Helps with performance under load |
| 10 | Auto-deploy | Optional. Quality of life improvement |
| 11 | Monitoring | Optional |
| Replication | Database read replicas | Optional. Not needed until thousands of users |
| Horizontal scaling | Multiple app instances | Optional. A single instance handles high concurrency |

**How it works**: Coolify sits on your server and acts as a mini-Heroku. It pulls your code from Git, builds a Docker image, runs it, and puts a reverse proxy (Traefik) in front. Traefik handles SSL certificates automatically.

```
Internet -> Traefik (SSL, port 443) -> teamrc container (port 4000) -> PostgreSQL
```

---

## Step 1. Get a Server

You need a Linux VPS. Any provider works: Hetzner, DigitalOcean, Linode, Vultr, etc.

**Minimum specs:**
- 1 vCPU, 2 GB RAM (fine for small teams)
- Ubuntu 22.04 or 24.04
- A public IPv4 address

**Recommended for production:**
- 2 vCPU, 4 GB RAM
- SSD storage

Once your server is running, note its **IP address**. You'll need it in the next step.

---

## Step 2. Point Your Domain to the Server

Go to your DNS provider (Cloudflare, Namecheap, Route 53, etc.) and create an **A record**:

| Type | Name | Value | TTL |
|------|------|-------|-----|
| A | `@` (or `teamrc`) | `YOUR_SERVER_IP` | 300 |

For example, if your domain is `teamrc.ai` and your server IP is `5.78.100.42`:

```
A   teamrc.ai   ->   5.78.100.42
```

**Wait 5-10 minutes** for DNS to propagate. You can verify with:

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

Create PostgreSQL as a standalone Coolify resource. This gives you Coolify's built-in backup UI, monitoring, and the ability to scale independently.

1. In Coolify, go to **Projects** -> click your project (or create one)
2. Click **+ New Resource** -> **Database** -> **PostgreSQL**
3. Fill in the settings:
   - **Name**: `teamrc-db`
   - **Version**: `18`
   - **Default Database**: `teamrc`
   - **Username**: `teamrc`
   - **Password**: click **Generate**
   - **Public Port**: leave **disabled**
4. Click **Deploy** and wait for the green "Running" status

### 5a. Find Your Database Connection String

1. Click on the `teamrc-db` resource -> **Connection** tab
2. Copy the **Internal URL**. It looks like: `postgresql://teamrc:generated-password@teamrc-db-abcd1234:5432/teamrc`
3. Convert to Ecto format by changing `postgresql://` to `ecto://`:

```
ecto://teamrc:generated-password@teamrc-db-abcd1234:5432/teamrc
```

Save this. You'll need it in Step 6.

### 5b. Set Up Backups (to S3)

Don't skip this. If your database dies without a backup, you lose all your teams. Backups must go off-server. A local backup dies with the server.

1. Click on your `teamrc-db` resource -> **Backups** tab
2. **Connect an S3 destination first**: go to **Settings** -> **S3 Storages** -> **+ Add** and configure an S3-compatible bucket:
   - **Backblaze B2**: cheapest option (~$0.005/GB/month)
   - **Cloudflare R2**: no egress fees
   - **AWS S3**: most features, higher cost
3. Back in the database **Backups** tab, configure:
   - **Schedule**: `0 3 * * *` (daily at 3 AM)
   - **Retention**: `7` (keep the last 7 backups)
   - **S3 Storage**: select the S3 destination you just configured

### 5c. Tune PostgreSQL (Optional but Recommended)

Paste this into the **Custom PostgreSQL Configuration** in the database's **Advanced** settings:

| Your Server RAM | shared_buffers | effective_cache_size | work_mem | max_connections |
|-----------------|---------------|---------------------|----------|----------------|
| 1 GB            | 256 MB        | 768 MB              | 2 MB     | 30             |
| 2 GB            | 512 MB        | 1.5 GB              | 4 MB     | 50             |
| 4 GB            | 1 GB          | 3 GB                | 8 MB     | 100            |
| 8 GB            | 2 GB          | 6 GB                | 16 MB    | 200            |

---

## Step 6. Deploy the teamrc Application

Coolify builds the app from `Dockerfile.prod` in the repo root. It connects to the Postgres database you created in Step 5.

### 6a. Create the Resource

1. In Coolify, go to **Projects** -> your project -> **+ New Resource** -> **Dockerfile**
2. Set the **Dockerfile location** to `Dockerfile.prod`
2. Select your Git source and pick the teamrc repository
3. Set the **branch** to `main` (or whichever branch you deploy from)

### 6b. Configure the Health Check

In the service settings, configure the health check:

- **Path**: `/health`
- **Port**: `4000`
- **Interval**: `10s`
- **Start Period**: `60s` (allows time for compilation and migrations)
- **Retries**: `5`

### 6c. Set Your Domain

In the service settings:

1. Set the **Domain** to your domain with `https://`, e.g., `https://teamrc.ai`
2. Coolify will automatically provision a Let's Encrypt SSL certificate

### 6d. Set Environment Variables

Set these in the **Environment Variables** tab:

**Required:**

| Variable | Value |
|----------|-------|
| `DATABASE_URL` | `ecto://teamrc:generated-password@teamrc-db-abcd1234:5432/teamrc` (from Step 5a) |
| `DATABASE_SSL` | `false` |
| `PHX_HOST` | Your domain without `https://`, e.g., `teamrc.ai` |
| `PHX_SERVER` | `true` |
| `SECRET_KEY_BASE` | Generate with `openssl rand -base64 64 \| tr -d '\n'` |
| `SESSION_SIGNING_SALT` | Generate with `openssl rand -base64 32 \| tr -d '\n'` |
| `LIVE_VIEW_SIGNING_SALT` | Generate with `openssl rand -base64 32 \| tr -d '\n'` |
| `SESSION_ENCRYPTION_SALT` | Generate with `openssl rand -base64 32 \| tr -d '\n'` |

**Optional:**

| Variable | Value |
|----------|-------|
| `POOL_SIZE` | DB connection pool size (default: `10`) |
| `ADMIN_EMAILS` | Comma-separated emails that can access `/admin/dashboard` |
| `ERL_FLAGS` | `+K true +Q 65536 +P 1048576 +A 32 +sbwt none +sbwtdcpu none +sbwtdio none` |
| `RESEND_API_KEY` | From Resend, for transactional email |
| `GITHUB_CLIENT_ID` | From your GitHub OAuth App settings |
| `GITHUB_CLIENT_SECRET` | From your GitHub OAuth App settings |
| `GOOGLE_CLIENT_ID` | From your Google Cloud Console OAuth credentials |
| `GOOGLE_CLIENT_SECRET` | From your Google Cloud Console OAuth credentials |
| `ANALYTICS_HOST` | Your analytics host |
| `ANALYTICS_WEBSITE_ID` | Your analytics website ID |
| `OTEL_ENDPOINT` | OpenTelemetry collector endpoint |

### 6e. Networking

The app and database must be on the same Docker network. Go to your `teamrc-db` resource in Coolify, then **Settings**, and enable **"Connect to Predefined Network"**. This puts Postgres on the same network so the app can reach it.

### 6f. Deploy

Click **Deploy**. Coolify will:

1. Pull the code from Git
2. Build the Docker image using `Dockerfile.prod`
3. Start the container with your environment variables
4. Run database migrations automatically (the `docker-entrypoint` script handles this)
5. Wait for the health check to pass
6. Route traffic via Traefik to the container

Watch the **Build Logs** tab. A successful build takes 2-5 minutes. When you see "Container is healthy", you're live.

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

## Step 8. Access Your Database (SSH Tunnel + DBeaver)

Your Postgres database should **never** be exposed to the internet. Don't deploy pgAdmin or other database GUIs as public Coolify services. They break behind reverse proxies and add attack surface.

Use [DBeaver Community](https://dbeaver.io/) instead. It's free, open source, and runs on Mac/Linux/Windows. It has a built-in SSH tunnel, so no terminal commands are needed.

### 8a. Gather Your Connection Details

You need three things from Coolify:

1. **Server SSH access**: your server IP and SSH key/password
2. **Postgres container name and IP**: SSH into your server and find your Postgres container. Coolify may have multiple Postgres instances running (its own internal DB and yours), so identify yours by the version you deployed:
   ```bash
   # List all Postgres containers with their image versions
   docker ps | grep -i postgres

   # Example output:
   # abc123def456  postgres:18-alpine  ...  example-container-name       <- your DB (v18)
   # fed654cba321  postgres:15-alpine  ...  coolify-db                     <- Coolify internal DB
   ```
   After identifying your container name, get its internal IP:
   ```bash
   docker inspect <container-name> --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
   ```
   Note the IP (e.g., `10.0.3.2`).
3. **Database credentials**: verify the credentials on the container:
   ```bash
   docker inspect <container-name> --format '{{range .Config.Env}}{{println .}}{{end}}' | grep POSTGRES
   ```
   This shows `POSTGRES_USER`, `POSTGRES_PASSWORD`, and `POSTGRES_DB`. You can also find these in Coolify under your Postgres resource's **Connection** tab.

### 8b. Create the Connection in DBeaver

1. Open DBeaver -> **Database** -> **New Database Connection** -> select **PostgreSQL** -> **Next**

2. **Main tab**: fill in the database details:

   | Field | Value |
   |-------|-------|
   | **Host** | the container IP from step 8a (e.g., `172.x.x.x`) |
   | **Port** | `5432` |
   | **Database** | `teamrc` |
   | **Username** | your Postgres user |
   | **Password** | your Postgres password |

3. **SSH tab**: check **Use SSH Tunnel** and configure:

   | Field | Value |
   |-------|-------|
   | **Host/IP** | your Coolify server IP (e.g., `5.78.100.42`) |
   | **Port** | `22` |
   | **Username** | `root` (or your SSH user) |
   | **Authentication Method** | **Public Key** (recommended) or **Password** |
   | **Private Key** | path to your SSH private key (e.g., `~/.ssh/id_ed25519`) |

4. Click **Test Connection**. DBeaver opens the SSH tunnel and connects through it automatically.

5. Click **Finish** to save. The connection is reusable. Double-click it next time to reconnect.

> **How it works**: DBeaver SSHs into your server, then connects to the Postgres container's internal IP from inside the server. The database port is never exposed to the internet.

> **Why this beats pgAdmin on Coolify:**
> - No public attack surface. The database port is never exposed.
> - No reverse proxy issues. SSH handles encryption and auth natively.
> - Better tool. DBeaver is more capable than pgAdmin's web UI.
> - Simpler. No extra containers to deploy, no domain or SSL to manage.

---

## Step 9. Tune the Server (Optional)

> You can skip this. The defaults work fine for small teams. Come back when you have real traffic or notice performance issues.

teamrc runs on the BEAM (Erlang VM), which is built for high concurrency. However, Linux's default limits are too conservative for it.

### 9a. Tune the Linux Kernel

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

# Prefer RAM over swap. The BEAM manages its own memory and swap causes latency spikes.
vm.swappiness = 1
```

Save the file (Ctrl+X, Y, Enter in nano), then apply it:

```bash
sudo sysctl --system
```

This takes effect immediately, no reboot needed.

### 9b. Raise Container File Descriptor Limits

Docker containers have a default limit on how many files and connections they can open. You need to raise this.

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

**Option B: Per-container ulimits**

Set `ulimits` in Coolify's container settings for the teamrc app:

```
nofile soft: 65536
nofile hard: 65536
```

### 9c. BEAM VM Flags (Advanced)

These flags optimize how the Erlang VM runs inside a container. Optional but helpful.

Add this environment variable in Coolify:

| Variable | Value |
|----------|-------|
| `ERL_FLAGS` | `+K true +Q 65536 +P 1048576 +A 32 +sbwt none +sbwtdcpu none +sbwtdio none` |

What these do:

| Flag | What it does |
|------|-------------|
| `+K true` | Use the OS's efficient I/O polling (epoll on Linux). Faster than the default. |
| `+Q 65536` | Allow up to 65k open ports and connections. Match this to your ulimit. |
| `+P 1048576` | Allow up to 1M lightweight BEAM processes. Generous, but costs nothing. |
| `+A 32` | Use 32 threads for file and network I/O (default is 1). |
| `+sbwt none` | **Important for containers**: Stops the BEAM from busy-waiting when idle. Without this, an idle container wastes CPU. |

> **Heads up**: Don't set `+Q` higher than your `nofile` ulimit. If `nofile` is 65536, set `+Q 65536`.

---

## Step 10. Set Up Auto-Deploy (Optional)

Coolify can automatically redeploy when you push to your branch.

1. Go to your application settings
2. Find **Auto Deploy** and enable it
3. Set the **branch** to watch (e.g., `main`)

Now every `git push origin main` triggers a new deployment. Coolify does rolling deploys. It starts the new container, waits for the health check, then stops the old one. Zero downtime.

---

## Step 11. Monitor and Maintain

### Viewing Logs

Click on your application in Coolify, then the **Logs** tab. Phoenix logs everything to stdout, and Coolify captures it. Check here when debugging issues.

To increase log detail temporarily, add this environment variable:

| Variable | Value |
|----------|-------|
| `LOGGER_LEVEL` | `debug` |

Change it back to `info` (or remove it) when done. Debug logs are very verbose.

### Redeploying

- **Automatic**: Push to your deploy branch (if auto-deploy is on)
- **Manual**: Click **Redeploy** in the Coolify UI
- **Migrations**: Run automatically on every container start. No manual migration needed.

### Scaling Up

If the server feels slow, the simplest fix is a bigger VPS:

| Team Size | Recommended Server | POOL_SIZE |
|-----------|--------------------|-----------|
| 1-100 users | 1 vCPU, 2 GB RAM | 10 |
| 100-500 users | 2 vCPU, 4 GB RAM | 15 |
| 500-2,000 users | 4 vCPU, 8 GB RAM | 20 |
| 2,000+ users | 4+ vCPU, 8+ GB RAM | 30 |

When you scale up, also update `POOL_SIZE` and the Postgres `max_connections`. Rule of thumb: `max_connections` should be at least `POOL_SIZE * 2 + 20`.

---

## How SSL Works (Behind the Scenes)

You don't need to configure SSL manually. Here's what happens:

1. You set your domain in Coolify with `https://`
2. Coolify's Traefik proxy requests a free SSL certificate from Let's Encrypt
3. All HTTPS traffic hits Traefik on port 443, where SSL terminates
4. Traefik forwards the request to your Phoenix container on port 4000 over plain HTTP (safe because it stays on the internal Docker network)
5. Traefik adds a header `X-Forwarded-Proto: https` so Phoenix knows the original request was HTTPS
6. Phoenix uses this header to generate correct `https://` URLs for invites, device auth, etc.

If someone visits `http://teamrc.ai`, Phoenix automatically redirects them to `https://teamrc.ai`.

---

## Troubleshooting

### "database connection refused"

**Cause**: The app container can't reach the database container.

**Fix**:
1. Check that both containers are running in Coolify's UI
2. Look at the database container logs. Is Postgres healthy?
3. Make sure the database has "Connect to Predefined Network" enabled (Step 6e)

### "SECRET_KEY_BASE is missing"

**Cause**: The environment variable isn't set.

**Fix**: Generate it with `openssl rand -base64 64 | tr -d '\n'` and add it to the Environment Variables tab in Coolify.

### Infinite redirect loop or page won't load

**Cause**: The `force_ssl` config is not trusting the `X-Forwarded-Proto` header from Traefik.

**Fix**: This is already handled in the codebase (`rewrite_on: [:x_forwarded_proto]`). If you see this error, make sure you're running the latest code.

### "certificate verify failed"

**Cause**: `DATABASE_SSL` is set to `true`, but the database is on the same Coolify server. SSL is not needed between containers on the same Docker network.

**Fix**: Set `DATABASE_SSL=false` in the environment variables.

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

**Fix**: Add the `ERL_FLAGS` environment variable from Step 9c. The key flag is `+sbwt none`.

### "emfile" error or BEAM crashes

**Cause**: The container hit its file descriptor limit.

**Fix**: Follow Step 9a and 9b to raise the kernel and container limits.

### LiveView pages disconnect or feel laggy

**Cause**: When running multiple instances, WebSocket connections need sticky sessions.

**Fix**: In Coolify's proxy settings, enable session affinity (sticky sessions). This is not an issue for single-instance deploys.

---

## Advanced: Database High Availability

> A single Postgres instance on one server handles thousands of users easily. For most teamrc deployments, the setup in Step 5 (standalone Postgres + S3 backups) is all you need.

### Why Not Replicate on the Same Server?

Same-server replication doesn't provide real HA. If the server dies, both primary and replica die together. It only protects against the Postgres process crashing, and Coolify already auto-restarts containers for that. It doubles your RAM and disk usage with no real benefit.

### What Actually Protects You (Single Server)

1. **Coolify auto-restart**: if Postgres crashes, the container restarts automatically
2. **S3 backups** (Step 5b): if the server dies, restore from backup onto a new server in minutes
3. **WAL archiving to S3** (optional): for point-in-time recovery between daily backups

### When You Need Real HA

If you need automatic failover and zero downtime, you have two options:

**Option A: Managed Postgres.** Simplest path. Point `DATABASE_URL` at an external provider:
- **Neon**: serverless, scales to zero, generous free tier
- **Crunchy Bridge**: traditional managed Postgres with HA replicas
- **Your VPS provider**: Hetzner, DigitalOcean, Vultr all offer managed Postgres ($15-30/mo)

**Option B: Autobase.** Self-hosted DBaaS. Deploy the [Autobase console](https://autobase.tech/) to manage HA Postgres clusters across multiple servers. Requires 3+ VMs for a proper HA cluster (Patroni + etcd). Gives you full control with automatic failover, backups, and scaling. The console can run as a Docker Compose resource in Coolify. The Postgres cluster runs on separate machines managed via Ansible.

---

## Advanced: Horizontal Scaling

> Probably not needed yet. A single BEAM node handles concurrency very well. One 4 GB server can serve thousands of concurrent CLI connections.

Phoenix supports clustering through DNS-based service discovery. If you need multiple instances:

1. Add `DNS_CLUSTER_QUERY=teamrc-app.internal` as an environment variable
2. Scale the service to multiple replicas in Coolify
3. Enable sticky sessions in Coolify's proxy config (required for LiveView WebSocket connections)
4. Set a shared Erlang cookie: add `RELEASE_COOKIE=your-shared-secret` as an env var. This must be the same across all instances.

---

## Quick Reference: All Environment Variables

| Variable | Required? | Example | Description |
|----------|-----------|---------|-------------|
| `DATABASE_URL` | Yes | `ecto://user:pass@host:5432/db` | PostgreSQL connection string |
| `DATABASE_SSL` | Yes | `false` | Use `false` for same-server DB |
| `PHX_HOST` | Yes | `teamrc.ai` | Your domain, without `https://` |
| `PHX_SERVER` | Yes | `true` | Enable the web server |
| `SECRET_KEY_BASE` | Yes | _(64+ char random string)_ | Cookie signing key |
| `SESSION_SIGNING_SALT` | Yes | _(random string)_ | Session signing salt |
| `LIVE_VIEW_SIGNING_SALT` | Yes | _(random string)_ | LiveView signing salt |
| `SESSION_ENCRYPTION_SALT` | Yes | _(random string)_ | Session encryption salt |
| `POOL_SIZE` | No | `10` | DB connection pool (default: 10) |
| `ERL_FLAGS` | No | `+K true +sbwt none ...` | BEAM VM tuning flags |
| `LOGGER_LEVEL` | No | `info` | Log verbosity: debug, info, or warn |
| `DNS_CLUSTER_QUERY` | No | `teamrc.internal` | For multi-instance clustering |
| `GITHUB_CLIENT_ID` | No | _(from GitHub OAuth App)_ | GitHub OAuth login |
| `GITHUB_CLIENT_SECRET` | No | _(from GitHub OAuth App)_ | GitHub OAuth login |
| `GOOGLE_CLIENT_ID` | No | _(from Google Cloud Console)_ | Google OAuth login |
| `GOOGLE_CLIENT_SECRET` | No | _(from Google Cloud Console)_ | Google OAuth login |
| `RESEND_API_KEY` | No | `re_xxxxx` | Transactional email for password reset and verification |
| `ANALYTICS_HOST` | No | _(your analytics host)_ | Analytics host |
| `ANALYTICS_WEBSITE_ID` | No | _(your website ID)_ | Analytics website ID |
| `OTEL_ENDPOINT` | No | _(collector URL)_ | OpenTelemetry collector endpoint |
