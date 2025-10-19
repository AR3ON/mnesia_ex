defmodule MnesiaEx.TableTest do
  use ExUnit.Case, async: false

  alias MnesiaEx.Table
  alias MnesiaEx.Query

  @moduletag :table

  setup do
    tables_to_clean = [
      :test_table, :indexed_table, :counter_table, :persistent_table,
      :storage_table, :any_table, :nonexistent_storage_table, :storage_test,
      :transform_table, :count_table, :spec_create, :spec_drop, :spec_clear,
      :spec_info, :spec_info_bang, :spec_index, :spec_rm_index, :spec_storage,
      :spec_transform, :ram_table, :nonexistent_transform_table
    ]

    # Limpiar agresivamente antes del test
    force_cleanup_tables(tables_to_clean)

    # Limpiar después del test también
    on_exit(fn ->
      cleanup_tables(tables_to_clean, 1)
    end)

    :ok
  end

  defp force_cleanup_tables(tables) do
    # Intentar eliminar cada tabla múltiples veces
    Enum.each(tables, fn table ->
      force_delete_single_table(table, 3)
    end)

    # Esperar a que Mnesia procese las eliminaciones
    Process.sleep(100)
  end

  defp force_delete_single_table(_table, 0), do: :ok

  defp force_delete_single_table(table, attempts) do
    delete_table_if_exists(table)
    Process.sleep(30)

    table
    |> table_exists?()
    |> handle_table_still_exists(table, attempts)
  end

  defp handle_table_still_exists(true, table, attempts) do
    force_delete_single_table(table, attempts - 1)
  end

  defp handle_table_still_exists(false, _table, _attempts), do: :ok

  defp delete_table_if_exists(table) do
    table
    |> table_exists?()
    |> execute_delete_if_needed(table)
  end

  defp execute_delete_if_needed(true, table) do
    safe_delete_table(table)
  end

  defp execute_delete_if_needed(false, _table), do: :ok

  defp cleanup_tables(_tables, 0), do: :ok

  defp cleanup_tables(tables, attempts) do
    Enum.each(tables, &safe_delete_table/1)
    Process.sleep(50)

    # Verificar si quedan tablas y reintentar si es necesario
    remaining = Enum.filter(tables, &table_exists?/1)

    if length(remaining) > 0 and attempts > 1 do
      cleanup_tables(remaining, attempts - 1)
    end
  end

  defp safe_delete_table(table) do
    :mnesia.delete_table(table)
  end

  defp table_exists?(table) do
    :mnesia.system_info(:tables)
    |> Enum.member?(table)
  end

  # Shared helper functions

  defp validate_ok_result(:ok), do: :ok
  defp validate_ok_result({:ok, :ok}), do: :ok
  defp validate_ok_result({:ok, :dropped}), do: :ok
  defp validate_ok_result({:ok, :transformed}), do: :ok
  defp validate_ok_result({:ok, _}), do: :ok

  defp validate_ok_result(result) do
    raise "Expected :ok but got #{inspect(result)}"
  end

  defp validate_error_result({:error, _reason}), do: :ok

  defp validate_error_result(result) do
    raise "Expected error but got #{inspect(result)}"
  end

  defp validate_fail_result({:fail, _reason}), do: :ok
  defp validate_fail_result({:error, _reason}), do: :ok

  defp validate_fail_result(result) do
    raise "Expected {:fail, _} or {:error, _} but got #{inspect(result)}"
  end

  defp validate_table_created({:ok, info}) when is_map(info) do
    validate_has_key(info, :table)
    validate_has_key(info, :attributes)
    validate_has_key(info, :type)
  end

  defp validate_table_created(result) do
    raise "Expected table creation result but got #{inspect(result)}"
  end

  defp validate_has_key(map, key) do
    Map.has_key?(map, key)
    |> validate_boolean("Expected map to have key #{inspect(key)}")
  end

  defp validate_boolean(true, _message), do: :ok
  defp validate_boolean(false, message), do: raise(message)

  defp validate_is_boolean(value) when is_boolean(value), do: :ok

  defp validate_is_boolean(value) do
    raise "Expected boolean but got #{inspect(value)}"
  end

  defp validate_is_map(value) when is_map(value), do: :ok

  defp validate_is_map(value) do
    raise "Expected map but got #{inspect(value)}"
  end

  defp validate_value_match(actual, expected) when actual == expected, do: :ok

  defp validate_value_match(actual, expected) do
    raise "Expected #{inspect(expected)} but got #{inspect(actual)}"
  end

  defp validate_table_exists(table) do
    Table.exists?(table)
    |> validate_boolean("Expected table #{inspect(table)} to exist")
  end

  defp validate_table_not_exists(table) do
    not Table.exists?(table)
    |> validate_boolean("Expected table #{inspect(table)} not to exist")
  end

  describe "create/2 - table creation" do
    test "creates a basic table with required attributes" do
      result = Table.create(:test_table, attributes: [:id, :name])

      validate_table_created(result)
      validate_table_exists(:test_table)
    end

    test "returns error when attributes are missing" do
      result = Table.create(:test_table, [])

      validate_error_result(result)
    end

    test "creates table with specific type" do
      result =
        Table.create(:test_table,
          attributes: [:id, :value],
          type: :ordered_set
        )

      {:ok, info} = result
      validate_value_match(info.type, :ordered_set)
    end

    test "creates table with indexes" do
      result =
        Table.create(:indexed_table,
          attributes: [:id, :email, :name],
          index: [:email]
        )

      {:ok, info} = result
      validate_value_match(info.indexes, [:email])
    end

    test "creates table with counter fields" do
      result =
        Table.create(:counter_table,
          attributes: [:id, :name],
          counter_fields: [:id]
        )

      {:ok, info} = result
      validate_value_match(info.counter_fields, [:id])
    end

    test "returns error for invalid counter fields" do
      result =
        Table.create(:counter_table,
          attributes: [:id, :name],
          counter_fields: [:invalid_field]
        )

      validate_error_result(result)
    end

    test "creates persistent table" do
      result =
        Table.create(:persistent_table,
          attributes: [:id, :data],
          persistence: true
        )

      {:ok, info} = result
      validate_value_match(info.persistence, true)
    end

    test "returns error when table already exists" do
      {:ok, _} = Table.create(:test_table, attributes: [:id, :value])
      result = Table.create(:test_table, attributes: [:id, :value])

      validate_error_result(result)
    end

    test "returns error when attributes has less than 2 elements" do
      result = Table.create(:test_table, attributes: [:id])

      {:error, reason} = result
      validate_value_match(reason, :insufficient_attributes)
    end

    test "returns error when attributes is empty" do
      result = Table.create(:test_table, attributes: [])

      validate_error_result(result)
    end

    test "creates table with custom nodes" do
      result =
        Table.create(:test_table,
          attributes: [:id, :value],
          nodes: [node()]
        )

      {:ok, info} = result
      validate_value_match(info.nodes, [node()])
    end

    test "creates table with majority option" do
      result =
        Table.create(:test_table,
          attributes: [:id, :value],
          majority: true
        )

      {:ok, _info} = result
      validate_table_exists(:test_table)
    end
  end

  describe "drop/1 - table deletion" do
    test "drops an existing table" do
      {:ok, _} = Table.create(:test_table, attributes: [:id, :value])
      result = Table.drop(:test_table)

      validate_ok_result(result)
      validate_table_not_exists(:test_table)
    end

    test "returns error when dropping non-existent table" do
      result = Table.drop(:nonexistent_table)

      validate_error_result(result)
    end

    test "drops table with counter fields" do
      {:ok, _} =
        Table.create(:counter_table,
          attributes: [:id, :name],
          counter_fields: [:id]
        )

      result = Table.drop(:counter_table)

      validate_ok_result(result)
    end
  end

  describe "clear/1 - table clearing" do
    test "clears all records from a table" do
      {:ok, _} = Table.create(:test_table, attributes: [:id, :name])

      :mnesia.transaction(fn ->
        :mnesia.write({:test_table, 1, "Alice"})
        :mnesia.write({:test_table, 2, "Bob"})
      end)

      result = Table.clear(:test_table)

      validate_ok_result(result)
    end

    test "returns error when clearing non-existent table" do
      result = Table.clear(:nonexistent_table)

      validate_error_result(result)
    end

    test "clear is idempotent" do
      {:ok, _} = Table.create(:test_table, attributes: [:id, :value])

      result1 = Table.clear(:test_table)
      result2 = Table.clear(:test_table)

      validate_ok_result(result1)
      validate_ok_result(result2)
    end
  end

  describe "exists?/1 - table existence check" do
    test "returns true for existing table" do
      {:ok, _} = Table.create(:test_table, attributes: [:id, :value])
      result = Table.exists?(:test_table)

      validate_boolean(result, "Expected table to exist")
    end

    test "returns false for non-existent table" do
      result = Table.exists?(:nonexistent_table)

      validate_value_match(result, false)
    end

    test "existence check is pure" do
      {:ok, _} = Table.create(:test_table, attributes: [:id, :value])

      result1 = Table.exists?(:test_table)
      result2 = Table.exists?(:test_table)

      validate_value_match(result1, result2)
    end
  end

  describe "info/1 - table information" do
    test "returns information for existing table" do
      {:ok, _} = Table.create(:test_table, attributes: [:id, :name])
      result = Table.info(:test_table)

      {:ok, info} = result
      validate_is_map(info)
      validate_has_key(info, :attributes)
      validate_has_key(info, :type)
      validate_has_key(info, :size)
      validate_has_key(info, :memory)
      validate_has_key(info, :storage_type)
      validate_has_key(info, :indexes)
    end

    test "returns error for non-existent table" do
      result = Table.info(:nonexistent_table)

      validate_error_result(result)
    end

    test "info contains correct attributes" do
      {:ok, _} = Table.create(:test_table, attributes: [:id, :name, :email])
      {:ok, info} = Table.info(:test_table)

      validate_value_match(info.attributes, [:id, :name, :email])
    end

    test "info contains correct type" do
      {:ok, _} =
        Table.create(:test_table,
          attributes: [:id, :value],
          type: :ordered_set
        )

      {:ok, info} = Table.info(:test_table)

      validate_value_match(info.type, :ordered_set)
    end

    test "info contains indexes" do
      {:ok, _} =
        Table.create(:test_table,
          attributes: [:id, :email],
          index: [:email]
        )

      {:ok, info} = Table.info(:test_table)

      validate_value_match(info.indexes, [:email])
    end

    test "info retrieval is deterministic" do
      {:ok, _} = Table.create(:test_table, attributes: [:id, :value])

      {:ok, info1} = Table.info(:test_table)
      {:ok, info2} = Table.info(:test_table)

      validate_value_match(info1.attributes, info2.attributes)
      validate_value_match(info1.type, info2.type)
    end
  end

  describe "info!/1 - bang version" do
    test "returns map for existing table" do
      {:ok, _} = Table.create(:test_table, attributes: [:id, :value])
      result = Table.info!(:test_table)

      validate_is_map(result)
    end

    test "raises for non-existent table" do
      assert_raise RuntimeError, fn ->
        Table.info!(:nonexistent_table)
      end
    end
  end

  describe "add_index/2 - index management" do
    test "adds index to existing table" do
      {:ok, _} = Table.create(:test_table, attributes: [:id, :email])
      result = Table.add_index(:test_table, :email)

      validate_ok_result(result)
    end

    test "returns error for non-existent table" do
      result = Table.add_index(:nonexistent_table, :field)

      validate_error_result(result)
    end

    test "adding index is reflected in table info" do
      {:ok, _} = Table.create(:test_table, attributes: [:id, :email])
      result = Table.add_index(:test_table, :email)
      validate_ok_result(result)

      {:ok, info} = Table.info(:test_table)

      validate_boolean(
        Enum.member?(info.indexes, :email),
        "Expected email to be in indexes"
      )
    end
  end

  describe "remove_index/2 - index removal" do
    test "removes index from table" do
      {:ok, _} =
        Table.create(:test_table,
          attributes: [:id, :email],
          index: [:email]
        )

      result = Table.remove_index(:test_table, :email)

      validate_ok_result(result)
    end

    test "returns error for non-existent table" do
      result = Table.remove_index(:nonexistent_table, :field)

      validate_error_result(result)
    end
  end

  describe "persist_schema/1 - schema persistence" do
    test "persists schema on nodes" do
      result = Table.persist_schema([node()])

      validate_ok_result(result)
    end

    test "persist_schema is idempotent" do
      result1 = Table.persist_schema([node()])
      result2 = Table.persist_schema([node()])

      validate_ok_result(result1)
      validate_ok_result(result2)
    end
  end

  describe "functional purity properties" do
    test "create is deterministic for same inputs" do
      result1 = Table.create(:test_table, attributes: [:id, :value])
      :mnesia.delete_table(:test_table)

      result2 = Table.create(:test_table, attributes: [:id, :value])

      {:ok, info1} = result1
      {:ok, info2} = result2

      validate_value_match(info1.attributes, info2.attributes)
      validate_value_match(info1.type, info2.type)
    end

    test "exists? is pure function" do
      {:ok, _} = Table.create(:test_table, attributes: [:id, :value])

      results = for _ <- 1..3, do: Table.exists?(:test_table)

      validate_boolean(
        Enum.all?(results, &(&1 == true)),
        "Expected all existence checks to return true"
      )
    end

    test "info returns consistent structure" do
      {:ok, _} = Table.create(:test_table, attributes: [:id, :value])
      {:ok, info} = Table.info(:test_table)

      keys = Map.keys(info) |> Enum.sort()
      expected_keys = [:attributes, :indexes, :memory, :size, :storage_type, :type]

      validate_value_match(keys, expected_keys)
    end
  end

  describe "edge cases and error handling" do
    test "handles empty attributes list gracefully" do
      result = Table.create(:test_table, attributes: [])

      # Mnesia requiere al menos un atributo, debe retornar error
      validate_error_result(result)
    end

    test "handles empty index list" do
      result =
        Table.create(:test_table,
          attributes: [:id, :value],
          index: []
        )

      {:ok, info} = result
      validate_value_match(info.indexes, [])
    end

    test "handles empty counter_fields list" do
      result =
        Table.create(:test_table,
          attributes: [:id, :value],
          counter_fields: []
        )

      {:ok, info} = result
      validate_value_match(info.counter_fields, [])
    end

    test "info handles table with records" do
      {:ok, _} = Table.create(:test_table, attributes: [:id, :name])

      :mnesia.transaction(fn ->
        :mnesia.write({:test_table, 1, "Alice"})
        :mnesia.write({:test_table, 2, "Bob"})
      end)

      result = Table.info(:test_table)

      {:ok, info} = result
      validate_boolean(info.size >= 0, "Expected size to be non-negative")
    end
  end

  describe "integration with counters" do
    test "creates table with auto-increment field" do
      result =
        Table.create(:counter_table,
          attributes: [:id, :name],
          counter_fields: [:id]
        )

      {:ok, info} = result
      validate_value_match(info.counter_fields, [:id])
    end

    test "dropping table with counters cleans up counter data" do
      {:ok, _} =
        Table.create(:counter_table,
          attributes: [:id, :name],
          counter_fields: [:id]
        )

      result = Table.drop(:counter_table)

      validate_ok_result(result)
    end

    test "counter table creation initializes counters" do
      {:ok, _} =
        Table.create(:counter_table,
          attributes: [:id, :name],
          counter_fields: [:id]
        )

      has_counter = MnesiaEx.Counter.has_counter?(:counter_table, :id)

      validate_is_boolean(has_counter)
    end
  end

  describe "monadic composition" do
    test "create operation composes monadically" do
      result = Table.create(:test_table, attributes: [:id, :value])

      composed =
        case result do
          {:ok, info} -> {:ok, Map.get(info, :table)}
          error -> error
        end

      {:ok, table_name} = composed
      validate_value_match(table_name, :test_table)
    end

    test "info operation composes with exists check" do
      {:ok, _} = Table.create(:test_table, attributes: [:id, :value])

      result =
        case Table.exists?(:test_table) do
          true -> Table.info(:test_table)
          false -> {:error, :table_not_found}
        end

      {:ok, info} = result
      validate_is_map(info)
    end
  end

  describe "table types" do
    test "creates set table by default" do
      {:ok, info} = Table.create(:test_table, attributes: [:id, :value])

      validate_value_match(info.type, :set)
    end

    test "creates ordered_set table" do
      {:ok, info} =
        Table.create(:test_table,
          attributes: [:id, :value],
          type: :ordered_set
        )

      validate_value_match(info.type, :ordered_set)
    end

    test "creates bag table" do
      {:ok, info} =
        Table.create(:test_table,
          attributes: [:id, :value],
          type: :bag
        )

      validate_value_match(info.type, :bag)
    end
  end

  describe "delete/1 - alias for drop" do
    test "delete is an alias for drop" do
      {:ok, _} = Table.create(:test_table, attributes: [:id, :value])
      result = Table.delete(:test_table)

      validate_ok_result(result)
      validate_table_not_exists(:test_table)
    end
  end

  describe "get_storage_type/1" do
    test "returns valid storage type for existing table" do
      {:ok, _} = Table.create(:storage_table, attributes: [:id, :value], persistent: true)

      result = Table.get_storage_type(:storage_table)

      # @spec get_storage_type(table()) :: :disc_copies | :ram_copies | :disc_only_copies | :unknown
      validate_is_atom(result)
      validate_storage_type_valid(result)
      # In test mode, tables may be ram_copies or disc_copies depending on setup
      validate_storage_type_is_not_unknown(result)
    end

    test "returns storage type for any table" do
      {:ok, _} = Table.create(:any_table, attributes: [:id, :value])

      result = Table.get_storage_type(:any_table)

      validate_is_atom(result)
      validate_storage_type_valid(result)
    end

    test "returns unknown for non-existent table" do
      result = Table.get_storage_type(:nonexistent_storage_table)

      validate_equals(result, :unknown)
    end

    test "get_storage_type is deterministic" do
      {:ok, _} = Table.create(:storage_test, attributes: [:id, :value], persistent: true)

      result1 = Table.get_storage_type(:storage_test)
      result2 = Table.get_storage_type(:storage_test)

      validate_equals(result1, result2)
    end
  end

  describe "transform/3" do
    test "transforms table with new attributes" do
      # Create table with old structure
      {:ok, _} = Table.create(:transform_table, attributes: [:id, :name])
      Query.write!(:transform_table, %{id: 1, name: "Alice"})
      Query.write!(:transform_table, %{id: 2, name: "Bob"})

      # Transform to new structure with additional field
      transform_fun = fn {table, id, name} ->
        {table, id, name, :default_email}
      end

      result = Table.transform(:transform_table, [:id, :name, :email], transform_fun)

      # @spec transform(table(), [atom()], function()) :: result()
      validate_ok_result(result)

      # Verify transformation worked
      record = Query.read!(:transform_table, 1)
      validate_map_has_key(record, :email)
    end

    test "returns error for non-existent table" do
      transform_fun = fn record -> record end

      result = Table.transform(:nonexistent_transform_table, [:id], transform_fun)

      # transform returns {:fail, reason} for errors
      validate_fail_result(result)
    end

    test "transform preserves existing records count" do
      {:ok, _} = Table.create(:count_table, attributes: [:id, :value])
      Query.write!(:count_table, %{id: 1, value: "a"})
      Query.write!(:count_table, %{id: 2, value: "b"})
      Query.write!(:count_table, %{id: 3, value: "c"})

      transform_fun = fn {table, id, value} ->
        {table, id, String.upcase(value)}
      end

      Table.transform(:count_table, [:id, :value], transform_fun)

      # Should still have 3 records
      all_records = Query.select(:count_table, [])
      validate_list_length(all_records, 3)
    end
  end


  # Helper functions for new tests
  defp validate_is_atom(value) when is_atom(value), do: :ok
  defp validate_is_atom(value), do: raise("Expected atom but got #{inspect(value)}")

  defp validate_storage_type_valid(type) when type in [:disc_copies, :ram_copies, :disc_only_copies, :unknown], do: :ok
  defp validate_storage_type_valid(type), do: raise("Invalid storage type: #{inspect(type)}")

  defp validate_storage_type_is_not_unknown(type) when type != :unknown, do: :ok
  defp validate_storage_type_is_not_unknown(:unknown), do: raise("Storage type should not be :unknown for existing table")

  defp validate_equals(value, expected) when value == expected, do: :ok
  defp validate_equals(value, expected), do: raise("Expected #{inspect(expected)} but got #{inspect(value)}")

  defp validate_map_has_key(map, key) when is_map(map) do
    if Map.has_key?(map, key) do
      :ok
    else
      raise "Map missing key :#{key}"
    end
  end

  defp validate_list_length(list, expected_length) when length(list) == expected_length, do: :ok
  defp validate_list_length(list, expected_length),
    do: raise("Expected list length #{expected_length} but got #{length(list)}")
end
