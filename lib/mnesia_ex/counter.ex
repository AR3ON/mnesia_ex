defmodule MnesiaEx.Counter do
  @moduledoc """
  Thread-safe auto-increment counters for Mnesia tables.

  Provides distributed, thread-safe counters perfect for:
  - Auto-incrementing primary keys
  - Order numbers
  - Invoice sequences
  - Ticket numbers
  - Any monotonically increasing values

  ## How It Works

  1. Configure counter fields when creating tables
  2. Records automatically get IDs assigned
  3. Thread-safe across distributed nodes
  4. No race conditions

  ## Quick Start

      # Configure counter on table creation
      MnesiaEx.Table.create(:orders, [
        attributes: [:order_number, :user_id, :total],
        counter_fields: [:order_number]
      ])

      # Records get IDs automatically
      MyApp.Orders.write(%{user_id: 123, total: 99.99})
      # => %{order_number: 1, user_id: 123, total: 99.99}

      # Or get ID manually
      {:ok, id} = MyApp.Orders.get_next_id(:order_number)

  ## Key Functions

  - `get_next_id/2` - Get next auto-increment value
  - `get_current_value/2` - Get current counter value
  - `reset_counter/3` - Reset counter to specific value
  - `has_counter?/2` - Check if counter exists

  ## Examples

      # Get next ID
      {:ok, 1} = MnesiaEx.Counter.get_next_id(:users, :id)
      {:ok, 2} = MnesiaEx.Counter.get_next_id(:users, :id)
      {:ok, 3} = MnesiaEx.Counter.get_next_id(:users, :id)

      # Reset counter
      MnesiaEx.Counter.reset_counter(:users, :id, 1)

      # Check current value
      {:ok, 3} = MnesiaEx.Counter.get_current_value(:users, :id)

  ## Transaction Convention

  - Functions without `!` - Non-transactional (use inside your transaction)
  - Functions with `!` - Transactional (automatic ACID)
  """

  require MnesiaEx.Monad, as: Error

  alias MnesiaEx.{Config, Query}

  @type result :: {:ok, term()} | {:error, term()}
  @type counter_key :: atom()
  @type counter_value :: integer()

  @counter_attributes [:key, :value]

  @doc """
  Ensures the counters table exists.

  ## Examples

      iex> MnesiaEx.Counter.ensure_counter_table()
      {:ok, :created}
  """
  @spec ensure_counter_table([node()]) :: {:ok, :created} | {:error, term()}
  def ensure_counter_table(nodes \\ [node()]) do
    Error.m do
      counter_table <- safe_get_config(:counter_table)
      _ <- safe_ensure_mnesia_running()
      exists <- check_table_exists(counter_table) |> Error.return()
      create_table_if_needed(exists, counter_table, nodes)
    end
  end

  @doc """
  Ensures the counters table exists (raises on error).

  ## Examples

      iex> MnesiaEx.Counter.ensure_counter_table!()
      :created
  """
  @spec ensure_counter_table!([node()]) :: :created | no_return()
  def ensure_counter_table!(nodes \\ [node()]) do
    ensure_counter_table(nodes)
    |> unwrap_ensure_result!()
  end

  defp unwrap_ensure_result!({:ok, :created}), do: :created
  defp unwrap_ensure_result!({:error, reason}), do: raise("Failed to ensure counter table: #{inspect(reason)}")

  defp create_table_if_needed(true, _table, _nodes), do: Error.return(:created)

  defp create_table_if_needed(false, table, nodes) do
    build_table_opts(nodes)
    |> then(&:mnesia.create_table(table, &1))
    |> atomic_to_error_monad()
    |> Error.bind(fn _ -> Error.return(:created) end)
  end

  @doc """
  Initializes a counter for a specific table field.

  ## Examples

      iex> MnesiaEx.Counter.init_counter(:users, :id)
      {:ok, :initialized}
  """
  @spec init_counter(atom(), atom()) :: {:ok, :initialized} | {:error, term()}
  def init_counter(table, field) do
    Error.m do
      counter_key <- build_counter_key(table, field) |> Error.return()
      counter_table <- safe_get_config(:counter_table)
      _ <- ensure_counter_table()

      _ <- safe_transaction(fn ->
        :mnesia.read(counter_table, counter_key)
        |> handle_initial_counter_read(counter_table, counter_key)
      end)

      Error.return(:initialized)
    end
  end

  @doc """
  Initializes a counter for a specific table field (raises on error).

  ## Examples

      iex> MnesiaEx.Counter.init_counter!(:users, :id)
      :initialized
  """
  @spec init_counter!(atom(), atom()) :: :initialized | no_return()
  def init_counter!(table, field) do
    init_counter(table, field)
    |> unwrap_init_result!()
  end

  defp unwrap_init_result!({:ok, :initialized}), do: :initialized
  defp unwrap_init_result!({:error, reason}), do: raise("Failed to initialize counter: #{inspect(reason)}")

  @doc """
  Deletes a counter for a specific table field.

  ## Examples

      iex> MnesiaEx.Counter.delete_counter(:users, :id)
      {:ok, :deleted}
  """
  @spec delete_counter(atom(), atom()) :: {:ok, :deleted} | {:error, term()}
  def delete_counter(table, field) do
    counter_key = build_counter_key(table, field)
    counter_table = Config.get(:counter_table)

    Query.delete(counter_table, counter_key)
    |> transform_delete_result()
  end

  defp transform_delete_result({:ok, _}), do: Error.return(:deleted)
  defp transform_delete_result({:error, :not_found}), do: Error.return(:deleted)
  defp transform_delete_result({:error, reason}), do: Error.fail(reason)

  @doc """
  Deletes a counter for a specific table field (raises on error).

  ## Examples

      iex> MnesiaEx.Counter.delete_counter!(:users, :id)
      :deleted
  """
  @spec delete_counter!(atom(), atom()) :: :deleted | no_return()
  def delete_counter!(table, field) do
    delete_counter(table, field)
    |> unwrap_delete_result!()
  end

  defp unwrap_delete_result!({:ok, :deleted}), do: :deleted
  defp unwrap_delete_result!({:error, reason}), do: raise("Failed to delete counter: #{inspect(reason)}")

  @doc """
  Gets the next value for a specific table field.

  ## Examples

      iex> MnesiaEx.Counter.get_next_id(:users, :id)
      {:ok, 1}
  """
  @spec get_next_id(atom(), atom()) :: {:ok, integer()} | {:error, term()}
  def get_next_id(table, field) do
    counter_key = build_counter_key(table, field)
    counter_table = Config.get(:counter_table)

    :mnesia.transaction(fn ->
      safe_increment_counter_in_transaction(counter_table, counter_key)
    end)
    |> transform_transaction_result()
  end

  @doc """
  Gets the next value for a specific field within a transaction.

  ## Examples

      iex> MnesiaEx.Counter.get_next_id!(:users, :id)
      1
  """
  @spec get_next_id!(atom(), atom()) :: integer() | no_return()
  def get_next_id!(table, field) do
    counter_key = build_counter_key(table, field)
    counter_table = Config.get(:counter_table)

    :mnesia.transaction(fn ->
      safe_increment_counter_in_transaction(counter_table, counter_key)
    end)
    |> transform_transaction_result_bang()
  end

  @doc """
  Gets the next value for use within an existing transaction.
  Does NOT start a new transaction. Must be called ONLY from within a transaction.

  ## Examples

      # From Query.write which is already in a transaction
      {:ok, id} = MnesiaEx.Counter.get_next_id_in_transaction(:users, :id)
  """
  @spec get_next_id_in_transaction(atom(), atom()) :: {:ok, integer()}
  def get_next_id_in_transaction(table, field) do
    counter_key = build_counter_key(table, field)
    counter_table = Config.get(:counter_table)

    next_value = safe_increment_counter_in_transaction(counter_table, counter_key)
    Error.return(next_value)
  end

  @doc """
  Resets a field counter to a specific value.

  ## Examples

      iex> MnesiaEx.Counter.reset_counter(:users, :id)
      {:ok, 1}

      iex> MnesiaEx.Counter.reset_counter(:users, :id, 100)
      {:ok, 100}
  """
  @spec reset_counter(atom(), atom(), integer()) :: {:ok, integer()} | {:error, term()}
  def reset_counter(table, field, value \\ 1)

  def reset_counter(table, field, value) when is_integer(value) and value > 0 do
    counter_key = build_counter_key(table, field)
    counter_table = Config.get(:counter_table)
    reset_value = value - 1
    counter_record = %{key: counter_key, value: reset_value}

    Query.upsert(counter_table, counter_record)
    |> transform_reset_result(value)
  end

  defp transform_reset_result({:ok, _record}, value), do: Error.return(value)
  defp transform_reset_result({:error, reason}, _value), do: Error.fail(reason)

  @doc """
  Gets the current value of a counter.

  ## Examples

      iex> MnesiaEx.Counter.get_current_value(:users, :id)
      {:ok, 42}
  """
  @spec get_current_value(atom(), atom()) :: {:ok, integer()} | {:error, term()}
  def get_current_value(table, field) do
    counter_key = build_counter_key(table, field)
    counter_table = Config.get(:counter_table)

    Query.read(counter_table, counter_key)
    |> extract_value_with_default()
  end

  defp extract_value_with_default({:ok, %{value: value}}), do: Error.return(value)
  defp extract_value_with_default({:error, :not_found}), do: Error.return(0)
  defp extract_value_with_default({:error, reason}), do: Error.fail(reason)

  @doc """
  Gets the current value of a counter (raises on error).

  ## Examples

      value = MnesiaEx.Counter.get_current_value!(:users, :id)
      #=> 42
  """
  @spec get_current_value!(atom(), atom()) :: integer() | no_return()
  def get_current_value!(table, field) do
    get_current_value(table, field)
    |> unwrap_counter_value!()
  end

  defp unwrap_counter_value!({:ok, value}), do: value
  defp unwrap_counter_value!({:error, reason}), do: raise("Failed to get counter value: #{inspect(reason)}")

  @doc """
  Checks if a field has an associated counter.

  ## Examples

      iex> MnesiaEx.Counter.has_counter?(:users, :id)
      true
  """
  @spec has_counter?(atom(), atom()) :: boolean()
  def has_counter?(table, field) do
    counter_key = build_counter_key(table, field)
    counter_table = Config.get(:counter_table)

    Query.read(counter_table, counter_key)
    |> transform_to_boolean()
  end

  defp transform_to_boolean({:ok, _}), do: true
  defp transform_to_boolean({:error, _}), do: false

  @doc """
  Resets a counter with transaction to a specific value.

  ## Examples

      iex> MnesiaEx.Counter.reset_counter!(:users, :id)
      1

      iex> MnesiaEx.Counter.reset_counter!(:users, :id, 100)
      100
  """
  @spec reset_counter!(atom(), atom(), integer()) :: integer() | no_return()
  def reset_counter!(table, field, value \\ 1)

  def reset_counter!(table, field, value) when is_integer(value) and value > 0 do
    counter_key = build_counter_key(table, field)
    counter_table = Config.get(:counter_table)
    reset_value = value - 1
    counter_record = %{key: counter_key, value: reset_value}

    Query.upsert!(counter_table, counter_record)
    value
  end

  # Pure functions - no side effects

  defp build_counter_key(table, field) do
    String.to_atom("#{table}_#{field}")
  end

  defp check_table_exists(table) do
    :mnesia.system_info(:tables)
    |> Enum.member?(table)
  end

  defp build_table_opts(nodes) do
    [
      {:attributes, @counter_attributes},
      {:type, :set},
      {:access_mode, :read_write},
      {get_storage_type(), nodes}
    ]
  end

  defp get_storage_type do
    :mnesia.system_info(:use_dir)
    |> transform_use_dir_to_storage_type()
  end

  defp transform_use_dir_to_storage_type(true), do: :disc_copies
  defp transform_use_dir_to_storage_type(false), do: :ram_copies

  # Safe wrappers for effects

  defp safe_increment_counter_in_transaction(counter_table, counter_key) do
    Query.read(counter_table, counter_key)
    |> handle_counter_read_for_increment(counter_table, counter_key)
  end

  # Safe wrappers for impure operations

  defp safe_get_config(key) do
    Config.get(key) |> transform_config_result(key)
  end

  defp safe_ensure_mnesia_running do
    :mnesia.system_info(:is_running) |> transform_mnesia_status()
  end

  defp safe_transaction(fun) when is_function(fun) do
    :mnesia.transaction(fun) |> transform_transaction_result()
  end

  # Pure transformations

  defp transform_config_result(nil, key), do: Error.fail({:config_missing, key})
  defp transform_config_result(value, _key), do: Error.return(value)

  defp transform_mnesia_status(:yes), do: Error.return(:ok)

  defp transform_mnesia_status(:no) do
    :mnesia.start()
    |> transform_start_result()
  end

  defp transform_mnesia_status(:stopping), do: Error.fail(:mnesia_stopping)

  defp transform_start_result(:ok), do: Error.return(:ok)
  defp transform_start_result({:error, {:already_started, _}}), do: Error.return(:ok)
  defp transform_start_result({:error, reason}), do: Error.fail(reason)

  defp transform_transaction_result({:atomic, value}), do: Error.return(value)
  defp transform_transaction_result({:aborted, reason}), do: Error.fail(reason)

  defp transform_transaction_result_bang({:atomic, value}), do: value

  defp transform_transaction_result_bang({:aborted, reason}) do
    raise "Error getting next ID: #{inspect(reason)}"
  end

  # Pattern matching for counter operations

  defp atomic_to_error_monad({:atomic, :ok}), do: Error.return(:ok)
  defp atomic_to_error_monad({:aborted, reason}), do: Error.fail(reason)

  defp handle_initial_counter_read([], counter_table, counter_key) do
    :mnesia.write({counter_table, counter_key, 0})
    :ok
  end

  defp handle_initial_counter_read([{_table, _key, _value}], _counter_table, _counter_key) do
    :ok
  end

  defp handle_initial_counter_read(error, _counter_table, _counter_key) do
    :mnesia.abort(error)
  end

  defp handle_counter_read_for_increment({:error, :not_found}, counter_table, counter_key) do
    counter_record = %{key: counter_key, value: 1}

    Query.upsert(counter_table, counter_record)
    |> handle_upsert_result_for_increment(1)
  end

  defp handle_counter_read_for_increment(
         {:ok, %{value: current_value}},
         counter_table,
         counter_key
       ) do
    next_value = current_value + 1
    counter_record = %{key: counter_key, value: next_value}

    Query.upsert(counter_table, counter_record)
    |> handle_upsert_result_for_increment(next_value)
  end

  defp handle_counter_read_for_increment({:error, reason}, _counter_table, _counter_key) do
    :mnesia.abort(reason)
  end

  defp handle_upsert_result_for_increment({:ok, _record}, next_value), do: next_value

  defp handle_upsert_result_for_increment({:error, reason}, _next_value),
    do: :mnesia.abort(reason)
end
