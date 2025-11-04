# Operations Runbook

## Health Checks

### Endpoints

- **Health Check**: `GET /healthz`
  - Returns: `{"status": "ok", "timestamp": "..."}`
  - Use for: Basic liveness probe
  - No database connectivity check

- **Readiness Check**: `GET /readyz`
  - Returns: `{"status": "ready", "database": "connected", "timestamp": "..."}`
  - Use for: Readiness probe (checks database connectivity)
  - Returns 503 if database is unavailable

### Monitoring

Configure your load balancer or orchestrator to use:
- Liveness: `/healthz` every 30s
- Readiness: `/readyz` every 10s

## Common Operations

### Database Migrations

```bash
# Local development
mix ecto.migrate

# Production (Gigalixir)
gigalixir run mix ecto.migrate
```

### Rollback Migrations

```bash
# Local development
mix ecto.rollback

# Production
gigalixir run mix ecto.rollback
```

### View Logs

```bash
# Local development
# Logs appear in terminal where `mix phx.server` is running

# Production
gigalixir logs
gigalixir logs --tail 100  # Last 100 lines
```

### Database Connection Issues

1. **Check database status:**
   ```bash
   gigalixir status
   ```

2. **Verify DATABASE_URL:**
   ```bash
   gigalixir config:get DATABASE_URL
   ```

3. **Test connection:**
   ```bash
   gigalixir run mix ecto.migrate
   ```

### Application Restart

```bash
gigalixir restart
```

### Scale Application

```bash
# Scale web dynos
gigalixir ps:scale web=2

# View current scaling
gigalixir ps
```

### Environment Variables

```bash
# List all
gigalixir config

# Get specific
gigalixir config:get VARIABLE_NAME

# Set
gigalixir config:set VARIABLE_NAME=value

# Unset
gigalixir config:unset VARIABLE_NAME
```

## Troubleshooting

### High Memory Usage

1. Check current usage: `gigalixir status`
2. Review logs for memory leaks: `gigalixir logs | grep -i memory`
3. Scale up dynos if needed: `gigalixir ps:scale web=2`
4. Review application code for memory-intensive operations

### Slow Database Queries

1. Check TimescaleDB metrics in Gigalixir dashboard
2. Review slow query logs
3. Verify indexes are present: `mix ecto.migrations`
4. Consider adding additional indexes for frequently queried columns

### Ingestion Pipeline Issues

1. **Check RabbitMQ status:**
   - Local: `docker-compose ps rabbitmq`
   - Production: Verify RabbitMQ addon status

2. **Check ingestion files:**
   ```bash
   gigalixir run mix pipeforge.ingestion.status
   ```

3. **View failed records:**
   - Access failed records UI: `/ingestion/failures`
   - Or via IEx: `PipeForge.Ingestion.list_failed_records()`

### Alert Configuration

1. **Update Slack webhook:**
   ```bash
   gigalixir config:set SLACK_WEBHOOK_URL=new-webhook-url
   ```

2. **Update email SMTP:**
   ```bash
   gigalixir config:set SMTP_HOST=smtp.gmail.com
   gigalixir config:set SMTP_PORT=587
   gigalixir config:set SMTP_USERNAME=email@example.com
   gigalixir config:set SMTP_PASSWORD=app-password
   ```

## Backup and Recovery

### Database Backups

Gigalixir automatically handles PostgreSQL backups. To manually backup:

```bash
# Download backup
gigalixir pg:backups:download

# Restore from backup
gigalixir pg:backups:restore BACKUP_ID
```

### Data Retention

- Raw orders: 1 month (automated cleanup job)
- Aggregates: 6 months (automated cleanup job)

To manually clean old data:

```bash
gigalixir run mix pipeforge.retention.cleanup
```

## Performance Optimization

### Query Performance

- Use `sales_aggregates_daily` table for dashboard queries
- Ensure date range filters use indexed `order_date` column
- Use TimescaleDB continuous aggregates for very large datasets

### Caching Strategy

- Cache dashboard queries for 5 minutes
- Invalidate cache on new data ingestion
- Use Phoenix LiveView for real-time updates

## Security

### SSL/TLS

- Gigalixir automatically provides SSL certificates
- Ensure `force_ssl` is enabled in production config
- Verify HTTPS redirects work: `curl -I https://your-app.gigalixir.app`

### Secrets Management

- Never commit secrets to git
- Use Gigalixir config for all sensitive values
- Rotate secrets regularly:
  ```bash
  gigalixir config:set SECRET_KEY_BASE=$(mix phx.gen.secret)
  gigalixir config:set JWT_SECRET=$(mix phx.gen.secret)
  ```

## Emergency Procedures

### Complete Outage

1. Check Gigalixir status page: https://status.gigalixir.com/
2. Verify database connectivity: `gigalixir run mix ecto.migrate`
3. Check application logs: `gigalixir logs --tail 500`
4. Restart application: `gigalixir restart`
5. If issue persists, rollback to last known good release

### Data Corruption

1. Stop ingestion immediately
2. Identify affected time range
3. Restore from backup if necessary
4. Re-run ingestion for affected period after fix

### Security Incident

1. Rotate all secrets immediately
2. Review access logs
3. Check for unauthorized data access
4. Follow incident response procedures

