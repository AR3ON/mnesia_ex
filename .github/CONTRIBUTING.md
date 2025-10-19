# Contributing to MnesiaEx

Thank you for your interest in contributing to MnesiaEx! We welcome contributions from the community.

## Code of Conduct

Be respectful, inclusive, and constructive. We're all here to build great software together.

## How to Contribute

### Reporting Bugs

1. Check existing issues to avoid duplicates
2. Use the issue template
3. Include:
   - Elixir and Erlang versions
   - MnesiaEx version
   - Minimal reproducible example
   - Expected vs actual behavior
   - Error messages and stack traces

### Suggesting Features

1. Open an issue with the "enhancement" label
2. Describe the use case
3. Explain why it fits MnesiaEx's goals
4. Provide examples of desired API

### Pull Requests

#### Before You Start

1. Fork the repository
2. Create a feature branch from `master`

#### Development Guidelines

**Strict Functional Programming Rules:**

MnesiaEx follows pure functional programming with category theory principles.

**❌ Prohibited:**
- `if`, `case`, `cond` statements
- `try`, `rescue`, `raise`, `throw`
- `nil` returns (use `:nothing` or `{:error, reason}`)
- Side effects in pure functions
- `Logger` or `IO` in domain logic

**✅ Required:**
- Pattern matching and guards
- Monadic composition with `Error.m do`
- Pure functions (no side effects)
- `MnesiaEx.Monad` (aliased as `Error`)
- Semantic function names (`safe_`, `validate_`, `fetch_`, etc.)
- Type specs for all public functions
- Follow Elixir standard conventions for `!`, `?`, and list functions

**Example:**

```elixir
# ❌ Bad - uses case
defp process_value(value) do
  case value do
    :ok -> {:ok, value}
    _ -> {:error, :invalid}
  end
end

# ✅ Good - uses pattern matching
defp process_value(:ok), do: Error.return(:ok)
defp process_value(_), do: Error.fail(:invalid)
```

#### Code Style

- Follow Elixir naming conventions
- Use pipes `|>` for transformations
- Small, composable functions
- No single-use helper functions (inline them)
- Self-documenting code (minimal comments)

#### Elixir Standard Conventions

**Functions with `!` (bang):**
- Use `!` suffix only for functions that raise exceptions on error
- Must have a non-`!` version that returns `{:ok, value} | {:error, reason}`
- Example: `read/2` returns tuple, `read!/2` raises

**Functions returning lists:**
- Return lists directly (not wrapped in `{:ok, list}`)
- Do NOT have a `!` version (empty list `[]` is valid, not an error)
- Example: `select/3` returns `[records]` directly

**Boolean functions:**
- Use `?` suffix
- Return `true` or `false` (never tuples or exceptions)
- Example: `exists?/1`, `expired?/2`

#### Testing

- Write tests for all new functionality
- Tests must be pure (no mocks, no external dependencies)
- Follow same functional rules as production code
- Ensure all tests pass: `mix test`
- Run formatter: `mix format`

#### Documentation

- Add `@moduledoc` for new modules
- Add `@doc` with examples for public functions
- Include `@spec` for type safety
- Write documentation in English
- Use `iex>` for examples

#### Commit Messages

Follow conventional commits:

```
feat: add support for custom table types
fix: correct counter initialization bug
docs: improve Query module examples
refactor: simplify table creation logic
test: add coverage for TTL edge cases
```

#### Pull Request Process

1. **Create your branch**
   ```bash
   git checkout -b feature/amazing-feature
   ```

2. **Make your changes**
   - Follow the functional programming rules
   - Write tests
   - Update documentation

3. **Run quality checks**
   ```bash
   mix test
   mix format --check-formatted
   mix compile --warnings-as-errors
   ```

4. **Commit and push**
   ```bash
   git add .
   git commit -m "feat: add amazing feature"
   git push origin feature/amazing-feature
   ```

5. **Create Pull Request**
   - Describe what and why
   - Reference related issues
   - Include examples if applicable
   - Ensure CI passes

6. **Code Review**
   - Address feedback
   - Make requested changes
   - Keep the conversation constructive

## Development Setup

```bash
# Clone the repository
git clone https://github.com/AR3ON/mnesia_ex.git
cd mnesia_ex

# Install dependencies
mix deps.get

# Run tests
mix test

# Generate documentation
mix docs

# Format code
mix format
```

## Project Structure

```
mnesia_ex/
├── lib/
│   └── mnesia_ex/
│       ├── application.ex      # Application supervisor
│       ├── backup.ex           # Backup/restore functionality
│       ├── config.ex           # Configuration management
│       ├── counter.ex          # Auto-increment counters
│       ├── duration.ex         # Time duration utilities
│       ├── events.ex           # Event subscription system
│       ├── query.ex            # CRUD operations
│       ├── schema.ex           # Schema management
│       ├── table.ex            # Table operations
│       ├── ttl.ex              # TTL functionality
│       └── utils.ex            # Utility functions
├── test/
│   └── mnesia_ex/              # Tests mirror lib structure
├── README.md
├── CHANGELOG.md
└── mix.exs
```

## Monadic Principles

This project uses `MnesiaEx.Monad` for functional composition and error handling.

### Error Monad

```elixir
require MnesiaEx.Monad, as: Error

# Monadic composition
Error.m do
  user <- fetch_user(id)
  validated <- validate_user(user)
  saved <- save_user(validated)
  Error.return(saved)
end
```

**Available operations:**
- `Error.return(value)` - Wrap value in success monad
- `Error.fail(reason)` - Create error monad
- `Error.m do ... end` - Monadic composition (no `case/if/cond` inside)
- `Error.bind(monad, fun)` - Chain operations

### Pure Functions

All business logic must be pure:

```elixir
# ✅ Good - pure function
defp calculate_total(items) do
  items
  |> Enum.map(& &1.price)
  |> Enum.sum()
  |> Error.return()
end

# ❌ Bad - has side effects
defp calculate_total(items) do
  Logger.info("Calculating total")  # Side effect!
  total = Enum.sum(items)
  {:ok, total}
end
```

### Elixir Standard Examples

**Functions that return a single value:**

```elixir
# Without ! - returns tuple
def read(table, id) do
  # ... implementation
  Error.return(record)  # Returns {:ok, record}
end

# With ! - raises on error
def read!(table, id) do
  read(table, id)
  |> unwrap_or_raise!()  # Returns record or raises
end
```

**Functions that return lists:**

```elixir
# No ! version needed - lists are always valid
def select(table, conditions) do
  # ... implementation
  records  # Returns [records] directly, not {:ok, [records]}
end

# ❌ WRONG - don't create select!/3
# Empty list [] is a valid result, not an error
```

**Boolean functions:**

```elixir
# Use ? suffix, return boolean
def exists?(table) do
  # ... implementation
  true  # or false, never {:ok, true} or exceptions
end
```

## Questions?

- Open an issue for questions
- Tag with "question" label
- Search existing issues first
- Be specific and provide context

## Recognition

Contributors will be added to the README and release notes. Thank you for making MnesiaEx better!

---

Happy Contributing! 🎉

