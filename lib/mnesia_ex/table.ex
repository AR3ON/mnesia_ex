defmodule MnesiaEx.Table do
  @moduledoc """
  Table management and administration for Mnesia.

  This module handles all aspects of table lifecycle: creation, configuration,
  distribution, indexing, and schema migrations.

  ## Key Functions

  ### Lifecycle
  - `create/2` - Create table with rich options
  - `drop/1` - Delete table permanently
  - `clear/1` - Remove all records
  - `exists?/1` - Check if table exists

  ### Information
  - `info/1` - Get structured table metadata
  - `get_storage_type/1` - Check storage configuration

  ### Indexing
  - `add_index/2` - Add secondary index for faster queries
  - `remove_index/2` - Remove index

  ### Distribution
  - `add_copy/3` - Replicate table to another node
  - `remove_copy/2` - Remove replica from node
  - `change_copy_type/2` - Change storage type on node

  ### Migrations
  - `transform/3` - Migrate table structure with data

  ## Examples

      # Create table with options
      MnesiaEx.Table.create(:users, [
        attributes: [:id, :name, :email],
        index: [:email],
        disc_copies: [node()]
      ])

      # Get table info
      {:ok, info} = MnesiaEx.Table.info(:users)
      # => %{attributes: [:id, :name, :email], type: :set, size: 100, ...}

      # Add replica to cluster
      MnesiaEx.Table.add_copy(:users, :"node2@host", :disc_copies)

      # Migrate schema
      transform_fn = fn {_, id, name} -> {_, id, name, DateTime.utc_now()} end
      MnesiaEx.Table.transform(:users, [:id, :name, :inserted_at], transform_fn)
  """

  require MnesiaEx.Monad, as: Error

  alias MnesiaEx.Counter

  @type table :: atom()
  @type result :: {:ok, term()} | {:error, term()}
  @type table_type :: :set | :ordered_set | :bag

  @doc """
  Creates a new table with the specified options.

  ## Options

    * `:attributes` - List of table attributes (required)
    * `:type` - Table type (:set, :ordered_set, :bag)
    * `:persistence` - true to store on disk, false for memory (default false)
    * `:nodes` - List of nodes where to create the table (default [node()])
    * `:index` - List of indexed fields
    * `:majority` - Majority requirement for writes
    * `:load_order` - Table load order
    * `:counter_fields` - List of fields that should use automatic counter

  ## Examples

      iex> MnesiaEx.Table.create(:users, attributes: [:id, :name, :email], persistence: true)
      {:ok, %{table: :users, attributes: [:id, :name, :email]}}

      iex> MnesiaEx.Table.create(:orders,
      ...>   attributes: [:order_number, :user_id, :total],
      ...>   counter_fields: [:order_number],
      ...>   index: [:user_id],
      ...>   persistence: true,
      ...>   nodes: [:"node1@host", :"node2@host"]
      ...> )
      {:ok, %{table: :orders, attributes: [:order_number, :user_id, :total], indexes: [:user_id]}}

  """
  @spec create(table(), Keyword.t()) :: result()
  def create(name, opts) do
    Error.m do
      attributes <- safe_validate_attributes(opts)
      config <- build_table_config(opts)
      _ <- safe_validate_counter_fields(attributes, config.counter_fields)
      _ <- safe_validate_no_index_on_counter_fields(config.index, config.counter_fields)
      _ <- safe_ensure_mnesia_running()
      _ <- safe_check_table_not_exists(name)
      _ <- safe_handle_persistence(config.persistence, config.nodes)
      _ <- Counter.ensure_counter_table(config.nodes)
      table_opts <- build_mnesia_table_opts(attributes, config)
      _ <- :mnesia.create_table(name, table_opts) |> transform_create_table_result()
      _ <- safe_initialize_counters(name, config.counter_fields)
      Error.return(build_table_info(name, attributes, config))
    end
  end

  @doc """
  Creates a new table with the specified options (raises on error).

  ## Examples

      iex> MnesiaEx.Table.create!(:users, attributes: [:id, :name, :email], persistence: true)
      %{table: :users, attributes: [:id, :name, :email]}

  """
  @spec create!(table(), Keyword.t()) :: map() | no_return()
  def create!(name, opts) do
    create(name, opts)
    |> unwrap_or_raise!("Failed to create table")
  end

  @doc """
  Deletes a table.

  ## Examples

      iex> MnesiaEx.Table.drop(:users)
      {:ok, :deleted}

      iex> MnesiaEx.Table.drop(:nonexistent_table)
      {:error, :not_found}
  """
  @spec drop(table()) :: result()
  def drop(table) when is_atom(table) do
    Error.m do
      counter_fields <- fetch_counter_fields(table)
      _ <- :mnesia.delete_table(table) |> atomic_to_monad()
      _ <- safe_delete_counters(table, counter_fields)
      Error.return(:dropped)
    end
  end

  @doc """
  Deletes a table (raises on error).

  ## Examples

      iex> MnesiaEx.Table.drop!(:users)
      :deleted

  """
  @spec drop!(table()) :: :deleted | no_return()
  def drop!(table) when is_atom(table) do
    drop(table)
    |> unwrap_or_raise!("Failed to drop table")
  end

  @doc """
  Clears all records from a table.

  ## Examples

      iex> MnesiaEx.Table.clear(:users)
      {:ok, :cleared}

      iex> MnesiaEx.Table.clear(:nonexistent_table)
      {:error, :no_exists}
  """
  @spec clear(table()) :: {:ok, :cleared} | {:error, term()}
  def clear(table) when is_atom(table) do
    :mnesia.clear_table(table)
    |> atomic_to_monad()
    |> transform_clear_result()
  end

  defp transform_clear_result({:ok, :ok}), do: Error.return(:cleared)
  defp transform_clear_result({:error, reason}), do: Error.fail(reason)

  @doc """
  Clears all records from a table (raises on error).

  ## Examples

      iex> MnesiaEx.Table.clear!(:users)
      :cleared

  """
  @spec clear!(table()) :: :cleared | no_return()
  def clear!(table) when is_atom(table) do
    clear(table)
    |> unwrap_or_raise!("Failed to clear table")
  end

  @doc """
  Checks if a table exists.

  ## Examples

      iex> MnesiaEx.Table.exists?(:users)
      true

      iex> MnesiaEx.Table.exists?(:nonexistent_table)
      false
  """
  @spec exists?(table()) :: boolean()
  def exists?(table) when is_atom(table) do
    :mnesia.system_info(:tables) |> Enum.member?(table)
  end

  @doc """
  Gets information about a table.

  ## Examples

      iex> MnesiaEx.Table.info(:users)
      {:ok, %{
        attributes: [:id, :name, :email],
        type: :set,
        size: 10,
        memory: 1000,
        storage_type: :disc_copies,
        indexes: [:email]
      }}
  """
  @spec info(table()) :: result()
  def info(table) when is_atom(table) do
    Error.m do
      attributes <- safe_fetch_table_info(table, :attributes)
      type <- safe_fetch_table_info(table, :type)
      size <- safe_fetch_table_info(table, :size)
      memory <- safe_fetch_table_info(table, :memory)
      storage <- safe_determine_storage_type(table)
      index_positions <- safe_fetch_table_info(table, :index)
      indexes <- transform_index_positions_to_names(attributes, index_positions)

      Error.return(%{
        attributes: attributes,
        type: type,
        size: size,
        memory: memory,
        storage_type: storage,
        indexes: indexes
      })
    end
  end

  @doc """
  Gets information about a table.

  Returns the table metadata map directly or raises if the table doesn't exist.

  ## Examples

      iex> MnesiaEx.Table.info!(:users)
      %{
        attributes: [:id, :name, :email],
        type: :set,
        size: 10,
        memory: 1000,
        ...
      }
  """
  @spec info!(table()) :: map() | no_return()
  def info!(table) do
    info(table)
    |> unwrap_or_raise!("Table info not found")
  end

  @doc """
  Copies a table to another node.

  ## Examples

      iex> MnesiaEx.Table.add_copy(:users, :node@host, :disc_copies)
      {:ok, %{table: :users, node: :node@host, type: :disc_copies}}

  """
  @spec add_copy(table(), node(), :ram_copies | :disc_copies) :: result()
  def add_copy(table, node, type) do
    :mnesia.add_table_copy(table, node, type)
    |> atomic_to_monad()
    |> Error.bind(fn :ok -> Error.return(%{table: table, node: node, type: type}) end)
  end

  @doc """
  Copies a table to another node (raises on error).

  ## Examples

      iex> MnesiaEx.Table.add_copy!(:users, :node@host, :disc_copies)
      %{table: :users, node: :node@host, type: :disc_copies}

  """
  @spec add_copy!(table(), node(), :ram_copies | :disc_copies) :: map() | no_return()
  def add_copy!(table, node, type) do
    add_copy(table, node, type)
    |> unwrap_or_raise!("Failed to add table copy")
  end

  @doc """
  Removes a table copy from a node.

  ## Examples

      iex> MnesiaEx.Table.remove_copy(:users, :node@host)
      {:ok, %{table: :users, node: :node@host}}

  """
  @spec remove_copy(table(), node()) :: result()
  def remove_copy(table, node) do
    :mnesia.del_table_copy(table, node)
    |> atomic_to_monad()
    |> Error.bind(fn :ok -> Error.return(%{table: table, node: node}) end)
  end

  @doc """
  Removes a table copy from a node (raises on error).

  ## Examples

      iex> MnesiaEx.Table.remove_copy!(:users, :node@host)
      %{table: :users, node: :node@host}

  """
  @spec remove_copy!(table(), node()) :: map() | no_return()
  def remove_copy!(table, node) do
    remove_copy(table, node)
    |> unwrap_or_raise!("Failed to remove table copy")
  end

  @doc """
  Changes the copy type of a table on a node.

  ## Examples

      iex> MnesiaEx.Table.change_copy_type(:users, :node@host, :disc_copies)
      {:ok, %{table: :users, node: :node@host, type: :disc_copies}}

  """
  @spec change_copy_type(table(), node(), :ram_copies | :disc_copies) :: result()
  def change_copy_type(table, node, type) do
    :mnesia.change_table_copy_type(table, node, type)
    |> atomic_to_monad()
    |> Error.bind(fn :ok -> Error.return(%{table: table, node: node, type: type}) end)
  end

  @doc """
  Changes the copy type of a table on a node (raises on error).

  ## Examples

      iex> MnesiaEx.Table.change_copy_type!(:users, :node@host, :disc_copies)
      %{table: :users, node: :node@host, type: :disc_copies}

  """
  @spec change_copy_type!(table(), node(), :ram_copies | :disc_copies) :: map() | no_return()
  def change_copy_type!(table, node, type) do
    change_copy_type(table, node, type)
    |> unwrap_or_raise!("Failed to change copy type")
  end

  @doc """
  Persists the Mnesia schema on the specified nodes.

  ## Examples

      iex> MnesiaEx.Table.persist_schema([:"node1@host", :"node2@host"])
      {:ok, :persisted}

  """
  @spec persist_schema([node()]) :: result()
  def persist_schema([]), do: Error.return(:persisted)

  def persist_schema(nodes) when is_list(nodes) do
    safe_persist_schema_nodes(nodes)
  end

  @doc """
  Persists the Mnesia schema on the specified nodes (raises on error).

  ## Examples

      iex> MnesiaEx.Table.persist_schema!([:"node1@host", :"node2@host"])
      :persisted

  """
  @spec persist_schema!([node()]) :: :persisted | no_return()
  def persist_schema!(nodes) when is_list(nodes) do
    persist_schema(nodes)
    |> unwrap_or_raise!("Failed to persist schema")
  end

  defp safe_persist_schema_nodes([]), do: Error.return(:persisted)

  defp safe_persist_schema_nodes([node | rest]) do
    Error.m do
      _ <-
        :mnesia.change_table_copy_type(:schema, node, :disc_copies)
        |> atomic_to_monad_ignore_schema()

      safe_persist_schema_nodes(rest)
    end
  end

  @doc """
  Adds an index to an existing table.

  ## Examples

      iex> MnesiaEx.Table.add_index(:users, :email)
      {:ok, :indexed}

  """
  @spec add_index(table(), atom()) :: {:ok, :indexed} | {:error, term()}
  def add_index(table, field) when is_atom(field) do
    :mnesia.add_table_index(table, field)
    |> atomic_to_monad_ignore_schema()
    |> transform_index_result()
  end

  defp transform_index_result({:ok, :ok}), do: Error.return(:indexed)
  defp transform_index_result({:error, reason}), do: Error.fail(reason)

  @doc """
  Adds an index to an existing table (raises on error).

  ## Examples

      iex> MnesiaEx.Table.add_index!(:users, :email)
      :indexed

  """
  @spec add_index!(table(), atom()) :: :indexed | no_return()
  def add_index!(table, field) when is_atom(field) do
    add_index(table, field)
    |> unwrap_or_raise!("Failed to add index")
  end

  @doc """
  Removes an index from a table.

  ## Examples

      iex> MnesiaEx.Table.remove_index(:users, :email)
      {:ok, :removed}

  """
  @spec remove_index(table(), atom()) :: {:ok, :removed} | {:error, term()}
  def remove_index(table, field) when is_atom(field) do
    :mnesia.del_table_index(table, field)
    |> atomic_to_monad()
    |> transform_remove_index_result()
  end

  defp transform_remove_index_result({:ok, :ok}), do: Error.return(:removed)
  defp transform_remove_index_result({:ok, value}), do: Error.return(value)
  defp transform_remove_index_result({:error, reason}), do: Error.fail(reason)

  @doc """
  Removes an index from a table (raises on error).

  ## Examples

      iex> MnesiaEx.Table.remove_index!(:users, :email)
      :removed

  """
  @spec remove_index!(table(), atom()) :: :removed | no_return()
  def remove_index!(table, field) when is_atom(field) do
    remove_index(table, field)
    |> unwrap_or_raise!("Failed to remove index")
  end

  @doc """
  Gets the storage type of a table.

  Returns the storage type used by the table.

  ## Returns

    - `:disc_copies` - Table is stored on disk and in memory
    - `:ram_copies` - Table is stored only in memory
    - `:disc_only_copies` - Table is stored only on disk
    - `:unknown` - Unable to determine storage type

  ## Examples

      iex> MnesiaEx.Table.get_storage_type(:users)
      :disc_copies

      iex> MnesiaEx.Table.get_storage_type(:cache)
      :ram_copies
  """
  @spec get_storage_type(table()) :: :disc_copies | :ram_copies | :disc_only_copies | :unknown
  def get_storage_type(table) when is_atom(table) do
    determine_storage_type(table)
  end

  @doc """
  Transforms a table by applying a function to all records.

  Useful for schema migrations when you need to change the structure
  of existing records or add new attributes.

  ## Parameters

    - `table` - The table to transform
    - `new_attributes` - New list of attributes after transformation
    - `transform_fun` - Function that transforms old record to new record

  ## Examples

      # Add new field with default value
      iex> transform = fn {_table, id, name, email} ->
      ...>   {_table, id, name, email, DateTime.utc_now()}
      ...> end
      iex> MnesiaEx.Table.transform(:users, [:id, :name, :email, :inserted_at], transform)
      {:ok, :transformed}

      # Using with maps
      iex> transform = fn old_record ->
      ...>   old_record
      ...>   |> Map.put(:version, 2)
      ...>   |> Map.put(:migrated_at, DateTime.utc_now())
      ...> end
      iex> MnesiaEx.Table.transform(:users, [:id, :name, :email, :version, :migrated_at], transform)
      {:ok, :transformed}
  """
  @spec transform(table(), [atom()], function()) :: result()
  def transform(table, new_attributes, transform_fun)
      when is_atom(table) and is_list(new_attributes) and is_function(transform_fun) do
    table
    |> table_exists?()
    |> execute_transform_if_exists(table, new_attributes, transform_fun)
  end

  @doc """
  Transforms a table by applying a function to all records (raises on error).

  ## Examples

      iex> transform = fn old_record -> Map.put(old_record, :version, 2) end
      iex> MnesiaEx.Table.transform!(:users, [:id, :name, :email, :version], transform)
      :transformed

  """
  @spec transform!(table(), [atom()], function()) :: :transformed | no_return()
  def transform!(table, new_attributes, transform_fun)
      when is_atom(table) and is_list(new_attributes) and is_function(transform_fun) do
    transform(table, new_attributes, transform_fun)
    |> unwrap_or_raise!("Failed to transform table")
  end

  defp execute_transform_if_exists(false, table, _new_attributes, _transform_fun) do
    Error.fail({:table_not_found, table})
  end

  defp execute_transform_if_exists(true, table, new_attributes, transform_fun) do
    :mnesia.transform_table(table, transform_fun, new_attributes)
    |> transform_transform_result()
  end

  defp transform_transform_result({:atomic, :ok}), do: Error.return(:transformed)
  defp transform_transform_result({:aborted, reason}), do: Error.fail(reason)

  @doc """
  Alias for drop/1.
  """
  def delete(table), do: drop(table)

  # Pure functions - Validation

  defp safe_validate_attributes(opts) do
    Keyword.fetch(opts, :attributes)
    |> validate_attributes_result()
  end

  defp validate_attributes_result({:ok, attributes})
       when is_list(attributes) and length(attributes) >= 2 do
    Error.return(attributes)
  end

  defp validate_attributes_result({:ok, _}), do: Error.fail(:insufficient_attributes)
  defp validate_attributes_result(_), do: Error.fail(:missing_attributes)

  defp safe_check_table_not_exists(table) do
    exists?(table)
    |> validate_not_exists()
  end

  defp validate_not_exists(true), do: Error.fail(:already_exists)
  defp validate_not_exists(false), do: Error.return(:ok)

  defp safe_validate_counter_fields(attributes, counter_fields) do
    Enum.all?(counter_fields, &(&1 in attributes))
    |> validate_fields_existence()
  end

  defp validate_fields_existence(true), do: Error.return(:ok)
  defp validate_fields_existence(false), do: Error.fail(:invalid_counter_fields)

  defp safe_validate_no_index_on_counter_fields(index_fields, counter_fields) do
    index_fields
    |> Enum.filter(&(&1 in counter_fields))
    |> validate_no_conflicts()
  end

  defp validate_no_conflicts([]), do: Error.return(:ok)
  defp validate_no_conflicts(conflicts), do: Error.fail({:cannot_index_counter_fields, conflicts})

  # Pure functions - Configuration building

  defp build_table_config(opts) do
    config = %{
      type: Keyword.get(opts, :type, :set),
      persistence: Keyword.get(opts, :persistence, false),
      nodes: Keyword.get(opts, :nodes, [node()]),
      majority: Keyword.get(opts, :majority, false),
      load_order: Keyword.get(opts, :load_order, 0),
      index: Keyword.get(opts, :index, []),
      counter_fields: Keyword.get(opts, :counter_fields, [])
    }

    Error.return(config)
  end

  defp build_mnesia_table_opts(attributes, config) do
    user_props = Enum.map(config.counter_fields, &{:field_type, &1, :autoincrement})
    storage_type = storage_type_from_persistence(config.persistence)

    Error.return([
      {:attributes, attributes},
      {:type, config.type},
      {:majority, config.majority},
      {:load_order, config.load_order},
      {:access_mode, :read_write},
      {:index, config.index},
      {:user_properties, user_props},
      {storage_type, config.nodes}
    ])
  end

  defp storage_type_from_persistence(true), do: :disc_copies
  defp storage_type_from_persistence(false), do: :ram_copies

  defp build_table_info(name, attributes, config) do
    %{
      table: name,
      attributes: attributes,
      type: config.type,
      indexes: config.index,
      counter_fields: config.counter_fields,
      persistence: config.persistence,
      nodes: config.nodes
    }
  end

  defp transform_index_positions_to_names(attributes, positions)
       when is_list(positions) and is_list(attributes) do
    indexed_attrs =
      positions
      |> Enum.filter(&is_integer/1)
      |> Enum.map(fn pos -> Enum.at(attributes, pos - 2) end)
      |> Enum.reject(&is_nil/1)

    Error.return(indexed_attrs)
  end

  # Safe functions - Mnesia operations

  defp safe_ensure_mnesia_running do
    :mnesia.system_info(:is_running)
    |> handle_mnesia_running_status()
  end

  defp handle_mnesia_running_status(:yes), do: Error.return(:ok)

  defp handle_mnesia_running_status(:no) do
    :mnesia.start() |> transform_mnesia_start_result()
  end

  defp handle_mnesia_running_status(:stopping), do: Error.fail(:mnesia_stopping)
  defp handle_mnesia_running_status({:error, _reason} = error), do: error

  defp transform_mnesia_start_result(:ok), do: Error.return(:ok)
  defp transform_mnesia_start_result({:error, {:already_started, _}}), do: Error.return(:ok)
  defp transform_mnesia_start_result({:error, reason}), do: Error.fail({:mnesia_start_failed, reason})

  defp safe_handle_persistence(true, nodes) do
    :mnesia.table_info(:schema, :disc_copies) |> transform_schema_info(nodes)
  end

  defp safe_handle_persistence(false, _nodes), do: Error.return(:ok)

  defp transform_schema_info({:aborted, reason}, _nodes), do: Error.fail({:schema_info_failed, reason})
  defp transform_schema_info(disc_copies, nodes), do: safe_persist_schema_on_nodes(disc_copies, nodes)

  defp transform_create_table_result({:atomic, :ok}), do: Error.return(:ok)

  defp transform_create_table_result({:aborted, {:already_exists, _}}),
    do: Error.fail(:already_exists)

  defp transform_create_table_result({:aborted, {:bad_type, table, reason}}),
    do: Error.fail({:table_metadata_corrupted, table, reason})

  defp transform_create_table_result({:aborted, reason}), do: Error.fail(reason)
  defp transform_create_table_result(other), do: Error.fail({:unexpected_result, other})

  defp safe_initialize_counters(_table, []), do: Error.return(:ok)

  defp safe_initialize_counters(table, [field | rest]) do
    Error.m do
      _ <- Counter.init_counter(table, field)
      safe_initialize_counters(table, rest)
    end
  end

  defp atomic_to_monad({:atomic, :ok}), do: Error.return(:ok)
  defp atomic_to_monad({:atomic, value}), do: Error.return(value)
  defp atomic_to_monad({:aborted, reason}), do: Error.fail(reason)

  defp safe_delete_counters(_table, []), do: Error.return(:ok)

  defp safe_delete_counters(table, [field | rest]) do
    Error.m do
      _ <- Counter.delete_counter(table, field)
      safe_delete_counters(table, rest)
    end
  end

  defp safe_fetch_table_info(table, key) when is_atom(table) do
    fetch_if_table_exists(table_exists?(table), table, key)
  end

  defp safe_fetch_table_info(_table, _key), do: Error.fail(:invalid_table_name)

  defp fetch_if_table_exists(true, table, key) do
    :mnesia.table_info(table, key) |> transform_table_info_result()
  end

  defp fetch_if_table_exists(false, _table, _key), do: Error.fail(:table_not_found)

  defp transform_table_info_result({:aborted, reason}), do: Error.fail({:table_info_failed, reason})
  defp transform_table_info_result(value), do: Error.return(value)

  defp table_exists?(table) do
    :mnesia.system_info(:tables)
    |> Enum.member?(table)
  end

  defp safe_determine_storage_type(table) do
    storage_type = determine_storage_type(table)
    Error.return(storage_type)
  end

  defp determine_storage_type(table) do
    table
    |> table_exists?()
    |> get_storage_for_existing_table(table)
  end

  defp get_storage_for_existing_table(false, _table), do: :unknown

  defp get_storage_for_existing_table(true, table) do
    [:disc_copies, :ram_copies, :disc_only_copies]
    |> Enum.find_value(:unknown, fn type ->
      table
      |> get_table_info_safe(type)
      |> storage_type_if_not_empty(type)
    end)
  end

  defp get_table_info_safe(table, key) do
    :mnesia.table_info(table, key)
  end

  defp storage_type_if_not_empty([], _type), do: nil
  defp storage_type_if_not_empty(_list, type), do: type

  defp fetch_counter_fields(table) when is_atom(table) do
    properties = fetch_user_properties_safe(table)
    Error.return(extract_counter_fields(properties))
  end

  defp fetch_counter_fields(_table), do: Error.return([])

  defp fetch_user_properties_safe(table) do
    table_exists?(table)
    |> get_user_properties_if_exists(table)
  end

  defp get_user_properties_if_exists(true, table), do: :mnesia.table_info(table, :user_properties)
  defp get_user_properties_if_exists(false, _table), do: []

  defp extract_counter_fields(properties) when is_list(properties) do
    Enum.flat_map(properties, fn
      {:field_type, field, :autoincrement} -> [field]
      _ -> []
    end)
  end

  defp extract_counter_fields(_), do: []

  defp atomic_to_monad_ignore_schema({:atomic, :ok}), do: Error.return(:ok)

  defp atomic_to_monad_ignore_schema({:aborted, {:already_exists, :schema, _, _}}),
    do: Error.return(:ok)

  defp atomic_to_monad_ignore_schema({:aborted, reason}), do: Error.fail(reason)

  defp safe_persist_schema_on_nodes([], nodes), do: persist_schema(nodes)
  defp safe_persist_schema_on_nodes(_disc_copies, _nodes), do: Error.return(:ok)

  # Utility functions

  # Helper for ! functions
  defp unwrap_or_raise!({:ok, value}, _message), do: value
  defp unwrap_or_raise!({:error, reason}, message), do: raise("#{message}: #{inspect(reason)}")
end
