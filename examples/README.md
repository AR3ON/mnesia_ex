# MnesiaEx Examples

This directory contains complete, runnable examples demonstrating all features of MnesiaEx.

## Running Examples

Each example is a standalone Elixir script (`.exs`) that you can run directly:

```bash
cd mnesia_ex
elixir examples/01_basic_crud.exs
```

## Examples

### 01. Basic CRUD Operations
**File:** `01_basic_crud.exs`

Learn the fundamentals:
- Creating tables with `use MnesiaEx`
- Write, read, update, delete operations
- Querying with conditions
- Finding records by field
- Batch operations
- Upsert (insert or update)

```bash
elixir examples/01_basic_crud.exs
```

### 02. TTL (Time To Live)
**File:** `02_ttl.exs`

Automatic record expiration:
- Writing records with TTL
- Checking remaining TTL
- Auto-cleanup of expired records
- Managing session-like data
- Listing active TTL records

```bash
elixir examples/02_ttl.exs
```

### 03. Auto-Increment Counters
**File:** `03_counters.exs`

Thread-safe, distributed ID generation:
- Auto-increment IDs for new records
- Multiple counter fields per table
- Resetting counters
- Checking current counter values
- Counter existence validation

```bash
elixir examples/03_counters.exs
```

### 04. Event Subscriptions
**File:** `04_events.exs`

Real-time notifications:
- Subscribing to table changes
- Receiving write/delete events
- Parsing event data
- Unsubscribing from events
- Building reactive systems

```bash
elixir examples/04_events.exs
```

### 05. Backup & Export
**File:** `05_backup_export.exs`

Data persistence and portability:
- Creating Mnesia backups
- Exporting to JSON format
- Exporting to CSV format
- Exporting to Erlang terms
- Restoring from backups
- Listing and managing exports

```bash
elixir examples/05_backup_export.exs
```

### 06. Complete Application
**File:** `06_complete_app.exs`

Full-featured blog system demonstrating:
- Multiple related tables (users, posts, comments, sessions)
- Auto-increment IDs across tables
- TTL for session management
- Complex queries and relationships
- Service-oriented architecture
- Real-world use cases

```bash
elixir examples/06_complete_app.exs
```

### 07. Composable Transactions
**File:** `07_transactions.exs`

Advanced transaction patterns demonstrating:
- Using `MnesiaEx.transaction/1` (like Ecto's `Repo.transaction/1`)
- Composing multiple operations atomically
- Error handling and rollback
- Mixing bang (!) and tuple-returning functions
- When to use manual transactions vs ! functions

```bash
elixir examples/07_transactions.exs
```

## Learning Path

If you're new to MnesiaEx, we recommend following the examples in order:

1. **Start with 01_basic_crud.exs** - Get familiar with basic operations
2. **Then 02_ttl.exs** - Learn about automatic expiration
3. **Then 03_counters.exs** - Understand auto-increment
4. **Then 04_events.exs** - Explore real-time features
5. **Then 05_backup_export.exs** - Learn data management
6. **Then 06_complete_app.exs** - See it all working together
7. **Finally 07_transactions.exs** - Master composable transactions

## What Each Example Teaches

| Example | Key Concepts | Use Cases |
|---------|--------------|-----------|
| 01_basic_crud | CRUD, queries, batch ops | Most applications |
| 02_ttl | Auto-expiration, cleanup | Sessions, caches, temporary data |
| 03_counters | Auto-increment, distributed IDs | Primary keys, analytics |
| 04_events | Pub/sub, real-time updates | Live dashboards, notifications |
| 05_backup_export | Data portability, recovery | Backups, migrations, reports |
| 06_complete_app | Architecture, relationships | Real applications |
| 07_transactions | Manual transactions, composition | Complex multi-table operations |

## Requirements

All examples use `Mix.install/1` to automatically download dependencies. You only need:

- Elixir 1.14 or later
- Internet connection (first run only)

No need to run `mix deps.get` - dependencies are managed automatically!

## Tips

- **Read the code**: Each example is heavily commented
- **Experiment**: Modify the examples to explore features
- **Check output**: Examples print detailed information
- **Error handling**: Examples use `!` functions for simplicity (production code should handle errors)

## Common Patterns

### Table Definition
```elixir
defmodule MyApp.TableName do
  use MnesiaEx, table: :table_name
end
```

### Initialization
```elixir
MnesiaEx.start()
MnesiaEx.Schema.create([node()])
MyApp.TableName.create(attributes: [:id, :field1, :field2])
```

### Cleanup
```elixir
MyApp.TableName.drop()
MnesiaEx.Schema.delete([node()])
MnesiaEx.stop()
```

## Need Help?

- 📖 Read the main [README](../README.md)
- 📚 Check the [API documentation](https://hexdocs.pm/mnesia_ex)
- 💬 Open an [issue on GitHub](https://github.com/AR3ON/mnesia_ex/issues)

## Contributing Examples

Have a great example to share? We'd love to include it! Please:

1. Make it self-contained (using `Mix.install/1`)
2. Add clear comments explaining key concepts
3. Include IO output to show results
4. Clean up resources at the end
5. Submit a pull request

Happy coding! 🚀

