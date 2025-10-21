# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2025-10-21

### 🎯 Major Improvements to Counter System

This release focuses on making counters more robust and preventing ID collisions.

#### ✨ Added

- **Counter Auto-Adjust**: Automatic counter adjustment when manual ID is higher than current counter value
  - Prevents future collisions between manual and auto-generated IDs
  - Seamless integration with existing code
  - Works transparently in transactions

- **Duplicate Prevention**: Validation against duplicate IDs for fields with counters
  - Clear error messages: `{:id_already_exists, field, id}`
  - Only applies to fields declared in `counter_fields`
  - Tables without counters maintain original Mnesia behavior

- **Schema-Based Validation**: Counter features only activate for configured fields
  - Checks `:user_properties` in table schema
  - Backward compatible with tables created before this version

- **New API Function**: `get_counter_fields/1` for inspecting table counter configuration
  - Returns list of fields with auto-increment enabled
  - Available in `MnesiaEx.Table` and table modules
  - Useful for dynamic validation and debugging
  - Example: `MyApp.Posts.get_counter_fields()` → `[:id, :views]`

#### 🔧 Changed

- **Breaking**: `write()` with `counter_fields` now prevents ID overwrites
  - Use `update()` to modify existing records
  - Improves data safety and clarity
  - Separation: `write` = insert, `update` = modify

#### 📚 Documentation

- Enhanced `examples/03_counters.exs` with comprehensive demonstrations
  - Auto-generation examples (recommended pattern)
  - Manual ID pattern (advanced use cases)
  - Auto-adjust demonstrations
  - Duplicate prevention examples
  - Tables with/without counters comparison

- Improved `README.md` with best practices for versioned documentation
- Updated `examples/01_basic_crud.exs` and `examples/07_transactions.exs` corrections

#### 🧪 Testing

- Added comprehensive test suite for auto-adjust functionality
- Added tests for duplicate prevention
- Added tests for `get_counter_fields/1` function
- All tests follow functional programming principles (no `Enum.map`, pure recursion)

#### 🐛 Fixed

- Counter validation now checks schema configuration, not just counter table existence
- Removed redundant `*_in_transaction` functions (auto-detection works correctly)
- Fixed example scripts to use correct API signatures

### 🔄 Migration Guide

If you're upgrading from 0.1.0:

```elixir
# Before (0.1.0): Could overwrite with same ID
MyApp.Users.write(%{id: 1, name: "Updated"})

# After (0.2.0): Use update for modifications
MyApp.Users.update(1, %{name: "Updated"})

# Auto-generation still works the same
MyApp.Users.write(%{name: "Alice"})  # ✅ Same as before
```

Tables **without** `counter_fields` are not affected and work exactly as before.

## [0.1.0] - 2025-10-19

### 🎉 Initial Public Beta

First public beta release of MnesiaEx - a functional, monadic wrapper for Mnesia built with category theory principles.

**⚠️ Beta Status**: This is a beta release. API may change based on community feedback. Use with caution in production.

### ✨ Features

#### Core Functionality
- **Schema Management** - Create, delete, and manage Mnesia schemas across nodes
- **Table Operations** - Full CRUD operations with functional API
- **Query Builder** - Intuitive query interface with conditions and filters
- **Transactions** - Automatic transaction handling with `!` functions

#### Advanced Features
- **Auto-increment Counters** - Automatic ID generation for specified fields
- **TTL (Time To Live)** - Record expiration with automatic cleanup
- **Backup & Restore** - Full database backup with advanced restore options
- **Event System** - Real-time event subscriptions for table changes
- **Multi-format Export** - Export tables to JSON, CSV, or Erlang terms

#### Architecture
- **Pure Functional** - No side effects, all functions are pure
- **Monadic Composition** - Uses `Monad.Error`, `Monad.Maybe`, `Monad.List`
- **Category Theory** - Built following categorical principles
- **Type Safe** - Comprehensive `@spec` for all public functions
- **Zero Warnings** - Clean compilation with no warnings

### 📚 Documentation
- Comprehensive module documentation in English
- Extensive examples for all functions
- Professional README with quick start guide
- Architecture documentation
- Contributing guidelines

### 🧪 Testing
- Full test coverage for all modules
- Functional tests without mocks
- Integration tests for distributed scenarios
- All tests passing

### 🎯 Modules

#### MnesiaEx.Schema
- `create/1` - Create Mnesia schema
- `delete/1` - Delete Mnesia schema
- `info/0` - Get schema information

#### MnesiaEx.Table
- `create/2` - Create tables with rich options
- `drop/1` - Delete tables
- `clear/1` - Clear all records
- `info/1` - Get table information
- `exists?/1` - Check table existence
- `add_index/2` - Add index to field
- `remove_index/2` - Remove index
- `add_copy/3` - Add table copy to node
- `remove_copy/2` - Remove table copy
- `change_copy_type/3` - Change copy type
- `persist_schema/1` - Persist schema to disk

#### MnesiaEx.Query
- `write/3` & `write!/3` - Write records
- `read/2` & `read!/2` - Read by ID
- `delete/2` & `delete!/2` - Delete records
- `update/4` & `update!/4` - Update records
- `upsert/2` & `upsert!/2` - Insert or update
- `select/3` & `select!/3` - Query with conditions
- `get_by/3` & `get_by!/3` - Find by field
- `batch_write/2` & `batch_write!/2` - Batch insert
- `batch_delete/2` & `batch_delete!/2` - Batch delete

#### MnesiaEx.TTL
- `set/3` - Set TTL for record
- `clear/2` - Remove TTL
- `get_remaining/2` - Get remaining time
- `expired?/2` - Check if expired
- `cleanup_expired/0` - Manual cleanup
- `write/3` - Write with TTL
- Automatic background cleanup process

#### MnesiaEx.Backup
- `backup/2` - Create database backup
- `restore/3` - Restore from backup
- `export_table/3` - Export table to file
- `import_table/3` - Import table from file
- `list_exported_records/2` - List exported data

#### MnesiaEx.Counter
- `get_next_id/2` - Get next auto-increment ID
- `get_current_value/2` - Get current counter value
- `reset_counter/3` - Reset counter to value
- `has_counter?/2` - Check if counter exists
- `delete_counter/2` - Delete counter

#### MnesiaEx.Events
- `subscribe/2` - Subscribe to events
- `unsubscribe/1` - Unsubscribe from events
- `parse_event/1` - Parse Mnesia events to friendly format
- Support for system, activity, and table events
- Simple and detailed event modes

#### MnesiaEx.Utils
- `tuple_to_map/1` & `tuple_to_map/2` - Convert tuples to maps
- `map_to_tuple/1` & `map_to_tuple/2` - Convert maps to tuples
- `record_to_map/1` - Convert records to maps
- `table_exists?/1` - Check table existence
- `has_counter?/2` - Check counter field
- `validate_required_fields/2` - Validate record fields

#### MnesiaEx.Duration
- `to_milliseconds/1` - Convert duration to milliseconds
- `to_milliseconds!/1` - Convert with exception on error
- Support for multiple time units

#### MnesiaEx.Config
- `all/0` - Get all configuration
- `get/1` - Get specific configuration value

### 📦 Dependencies
- `jason ~> 1.4` - JSON encoding/decoding
- `csv ~> 3.0` - CSV parsing/generation

### 🔧 Technical Improvements
- **Code Simplification**: Reduced codebase by 297 lines
- **Function Optimization**: Eliminated 50+ unnecessary helper functions
- **Consistent Error Handling**: Standardized `Error.return()` and `Error.fail()`
- **No Imperative Constructs**: Zero `if`, `case`, `cond`, `try/rescue` statements
- **Pattern Matching**: Extensive use of guards and pattern matching
- **Monadic Composition**: All operations use `Error.m do` blocks

### 🐛 Bug Fixes
- Fixed circular dependency between Counter and Table modules
- Fixed nested transaction issues in Query operations
- Fixed Mnesia index handling (attribute names vs positions)
- Fixed counter field validation preventing index creation
- Corrected minimum attribute requirement (2+ fields)

### 📝 Breaking Changes
None - this is the initial release.

### 🔄 Migration Guide
Not applicable - initial release.

---

## Roadmap to v1.0.0

### v0.2.0 (Planned)
- API refinements based on community feedback
- Performance benchmarks and optimizations
- More examples and production guides
- Additional export/import formats

### v0.5.0 (Planned)
- Query DSL improvements
- Streaming API for large datasets
- Enhanced observability

### v0.9.0 (Planned - Release Candidate)
- API freeze
- Production hardening
- Full test coverage with property-based testing
- Security audit

### v1.0.0 (Future - Stable Release)
- Stable API with backward compatibility guarantee
- Battle-tested in production
- Complete documentation
- Enterprise support ready

---

[0.1.0]: https://github.com/AR3ON/mnesia_ex/releases/tag/v0.1.0
