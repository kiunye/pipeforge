# Deployment Guide

## Gigalixir Deployment

### Prerequisites

1. Gigalixir account
2. Gigalixir CLI installed: `pip install gigalixir`
3. GitHub repository with secrets configured

### Required GitHub Secrets

Configure the following secrets in your GitHub repository settings:

- `GIGALIXIR_EMAIL`: Your Gigalixir account email
- `GIGALIXIR_API_KEY`: Your Gigalixir API key (from https://gigalixir.com/)
- `GIGALIXIR_APP_NAME`: Your Gigalixir app name

### Initial Setup

1. **Create Gigalixir App:**
   ```bash
   gigalixir create
   ```

2. **Add PostgreSQL Add-on:**
   ```bash
   gigalixir addons:create timescaledb:community
   ```

3. **Set Environment Variables:**
   ```bash
   gigalixir config:set SECRET_KEY_BASE=$(mix phx.gen.secret)
   gigalixir config:set DATABASE_URL=$(gigalixir config:get DATABASE_URL)
   gigalixir config:set PHX_HOST=your-app-name.gigalixir.app
   ```

4. **Configure Additional Environment Variables:**
   ```bash
   # OAuth
   gigalixir config:set GOOGLE_CLIENT_ID=your-google-client-id
   gigalixir config:set GOOGLE_CLIENT_SECRET=your-google-client-secret
   gigalixir config:set GITHUB_CLIENT_ID=your-github-client-id
   gigalixir config:set GITHUB_CLIENT_SECRET=your-github-client-secret

   # JWT
   gigalixir config:set JWT_SECRET=$(mix phx.gen.secret)

   # MinIO/S3 (or use Gigalixir S3 addon)
   gigalixir config:set MINIO_ENDPOINT=your-minio-endpoint
   gigalixir config:set MINIO_ACCESS_KEY=your-access-key
   gigalixir config:set MINIO_SECRET_KEY=your-secret-key
   gigalixir config:set MINIO_BUCKET=pipeforge-uploads

   # Slack & Email
   gigalixir config:set SLACK_WEBHOOK_URL=your-slack-webhook
   gigalixir config:set SMTP_HOST=smtp.gmail.com
   gigalixir config:set SMTP_PORT=587
   gigalixir config:set SMTP_USERNAME=your-email@gmail.com
   gigalixir config:set SMTP_PASSWORD=your-app-password
   ```

5. **Run Migrations:**
   ```bash
   gigalixir run mix ecto.migrate
   ```

### Automatic Deployment

Deployment is automated via GitHub Actions. When you push to `main`:
1. Tests run (formatting, credo, sobelow, dialyzer, tests)
2. If all pass, the app is automatically deployed to Gigalixir

### Manual Deployment

```bash
gigalixir login
gigalixir git:remote your-app-name
git push gigalixir main
```

### Rollback

To rollback to a previous release:

```bash
gigalixir releases
gigalixir releases:rollback VERSION_NUMBER
```

Or via Gigalixir dashboard:
1. Go to https://gigalixir.com/
2. Select your app
3. Navigate to Releases
4. Click "Rollback" on the desired release

### Health Checks

The app includes health check endpoints:
- `/healthz` - Basic health check
- `/readyz` - Readiness check (database connectivity)

### Monitoring

- View logs: `gigalixir logs`
- View metrics: `gigalixir status`
- Scale dynos: `gigalixir ps:scale web=2`

### Custom Domain

1. Add domain in Gigalixir dashboard
2. Update DNS records as instructed
3. Update `PHX_HOST` environment variable
4. Configure SSL (automatic with Gigalixir)

## Environment-Specific Configuration

### Development
- Uses local Docker Compose services
- Database: `pipeforge_dev`
- No SSL required

### Production
- Uses Gigalixir PostgreSQL (TimescaleDB)
- HTTPS enforced
- Environment variables managed via Gigalixir config

