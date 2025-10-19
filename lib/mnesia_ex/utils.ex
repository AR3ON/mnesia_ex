defmodule MnesiaEx.Utils do
  @moduledoc """
  Provides utility functions for data manipulation in MnesiaEx.
  """

  require MnesiaEx.Monad, as: Error

  @type table :: atom()
  @type record :: tuple()
  @type result :: {:ok, map()} | {:error, term()}

  @doc """
  Converts a Mnesia tuple or list of tuples into a map or list of maps.

  ## Examples

      iex> MnesiaEx.Utils.tuple_to_map({:users, 1, "John", "john@example.com"})
      %{id: 1, name: "John", email: "john@example.com"}

      iex> MnesiaEx.Utils.tuple_to_map([{:users, 1, "John"}, {:users, 2, "Jane"}])
      [%{id: 1, name: "John"}, %{id: 2, name: "Jane"}]

      iex> MnesiaEx.Utils.tuple_to_map({:users, 1})
      %{id: 1}
  """
  def tuple_to_map(records) when is_list(records) do
    build_maps_from_records(records, [])
  end

  def tuple_to_map({table, key}) when is_atom(table) do
    table_key(table)
    |> build_key_map(key)
  end

  def tuple_to_map(record) when is_tuple(record) and tuple_size(record) > 0 do
    transform_record_to_map(record)
  end

  def tuple_to_map(_), do: %{}

  defp build_key_map({:ok, key_field}, key), do: %{key_field => key}
  defp build_key_map(_, key), do: %{id: key}

  @doc """
  Converts a map into a Mnesia tuple.

  ## Examples

      iex> MnesiaEx.Utils.map_to_tuple(:users, %{id: 1, name: "John", email: "john@example.com"})
      {:ok, {:users, 1, "John", "john@example.com"}}

      iex> MnesiaEx.Utils.map_to_tuple(:users, %{invalid: "data"})
      {:error, :missing_fields}
  """
  @spec map_to_tuple(table(), map()) :: {:ok, record()} | {:error, term()}
  def map_to_tuple(table, map) when is_atom(table) and is_map(map) do
    Error.m do
      fields <- safe_get_table_fields(table)
      values <- safe_extract_field_values(fields, map)
      build_tuple_from_table_and_values(table, values)
    end
  end

  def map_to_tuple(_, _), do: Error.fail(:invalid_arguments)

  @doc """
  Validates that a map contains all required fields for a table.

  ## Examples

      iex> MnesiaEx.Utils.validate_required_fields(:users, %{id: 1, name: "John"})
      :ok

      iex> MnesiaEx.Utils.validate_required_fields(:users, %{id: 1})
      {:error, {:missing_fields, [:name]}}
  """
  @spec validate_required_fields(table(), map()) :: :ok | {:error, {:missing_fields, [atom()]}}
  def validate_required_fields(table, map) when is_atom(table) and is_map(map) do
    Error.m do
      fields <- safe_get_table_fields(table)
      validate_fields_present(fields, map)
    end
  end

  def validate_required_fields(_, _), do: Error.fail(:invalid_arguments)

  @doc """
  Gets the key field of a table.
  """
  def table_key(table) do
    Error.m do
      fields <- safe_get_table_fields(table)
      extract_first_field_as_key(fields)
    end
  end

  @doc """
  Checks if a field has an associated counter.
  """
  @spec has_counter?(table(), atom()) :: boolean()
  def has_counter?(table, field) do
    check_counter_in_properties(table, field)
  end

  @doc """
  Gets the autoincrement fields of a table.
  """
  @spec get_autoincrement_fields(table()) :: [atom()]
  def get_autoincrement_fields(table) do
    Error.m do
      key <- table_key(table)
      validate_autoincrement_field(table, key)
    end
    |> transform_autoincrement_result()
  end

  # Funciones puras - Transformación de datos

  defp build_maps_from_records([], acc), do: Enum.reverse(acc)

  defp build_maps_from_records([record | rest], acc) do
    map = transform_record_to_map(record)
    build_maps_from_records(rest, [map | acc])
  end

  defp transform_record_to_map(record) when is_tuple(record) and tuple_size(record) > 0 do
    table = elem(record, 0)
    values = Tuple.delete_at(record, 0) |> Tuple.to_list()
    fields = safe_fetch_table_attributes(table)

    build_validated_map(fields, values)
  end

  defp transform_record_to_map(_), do: %{}

  defp build_validated_map(fields, values) when length(fields) == length(values) do
    Enum.zip(fields, values)
    |> Enum.into(%{})
  end

  defp build_validated_map(_fields, _values), do: %{}

  defp safe_get_table_fields(table) when is_atom(table) do
    Error.m do
      _ <- validate_mnesia_running()
      fields <- fetch_table_attributes_if_exists(table)
      Error.return(fields)
    end
  end

  defp safe_get_table_fields(_), do: Error.fail(:invalid_table_name)

  defp validate_mnesia_running() do
    :mnesia.system_info(:is_running)
    |> handle_mnesia_status()
  end

  defp handle_mnesia_status(:yes), do: Error.return(:ok)
  defp handle_mnesia_status(:no), do: Error.fail(:mnesia_not_running)
  defp handle_mnesia_status(:stopping), do: Error.fail(:mnesia_stopping)
  defp handle_mnesia_status(_), do: Error.fail(:unknown_mnesia_state)

  defp fetch_table_attributes_if_exists(table) do
    table_exists?(table)
    |> handle_table_existence(table)
  end

  defp handle_table_existence(true, table),
    do: Error.return(:mnesia.table_info(table, :attributes))

  defp handle_table_existence(false, _table), do: Error.fail(:table_not_found)

  defp table_exists?(table) do
    :mnesia.system_info(:tables)
    |> Enum.member?(table)
  end

  defp safe_fetch_table_attributes(table) do
    :mnesia.table_info(table, :attributes)
  end

  defp safe_extract_field_values(fields, map) do
    values = Enum.map(fields, &Map.get(map, &1))
    validate_no_nil_values(values)
  end

  defp validate_no_nil_values(values) do
    Enum.any?(values, &is_nil/1)
    |> handle_nil_validation(values)
  end

  defp handle_nil_validation(true, _values), do: Error.fail(:missing_fields)
  defp handle_nil_validation(false, values), do: Error.return(values)

  defp build_tuple_from_table_and_values(table, values) do
    Error.return(List.to_tuple([table | values]))
  end

  defp validate_fields_present(fields, map) do
    (fields -- Map.keys(map))
    |> handle_missing_fields()
  end

  defp handle_missing_fields([]), do: :ok
  defp handle_missing_fields(missing), do: Error.fail({:missing_fields, missing})

  defp extract_first_field_as_key([key | _]), do: Error.return(key)
  defp extract_first_field_as_key([]), do: Error.fail(:no_fields)

  defp check_counter_in_properties(table, field) do
    table_exists?(table)
    |> fetch_properties_if_exists(table, field)
  end

  defp fetch_properties_if_exists(true, table, field) do
    :mnesia.table_info(table, :user_properties)
    |> check_counter_in_properties_list(field)
  end

  defp fetch_properties_if_exists(false, _table, _field), do: false

  defp check_counter_in_properties_list(properties, field) when is_list(properties) do
    Enum.any?(properties, fn
      {:field_type, ^field, :autoincrement} -> true
      _ -> false
    end)
  end

  defp check_counter_in_properties_list(_, _), do: false

  defp validate_autoincrement_field(table, key) do
    has_counter?(table, key)
    |> handle_counter_validation(key)
  end

  defp handle_counter_validation(true, key), do: Error.return(key)
  defp handle_counter_validation(false, _key), do: Error.fail(:no_counter)

  defp transform_autoincrement_result({:ok, key}), do: [key]
  defp transform_autoincrement_result(_), do: []

  @doc """
  Converts a Mnesia record (tuple) to a map.
  """
  def record_to_map(records) when is_list(records) do
    build_maps_from_records(records, [])
  end

  def record_to_map(record) when is_tuple(record) do
    transform_record_to_map(record)
  end

  def record_to_map(nil), do: %{}
  def record_to_map(_), do: %{}

  @doc """
  Converts a map to a Mnesia record (tuple).
  """
  def map_to_record(table, attrs) when is_map(attrs) do
    fields = safe_fetch_table_attributes(table)
    values = Enum.map(fields, &Map.get(attrs, &1))
    List.to_tuple([table | values])
  end

  @doc """
  Converts a map to a tuple for storing in Mnesia.
  """
  def map_to_tuple(map) when is_map(map) do
    map
    |> Map.to_list()
    |> Enum.sort_by(fn {k, _v} -> k end)
    |> Enum.map(fn {_k, v} -> v end)
    |> List.to_tuple()
  end
end
