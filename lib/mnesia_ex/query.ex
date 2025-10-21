defmodule MnesiaEx.Query do
  @moduledoc """
  CRUD operations and query interface for Mnesia tables.

  This module provides a complete set of database operations with both transactional
  and non-transactional variants, plus high-performance dirty operations.

  ## Function Categories

  ### Basic CRUD
  - `write/3`, `write!/3` - Insert or update records
  - `read/2`, `read!/2` - Fetch by primary key
  - `update/4`, `update!/4` - Update specific fields
  - `delete/2`, `delete!/2` - Remove records
  - `upsert/2`, `upsert!/2` - Insert or update atomically

  ### Queries
  - `select/3` - Query with conditions (returns `{:ok, [records]}`)
  - `get_by/3`, `get_by!/3` - Find by specific field
  - `all_keys/1` - List all primary keys (returns `{:ok, [keys]}`)

  ### Batch Operations
  - `batch_write/2` - Bulk insert (returns `{:ok, [records]}`)
  - `batch_delete/2` - Bulk delete (returns `{:ok, [records]}`)

  ### High-Performance Dirty Operations
  - `dirty_write/3` - ~10x faster write (no transaction)
  - `dirty_read/2` - ~10x faster read (no transaction)
  - `dirty_update/4` - ~10x faster update (no transaction)
  - `dirty_delete/2` - ~10x faster delete (no transaction)

  ## Transaction Convention

      # Transactional (automatic ACID guarantees)
      {:ok, user} = MnesiaEx.Query.write!(:users, %{name: "Alice"})

      # Non-transactional (use inside your own transaction)
      :mnesia.transaction(fn ->
        {:ok, user} = MnesiaEx.Query.write(:users, %{name: "Alice"})
        {:ok, order} = MnesiaEx.Query.write(:orders, %{user_id: user.id})
        {:ok, user, order}
      end)

  ## Auto-Increment Support

  When a field has an auto-increment counter configured, it's automatically
  generated if not provided:

      # Counter configured for :id field
      MyApp.Users.write(%{name: "Alice"})
      # => %{id: 1, name: "Alice"} (id auto-generated)

  ## Performance

  Use dirty operations when ACID guarantees aren't critical:

      # Regular (transactional, ~100μs)
      MnesiaEx.Query.write!(:cache, %{key: "data"})

      # Dirty (non-transactional, ~10μs)
      MnesiaEx.Query.dirty_write(:cache, %{key: "data"})

  Perfect for: high-frequency writes, analytics, cache, non-critical data.
  """

  require MnesiaEx.Monad, as: Error

  alias MnesiaEx.{Utils, Counter}

  @type table :: atom()
  @type key :: term()
  @type record :: map()
  @type result :: {:ok, term()} | {:error, term()}
  @type condition ::
          {atom(), :== | :> | :< | :>= | :<= | :"/=", term()}

  # Write operations

  @doc """
  Writes a record to the table.

  Automatically creates a transaction if not already in one.
  If a field has an initialized counter and no value is provided,
  it will be automatically generated using MnesiaEx.Counter.
  Returns `{:ok, record}` on success or `{:error, reason}` on failure.

  ## Options
    * `:unique_fields` - List of fields that must be unique

  ## Examples

      # Single operation (auto-transaction)
      {:ok, user} = MnesiaEx.Query.write(:users, %{id: 1, name: "Alice"})

      # Inside manual transaction (no double-transaction)
      {:ok, {user, post}} = MnesiaEx.transaction(fn ->
        {:ok, user} = MnesiaEx.Query.write(:users, %{id: 1, name: "Alice"})
        {:ok, post} = MnesiaEx.Query.write(:posts, %{user_id: user.id})
        {user, post}
      end)
  """
  @spec write(table(), map(), Keyword.t()) :: result()
  def write(table, record, opts \\ []) do
    safe_check_in_transaction()
    |> safe_write_with_context(table, record, opts)
  end

  defp safe_check_in_transaction do
    :mnesia.is_transaction()
    |> Error.return()
  end

  defp safe_write_with_context({:ok, true}, table, record, opts) do
    write_core(table, record, opts)
  end

  defp safe_write_with_context({:ok, false}, table, record, opts) do
    MnesiaEx.transaction(fn ->
      write_core(table, record, opts)
      |> unwrap_or_abort()
    end)
  end

  defp write_core(table, record, opts) do
    Error.m do
      fields <- safe_get_table_fields(table)
      record_with_ids <- safe_generate_ids(table, record, fields)
      _ <- safe_validate_unique_fields(table, record_with_ids, Keyword.get(opts, :unique_fields, []))
      safe_write_record(table, record_with_ids, fields)
    end
  end

  # Pure functions - Table field operations

  defp safe_get_table_fields(table) do
    :mnesia.table_info(table, :attributes)
    |> Error.return()
  end

  defp is_counter_field_in_schema(table, field) do
    get_counter_fields_from_schema(table)
    |> check_field_in_list(field)
  end

  defp get_counter_fields_from_schema(table) do
    :mnesia.table_info(table, :user_properties)
    |> extract_counter_fields_from_properties()
  end

  defp extract_counter_fields_from_properties(properties) when is_list(properties) do
    extract_autoincrement_fields(properties, [])
  end

  defp extract_counter_fields_from_properties(_), do: []

  defp extract_autoincrement_fields([], acc), do: Enum.reverse(acc)

  defp extract_autoincrement_fields([{:field_type, field, :autoincrement} | rest], acc) do
    extract_autoincrement_fields(rest, [field | acc])
  end

  defp extract_autoincrement_fields([_other | rest], acc) do
    extract_autoincrement_fields(rest, acc)
  end

  defp check_field_in_list(fields, field) when is_list(fields) do
    check_field_membership(fields, field)
  end

  defp check_field_in_list(_fields, _field), do: false

  defp check_field_membership([], _field), do: false

  defp check_field_membership([field | _rest], field), do: true

  defp check_field_membership([_other | rest], field) do
    check_field_membership(rest, field)
  end

  # Pure functions - ID generation

  defp safe_generate_ids(table, record, fields) do
    generate_ids_recursive(table, record, fields, [])
  end

  defp generate_ids_recursive(_table, record, [], _processed_fields) do
    Error.return(record)
  end

  defp generate_ids_recursive(table, record, [field | rest], processed_fields) do
    Error.m do
      updated_record <- process_field_id(table, record, field)
      generate_ids_recursive(table, updated_record, rest, [field | processed_fields])
    end
  end

  defp process_field_id(table, record, field) do
    Map.get(record, field)
    |> handle_id_field(table, field, record)
  end

  defp handle_id_field(nil, table, field, acc) do
    Counter.has_counter?(table, field)
    |> generate_id_if_has_counter(table, field, acc)
  end

  defp handle_id_field(manual_id, table, field, acc) when is_integer(manual_id) do
    is_counter_field_in_schema(table, field)
    |> validate_and_adjust_counter(table, field, manual_id, acc)
  end

  defp handle_id_field(_value, _table, _field, acc), do: Error.return(acc)

  defp generate_id_if_has_counter(true, table, field, acc) do
    Counter.get_next_id_in_transaction(table, field)
    |> transform_counter_id_result(field, acc)
  end

  defp generate_id_if_has_counter(false, _table, _field, acc), do: Error.return(acc)

  defp transform_counter_id_result({:ok, id}, field, acc) do
    Error.return(Map.put(acc, field, id))
  end

  defp transform_counter_id_result({:error, reason}, _field, _acc) do
    Error.fail(reason)
  end

  defp validate_and_adjust_counter(true, table, field, manual_id, acc) do
    validate_manual_id_not_exists(table, manual_id, field, acc)
  end

  defp validate_and_adjust_counter(false, _table, _field, _manual_id, acc) do
    Error.return(acc)
  end

  defp validate_manual_id_not_exists(table, manual_id, field, acc) do
    read(table, manual_id)
    |> handle_existence_check_for_manual_id(table, field, manual_id, acc)
  end

  defp handle_existence_check_for_manual_id({:error, :not_found}, table, field, manual_id, acc) do
    adjust_counter_if_needed(table, field, manual_id, acc)
  end

  defp handle_existence_check_for_manual_id({:ok, _existing_record}, _table, field, manual_id, _acc) do
    Error.fail({:id_already_exists, field, manual_id})
  end

  defp handle_existence_check_for_manual_id({:error, reason}, _table, _field, _manual_id, _acc) do
    Error.fail(reason)
  end

  defp adjust_counter_if_needed(table, field, manual_id, acc) do
    Counter.get_current_value(table, field)
    |> update_counter_if_manual_id_higher(table, field, manual_id, acc)
  end

  defp update_counter_if_manual_id_higher({:ok, current_value}, table, field, manual_id, acc)
       when manual_id > current_value do
    Counter.reset_counter(table, field, manual_id + 1)
    |> transform_counter_reset_result(acc)
  end

  defp update_counter_if_manual_id_higher({:ok, _current_value}, _table, _field, _manual_id, acc) do
    Error.return(acc)
  end

  defp update_counter_if_manual_id_higher({:error, reason}, _table, _field, _manual_id, _acc) do
    Error.fail(reason)
  end

  defp transform_counter_reset_result({:ok, _value}, acc), do: Error.return(acc)
  defp transform_counter_reset_result({:error, reason}, _acc), do: Error.fail(reason)

  # Pure functions - Unique field validation

  defp safe_validate_unique_fields(_table, _record, []), do: Error.return(:ok)

  defp safe_validate_unique_fields(table, record, [field | rest]) do
    Map.get(record, field)
    |> check_field_uniqueness(table, record, field, rest)
  end

  defp check_field_uniqueness(nil, table, record, _field, rest) do
    safe_validate_unique_fields(table, record, rest)
  end

  defp check_field_uniqueness(value, table, record, field, rest) do
    select(table, [{field, :==, value}])
    |> handle_uniqueness_result(table, record, field, value, rest)
  end

  defp handle_uniqueness_result([], table, record, _field, _value, rest) do
    safe_validate_unique_fields(table, record, rest)
  end

  defp handle_uniqueness_result([existing], table, record, field, value, rest) do
    is_same_record = Map.get(record, :id) == Map.get(existing, :id)
    handle_same_record_result(is_same_record, table, record, field, value, rest)
  end

  defp handle_same_record_result(true, table, record, _field, _value, rest) do
    safe_validate_unique_fields(table, record, rest)
  end

  defp handle_same_record_result(false, _table, _record, field, value, _rest) do
    Error.fail({:unique_violation, field, value})
  end

  # Side effects - Write operations

  defp safe_write_record(table, record, fields) do
    [table | Enum.map(fields, &Map.get(record, &1))]
    |> List.to_tuple()
    |> :mnesia.write()
    |> to_result_with_record(record)
  end

  defp to_result_with_record(:ok, record), do: Error.return(record)
  defp to_result_with_record(error, _record), do: Error.fail(error)

  @doc """
  Writes a record in a transaction.

  Returns the written record directly or raises an exception on error.

  ## Options
    * `:unique_fields` - List of fields that must be unique

  ## Examples

      # Returns the record directly
      user = MnesiaEx.Query.write!(:users, %{id: 1, name: "John"})
      #=> %{id: 1, name: "John"}

      # Write with unique fields
      user = MnesiaEx.Query.write!(:users, %{name: "John", email: "john@example.com"}, unique_fields: [:email])

      # Raises on error
      MnesiaEx.Query.write!(:users, %{name: "John", email: "duplicate@example.com"}, unique_fields: [:email])
      #=> ** (RuntimeError) Transaction aborted: ...
  """
  @spec write!(table(), map(), Keyword.t()) :: map() | no_return()
  def write!(table, attrs, opts \\ []) do
    write(table, attrs, opts)
    |> unwrap_result_or_raise!()
  end

  defp unwrap_result_or_raise!({:ok, value}), do: value
  defp unwrap_result_or_raise!({:error, reason}), do: raise("Operation failed: #{inspect(reason)}")

  defp unwrap_or_abort({:ok, result}), do: result
  defp unwrap_or_abort({:error, reason}), do: :mnesia.abort(reason)


  @doc """
  Writes multiple records.

  Automatically creates a transaction if not already in one.
  Returns a list of written records (empty list if input was empty).

  ## Examples

      # Single operation (auto-transaction)
      users = MnesiaEx.Query.batch_write(:users, [
        %{name: "John", email: "john@example.com"},
        %{name: "Jane", email: "jane@example.com"}
      ])
      #=> [%{id: 1, name: "John", ...}, %{id: 2, name: "Jane", ...}]

      # Inside manual transaction
      {:ok, result} = MnesiaEx.transaction(fn ->
        users = MnesiaEx.Query.batch_write(:users, [...])
        posts = MnesiaEx.Query.batch_write(:posts, [...])
        {users, posts}
      end)
  """
  @spec batch_write(table(), [map()]) :: [map()]
  def batch_write(_table, []), do: []

  def batch_write(table, records) when is_list(records) do
    safe_check_in_transaction()
    |> safe_batch_write_with_context(table, records)
    |> unwrap_list_or_raise!()
  end

  defp safe_batch_write_with_context({:ok, true}, table, records) do
    batch_write_core(table, records)
  end

  defp safe_batch_write_with_context({:ok, false}, table, records) do
    MnesiaEx.transaction(fn ->
      batch_write_core(table, records)
      |> unwrap_or_abort()
    end)
  end

  defp batch_write_core(table, records) do
    batch_write_recursive(table, records, [])
  end

  defp batch_write_recursive(_table, [], acc), do: Error.return(Enum.reverse(acc))

  defp batch_write_recursive(table, [record | rest], acc) do
    Error.m do
      result <- write_core(table, record, [])
      batch_write_recursive(table, rest, [result | acc])
    end
  end

  # Read operations

  @doc """
  Reads a record by its ID.

  Automatically creates a transaction if not already in one.
  Returns `{:ok, record}` on success or `{:error, :not_found}` if not found.

  ## Examples

      # Single operation (auto-transaction)
      {:ok, user} = MnesiaEx.Query.read(:users, 1)

      # Inside manual transaction
      {:ok, user} = MnesiaEx.transaction(fn ->
        {:ok, user} = MnesiaEx.Query.read(:users, 1)
        {:ok, user}
      end)
  """
  @spec read(table(), key()) :: {:ok, map()} | {:error, :not_found}
  def read(table, id) do
    safe_check_in_transaction()
    |> safe_read_with_context(table, id)
  end

  defp safe_read_with_context({:ok, true}, table, id) do
    read_core(table, id)
  end

  defp safe_read_with_context({:ok, false}, table, id) do
    MnesiaEx.transaction(fn ->
      read_core(table, id)
      |> unwrap_or_abort()
    end)
  end

  defp read_core(table, id) do
    :mnesia.read(table, id)
    |> transform_read_result()
  end

  defp transform_read_result([record | _]) do
    Utils.tuple_to_map(record)
    |> Error.return()
  end

  defp transform_read_result([]), do: Error.fail(:not_found)
  defp transform_read_result(error), do: Error.fail(error)

  @doc """
  Reads a record in a transaction.

  Returns the record directly or raises if not found.

  ## Examples

      user = MnesiaEx.Query.read!(:users, 1)
      #=> %{id: 1, name: "John", email: "john@example.com"}

      MnesiaEx.Query.read!(:users, 999)
      #=> ** (RuntimeError) Transaction aborted: :not_found
  """
  @spec read!(table(), key()) :: map() | no_return()
  def read!(table, key) do
    read(table, key)
    |> unwrap_result_or_raise!()
  end

  # Delete operations

  @doc """
  Deletes a record from the table.

  Automatically creates a transaction if not already in one.
  Accepts either an ID or a map of fields for deletion.
  Returns `{:ok, deleted_record}` on success or `{:error, reason}` on failure.

  ## Examples

      # Single operation (auto-transaction)
      {:ok, deleted} = MnesiaEx.Query.delete(:users, 1)

      # Inside manual transaction
      {:ok, {deleted_user, deleted_post}} = MnesiaEx.transaction(fn ->
        {:ok, user} = MnesiaEx.Query.delete(:users, 1)
        {:ok, post} = MnesiaEx.Query.delete(:posts, 100)
        {user, post}
      end)
  """
  @spec delete(table(), key() | map()) :: {:ok, map()} | {:error, term()}
  def delete(table, id_or_fields) do
    safe_check_in_transaction()
    |> safe_delete_with_context(table, id_or_fields)
  end

  defp safe_delete_with_context({:ok, true}, table, id_or_fields) do
    delete_core(table, id_or_fields)
  end

  defp safe_delete_with_context({:ok, false}, table, id_or_fields) do
    MnesiaEx.transaction(fn ->
      delete_core(table, id_or_fields)
      |> unwrap_or_abort()
    end)
  end

  defp delete_core(table, id) when not is_map(id) do
    Error.m do
      record <- read_core(table, id)
      _ <- safe_delete_by_id(table, id)
      Error.return(record)
    end
  end

  defp delete_core(table, fields) when is_map(fields) do
    Error.m do
      table_fields <- safe_get_table_fields(table)
      record_tuple <- Error.return(build_delete_tuple(table, table_fields, fields))
      _ <- safe_delete_object(record_tuple)
      Error.return(fields)
    end
  end

  defp safe_delete_by_id(table, id) do
    :mnesia.delete({table, id})
    |> transform_delete_result()
  end

  defp safe_delete_object(record_tuple) do
    :mnesia.delete_object(record_tuple)
    |> transform_delete_result()
  end

  defp transform_delete_result(:ok), do: Error.return(:ok)
  defp transform_delete_result(error), do: Error.fail(error)

  @doc """
  Deletes a record in a transaction.

  Returns the deleted record directly or raises on error.

  ## Examples

      # Delete by ID
      user = MnesiaEx.Query.delete!(:users, 1)
      #=> %{id: 1, name: "John", ...}

      # Delete by fields
      user = MnesiaEx.Query.delete!(:users, %{id: 1, email: "john@example.com"})
      #=> %{id: 1, name: "John", email: "john@example.com"}
  """
  @spec delete!(table(), key() | map()) :: map() | no_return()
  def delete!(table, key_or_fields) do
    delete(table, key_or_fields)
    |> unwrap_result_or_raise!()
  end

  # Select operations

  @doc """
  Searches for records matching the specified conditions.

  Automatically creates a transaction if not already in one.
  Returns a list of matching records directly (empty list if none found).

  ## Examples

      # Single operation (auto-transaction)
      users = MnesiaEx.Query.select(:users, [{:age, :>, 18}])
      #=> [%{id: 1, name: "Alice", age: 30}, ...]

      # Inside manual transaction
      {:ok, result} = MnesiaEx.transaction(fn ->
        users = MnesiaEx.Query.select(:users, [{:age, :>, 18}])
        posts = MnesiaEx.Query.select(:posts, [{:user_id, :==, 1}])
        {users, posts}
      end)
  """
  @spec select(atom(), [condition()], [atom() | :"$_"]) :: list(map())
  def select(table, conditions \\ [], return_fields \\ [:"$_"]) do
    safe_check_in_transaction()
    |> safe_select_with_context(table, conditions, return_fields)
    |> unwrap_list_or_raise!()
  end

  defp safe_select_with_context({:ok, true}, table, conditions, return_fields) do
    select_core(table, conditions, return_fields)
  end

  defp safe_select_with_context({:ok, false}, table, conditions, return_fields) do
    MnesiaEx.transaction(fn ->
      select_core(table, conditions, return_fields)
      |> unwrap_or_abort()
    end)
  end

  defp unwrap_list_or_raise!({:ok, list}) when is_list(list), do: list
  defp unwrap_list_or_raise!({:error, reason}), do: raise "Query failed: #{inspect(reason)}"

  defp select_core(table, conditions, return_fields) do
    safe_get_table_fields(table)
    |> Error.bind(fn fields ->
      match_spec = build_match_spec(table, fields, conditions, return_fields)
      safe_select_records(table, match_spec)
    end)
  end

  defp safe_select_records(table, match_spec) do
    :mnesia.select(table, match_spec)
    |> transform_select_result()
  end

  defp transform_select_result(records) when is_list(records) do
    Utils.tuple_to_map(records)
    |> Error.return()
  end

  defp transform_select_result(_error), do: Error.return([])

  @doc """
  Returns all keys in a table.

  Automatically creates a transaction if not already in one.
  Useful for iteration or getting a list of all IDs without loading full records.
  Returns an empty list if the table is empty.

  ## Examples

      # Single operation (auto-transaction)
      keys = MnesiaEx.Query.all_keys(:users)
      #=> [1, 2, 3, 4, 5]

      # Inside manual transaction
      {:ok, all_keys} = MnesiaEx.transaction(fn ->
        user_keys = MnesiaEx.Query.all_keys(:users)
        post_keys = MnesiaEx.Query.all_keys(:posts)
        {user_keys, post_keys}
      end)
  """
  @spec all_keys(table()) :: [term()]
  def all_keys(table) when is_atom(table) do
    safe_check_in_transaction()
    |> safe_all_keys_with_context(table)
    |> unwrap_list_or_raise!()
  end

  defp safe_all_keys_with_context({:ok, true}, table) do
    all_keys_core(table)
  end

  defp safe_all_keys_with_context({:ok, false}, table) do
    MnesiaEx.transaction(fn ->
      all_keys_core(table)
      |> unwrap_or_abort()
    end)
  end

  defp all_keys_core(table) do
    :mnesia.all_keys(table)
    |> Error.return()
  end

  # Dirty operations (fast, non-transactional)

  @doc """
  Fast write without transaction overhead.

  Uses dirty operations which are faster but without ACID guarantees.
  Only use when performance is critical and consistency can be relaxed.

  ## Examples

      iex> MnesiaEx.Query.dirty_write(:users, %{id: 1, name: "John"})
      {:ok, %{id: 1, name: "John"}}
  """
  @spec dirty_write(table(), map(), Keyword.t()) :: {:ok, map()} | {:error, term()}
  def dirty_write(table, attrs, _opts \\ []) do
    Error.m do
      fields <- safe_get_table_fields(table)
      _ <- build_record_tuple(table, attrs, fields) |> safe_dirty_write()
      Error.return(attrs)
    end
  end

  defp build_record_tuple(table, record, fields) do
    [table | Enum.map(fields, &Map.get(record, &1))]
    |> List.to_tuple()
  end

  defp safe_dirty_write(record) do
    :mnesia.dirty_write(record)
    |> transform_dirty_result()
  end

  defp transform_dirty_result(:ok), do: Error.return(:ok)
  defp transform_dirty_result(error), do: Error.fail(error)

  @doc """
  Fast read without transaction overhead.

  ## Examples

      iex> MnesiaEx.Query.dirty_read(:users, 1)
      {:ok, %{id: 1, name: "John"}}
  """
  @spec dirty_read(table(), key()) :: {:ok, map()} | {:error, :not_found | term()}
  def dirty_read(table, key) do
    :mnesia.dirty_read(table, key)
    |> transform_dirty_read_result()
  end

  defp transform_dirty_read_result([record]), do: Utils.tuple_to_map(record) |> Error.return()
  defp transform_dirty_read_result([]), do: Error.fail(:not_found)
  defp transform_dirty_read_result(_), do: Error.fail(:unexpected_result)

  @doc """
  Fast delete without transaction overhead.

  ## Examples

      iex> MnesiaEx.Query.dirty_delete(:users, 1)
      {:ok, :deleted}
  """
  @spec dirty_delete(table(), key()) :: {:ok, :deleted} | {:error, term()}
  def dirty_delete(table, key) do
    :mnesia.dirty_delete(table, key)
    |> transform_dirty_delete_result()
  end

  defp transform_dirty_delete_result(:ok), do: Error.return(:deleted)
  defp transform_dirty_delete_result(error), do: Error.fail(error)

  @doc """
  Fast update without transaction overhead.

  ## Examples

      iex> MnesiaEx.Query.dirty_update(:users, 1, %{name: "Updated"})
      {:ok, %{id: 1, name: "Updated"}}
  """
  @spec dirty_update(table(), key(), map(), Keyword.t()) :: {:ok, map()} | {:error, term()}
  def dirty_update(table, id, attrs, opts \\ [])

  def dirty_update(table, id, %{} = attrs, opts) do
    Error.m do
      record <- dirty_read(table, id)
      updated <- Error.return(Map.merge(record, attrs))
      _ <- dirty_write(table, updated, opts)
      Error.return(updated)
    end
  end

  # Get by operations

  @doc """
  Searches for a record by a specific field.

  Automatically creates a transaction if not already in one.
  Returns `{:ok, record}` on success or `{:error, :not_found}` if not found.

  ## Examples

      # Single operation (auto-transaction)
      {:ok, user} = MnesiaEx.Query.get_by(:users, :email, "john@example.com")

      # Inside manual transaction
      {:ok, user} = MnesiaEx.transaction(fn ->
        {:ok, user} = MnesiaEx.Query.get_by(:users, :email, "john@example.com")
        {:ok, user}
      end)
  """
  @spec get_by(table(), atom(), term()) :: {:ok, map()} | {:error, :not_found}
  def get_by(table, field, value) do
    safe_check_in_transaction()
    |> safe_get_by_with_context(table, field, value)
  end

  defp safe_get_by_with_context({:ok, true}, table, field, value) do
    get_by_core(table, field, value)
  end

  defp safe_get_by_with_context({:ok, false}, table, field, value) do
    MnesiaEx.transaction(fn ->
      get_by_core(table, field, value)
      |> unwrap_or_abort()
    end)
  end

  defp get_by_core(table, field, value) do
    safe_get_table_fields(table)
    |> Error.bind(fn fields ->
      match_spec = build_match_spec(table, fields, [{field, :==, value}], [:"$_"])
      safe_select_records(table, match_spec)
    end)
    |> transform_select_to_get_by_result()
  end

  defp transform_select_to_get_by_result({:ok, []}), do: Error.fail(:not_found)
  defp transform_select_to_get_by_result({:ok, [result | _]}), do: Error.return(result)
  defp transform_select_to_get_by_result({:error, _} = error), do: error

  @doc """
  Searches for a record by field in a transaction.

  Returns the first matching record directly or raises if not found.

  ## Examples

      user = MnesiaEx.Query.get_by!(:users, :email, "john@example.com")
      #=> %{id: 1, name: "John", email: "john@example.com"}

      MnesiaEx.Query.get_by!(:users, :email, "nonexistent@example.com")
      #=> ** (RuntimeError) Transaction aborted: :not_found
  """
  @spec get_by!(atom(), atom(), term()) :: map() | no_return()
  def get_by!(table, field, value) do
    get_by(table, field, value)
    |> unwrap_result_or_raise!()
  end

  # Update operations

  @doc """
  Updates an existing record in the specified table.

  Automatically creates a transaction if not already in one.
  Returns `{:ok, updated_record}` on success or `{:error, reason}` on failure.

  ## Examples

      # Single operation (auto-transaction)
      {:ok, user} = MnesiaEx.Query.update(:users, 1, %{name: "Jane"})

      # Inside manual transaction
      {:ok, {user, post}} = MnesiaEx.transaction(fn ->
        {:ok, user} = MnesiaEx.Query.update(:users, 1, %{name: "Jane"})
        {:ok, post} = MnesiaEx.Query.update(:posts, 100, %{title: "Updated"})
        {user, post}
      end)
  """
  @spec update(table(), key(), map() | any(), Keyword.t()) :: result()
  def update(table, id, attrs, opts \\ [])

  def update(table, id, attrs_or_value, opts) do
    safe_check_in_transaction()
    |> safe_update_with_context(table, id, attrs_or_value, opts)
  end

  defp safe_update_with_context({:ok, true}, table, id, attrs_or_value, opts) do
    update_core(table, id, attrs_or_value, opts)
  end

  defp safe_update_with_context({:ok, false}, table, id, attrs_or_value, opts) do
    MnesiaEx.transaction(fn ->
      update_core(table, id, attrs_or_value, opts)
      |> unwrap_or_abort()
    end)
  end

  defp update_core(table, id, %{} = attrs, opts) do
    Error.m do
      existing <- read_core(table, id)
      updated <- Map.merge(existing, attrs) |> Error.return()
      _ <- safe_validate_unique_fields(table, updated, Keyword.get(opts, :unique_fields, []))
      fields <- safe_get_table_fields(table)
      safe_write_record(table, updated, fields)
    end
  end

  defp update_core(table, id, value, opts) do
    Error.m do
      fields <- safe_get_table_fields(table)
      second_field <- Enum.at(fields, 1) |> Error.return()
      attrs <- %{second_field => value} |> Error.return()
      update_core(table, id, attrs, opts)
    end
  end

  @doc """
  Updates a record in a transaction.

  Returns the updated record directly or raises if not found.

  ## Examples

      user = MnesiaEx.Query.update!(:users, 1, %{name: "Jane"})
      #=> %{id: 1, name: "Jane", email: "john@example.com"}

      MnesiaEx.Query.update!(:users, 999, %{name: "Unknown"})
      #=> ** (RuntimeError) Transaction aborted: :not_found
  """
  @spec update!(table(), key(), map(), Keyword.t()) :: map() | no_return()
  def update!(table, id, attrs, opts \\ []) do
    update(table, id, attrs, opts)
    |> unwrap_result_or_raise!()
  end

  # Upsert operations

  @doc """
  Updates a record if it exists, or creates it if it doesn't.

  Automatically creates a transaction if not already in one.
  Returns `{:ok, record}` on success or `{:error, reason}` on failure.

  ## Examples

      # Single operation (auto-transaction)
      {:ok, user} = MnesiaEx.Query.upsert(:users, %{id: 1, name: "John"})

      # Inside manual transaction
      {:ok, user} = MnesiaEx.transaction(fn ->
        {:ok, user} = MnesiaEx.Query.upsert(:users, %{id: 1, name: "John"})
        {:ok, user}
      end)
  """
  @spec upsert(table(), map()) :: {:ok, map()} | {:error, term()}
  def upsert(table, record) do
    safe_check_in_transaction()
    |> safe_upsert_with_context(table, record)
  end

  defp safe_upsert_with_context({:ok, true}, table, record) do
    upsert_core(table, record)
  end

  defp safe_upsert_with_context({:ok, false}, table, record) do
    MnesiaEx.transaction(fn ->
      upsert_core(table, record)
      |> unwrap_or_abort()
    end)
  end

  defp upsert_core(table, record) do
    record_id = Map.get(record, :id)

    read_core(table, record_id)
    |> handle_upsert_read_result(table, record_id, record)
  end

  defp handle_upsert_read_result({:ok, _existing}, table, record_id, record) do
    update_core(table, record_id, record, [])
  end

  defp handle_upsert_read_result({:error, :not_found}, table, _record_id, record) do
    write_core(table, record, [])
  end

  defp handle_upsert_read_result({:error, reason}, _table, _record_id, _record) do
    Error.fail(reason)
  end

  @doc """
  Upserts a record in a transaction (update if exists, insert if not).

  Returns the upserted record directly or raises on error.

  ## Examples

      # Insert new record
      user = MnesiaEx.Query.upsert!(:users, %{id: 1, name: "John"})
      #=> %{id: 1, name: "John"}

      # Update existing record
      user = MnesiaEx.Query.upsert!(:users, %{id: 1, name: "Jane"})
      #=> %{id: 1, name: "Jane"}
  """
  @spec upsert!(table(), map()) :: map() | no_return()
  def upsert!(table, record) do
    upsert(table, record)
    |> unwrap_result_or_raise!()
  end

  # Pure functions - Match specification building

  defp build_match_spec(table, fields, conditions, return_fields) do
    match_head = build_match_head(table, fields)
    guards = build_guards(fields, conditions)
    [{match_head, guards, return_fields}]
  end

  defp build_match_head(table, fields) do
    List.to_tuple([table | Enum.map(1..length(fields), &:"$#{&1}")])
  end

  defp build_guards(fields, conditions) do
    Enum.map(conditions, fn {field, operator, value} ->
      position = Enum.find_index(fields, &(&1 == field)) + 1
      {operator, :"$#{position}", value}
    end)
  end

  defp build_delete_tuple(table, table_fields, fields) do
    List.to_tuple([table | Enum.map(table_fields, &Map.get(fields, &1))])
  end

  @doc """
  Deletes multiple records.

  Automatically creates a transaction if not already in one.
  Returns a list of deleted records (empty list if none deleted).

  ## Examples

      # Single operation (auto-transaction)
      deleted = MnesiaEx.Query.batch_delete(:users, [1, 2, 3])
      #=> [%{id: 1, name: "John"}, %{id: 2, name: "Jane"}, ...]

      # Inside manual transaction
      {:ok, result} = MnesiaEx.transaction(fn ->
        users = MnesiaEx.Query.batch_delete(:users, [1, 2])
        posts = MnesiaEx.Query.batch_delete(:posts, [100, 101])
        {users, posts}
      end)
  """
  @spec batch_delete(table(), [key() | map()]) :: [map()]
  def batch_delete(table, keys_or_fields) when is_list(keys_or_fields) do
    safe_check_in_transaction()
    |> safe_batch_delete_with_context(table, keys_or_fields)
    |> unwrap_list_or_raise!()
  end

  defp safe_batch_delete_with_context({:ok, true}, table, keys_or_fields) do
    batch_delete_core(table, keys_or_fields)
  end

  defp safe_batch_delete_with_context({:ok, false}, table, keys_or_fields) do
    MnesiaEx.transaction(fn ->
      batch_delete_core(table, keys_or_fields)
      |> unwrap_or_abort()
    end)
  end

  defp batch_delete_core(table, keys_or_fields) do
    batch_delete_recursive(table, keys_or_fields, [])
  end

  defp batch_delete_recursive(_table, [], acc), do: Error.return(Enum.reverse(acc))

  defp batch_delete_recursive(table, [key_or_field | rest], acc) do
    Error.m do
      deleted <- delete_core(table, key_or_field)
      batch_delete_recursive(table, rest, [deleted | acc])
    end
  end

end
