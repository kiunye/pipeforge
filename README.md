# PipeForge

Sales Analytics Platform - A backend-first analytics platform that ingests order data from e-commerce merchants and transforms it into actionable insights.

## Quick Start

### Prerequisites

- Elixir 1.18.4 and Erlang 27.2.2 (managed via `mise`)
- Docker and Docker Compose
- mise (for version management)

### Setup

1. **Install versions:**
   ```bash
   mise install
   ```

2. **Activate mise in your shell:**
   ```bash
   eval "$(mise activate zsh)"  # or bash/fish as appropriate
   ```

3. **Start Docker services:**
   ```bash
   docker-compose up -d
   ```

4. **Install dependencies and setup database:**
   ```bash
   mix setup
   ```

5. **Start Phoenix server:**
   ```bash
   mix phx.server
   ```

Visit [`localhost:4000`](http://localhost:4000) from your browser.

## Services

- **Phoenix Application**: `http://localhost:4000`
- **RabbitMQ Management**: `http://localhost:15672` (guest/guest)
- **MinIO Console**: `http://localhost:9001` (minioadmin/minioadmin)
- **PostgreSQL/TimescaleDB**: `localhost:5432`

See [docs/docker-setup.md](docs/docker-setup.md) for detailed Docker setup instructions.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for development guidelines.

## Deployment

See [docs/deployment.md](docs/deployment.md) for deployment instructions.

Ready to run in production? Please [check our deployment guides](docs/deployment.md).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
