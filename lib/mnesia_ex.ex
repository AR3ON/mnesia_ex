defmodule MnesiaEx do
  @moduledoc """
  Modern Elixir wrapper for Erlang/OTP's Mnesia database.

  MnesiaEx provides a clean, functional API for working with Mnesia, Erlang's
  distributed embedded database. Built with category theory principles and
  monadic composition, it offers automatic TTL, auto-increment counters,
  schema migrations, and JSON/CSV export.

  ## Why MnesiaEx?

  | Feature | Description |
  |---------|-------------|
  | 🎯 **Table-Scoped Modules** | No more passing table names everywhere |
  | ⏰ **Automatic TTL** | Records expire automatically |
  | 🔢 **Auto-Increment** | Built-in counter support |
  | 📦 **JSON/CSV Export** | Human-readable backups |
  | ⚡ **Dirty Operations** | 10x faster when ACID isn't critical |
  | 🔧 **Schema Migrations** | Transform tables with data |
  | 🧪 **Pure Functional** | All code follows category theory principles |

  ## Quick Example

      # Define your table
      defmodule MyApp.Users do
        use MnesiaEx, table: :users
      end

      # Use it
      MnesiaEx.start()

      # Bang functions return value directly (auto-transaction)
      user = MyApp.Users.write!(%{id: 1, name: "Alice"})
      user = MyApp.Users.read!(1)

      # Non-bang return tuples (composable)
      {:ok, user} = MyApp.Users.write(%{id: 2, name: "Bob"})
      {:error, :not_found} = MyApp.Users.read(999)

  ## Key Concepts

  ### Table-Scoped API

  The `use MnesiaEx, table: :table_name` macro injects all database functions
  scoped to your table. This eliminates repetition and creates a clean,
  domain-specific API:

      user = MyApp.Users.write!(%{name: "Alice"})    # vs MnesiaEx.Query.write!(:users, %{...})
      {:ok, users} = MyApp.Users.select([{:age, :>, 18}])  # vs MnesiaEx.Query.select(:users, [...])

  ### Smart Auto-Transaction Detection (Unique Feature)

  **MnesiaEx automatically detects if you're inside a transaction:**

      # Standalone - auto-creates transaction
      {:ok, user} = MyApp.Users.write(%{id: 1, name: "Alice"})

      # Inside transaction - no double-wrapping
      {:ok, {user, post}} = MnesiaEx.transaction(fn ->
        {:ok, user} = MyApp.Users.write(%{id: 1, name: "Alice"})  # Detects existing transaction
        {:ok, post} = MyApp.Posts.write(%{user_id: user.id})      # No double-transaction
        {user, post}
      end)

  ### API Convention

  **Bang functions (`!`)** - Always transactional, return value or raise:

      user = MyApp.Users.write!(%{id: 1, name: "Alice"})  # Returns map or raises
      user = MyApp.Users.read!(1)                         # Returns map or raises

  **Non-bang functions** - Smart auto-transaction, return tuples:

      # Works standalone (auto-transaction)
      {:ok, user} = MyApp.Users.write(%{id: 1, name: "Alice"})

      # Works inside transaction (detected, no double-wrap)
      {:ok, result} = MnesiaEx.transaction(fn ->
        {:ok, user} = MyApp.Users.write(%{id: 1, name: "Alice"})
        {:ok, post} = MyApp.Posts.write(%{user_id: user.id})
        {user, post}
      end)

      # Error handling
      {:error, :not_found} = MyApp.Users.read(999)

  ### Features

  #### TTL (Time To Live)
  Automatic record expiration with background cleanup:

      MyApp.Sessions.write_with_ttl(%{id: "abc"}, {1, :hour})

  #### Auto-Increment Counters
  Thread-safe, distributed ID generation:

      {:ok, id} = MyApp.Users.get_next_id(:id)

  #### Export/Import
  Backup to human-readable formats:

      MnesiaEx.Backup.export_table(:users, "users.json", :json)

  ## Modules

  MnesiaEx is organized into focused modules:

  - `MnesiaEx` - Core API and table-scoped macro
  - `MnesiaEx.Schema` - Schema management (create/delete/info)
  - `MnesiaEx.Table` - Table operations (create/drop/transform)
  - `MnesiaEx.Query` - CRUD and queries (write/read/select/etc)
  - `MnesiaEx.TTL` - Time-To-Live management (unique)
  - `MnesiaEx.Counter` - Auto-increment counters (unique)
  - `MnesiaEx.Events` - Event subscriptions
  - `MnesiaEx.Backup` - Backup and export (JSON/CSV)

  ## Learn More

  - See `README.md` for comprehensive guide
  - Use `h ModuleName.function/arity` in IEx for inline help
  - Check individual modules for specific functionality
  - Visit [hexdocs.pm/mnesia_ex](https://hexdocs.pm/mnesia_ex) for online docs

  ## Example Project

      # 1. Define tables
      defmodule MyApp.Users do
        use MnesiaEx, table: :users

        def setup do
          create([
            attributes: [:id, :name, :email, :role],
            index: [:email],
            disc_copies: [node()]
          ])
        end

        def admins, do: select([{:role, :==, :admin}])
      end

      # 2. Use in your application
      def init do
        MnesiaEx.start()
        MyApp.Users.setup()

        MyApp.Users.write(%{id: 1, name: "Alice", email: "alice@example.com", role: :admin})
        admins = MyApp.Users.admins()  # Returns list directly
      end

  ## Function Convention

  - **Functions returning a single value:**
    - Without `!`: Return `{:ok, result}` or `{:error, reason}`
    - With `!`: Return value directly or raise exception
  - **Functions returning lists** (`select`, `all_keys`, `batch_*`):
    - Return list directly (no `!` version needed, `[]` is valid)
  - **`dirty_*`** - Fast operations without transaction overhead
  - **All generated** - Fully `defoverridable` for customization
  """

  @doc """
  Starts the Mnesia application.

  This function should be called before any Mnesia operations.
  It's typically called in your application's start/2 callback.

  ## Returns

    - `:ok` - Mnesia started successfully
    - `{:error, reason}` - Failed to start Mnesia

  ## Examples

      iex> MnesiaEx.start()
      :ok

      # In your application.ex
      def start(_type, _args) do
        MnesiaEx.start()
        # ...
      end
  """
  @spec start() :: :ok | {:error, term()}
  def start, do: :mnesia.start()

  @doc """
  Stops the Mnesia application.

  Gracefully shuts down Mnesia. All tables will be closed and
  data will be persisted to disk.

  ## Returns

    - `:stopped` - Mnesia stopped successfully
    - `{:error, reason}` - Failed to stop Mnesia

  ## Examples

      iex> MnesiaEx.stop()
      :stopped
  """
  @spec stop() :: :stopped | {:error, term()}
  def stop, do: :mnesia.stop()

  @doc """
  Runs the given function inside a Mnesia transaction.

  Similar to `Repo.transaction/1` in Ecto, this function executes
  the given anonymous function inside a Mnesia transaction. All
  operations inside the function are atomic - they all succeed or
  all fail together.

  ## Returns

    - `{:ok, result}` - Transaction committed successfully
    - `{:error, reason}` - Transaction aborted

  ## Examples

      # Simple transaction
      {:ok, users} = MnesiaEx.transaction(fn ->
        user1 = MyApp.Users.write(%{id: 1, name: "Alice"})
        user2 = MyApp.Users.write(%{id: 2, name: "Bob"})
        [user1, user2]
      end)

      # Transaction with error handling
      case MnesiaEx.transaction(fn ->
        user = MyApp.Users.read(1)
        MyApp.Posts.write(%{user_id: user.id, title: "Post"})
      end) do
        {:ok, post} -> IO.puts("Success!")
        {:error, reason} -> IO.puts("Failed: \#{inspect(reason)}")
      end

      # Composing multiple operations
      MnesiaEx.transaction(fn ->
        user = MyApp.Users.write(%{id: 1, name: "Alice"})
        MyApp.Posts.write(%{user_id: user.id, title: "First Post"})
        MyApp.Comments.write(%{post_id: 1, content: "Great!"})
      end)

  ## Important Notes

  - Use non-bang versions of functions inside transactions (e.g., `write/2` instead of `write!/2`)
  - Bang versions (`write!/2`) already wrap in transactions, don't nest them
  - If any operation returns `{:error, reason}`, the transaction aborts
  - All changes are rolled back on abort
  """
  @spec transaction((-> term())) :: {:ok, term()} | {:error, term()}
  def transaction(fun) when is_function(fun, 0) do
    :mnesia.transaction(fun)
    |> transform_mnesia_transaction_result()
  end

  @doc """
  Runs the given function inside a synchronous Mnesia transaction.

  Similar to `transaction/1` but waits for the transaction to be committed
  on all nodes before returning. This ensures stronger consistency guarantees
  in distributed environments at the cost of slightly higher latency.

  ## Returns

    - `{:ok, result}` - Transaction committed successfully on all nodes
    - `{:error, reason}` - Transaction aborted

  ## Examples

      # Synchronous transaction (waits for all nodes)
      {:ok, user} = MnesiaEx.sync_transaction(fn ->
        MyApp.Users.write(%{id: 1, name: "Alice"})
      end)

      # Critical operations that need strong consistency
      {:ok, _} = MnesiaEx.sync_transaction(fn ->
        {:ok, balance} = MyApp.Accounts.read(account_id)
        MyApp.Accounts.update(account_id, %{balance: balance - amount})
      end)

  ## When to Use

  - **Use `sync_transaction`** for critical operations requiring strong consistency
  - **Use `transaction`** for most operations (faster, async commit)
  - In single-node setups, both behave identically
  """
  @spec sync_transaction((-> term())) :: {:ok, term()} | {:error, term()}
  def sync_transaction(fun) when is_function(fun, 0) do
    :mnesia.sync_transaction(fun)
    |> transform_mnesia_transaction_result()
  end

  defp transform_mnesia_transaction_result({:atomic, result}), do: {:ok, result}
  defp transform_mnesia_transaction_result({:aborted, reason}), do: {:error, reason}

  @doc """
  Waits for all tables to be ready for use.

  This function waits for all Mnesia tables to be loaded and accessible.
  Useful during application startup to ensure tables are ready before
  accepting requests.

  ## Parameters

    - `timeout` - Maximum time to wait in milliseconds (default: 5000)

  ## Returns

    - `:ok` - All tables are ready
    - `{:timeout, bad_tables}` - Timeout reached, some tables not ready
    - `{:error, reason}` - An error occurred

  ## Examples

      # Wait with default timeout (5 seconds)
      iex> MnesiaEx.wait_for_tables()
      :ok

      # Wait with custom timeout (10 seconds)
      iex> MnesiaEx.wait_for_tables(10_000)
      :ok

      # Handle timeout
      case MnesiaEx.wait_for_tables(5000) do
        :ok -> :ready
        {:timeout, tables} -> Logger.warning("Tables not ready: \#{inspect(tables)}")
      end
  """
  @spec wait_for_tables(timeout :: pos_integer()) :: :ok | {:timeout, [atom()]} | {:error, term()}
  def wait_for_tables(timeout \\ 5000) do
    :mnesia.system_info(:tables)
    |> :mnesia.wait_for_tables(timeout)
  end

  @doc """
  Gets Mnesia system information.

  Provides access to various Mnesia system metrics and configuration.

  ## Parameters

    - `key` - The information key to retrieve

  ## Common Keys

    - `:db_nodes` - All nodes with schema
    - `:running_db_nodes` - Currently running nodes
    - `:tables` - All tables in database
    - `:local_tables` - Tables on current node
    - `:is_running` - Mnesia running status (`:yes`, `:no`, `:stopping`)
    - `:directory` - Mnesia data directory
    - `:version` - Mnesia version
    - `:db_nodes` - Database nodes
    - `:extra_db_nodes` - Extra database nodes

  ## Examples

      iex> MnesiaEx.system_info(:tables)
      [:users, :sessions, :schema]

      iex> MnesiaEx.system_info(:running_db_nodes)
      [:"node1@host", :"node2@host"]

      iex> MnesiaEx.system_info(:is_running)
      :yes

      iex> MnesiaEx.system_info(:directory)
      '/var/lib/mnesia/myapp@host'
  """
  @spec system_info(atom()) :: term()
  def system_info(key) when is_atom(key) do
    :mnesia.system_info(key)
  end

  @doc """
  Injects MnesiaEx functionality into a module for a specific table.

  When you `use MnesiaEx`, it generates table-scoped versions of all
  MnesiaEx functions, eliminating the need to specify the table name
  on every call. All generated functions are `defoverridable`, allowing
  you to customize behavior as needed.

  ## Options

    - `:table` - (required) The atom name of the Mnesia table this module manages

  ## Generated Functions

  The macro injects the following categories of functions:

  ### Query Operations
  - `write/2`, `write!/2` - Insert or update records
  - `read/1`, `read!/1` - Read record by key
  - `delete/1`, `delete!/1` - Delete record by key or fields
  - `select/2` - Query with conditions (returns `{:ok, [records]}`)
  - `get_by/2`, `get_by!/2` - Find by specific field
  - `list/0`, `list!/0` - Get all records
  - `update/3`, `update!/3` - Update record attributes
  - `upsert/1`, `upsert!/1` - Insert or update record
  - `batch_write/1` - Write multiple records (returns `{:ok, [records]}`)
  - `batch_delete/1` - Delete multiple records (returns `{:ok, [records]}`)

  ### Table Management
  - `create/1`, `create!/1` - Create table with options
  - `exists?/0` - Check if table exists
  - `table_info/0`, `info!/0` - Get table metadata
  - `drop/0`, `drop!/0` - Delete table
  - `clear/0`, `clear!/0` - Remove all records
  - `add_index/1`, `add_index!/1` - Add secondary index
  - `remove_index/1`, `remove_index!/1` - Remove secondary index
  - `transform/2`, `transform!/2` - Migrate table schema

  ### Distribution
  - `add_table_copy/2`, `add_table_copy!/2` - Add table replica to node
  - `remove_table_copy/1`, `remove_table_copy!/1` - Remove table replica from node
  - `change_table_copy_type/2`, `change_table_copy_type!/2` - Change replica storage type

  ### TTL (Time To Live)
  - `write_with_ttl/2`, `write_with_ttl!/2` - Write with expiration
  - `get_ttl/1`, `get_ttl!/1` - Get remaining TTL
  - `set/2`, `set!/2` - Set TTL for existing record
  - `clear/1`, `clear!/1` - Remove TTL from record
  - `get_remaining/1`, `get_remaining!/1` - Get remaining time

  ### Counters
  - `get_next_id/1`, `get_next_id!/1` - Get auto-increment ID
  - `get_current_value/1`, `get_current_value!/1` - Get counter value
  - `reset_counter/1`, `reset_counter/2` - Reset counter to value
  - `reset_counter!/1`, `reset_counter!/2` - Reset counter (transactional)
  - `has_counter?/1` - Check if counter exists

  ### Events
  - `subscribe/0`, `subscribe/1`, `subscribe!/0`, `subscribe!/1` - Subscribe to table events
  - `unsubscribe/0`, `unsubscribe!/0` - Unsubscribe from events
  - `parse_event/1` - Parse raw Mnesia events

  ## Examples

      defmodule MyApp.Users do
        use MnesiaEx, table: :users

        @doc "Create the users table with schema"
        def setup do
          create([
            attributes: [:id, :name, :email, :inserted_at],
            index: [:email],
            disc_copies: [node()]
          ])
        end

        @doc "Custom query for active users"
        def active_users do
          select([{:active, :==, true}])
        end

        # Override generated function with custom logic
        def write(attrs, opts \\\\ []) do
          attrs
          |> Map.put(:inserted_at, DateTime.utc_now())
          |> then(&Query.write(@table, &1, opts))
        end
      end

      # Using the module
      MyApp.Users.setup()
      MyApp.Users.write(%{id: 1, name: "Alice", email: "alice@example.com"})
      {:ok, user} = MyApp.Users.read(1)
      {:ok, users} = MyApp.Users.active_users()
  """
  defmacro __using__(opts) do
    table = Keyword.get(opts, :table)

    quote do
      import MnesiaEx
      alias MnesiaEx.{Query, Table, TTL, Counter, Events}

      @table unquote(table)

      if !@table do
        raise "Table option is required when using MnesiaEx"
      end

      # Event functions
      @doc """
      Subscribes the current process to table events.

      ## Event types
        * `:simple` - Basic events (default)
        * `:detailed` - Detailed events with additional information

      ## Examples

          # Subscribe to simple events
          subscribe()

          # Subscribe to detailed events
          subscribe(:detailed)
      """
      @spec subscribe(Events.event_type()) :: {:ok, :subscribed} | {:error, term()}
      def subscribe(event_type \\ :simple) do
        Events.subscribe(@table, event_type)
      end

      @doc """
      Subscribes to table events (raises on error).

      ## Examples

          subscribe!()
          subscribe!(:detailed)
      """
      @spec subscribe!(Events.event_type()) :: :subscribed | no_return()
      def subscribe!(event_type \\ :simple) do
        Events.subscribe!(@table, event_type)
      end

      @doc """
      Unsubscribes the current process from table events.

      ## Examples

          {:ok, :unsubscribed} = unsubscribe()
      """
      @spec unsubscribe() :: {:ok, :unsubscribed} | {:error, term()}
      def unsubscribe do
        Events.unsubscribe(@table)
      end

      @doc """
      Unsubscribes the current process from table events (raises on error).

      ## Examples

          unsubscribe!()
      """
      @spec unsubscribe!() :: :unsubscribed | no_return()
      def unsubscribe! do
        Events.unsubscribe!(@table)
      end

      @doc """
      Parses a Mnesia event into a friendlier format.

      ## Examples

          # Write event
          parse_event({:mnesia_table_event, {:write, :users, record, _}})
          # => {:write, :users, %{id: 1, name: "John"}}

          # Delete event
          parse_event({:mnesia_table_event, {:delete, :users, record, _}})
          # => {:delete, :users, 1}
      """
      def parse_event(event) do
        Events.parse_event(event)
      end

      # Query functions - with transaction
      @doc "See `MnesiaEx.Query.write!/3`"
      def write!(attrs, opts \\ []), do: Query.write!(@table, attrs, opts)

      @doc "See `MnesiaEx.Query.read!/2`"
      def read!(key), do: Query.read!(@table, key)

      @doc "See `MnesiaEx.Query.delete!/2`"
      def delete!(key), do: Query.delete!(@table, key)

      @doc "See `MnesiaEx.Query.get_by!/3`"
      def get_by!(field, value), do: Query.get_by!(@table, field, value)

      @doc "See `MnesiaEx.Query.upsert!/2`"
      def upsert!(record), do: Query.upsert!(@table, record)

      @doc "See `MnesiaEx.Query.update!/4`"
      def update!(id, attrs, opts \\ []), do: Query.update!(@table, id, attrs, opts)

      # Query functions - without transaction
      @doc "See `MnesiaEx.Query.write/3`"
      def write(attrs, opts \\ []), do: Query.write(@table, attrs, opts)

      @doc "See `MnesiaEx.Query.read/2`"
      def read(key), do: Query.read(@table, key)

      @doc "See `MnesiaEx.Query.delete/2`"
      def delete(id_or_fields), do: Query.delete(@table, id_or_fields)

      @doc "See `MnesiaEx.Query.select/3`"
      def select(conditions \\ [], return_fields \\ [:"$_"]),
        do: Query.select(@table, conditions, return_fields)

      @doc "See `MnesiaEx.Query.get_by/3`"
      def get_by(field, value), do: Query.get_by(@table, field, value)

      @doc "See `MnesiaEx.Query.upsert/2`"
      def upsert(record), do: Query.upsert(@table, record)

      @doc "See `MnesiaEx.Query.batch_write/2`"
      def batch_write(records), do: Query.batch_write(@table, records)

      @doc "See `MnesiaEx.Query.batch_delete/2`"
      def batch_delete(records), do: Query.batch_delete(@table, records)

      @doc "See `MnesiaEx.Query.update/4`"
      def update(id, attrs, opts \\ []), do: Query.update(@table, id, attrs, opts)

      @doc "See `MnesiaEx.Query.all_keys/1`"
      def all_keys(), do: Query.all_keys(@table)

      # Dirty operations (fast, non-transactional)
      @doc "See `MnesiaEx.Query.dirty_write/3`"
      def dirty_write(attrs, opts \\ []), do: Query.dirty_write(@table, attrs, opts)

      @doc "See `MnesiaEx.Query.dirty_read/2`"
      def dirty_read(key), do: Query.dirty_read(@table, key)

      @doc "See `MnesiaEx.Query.dirty_delete/2`"
      def dirty_delete(key), do: Query.dirty_delete(@table, key)

      @doc "See `MnesiaEx.Query.dirty_update/4`"
      def dirty_update(id, attrs, opts \\ []), do: Query.dirty_update(@table, id, attrs, opts)

      # Table functions
      @doc "See `MnesiaEx.Table.create/2`"
      def create(opts \\ []), do: Table.create(@table, opts)

      @doc "See `MnesiaEx.Table.create!/2`"
      def create!(opts \\ []), do: Table.create!(@table, opts)

      @doc "See `MnesiaEx.Table.exists?/1`"
      def exists?, do: Table.exists?(@table)

      @doc "See `MnesiaEx.Table.info/1`"
      def table_info, do: Table.info(@table)

      @doc "See `MnesiaEx.Table.info!/1`"
      def info!, do: Table.info!(@table)

      @doc "See `MnesiaEx.Table.drop/1`"
      def drop, do: Table.drop(@table)

      @doc "See `MnesiaEx.Table.drop!/1`"
      def drop!, do: Table.drop!(@table)

      @doc "See `MnesiaEx.Table.clear/1`"
      def clear, do: Table.clear(@table)

      @doc "See `MnesiaEx.Table.clear!/1`"
      def clear!, do: Table.clear!(@table)
      @doc "See `MnesiaEx.Table.add_copy/3`"
      def add_table_copy(node, type), do: Table.add_copy(@table, node, type)

      @doc "See `MnesiaEx.Table.add_copy!/3`"
      def add_table_copy!(node, type), do: Table.add_copy!(@table, node, type)

      @doc "See `MnesiaEx.Table.remove_copy/2`"
      def remove_table_copy(node), do: Table.remove_copy(@table, node)

      @doc "See `MnesiaEx.Table.remove_copy!/2`"
      def remove_table_copy!(node), do: Table.remove_copy!(@table, node)

      @doc "See `MnesiaEx.Table.change_copy_type/3`"
      def change_table_copy_type(node, type), do: Table.change_copy_type(@table, node, type)

      @doc "See `MnesiaEx.Table.change_copy_type!/3`"
      def change_table_copy_type!(node, type), do: Table.change_copy_type!(@table, node, type)

      @doc "See `MnesiaEx.Table.add_index/2`"
      def add_index(field), do: Table.add_index(@table, field)

      @doc "See `MnesiaEx.Table.add_index!/2`"
      def add_index!(field), do: Table.add_index!(@table, field)

      @doc "See `MnesiaEx.Table.remove_index/2`"
      def remove_index(field), do: Table.remove_index(@table, field)

      @doc "See `MnesiaEx.Table.remove_index!/2`"
      def remove_index!(field), do: Table.remove_index!(@table, field)

      @doc "See `MnesiaEx.Table.get_storage_type/1`"
      def get_storage_type, do: Table.get_storage_type(@table)

      @doc "See `MnesiaEx.Table.transform/3`"
      def transform(new_attributes, transform_fun), do: Table.transform(@table, new_attributes, transform_fun)

      @doc "See `MnesiaEx.Table.transform!/3`"
      def transform!(new_attributes, transform_fun), do: Table.transform!(@table, new_attributes, transform_fun)

      # TTL functions
      @doc "See `MnesiaEx.TTL.write!/3`"
      def write_with_ttl!(record, ttl), do: TTL.write!(@table, record, ttl)

      @doc "See `MnesiaEx.TTL.get!/2`"
      def get_ttl!(key), do: TTL.get!(@table, key)

      @doc "See `MnesiaEx.TTL.write/3`"
      def write_with_ttl(record, ttl), do: TTL.write(@table, record, ttl)

      @doc "See `MnesiaEx.TTL.get/2`"
      def get_ttl(key), do: TTL.get(@table, key)

      @doc "See `MnesiaEx.TTL.set!/3`"
      def set_ttl!(key, ttl), do: TTL.set!(@table, key, ttl)

      @doc "See `MnesiaEx.TTL.set/3`"
      def set_ttl(key, ttl), do: TTL.set(@table, key, ttl)

      @doc "See `MnesiaEx.TTL.clear!/2`"
      def clear_ttl!(key), do: TTL.clear!(@table, key)

      @doc "See `MnesiaEx.TTL.clear/2`"
      def clear_ttl(key), do: TTL.clear(@table, key)

      @doc "See `MnesiaEx.TTL.get_remaining!/2`"
      def get_remaining!(key), do: TTL.get_remaining!(@table, key)

      @doc "See `MnesiaEx.TTL.get_remaining/2`"
      def get_remaining(key), do: TTL.get_remaining(@table, key)

      # Counter functions
      @doc "See `MnesiaEx.Counter.get_next_id!/2`"
      def get_next_id!(field), do: Counter.get_next_id!(@table, field)

      @doc "See `MnesiaEx.Counter.get_next_id/2`"
      def get_next_id(field), do: Counter.get_next_id(@table, field)

      @doc "See `MnesiaEx.Counter.get_current_value!/2`"
      def get_current_value!(field), do: Counter.get_current_value!(@table, field)

      @doc "See `MnesiaEx.Counter.get_current_value/2`"
      def get_current_value(field), do: Counter.get_current_value(@table, field)

      # Definir explícitamente las funciones reset_counter con 1 y 2 argumentos
      @doc "See `MnesiaEx.Counter.reset_counter/3`"
      def reset_counter(field), do: Counter.reset_counter(@table, field, 1)

      @doc "See `MnesiaEx.Counter.reset_counter/3`"
      def reset_counter(field, value), do: Counter.reset_counter(@table, field, value)

      # Definir explícitamente las funciones reset_counter! con 1 y 2 argumentos
      @doc "See `MnesiaEx.Counter.reset_counter!/3`"
      def reset_counter!(field), do: Counter.reset_counter!(@table, field, 1)

      @doc "See `MnesiaEx.Counter.reset_counter!/3`"
      def reset_counter!(field, value), do: Counter.reset_counter!(@table, field, value)

      @doc "See `MnesiaEx.Counter.has_counter?/2`"
      def has_counter?(field), do: Counter.has_counter?(@table, field)

      # Allow overriding any function
      defoverridable [
        # Event functions
        subscribe: 1,
        subscribe!: 1,
        unsubscribe: 0,
        unsubscribe!: 0,
        parse_event: 1,

        # Query functions with transaction
        write!: 1,
        write!: 2,
        read!: 1,
        delete!: 1,
        get_by!: 2,
        upsert!: 1,
        update!: 2,
        update!: 3,

        # Query functions without transaction
        write: 1,
        write: 2,
        read: 1,
        delete: 1,
        select: 0,
        select: 1,
        select: 2,
        get_by: 2,
        upsert: 1,
        batch_write: 1,
        batch_delete: 1,
        update: 2,
        update: 3,
        all_keys: 0,

        # Dirty operations
        dirty_write: 1,
        dirty_write: 2,
        dirty_read: 1,
        dirty_delete: 1,
        dirty_update: 2,
        dirty_update: 3,

        # Table functions
        create: 0,
        create: 1,
        create!: 0,
        create!: 1,
        exists?: 0,
        table_info: 0,
        info!: 0,
        drop: 0,
        drop!: 0,
        clear: 0,
        clear!: 0,
        add_table_copy: 2,
        add_table_copy!: 2,
        remove_table_copy: 1,
        remove_table_copy!: 1,
        change_table_copy_type: 2,
        change_table_copy_type!: 2,
        add_index: 1,
        add_index!: 1,
        remove_index: 1,
        remove_index!: 1,
        get_storage_type: 0,
        transform: 2,
        transform!: 2,

        # TTL functions
        write_with_ttl!: 2,
        write_with_ttl: 2,
        get_ttl!: 1,
        get_ttl: 1,
        set_ttl!: 2,
        set_ttl: 2,
        clear_ttl!: 1,
        clear_ttl: 1,
        get_remaining!: 1,
        get_remaining: 1,

        # Counter functions
        get_next_id: 1,
        get_next_id!: 1,
        get_current_value: 1,
        get_current_value!: 1,
        has_counter?: 1,
        reset_counter: 1,
        reset_counter: 2,
        reset_counter!: 1,
        reset_counter!: 2
      ]
    end
  end

end
