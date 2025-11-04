# Docker Compose Setup

This project uses Docker Compose to run local development services: TimescaleDB (PostgreSQL), RabbitMQ, and MinIO.

## Services

### TimescaleDB (PostgreSQL)
- **Container**: `pipeforge_postgres`
- **Port**: `5432`
- **Database**: `pipeforge_dev`
- **User**: `postgres`
- **Password**: `postgres`
- **Volume**: `postgres_data` (persistent storage)

### RabbitMQ
- **Container**: `pipeforge_rabbitmq`
- **AMQP Port**: `5672`
- **Management UI**: `http://localhost:15672`
- **User**: `guest`
- **Password**: `guest`
- **Volume**: `rabbitmq_data` (persistent storage)

### MinIO (S3-compatible storage)
- **Container**: `pipeforge_minio`
- **API Port**: `9000`
- **Console Port**: `9001` (Management UI)
- **Console URL**: `http://localhost:9001`
- **Root User**: `minioadmin`
- **Root Password**: `minioadmin`
- **Volume**: `minio_data` (persistent storage)

## Quick Start

1. **Start all services:**
   ```bash
   docker-compose up -d
   ```

2. **Check service status:**
   ```bash
   docker-compose ps
   ```

3. **View logs:**
   ```bash
   docker-compose logs -f
   # Or for a specific service:
   docker-compose logs -f postgres
   ```

4. **Stop all services:**
   ```bash
   docker-compose down
   ```

5. **Stop and remove volumes (clean slate):**
   ```bash
   docker-compose down -v
   ```

## Initial Setup

### TimescaleDB

The database is automatically created. To set up the schema:

```bash
# Make sure services are running
docker-compose up -d

# Run migrations
mix ecto.create
mix ecto.migrate
```

### RabbitMQ

The default guest user is configured automatically. For production, create dedicated users and vhosts.

Access the management UI at `http://localhost:15672` to:
- Monitor queues and connections
- Create exchanges and queues
- View message rates

### MinIO

1. **Access the Console:**
   - Open `http://localhost:9001`
   - Login with `minioadmin` / `minioadmin`

2. **Create Bucket:**
   - Click "Buckets" → "Create Bucket"
   - Name: `pipeforge-uploads`
   - Set appropriate access policy

3. **Configure Application:**
   The application expects these environment variables:
   ```bash
   export MINIO_ENDPOINT=http://localhost:9000
   export MINIO_ACCESS_KEY=minioadmin
   export MINIO_SECRET_KEY=minioadmin
   export MINIO_BUCKET=pipeforge-uploads
   export MINIO_REGION=us-east-1
   ```

## Health Checks

All services include health checks. Verify they're healthy:

```bash
docker-compose ps
```

You should see `(healthy)` status for all services.

## Troubleshooting

### Port Already in Use

If you get port conflict errors:

```bash
# Check what's using the port
lsof -i :5432  # PostgreSQL
lsof -i :5672  # RabbitMQ
lsof -i :9000  # MinIO

# Stop conflicting services or change ports in docker-compose.yml
```

### Database Connection Issues

1. Verify PostgreSQL is running:
   ```bash
   docker-compose ps postgres
   ```

2. Check logs:
   ```bash
   docker-compose logs postgres
   ```

3. Test connection:
   ```bash
   docker-compose exec postgres psql -U postgres -d pipeforge_dev
   ```

### RabbitMQ Management UI Not Accessible

1. Check if port 15672 is available
2. Verify container is healthy: `docker-compose ps rabbitmq`
3. Check logs: `docker-compose logs rabbitmq`

### MinIO Bucket Creation

If you need to create the bucket programmatically:

```bash
docker-compose exec minio mc alias set local http://localhost:9000 minioadmin minioadmin
docker-compose exec minio mc mb local/pipeforge-uploads
docker-compose exec minio mc anonymous set download local/pipeforge-uploads
```

## Environment Variables

Default credentials are suitable for local development only. For production:

1. Use environment-specific docker-compose files
2. Use Docker secrets or environment variable files
3. Never commit production credentials to git

## Data Persistence

All data is stored in Docker volumes:
- `postgres_data`: Database files
- `rabbitmq_data`: RabbitMQ data and messages
- `minio_data`: MinIO objects

To backup:
```bash
docker run --rm -v pipeforge_postgres_data:/data -v $(pwd):/backup alpine tar czf /backup/postgres_backup.tar.gz /data
```

To restore:
```bash
docker run --rm -v pipeforge_postgres_data:/data -v $(pwd):/backup alpine tar xzf /backup/postgres_backup.tar.gz -C /
```

## Networking

All services are on the `pipeforge_network` bridge network and can communicate using service names:
- `postgres` (hostname for PostgreSQL)
- `rabbitmq` (hostname for RabbitMQ)
- `minio` (hostname for MinIO)

Your application should connect to `localhost` ports when running outside Docker, or use service names when running inside Docker.

