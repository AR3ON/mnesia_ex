# MnesiaEx

**A modern, functional wrapper for Erlang/OTP's Mnesia database**

[![Hex.pm Version](https://img.shields.io/hexpm/v/mnesia_ex.svg)](https://hex.pm/packages/mnesia_ex)
[![Hex.pm Downloads](https://img.shields.io/hexpm/dt/mnesia_ex.svg)](https://hex.pm/packages/mnesia_ex)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/mnesia_ex)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Status: Beta](https://img.shields.io/badge/status-beta-orange.svg)](https://github.com/AR3ON/mnesia_ex/releases)

> **⚠️ Beta Release (v0.1.0)**: API is functional and tested but may evolve based on community feedback. Use in production with thorough testing.

MnesiaEx brings the power of Mnesia to Elixir with a clean, functional API. Built with category theory principles and monadic composition, it provides an idiomatic Elixir experience for distributed databases with features like automatic TTL, auto-increment counters, schema migrations, dirty operations, and JSON/CSV export.

## Why MnesiaEx?

Mnesia is a distributed database built into Erlang/OTP. MnesiaEx provides an Elixir-friendly API:

- 🎯 **Elixir-First API** - Idiomatic Elixir patterns and conventions
- 🔄 **Functional & Pure** - Built with monads and composable functions
- ⚡ **Zero External Dependencies** - Uses only Mnesia (no Postgres, MySQL, etc.)
- 🌐 **Distributed by Default** - Multi-node clustering out of the box

### Use Cases

- 🔑 Session storage and caching
- 🎮 Real-time multiplayer game state
- 📊 Distributed counters and metrics
- 🔐 Feature flags and configuration
- 📝 Small to medium datasets (< 2GB per node)
- 🌍 Edge computing and embedded systems

## Features

- 🎯 **Smart Auto-Transaction** - Functions auto-detect if inside transaction (UNIQUE!)
- ✨ **Table-Scoped Modules** - Clean API without repeating table names
- 🔄 **Auto-Increment** - Built-in counter support for IDs
- ⏰ **TTL Support** - Automatic record expiration and cleanup
- 💾 **Backup & Restore** - Export/import to JSON, CSV, or Erlang terms
- 📡 **Event Subscriptions** - Real-time notifications on data changes
- 🔍 **Query Builder** - Composable conditions for data filtering
- ⚡ **Dirty Operations** - 10x faster operations when ACID isn't critical
- 🔧 **Schema Migrations** - Transform table structure with data migration
- 🌐 **Distribution** - Multi-node replication and fault tolerance
- 📊 **System Info** - Cluster monitoring and diagnostics
- 🎯 **Type Safety** - Full typespecs and dialyzer support
- 🧪 **Pure Functional** - No side effects, full monad support

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:mnesia_ex, "~> 0.1"}
  ]
end
```

⚠️ **Beta Release**: This is a beta release (v0.1.x). The API may change before v1.0.0.

For production use, consider pinning to a specific minor version:

```elixir
{:mnesia_ex, "~> 0.1.0"}  # Only allows 0.1.x patches
```

## Examples

Check out the [`examples/`](https://github.com/AR3ON/mnesia_ex/tree/main/examples) directory for complete, runnable examples:

- **[01_basic_crud.exs](https://github.com/AR3ON/mnesia_ex/blob/main/examples/01_basic_crud.exs)** - Write, read, update, delete, queries
- **[02_ttl.exs](https://github.com/AR3ON/mnesia_ex/blob/main/examples/02_ttl.exs)** - Automatic record expiration
- **[03_counters.exs](https://github.com/AR3ON/mnesia_ex/blob/main/examples/03_counters.exs)** - Auto-increment IDs and distributed counters
- **[04_events.exs](https://github.com/AR3ON/mnesia_ex/blob/main/examples/04_events.exs)** - Real-time event subscriptions
- **[05_backup_export.exs](https://github.com/AR3ON/mnesia_ex/blob/main/examples/05_backup_export.exs)** - Backup to JSON/CSV/Erlang
- **[06_complete_app.exs](https://github.com/AR3ON/mnesia_ex/blob/main/examples/06_complete_app.exs)** - Full blog system demo
- **[07_transactions.exs](https://github.com/AR3ON/mnesia_ex/blob/main/examples/07_transactions.exs)** - Composable transactions

Run any example with:
```bash
elixir examples/01_basic_crud.exs
```

All examples use `Mix.install/1` - no setup required!

## Quick Start

### 1. Initialize Schema (first time only)

```elixir
# Create Mnesia schema on disk
MnesiaEx.Schema.create([node()])
MnesiaEx.start()
```

### 2. Define Your Table Module

```elixir
defmodule MyApp.Users do
  use MnesiaEx, table: :users

  def setup do
    create([
      attributes: [:id, :name, :email, :age],
      index: [:email],
      disc_copies: [node()]
    ])
  end
end
```

### 3. Create and Use Tables

```elixir
# Create table (first time)
MyApp.Users.setup()

# Functions with ! return value directly (in transactions)
user = MyApp.Users.write!(%{id: 1, name: "Alice", email: "alice@example.com", age: 30})
user = MyApp.Users.read!(1)
user = MyApp.Users.update!(1, %{age: 31})
deleted = MyApp.Users.delete!(1)

# Functions without ! return tuples (composable)
{:ok, user} = MyApp.Users.write(%{id: 2, name: "Bob", email: "bob@example.com"})
{:error, :not_found} = MyApp.Users.read(999)

# Select and all_keys return lists directly (no ! needed, lists are always valid)
users = MyApp.Users.select([{:age, :>=, 18}])
all_users = MyApp.Users.select([])
keys = MyApp.Users.all_keys()

# Compose your own transactions
{:ok, {user, post}} = MnesiaEx.transaction(fn ->
  {:ok, user} = MyApp.Users.write(%{id: 3, name: "Carol"})
  {:ok, post} = MyApp.Posts.write(%{user_id: user.id, title: "Hello"})
  {user, post}
end)
```

### API Convention - Smart Auto-Transaction Detection

**MnesiaEx has a unique feature:** functions automatically detect if they're inside a transaction and adapt their behavior. This makes the API extremely comfortable to use while maintaining full control when needed.

**Functions with `!`** (convenience, always transactional):
- ✅ Auto-transaction + return value directly
- ✅ Raise exception on error
- 👉 Best for single operations

```elixir
user = MyApp.Users.write!(%{id: 1, name: "Alice"})  
# Auto-transaction + returns value directly
```

**Functions without `!`** (smart, auto-detecting):
- ✅ **Standalone:** Creates transaction automatically
- ✅ **Inside `MnesiaEx.transaction`:** Uses existing transaction (no double-wrap)
- ✅ Return `{:ok, value} | {:error, reason}`
- 👉 Works everywhere, adapts automatically

```elixir
# Standalone - auto-transaction
{:ok, user} = MyApp.Users.write(%{id: 1, name: "Alice"})
# Internally creates a transaction automatically

# Inside manual transaction - no double-transaction
{:ok, {user, post}} = MnesiaEx.transaction(fn ->
  {:ok, user} = MyApp.Users.write(%{id: 1, name: "Alice"})  # Detects transaction → doesn't create another
  {:ok, post} = MyApp.Posts.write(%{user_id: user.id})      # Detects transaction → doesn't create another
  {user, post}  # Both succeed or both fail atomically
end)
```

**`dirty_*` functions** (fast, no ACID guarantees):
- ✅ No transaction overhead (10x faster)
- ✅ Return tuples
- ❌ No atomic guarantees
- 👉 Use when speed > consistency

```elixir
{:ok, user} = MyApp.Users.dirty_write(%{id: 1, name: "Alice"})
```

**`MnesiaEx.sync_transaction/1`** (distributed consistency):
- ✅ Waits for commit on ALL nodes
- ✅ Stronger consistency guarantees
- ❌ Higher latency
- 👉 Use for critical distributed operations

```elixir
{:ok, transfer} = MnesiaEx.sync_transaction(fn ->
  {:ok, _} = Accounts.update(from_id, %{balance: balance1 - amount})
  {:ok, _} = Accounts.update(to_id, %{balance: balance2 + amount})
  :transfer_complete
end)
```

### Why This Is Unique

Unlike other Mnesia wrappers, MnesiaEx's auto-transaction detection means:
- ✅ Functions work standalone (no manual transaction needed)
- ✅ Functions compose inside transactions (no double-wrapping)
- ✅ Best of both worlds: convenience + control
- ✅ You don't have to think about transactions unless composing

## Exploring the Documentation

All modules and functions include inline documentation. Use `h` in IEx to explore:

```elixir
# Start IEx
iex -S mix

# Get help on modules
iex> h MnesiaEx
iex> h MnesiaEx.Query
iex> h MnesiaEx.Table

# Get help on specific functions
iex> h MnesiaEx.Backup.backup/1
iex> h MnesiaEx.Counter.get_next_id/2
iex> h MnesiaEx.TTL.write/3
iex> h MnesiaEx.Query.select/3
iex> h MnesiaEx.Schema.create/1

# Get help on generated functions (after using MnesiaEx)
iex> h MyApp.Users.write/2
iex> h MyApp.Users.select/2
iex> h MyApp.Users.dirty_write/2
```

## Requirements

- Elixir `~> 1.15`
- Erlang/OTP `~> 25`

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Usage Guide](#usage-guide)
- [API Reference](#api-reference)
- [Performance Tips](#performance-tips)
- [Contributing](#contributing)
- [License](#license)

## Configuration

Configure MnesiaEx in your `config/config.exs`:

```elixir
config :mnesia_ex,
  # Directory paths
  backup_dir: "priv/backups",
  export_dir: "priv/exports",
  
  # System table names
  counter_table: :mnesia_counters,
  ttl_table: :mnesia_ttl,
  
  # TTL settings
  cleanup_interval: {5, :minutes},  # How often to clean expired records
  auto_cleanup: true,               # Enable automatic cleanup
  ttl_persistence: true             # Persist TTL table to disk
```

### Configuration Reference

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `backup_dir` | `String.t()` | `"priv/backups"` | Directory for backup files |
| `export_dir` | `String.t()` | `"priv/exports"` | Directory for exported files |
| `counter_table` | `atom()` | `:mnesia_counters` | System table for auto-increment |
| `ttl_table` | `atom()` | `:mnesia_ttl` | System table for TTL tracking |
| `cleanup_interval` | `tuple() \| integer()` | `{5, :minutes}` | TTL cleanup frequency |
| `auto_cleanup` | `boolean()` | `true` | Enable/disable automatic TTL cleanup |
| `ttl_persistence` | `boolean()` | `true` | Persist TTL data to disk |

## Usage Guide

### Schema Management

Before using Mnesia, you need to create a schema on disk. This is a one-time setup:

```elixir
# In production, do this during deployment setup
MnesiaEx.Schema.create([node()])

# For distributed setup
nodes = [:"node1@host", :"node2@host"]
MnesiaEx.Schema.create(nodes)

# Check if schema exists
MnesiaEx.Schema.exists?([node()])
# => true

# Get schema information
{:ok, info} = MnesiaEx.Schema.info()
# => %{
#   directory: "/var/mnesia/data",
#   nodes: [:"myapp@host"],
#   tables: [:users, :sessions],
#   version: "4.21.0",
#   running: true
# }

# Delete schema (careful!)
MnesiaEx.Schema.delete([node()])
```

> **Note:** Schema creation is typically done once during initial deployment or in `mix` tasks,
> not in your application startup code.

### Table-Scoped Modules

The recommended way to use MnesiaEx is through table-scoped modules. This gives you a clean, focused API:

```elixir
defmodule MyApp.Users do
  use MnesiaEx, table: :users

  def setup do
    create([
      attributes: [:id, :name, :email, :role],
      index: [:email],
      disc_copies: [node()]
    ])
  end

  # Add custom queries
  def admins do
    select([{:role, :==, :admin}])
  end

  def active_users do
    select([{:status, :==, :active}])
  end
end
```

**Available Functions:**

All standard CRUD operations are automatically injected:
- `write/2`, `write!/2` - Insert or update
- `read/1`, `read!/1` - Read by key
- `delete/1`, `delete!/1` - Delete by key
- `select/2` - Query with conditions (returns list directly)
- `update/3`, `update!/3` - Update attributes
- `list/0`, `list!/0` - Get all records
- `get_by/2`, `get_by!/2` - Find by field value
- And many more... (see [full API](#api-reference))

### Queries and Conditions

Build queries with conditions:

```elixir
# Simple condition
{:ok, adults} = MyApp.Users.select([{:age, :>, 18}])

# Multiple conditions (AND - implicit)
{:ok, active_adults} = MyApp.Users.select([
  {:age, :>=, 18},
  {:status, :==, :active}
])

# Find by specific field
{:ok, user} = MyApp.Users.get_by(:email, "alice@example.com")

# Get all records (returns list directly)
all_users = MyApp.Users.select([])

# Get all keys (lightweight, returns list directly)
keys = MyApp.Users.all_keys()
# => [1, 2, 3, 4, 5]
```

**Supported operators:**
- `:==` - Equal
- `:"/="` - Not equal
- `:>` - Greater than
- `:<` - Less than
- `:>=` - Greater than or equal
- `:<=` - Less than or equal

> **Note:** Multiple conditions in a list use AND logic implicitly.

### Basic Operations

```elixir
# Create
{:ok, user} = MyApp.Users.write(%{
  id: 1, 
  name: "Alice", 
  email: "alice@example.com"
})

# Read
{:ok, user} = MyApp.Users.read(1)

# Update
{:ok, updated_user} = MyApp.Users.update(1, %{name: "Alice Updated"})

# Delete
{:ok, deleted_user} = MyApp.Users.delete(1)

# Batch operations (return lists directly)
users = MyApp.Users.batch_write([
  %{id: 1, name: "Alice"},
  %{id: 2, name: "Bob"},
  %{id: 3, name: "Charlie"}
])

deleted_users = MyApp.Users.batch_delete([1, 2, 3])
```

### TTL (Time To Live)

Automatic record expiration for sessions, caches, and temporary data:

```elixir
defmodule MyApp.Sessions do
  use MnesiaEx, table: :sessions
end

# Write with automatic expiration
MyApp.Sessions.write_with_ttl(%{id: "abc123", data: "..."}, {1, :hour})

# Check remaining time
{:ok, ttl_ms} = MyApp.Sessions.get_remaining("abc123")

# TTL cleanup runs automatically in background
# Configure interval in config.exs
```

**Time units:** `:milliseconds`, `:seconds`, `:minutes`, `:hours`, `:days`, `:weeks`

### Auto-Increment Counters

Automatic ID generation for your records:

```elixir
defmodule MyApp.Orders do
  use MnesiaEx, table: :orders
end

# Get next ID
{:ok, next_id} = MyApp.Orders.get_next_id(:order_number)

{:ok, order} = MyApp.Orders.write(%{
  order_number: next_id,
  user_id: 123,
  total: 99.99
})

# Or let it auto-increment on write (if configured in table creation)
# Just omit the ID field and it will be assigned automatically
```

### Event Subscriptions

Monitor table changes in real-time:

```elixir
defmodule MyApp.UserMonitor do
  use GenServer
  alias MnesiaEx.Events

  def init(_) do
    {:ok, :subscribed} = MyApp.Users.subscribe()  # or subscribe(:detailed) for more info
    {:ok, %{}}
  end

  def handle_info(event, state) do
    case MyApp.Users.parse_event(event) do
      {:write, :users, record} ->
        IO.puts("User created/updated: #{inspect(record)}")
      
      {:delete, :users, id} ->
        IO.puts("User deleted: #{id}")
      
      _ ->
        :ok
    end
    
    {:noreply, state}
  end
end
```

### Backup & Restore

Easy database backup and migration:

```elixir
# Backup entire database
{:ok, file} = MnesiaEx.Backup.backup("backup.mnesia")

# Restore from backup
{:ok, _} = MnesiaEx.Backup.restore("backup.mnesia")

# Export table to JSON/CSV
{:ok, _} = MnesiaEx.Backup.export_table(:users, "users.json", :json)
{:ok, _} = MnesiaEx.Backup.export_table(:users, "users.csv", :csv)

# Import from file (format auto-detected by extension)
{:ok, :imported} = MnesiaEx.Backup.import_table(:users, "users.json")
```

### Distributed Tables

Run across multiple nodes with automatic replication:

```elixir
defmodule MyApp.Sessions do
  use MnesiaEx, table: :sessions

  def setup_distributed do
    create([
      attributes: [:id, :user_id, :data],
      disc_copies: [node() | Node.list()]  # All connected nodes
    ])
  end
end

# Add/remove nodes dynamically
{:ok, result} = MyApp.Sessions.add_table_copy(:"node2@host", :disc_copies)
{:ok, result} = MyApp.Sessions.remove_table_copy(:"node2@host")

# Check cluster status
MnesiaEx.system_info(:running_db_nodes)
# => [:"node1@host", :"node2@host"]

MnesiaEx.system_info(:tables)
# => [:users, :sessions, :schema]
```

### Schema Migrations

Transform table structure with data migration:

```elixir
# Add new field to existing table
transform_fn = fn {_table, id, name, email} ->
  # Old: {table, id, name, email}
  # New: {table, id, name, email, inserted_at}
  {_table, id, name, email, DateTime.utc_now()}
end

MyApp.Users.transform(
  [:id, :name, :email, :inserted_at],
  transform_fn
)
```

### Performance: Dirty Operations

When you need speed and can relax ACID guarantees:

```elixir
# Regular operations (transactional, slower)
MyApp.Users.write(%{id: 1, name: "Alice"})     # ~100μs
MyApp.Users.read(1)                            # ~80μs

# Dirty operations (no transaction, faster)
MyApp.Users.dirty_write(%{id: 1, name: "Alice"})  # ~10μs
MyApp.Users.dirty_read(1)                         # ~5μs

# Perfect for:
# - High-frequency counters
# - Real-time analytics
# - Cache writes
# - Non-critical data
```

## API Reference

> 💡 **Tip:** Use `h ModuleName.function/arity` in IEx to see detailed documentation for any function.
> Example: `h MnesiaEx.Query.select/3`

### Generated Functions (via `use MnesiaEx`)

**CRUD Operations:**
- `write/2`, `write!/2` - Create or update record
- `read/1`, `read!/1` - Read by primary key
- `update/3`, `update!/3` - Update specific fields
- `delete/1`, `delete!/1` - Delete record
- `upsert/1`, `upsert!/1` - Insert or update

**Queries:**
- `select/2` - Query with conditions (returns list)
- `get_by/2`, `get_by!/2` - Find by field value
- `all_keys/0` - Get all primary keys (returns list)

**Fast Operations (Dirty - No Transaction):**
- `dirty_write/2` - Fast write
- `dirty_read/1` - Fast read
- `dirty_update/3` - Fast update
- `dirty_delete/1` - Fast delete

> **Tip:** Use `select/0` without conditions to get all records.
> Dirty operations are faster but skip transaction overhead.

**Batch:**
- `batch_write/1` - Write multiple (returns list)
- `batch_delete/1` - Delete multiple (returns list)

**Table Management:**
- `create/1` - Create table
- `exists?/0` - Check if exists
- `drop/0` - Delete table
- `clear/0` - Remove all records
- `table_info/0` - Get metadata
- `add_index/1`, `remove_index/1` - Manage indexes
- `transform/2` - Migrate table structure
- `get_storage_type/0` - Get storage type

**TTL:**
- `write_with_ttl/2`, `write_with_ttl!/2` - Write with expiration
- `get_ttl/1`, `get_ttl!/1` - Get remaining time

**Counters:**
- `get_next_id/1`, `get_next_id!/1` - Get auto-increment ID
- `reset_counter/1`, `reset_counter/2` - Reset counter
- `has_counter?/1` - Check if counter exists

**Events:**
- `subscribe/0`, `subscribe/1` - Subscribe to changes
- `unsubscribe/0` - Unsubscribe
- `parse_event/1` - Parse Mnesia events

> **Note:** Functions with `!` run in transactions and raise on error.
> Functions without `!` return `{:ok, result}` or `{:error, reason}`.

## Performance Tips

| Tip | Description |
|-----|-------------|
| 🚀 **Batch Operations** | Use `batch_write` and `batch_delete` for bulk operations |
| ⚡ **Dirty Operations** | Use `dirty_*` functions when ACID isn't critical (10x faster) |
| 📇 **Indexes** | Only index fields you actually query on |
| 💾 **Storage Types** | Use `:ram_copies` for cache, `:disc_copies` for persistence |
| 🔄 **TTL** | Auto-cleanup temporary data instead of manual deletion |
| 📊 **Monitor** | Check memory usage with `table_info/0` |
| 🔑 **Keys Only** | Use `all_keys/0` instead of `select/0` when you only need IDs |
| 🌐 **Distribution** | Monitor cluster with `system_info(:running_db_nodes)` |

## Contributing

We welcome contributions! Here's how to help:

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/amazing`)
3. Make your changes following functional programming principles (pure functions, monads, no side effects)
4. Add tests (`mix test`)
5. Submit a PR

**Development Principles:**
- Pure functions only
- Monadic composition (use `Monad.Error`, `Monad.Maybe`)
- Pattern matching over conditionals
- Full typespecs
- Documented code

## License

MIT License - see [LICENSE](LICENSE) for details.

## Documentation

### Online Documentation
- 📖 **HexDocs:** [hexdocs.pm/mnesia_ex](https://hexdocs.pm/mnesia_ex)
- 📦 **Hex Package:** [hex.pm/packages/mnesia_ex](https://hex.pm/packages/mnesia_ex)

### Interactive Documentation (IEx)

Access documentation directly in your console:

```elixir
iex> h MnesiaEx.Query.select/3

                       def select(table, conditions \\ [], return_fields \\ [:"$_"])

  @spec select(atom(), [condition()], [atom() | :"$_"]) :: list(map())

Searches for records matching the specified conditions.

## Examples

    iex> MnesiaEx.Query.select(:users, [{:age, :>, 18}])
    [%{id: 1, name: "Alice", age: 25}, %{id: 2, name: "Bob", age: 30}]
```

### Support
- 🐛 **Issues:** [github.com/AR3ON/mnesia_ex/issues](https://github.com/AR3ON/mnesia_ex/issues)
