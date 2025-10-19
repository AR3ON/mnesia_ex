defmodule MnesiaEx.TTL do
  @moduledoc """
  Automatic record expiration with Time-To-Live (TTL) support.

  This module provides automatic record expiration, perfect for:
  - Session storage
  - Cache implementations
  - Temporary data
  - Rate limiting buckets
  - Token expiration

  ## How It Works

  1. Write records with TTL
  2. Background worker automatically cleans expired records
  3. Zero manual cleanup required

  ## Quick Start

      # Write with 1 hour expiration
      MnesiaEx.TTL.write(:sessions, %{id: "abc", data: "..."}, {1, :hour})

      # Check remaining time
      {:ok, milliseconds} = MnesiaEx.TTL.get_ttl(:sessions, "abc")

      # Records auto-delete when expired ✨

  ## Configuration

  Configure in `config/config.exs`:

      config :mnesia_ex,
        cleanup_interval: {5, :minutes},  # How often to clean
        auto_cleanup: true,               # Enable auto-cleanup
        ttl_table: :mnesia_ttl,          # System table name
        ttl_persistence: true             # Persist to disk

  ## Supported Time Units

  Accepts both singular and plural forms:
  - `:millisecond` / `:milliseconds`
  - `:second` / `:seconds`
  - `:minute` / `:minutes`
  - `:hour` / `:hours`
  - `:day` / `:days`
  - `:week` / `:weeks`
  - `:month` / `:months`
  - `:year` / `:years`
  - Or raw integer (milliseconds)

  ## Examples

      # Session that expires in 1 hour
      MnesiaEx.TTL.write(:sessions, %{id: "user_123", token: "..."}, {1, :hour})

      # Cache that expires in 5 minutes
      MnesiaEx.TTL.write(:cache, %{key: "data", value: 42}, {5, :minutes})

      # Check if expired
      MnesiaEx.TTL.expired?(:sessions, "user_123")
      # => false

      # Manual cleanup (auto-cleanup runs in background)
      MnesiaEx.TTL.cleanup_expired()
  """

  use GenServer
  require MnesiaEx.Monad, as: Error
  alias MnesiaEx.{Config, Query, Table, Duration}

  @type table :: atom()
  @type key :: term()
  @type ttl :: integer() | {integer(), Duration.time_unit()}
  @type result :: {:ok, term()} | {:error, term()}

  @ttl_table :mnesia_ttl

  # API Pública

  @doc """
  Starts the TTL service.

  ## Examples

      iex> MnesiaEx.TTL.start_link()
      {:ok, pid}
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Checks if the TTL process is running.
  """
  def running? do
    __MODULE__
    |> Process.whereis()
    |> check_process_alive()
  end

  @doc """
  Stops the TTL process if it's running.
  """
  def stop do
    __MODULE__
    |> Process.whereis()
    |> stop_process_if_alive()
  end

  defp stop_process_if_alive(nil), do: :ok

  defp stop_process_if_alive(pid) do
    Process.exit(pid, :normal)
    :ok
  end

  @doc """
  Sets a TTL for a specific record.

  ## Examples

      iex> MnesiaEx.TTL.set(:users, 1, {1, :hour})
      {:ok, :ok}

      iex> MnesiaEx.TTL.set(:users, 1, 3600000)
      {:ok, :ok}
  """
  @spec set(table(), key(), ttl()) :: result()
  def set(table, key, ttl) do
    Error.m do
      milliseconds <- Duration.to_milliseconds(ttl)
      expiry <- safe_calculate_expiry(milliseconds)
      _ <- ensure_ttl_table([])
      _ <- safe_write_ttl_record(table, key, expiry)
      Error.return(:ok)
    end
  end

  defp safe_write_ttl_record(table, key, expiry) do
    Query.write(@ttl_table, build_ttl_record(table, key, expiry))
  end

  @doc """
  Sets a TTL for a specific record (raises on error).

  ## Examples

      iex> MnesiaEx.TTL.set!(:users, 1, {1, :hour})
      :ok

  """
  @spec set!(table(), key(), ttl()) :: :ok | no_return()
  def set!(table, key, ttl) do
    set(table, key, ttl)
    |> unwrap_or_raise("Failed to set TTL")
  end

  @doc """
  Removes the TTL from a specific record.

  ## Examples

      iex> MnesiaEx.TTL.clear(:users, 1)
      {:ok, :ok}
  """
  @spec clear(table(), key()) :: result()
  def clear(table, key) do
    Error.m do
      _ <- ensure_ttl_table([])
      ttl_id <- safe_build_ttl_id(table, key)
      _ <- Query.delete(@ttl_table, ttl_id)
      Error.return(:ok)
    end
  end

  @doc """
  Removes the TTL from a specific record (raises on error).

  ## Examples

      iex> MnesiaEx.TTL.clear!(:users, 1)
      :ok
  """
  @spec clear!(table(), key()) :: :ok | no_return()
  def clear!(table, key) do
    clear(table, key)
    |> unwrap_or_raise("Failed to clear TTL")
  end

  @doc """
  Gets the remaining time for a specific record.

  ## Examples

      iex> MnesiaEx.TTL.get_remaining(:users, 1)
      {:ok, 3540000}  # remaining milliseconds
  """
  @spec get_remaining(table(), key()) :: {:ok, integer()} | {:error, term()}
  def get_remaining(table, key) do
    Error.m do
      _ <- ensure_ttl_table([])
      ttl_id <- safe_build_ttl_id(table, key)
      record <- safe_read_ttl_record(ttl_id)
      calculate_remaining_time(record.expires_at)
    end
  end

  defp safe_read_ttl_record(ttl_id) do
    Query.read(@ttl_table, ttl_id)
  end

  @doc """
  Gets the remaining time for a specific record (raises on error).

  ## Examples

      iex> MnesiaEx.TTL.get_remaining!(:users, 1)
      3540000  # remaining milliseconds
  """
  @spec get_remaining!(table(), key()) :: integer() | no_return()
  def get_remaining!(table, key) do
    get_remaining(table, key)
    |> unwrap_or_raise("Failed to get remaining time")
  end

  @doc """
  Checks if a record has expired.

  ## Examples

      iex> MnesiaEx.TTL.expired?(:users, 1)
      false
  """
  @spec expired?(table(), key()) :: boolean()
  def expired?(table, key) do
    table
    |> get_remaining(key)
    |> transform_to_expired_status()
  end

  @doc """
  Lists all records with TTL (across all tables).

  Returns a list with table, key, and expiry information.

  ## Examples

      iex> MnesiaEx.TTL.list_all()
      [
        %{table: :session, key: "sid_123", expires_at: 1234567890, remaining_ms: 3600000},
        %{table: :users, key: 42, expires_at: 1234567900, remaining_ms: 7200000}
      ]
  """
  @spec list_all() :: [map()]
  def list_all do
    ensure_ttl_table([])
    |> safe_list_all_ttls()
  end

  defp safe_list_all_ttls({:ok, _}) do
    Query.select(@ttl_table, [])
    |> transform_ttl_records_direct()
  end

  defp safe_list_all_ttls({:error, _}), do: []

  @doc """
  Lists all records with TTL for a specific table.

  Returns a list with key and expiry information.

  ## Examples

      iex> MnesiaEx.TTL.list_by_table(:session)
      [
        %{key: "sid_123", expires_at: 1234567890, remaining_ms: 3600000},
        %{key: "sid_456", expires_at: 1234567900, remaining_ms: 7200000}
      ]
  """
  @spec list_by_table(table()) :: [map()]
  def list_by_table(table) do
    ensure_ttl_table([])
    |> safe_list_ttls_by_table(table)
  end

  defp safe_list_ttls_by_table({:ok, _}, table) do
    Query.select(@ttl_table, [{:table, :==, table}])
    |> transform_ttl_records_direct()
  end

  defp safe_list_ttls_by_table({:error, _}, _table), do: []

  @doc """
  Lists only active (non-expired) records with TTL.

  Returns a list with only non-expired records.

  ## Examples

      iex> MnesiaEx.TTL.list_active()
      [
        %{table: :session, key: "sid_123", expires_at: 1234567890, remaining_ms: 3600000}
      ]
  """
  @spec list_active() :: [map()]
  def list_active do
    now = :os.system_time(:millisecond)

    ensure_ttl_table([])
    |> safe_list_active_ttls(now)
  end

  defp safe_list_active_ttls({:ok, _}, now) do
    Query.select(@ttl_table, [{:expires_at, :>, now}])
    |> transform_ttl_records_direct()
  end

  defp safe_list_active_ttls({:error, _}, _now), do: []

  @doc """
  Lists only active (non-expired) records with TTL for a specific table.

  Returns a list with only non-expired records for the table.

  ## Examples

      iex> MnesiaEx.TTL.list_active_by_table(:session)
      [%{key: "sid_123", expires_at: 1234567890, remaining_ms: 3600000}]
  """
  @spec list_active_by_table(table()) :: [map()]
  def list_active_by_table(table) do
    list_by_table(table)
    |> filter_active_records()
  end

  @doc """
  Counts how many records have TTL activated.

  ## Examples

      iex> MnesiaEx.TTL.count_all()
      5
  """
  @spec count_all() :: integer()
  def count_all do
    list_all()
    |> length()
  end

  @doc """
  Counts how many active (non-expired) records have TTL.

  ## Examples

      iex> MnesiaEx.TTL.count_active()
      3
  """
  @spec count_active() :: integer()
  def count_active do
    list_active()
    |> length()
  end

  @doc """
  Ensures the TTL table exists.
  """
  def ensure_ttl_table(nodes \\ [node()]) do
    nodes
    |> create_ttl_table()
    |> normalize_table_result()
  end

  defp normalize_table_result({:error, :already_exists}), do: Error.return(:ok)
  defp normalize_table_result(result), do: result

  @doc """
  Sets a TTL for a specific record.
  """
  def set_ttl(table, key, ttl) when is_integer(ttl) and ttl > 0 do
    Query.write(Config.get(:ttl_table), build_ttl_attributes(ttl, table, key))
  end

  @doc """
  Removes the TTL from a specific record.
  """
  def delete_ttl(table, key) do
    Query.delete(@ttl_table, build_ttl_key(table, key))
  end

  @doc """
  Gets the TTL record of a specific record.
  Returns the TTL record or a default record with expires_at: 0 if not found.
  """
  def get_ttl(table, key) do
    ttl_key = build_ttl_key(table, key)

    Query.read(Config.get(:ttl_table), ttl_key)
    |> transform_get_ttl_result()
  end

  defp transform_get_ttl_result({:ok, record}), do: Error.return(record)
  defp transform_get_ttl_result({:error, :not_found}), do: Error.return(%{expires_at: 0})
  defp transform_get_ttl_result({:error, reason}), do: Error.fail(reason)

  @doc """
  Cleans up expired records.
  """
  @spec cleanup_expired() :: :ok | {:error, term()}
  def cleanup_expired do
    :os.system_time(:millisecond)
    |> then(&Query.select(@ttl_table, [{:expires_at, :<, &1}]))
    |> handle_batch_delete()
  end

  defp handle_batch_delete(records) when is_list(records) and length(records) > 0 do
    Query.batch_delete(@ttl_table, records)
    :ok
  end

  defp handle_batch_delete([]), do: :ok

  @doc """
  Writes a record with TTL.

  Accepts either an integer (milliseconds) or a tuple like `{1, :hour}`.
  The primary key is automatically detected from the table schema.

  ## Examples

      # Using tuple format with :id as primary key
      MnesiaEx.TTL.write(:users, %{id: "abc", name: "..."}, {1, :hour})

      # Using tuple format with :sid as primary key
      MnesiaEx.TTL.write(:sessions, %{sid: "xyz", data: "..."}, {1, :hour})

      # Using milliseconds
      MnesiaEx.TTL.write(:sessions, %{sid: "abc", data: "..."}, 3_600_000)
  """
  def write(table, record, ttl) do
    Error.m do
      milliseconds <- Duration.to_milliseconds(ttl)
      written_record <- safe_write_record(table, record)
      primary_key_field <- safe_get_primary_key_field(table)
      primary_key_value <- safe_fetch_from_map(written_record, primary_key_field)
      _ <- set(table, primary_key_value, milliseconds)
      Error.return(written_record)
    end
  end

  defp safe_write_record(table, record) do
    Query.write(table, record)
  end

  @doc """
  Writes a record with TTL (version without error handling).
  """
  def write!(table, record, ttl) do
    table
    |> write(record, ttl)
    |> unwrap_or_raise("Error writing record with TTL")
  end

  @doc """
  Gets the TTL of a record.
  """
  def get(table, key) do
    get_ttl(table, key)
  end

  @doc """
  Gets the TTL of a record (version without error handling).
  """
  def get!(table, key) do
    table
    |> get_ttl(key)
    |> unwrap_or_raise("Error getting TTL")
  end

  @doc """
  Writes a record with TTL (alias for write/3).
  """
  def write_with_ttl(table, record, ttl), do: write(table, record, ttl)

  @doc """
  Writes a record with TTL (alias for write!/3).
  """
  def write_with_ttl!(table, record, ttl), do: write!(table, record, ttl)

  # Callbacks de GenServer

  @impl true
  def init(_opts) do
    ensure_ttl_table()
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired()
    schedule_cleanup()
    {:noreply, state}
  end

  # Pure functions - Transformation

  defp transform_to_expired_status({:ok, _}), do: false
  defp transform_to_expired_status({:error, :expired}), do: true
  defp transform_to_expired_status({:error, _}), do: false

  defp calculate_remaining_time(expiry) do
    expiry
    |> compute_time_difference()
    |> validate_time_remaining()
  end

  defp compute_time_difference(expiry) do
    expiry - :os.system_time(:millisecond)
  end

  defp validate_time_remaining(remaining) when remaining > 0, do: Error.return(remaining)
  defp validate_time_remaining(_), do: Error.fail(:expired)

  defp unwrap_or_raise({:ok, value}, _message), do: value

  defp unwrap_or_raise({:error, reason}, message) do
    raise "#{message}: #{inspect(reason)}"
  end

  # Pure functions - Building

  defp build_ttl_attributes(ttl, table, key) do
    %{
      key: build_ttl_id(table, key),
      table: table,
      record_key: key,
      expires_at: :os.system_time(:millisecond) + ttl
    }
  end

  defp build_ttl_key(table, key), do: build_ttl_id(table, key)

  defp build_ttl_id(table, key) do
    "#{table}_#{key}"
    |> String.replace(~r/[^\w-]/, "_")
    |> String.to_atom()
  end

  defp build_ttl_record(table, record_key, expiry) do
    %{
      key: build_ttl_id(table, record_key),
      table: table,
      record_key: record_key,
      expires_at: expiry
    }
  end

  # Database operations

  defp create_ttl_table(nodes) do
    Table.create(
      Config.get(:ttl_table),
      attributes: [:key, :table, :record_key, :expires_at],
      type: :ordered_set,
      persistence: Config.get(:ttl_persistence),
      nodes: nodes
    )
  end

  # Utility functions

  # Safe wrappers for impure values
  defp safe_calculate_expiry(milliseconds) when is_integer(milliseconds) do
    Error.return(:os.system_time(:millisecond) + milliseconds)
  end

  defp safe_calculate_expiry(_invalid), do: Error.fail(:invalid_milliseconds)

  defp safe_build_ttl_id(table, key) when is_atom(table) do
    ttl_id = build_ttl_id(table, key)
    Error.return(ttl_id)
  end

  defp safe_build_ttl_id(nil, _key), do: Error.fail(:invalid_table)
  defp safe_build_ttl_id(_table, nil), do: Error.fail(:invalid_key)

  defp safe_get_primary_key_field(table) when is_atom(table) do
    :mnesia.table_info(table, :attributes) |> transform_attributes_result()
  end

  defp safe_get_primary_key_field(_invalid), do: Error.fail(:invalid_table)

  defp safe_fetch_from_map(map, key) when is_map(map) do
    Map.fetch(map, key) |> transform_fetch_result()
  end

  defp safe_fetch_from_map(_invalid, _key), do: Error.fail(:invalid_map)

  defp transform_attributes_result({:aborted, reason}), do: Error.fail({:table_info_failed, reason})
  defp transform_attributes_result([first | _]), do: Error.return(first)
  defp transform_attributes_result([]), do: Error.fail(:no_attributes)

  defp transform_fetch_result({:ok, value}), do: Error.return(value)
  defp transform_fetch_result(:error), do: Error.fail(:primary_key_not_found)


  # Transforms TTL records into user-friendly maps (returns list directly)
  defp transform_ttl_records_direct(records) when is_list(records) do
    now = :os.system_time(:millisecond)

    Enum.map(records, fn record ->
      expiry_ms = record.expires_at
      remaining = max(0, expiry_ms - now)

      %{
        table: record.table,
        key: record.record_key,
        expires_at: expiry_ms,
        remaining_ms: remaining,
        remaining_seconds: div(remaining, 1000),
        remaining_minutes: div(remaining, 60_000),
        expired: remaining == 0
      }
    end)
  end

  defp transform_ttl_records_direct(_), do: []

  # Filters only active (non-expired) records
  defp filter_active_records(records) when is_list(records) do
    Enum.filter(records, fn record ->
      not Map.get(record, :expired, false)
    end)
  end

  defp filter_active_records(_), do: []

  defp check_process_alive(nil), do: false
  defp check_process_alive(pid), do: Process.alive?(pid)

  defp schedule_cleanup do
    Config.get(:cleanup_interval)
    |> Duration.to_milliseconds!()
    |> schedule_message()
  end

  defp schedule_message(milliseconds) do
    Process.send_after(self(), :cleanup, milliseconds)
  end
end
