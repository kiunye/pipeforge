# Contributing to PipeForge

Thank you for your interest in contributing to PipeForge!

## Development Setup

1. **Version Management**: This project uses `mise` (formerly rtx) for version management
   - Ensure mise is installed and configured
   - Run `mise install` to install the required versions
   - Activate mise in your shell: `eval "$(mise activate zsh)"` (or `bash`/`fish` as appropriate)
   - Verify versions: `mise current` should show Elixir 1.18.4 and Erlang 27.2.2

2. Install dependencies: `mix deps.get`
3. Install rebar3 (if not already installed): `mix local.rebar --force`
4. Start Docker services: `docker-compose up -d`
5. Set up the database: `mix ecto.setup`
6. Start the Phoenix server: `mix phx.server`

## Code Style

- Follow Elixir style guidelines
- Run `mix format` before committing
- Run `mix credo` to check code quality
- Run `mix dialyzer` to check for type errors

## Testing

- Write tests for new features
- Run tests with `mix test`
- Aim for 80%+ code coverage on domain logic

## Pull Requests

1. Create a feature branch from `main`
2. Make your changes
3. Ensure all tests pass
4. Update documentation as needed
5. Submit a PR with a clear description

## Commit Messages

- Use clear, descriptive commit messages
- Reference issue numbers when applicable

