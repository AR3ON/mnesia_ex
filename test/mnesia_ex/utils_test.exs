defmodule MnesiaEx.UtilsTest do
  use ExUnit.Case, async: false

  alias MnesiaEx.Utils

  setup do
    :ok
  end

  describe "tuple_to_map/1" do
    test "converts list of tuples to list of maps" do
      records = [
        {:users, 1, "John", "john@example.com"},
        {:users, 2, "Jane", "jane@example.com"}
      ]

      result = Utils.tuple_to_map(records)

      assert result == [
               %{id: 1, name: "John", email: "john@example.com"},
               %{id: 2, name: "Jane", email: "jane@example.com"}
             ]
    end

    test "converts single tuple with table and key to map" do
      result = Utils.tuple_to_map({:users, 1})

      assert result == %{id: 1}
    end

    test "converts full record tuple to map" do
      record = {:users, 1, "John", "john@example.com"}

      result = Utils.tuple_to_map(record)

      assert result == %{id: 1, name: "John", email: "john@example.com"}
    end

    test "returns empty map for invalid input" do
      assert Utils.tuple_to_map("invalid") == %{}
      assert Utils.tuple_to_map({}) == %{}
    end

    test "handles empty list" do
      assert Utils.tuple_to_map([]) == []
    end
  end

  describe "map_to_tuple/2" do
    test "converts map to tuple successfully" do
      map = %{id: 1, name: "John", email: "john@example.com"}

      result = Utils.map_to_tuple(:users, map)

      assert result == {:ok, {:users, 1, "John", "john@example.com"}}
    end

    test "returns error for missing fields" do
      map = %{id: 1, name: "John"}

      result = Utils.map_to_tuple(:users, map)

      assert result == {:error, :missing_fields}
    end

    test "returns error for invalid arguments" do
      assert Utils.map_to_tuple("invalid", %{}) == {:error, :invalid_arguments}
      assert Utils.map_to_tuple(:users, "invalid") == {:error, :invalid_arguments}
    end

    test "returns error for non-existent table" do
      map = %{id: 1, name: "John", email: "john@example.com"}

      result = Utils.map_to_tuple(:non_existent, map)

      assert {:error, _} = result
    end
  end

  describe "validate_required_fields/2" do
    test "returns :ok when all fields are present" do
      map = %{id: 1, name: "John", email: "john@example.com"}

      result = Utils.validate_required_fields(:users, map)

      assert result == :ok
    end

    test "returns error with missing fields" do
      map = %{id: 1, name: "John"}

      result = Utils.validate_required_fields(:users, map)

      assert result == {:error, {:missing_fields, [:email]}}
    end

    test "returns error for invalid arguments" do
      assert Utils.validate_required_fields("invalid", %{}) == {:error, :invalid_arguments}
      assert Utils.validate_required_fields(:users, "invalid") == {:error, :invalid_arguments}
    end
  end

  describe "table_key/1" do
    test "returns first field as key" do
      result = Utils.table_key(:users)

      assert result == {:ok, :id}
    end

    test "returns error for non-existent table" do
      result = Utils.table_key(:non_existent)

      assert {:error, _} = result
    end
  end

  describe "has_counter?/2" do
    test "returns true for field with counter" do
      result = Utils.has_counter?(:posts, :id)

      assert result == true
    end

    test "returns false for field without counter" do
      result = Utils.has_counter?(:users, :id)

      assert result == false
    end

    test "returns false for non-existent field" do
      result = Utils.has_counter?(:users, :non_existent)

      assert result == false
    end
  end

  describe "get_autoincrement_fields/1" do
    test "returns list with counter field" do
      result = Utils.get_autoincrement_fields(:posts)

      assert result == [:id]
    end

    test "returns empty list for table without counters" do
      result = Utils.get_autoincrement_fields(:users)

      assert result == []
    end

    test "returns empty list for non-existent table" do
      result = Utils.get_autoincrement_fields(:non_existent)

      assert result == []
    end
  end

  describe "record_to_map/1" do
    test "converts list of records to list of maps" do
      records = [
        {:users, 1, "John", "john@example.com"},
        {:users, 2, "Jane", "jane@example.com"}
      ]

      result = Utils.record_to_map(records)

      assert result == [
               %{id: 1, name: "John", email: "john@example.com"},
               %{id: 2, name: "Jane", email: "jane@example.com"}
             ]
    end

    test "converts single record to map" do
      record = {:users, 1, "John", "john@example.com"}

      result = Utils.record_to_map(record)

      assert result == %{id: 1, name: "John", email: "john@example.com"}
    end

    test "returns empty map for nil input" do
      assert Utils.record_to_map(nil) == %{}
    end

    test "returns empty map for invalid input" do
      assert Utils.record_to_map("invalid") == %{}
    end
  end

  describe "map_to_record/2" do
    test "converts map to record tuple" do
      attrs = %{id: 1, name: "John", email: "john@example.com"}

      result = Utils.map_to_record(:users, attrs)

      assert result == {:users, 1, "John", "john@example.com"}
    end

    test "handles missing fields by using nil" do
      attrs = %{id: 1, name: "John"}

      result = Utils.map_to_record(:users, attrs)

      assert result == {:users, 1, "John", nil}
    end
  end

  describe "map_to_tuple/1" do
    test "converts map to sorted tuple" do
      map = %{c: 3, a: 1, b: 2}

      result = Utils.map_to_tuple(map)

      assert result == {1, 2, 3}
    end

    test "handles empty map" do
      result = Utils.map_to_tuple(%{})

      assert result == {}
    end

    test "handles single key map" do
      result = Utils.map_to_tuple(%{a: 1})

      assert result == {1}
    end
  end

  describe "functional purity" do
    test "all functions are pure - no side effects" do
      # Test that functions don't modify external state
      original_map = %{id: 1, name: "John", email: "john@example.com"}

      _result = Utils.map_to_tuple(:users, original_map)

      # Original map should remain unchanged
      assert original_map == %{id: 1, name: "John", email: "john@example.com"}
    end

    test "functions are deterministic" do
      input = {:users, 1, "John", "john@example.com"}

      result1 = Utils.tuple_to_map(input)
      result2 = Utils.tuple_to_map(input)

      assert result1 == result2
    end
  end

  describe "monadic composition" do
    test "Error monad composition works correctly" do
      # Test that Error.m do blocks work as expected
      map = %{id: 1, name: "John", email: "john@example.com"}

      result = Utils.map_to_tuple(:users, map)

      assert {:ok, _} = result
    end

    test "Error monad handles failures correctly" do
      map = %{id: 1, name: "John"}

      result = Utils.map_to_tuple(:users, map)

      assert {:error, :missing_fields} = result
    end
  end

  describe "edge cases" do
    test "handles tables with minimum attributes" do
      # Create a simple table for testing (Mnesia requires at least 2 attributes)
      :mnesia.create_table(:simple, attributes: [:id, :value])

      result = Utils.table_key(:simple)

      # Cleanup
      :mnesia.delete_table(:simple)

      assert result == {:ok, :id}
    end

    test "handles very large records" do
      large_record = {:users, 1, "John", "john@example.com", "extra1", "extra2", "extra3"}

      result = Utils.tuple_to_map(large_record)

      # Should handle gracefully even if fields don't match (returns empty map)
      assert result == %{}
    end

    test "handles nested data structures in values" do
      complex_email = %{address: "john@example.com", verified: true}

      complex_map = %{
        id: 1,
        name: "John",
        email: complex_email
      }

      result = Utils.map_to_record(:users, complex_map)

      # Should preserve the nested structure
      assert {:users, 1, "John", email} = result
      assert email == complex_email
    end
  end

  describe "@spec validation for all Utils functions" do
    test "map_to_tuple/2 returns ok tuple or error as per spec" do
      result = Utils.map_to_tuple(:users, %{id: 1, name: "Test", email: "test@example.com"})

      # @spec map_to_tuple(table(), map()) :: {:ok, record()} | {:error, term()}
      validate_is_ok_tuple_or_error(result)
    end

    test "validate_required_fields/2 returns :ok or error as per spec" do
      result = Utils.validate_required_fields(:users, %{id: 1, name: "Test", email: "test@example.com"})

      # @spec validate_required_fields(table(), map()) :: :ok | {:error, {:missing_fields, [atom()]}}
      validate_is_ok_or_missing_fields_error(result)
    end

    test "has_counter?/2 returns boolean as per spec" do
      result = Utils.has_counter?(:counters, :id)

      # @spec has_counter?(table(), atom()) :: boolean()
      validate_is_boolean(result)
    end

    test "get_autoincrement_fields/1 returns list as per spec" do
      result = Utils.get_autoincrement_fields(:counters)

      # @spec get_autoincrement_fields(table()) :: [atom()]
      validate_is_list(result)
    end

    test "tuple_to_map/1 always returns map" do
      # Multiple clause function, should always return a map
      result1 = Utils.tuple_to_map({:users, 1, "Alice", "alice@example.com"})
      result2 = Utils.tuple_to_map({:users, 1})
      result3 = Utils.tuple_to_map(nil)
      result4 = Utils.tuple_to_map("invalid")

      validate_is_map(result1)
      validate_is_map(result2)
      validate_is_map(result3)
      validate_is_map(result4)
    end

    test "record_to_map/1 always returns map or list of maps" do
      # Multiple clause function
      single = Utils.record_to_map({:users, 1, "Alice", "alice@example.com"})
      list = Utils.record_to_map([{:users, 1, "Alice", "alice@example.com"}])
      nil_result = Utils.record_to_map(nil)

      validate_is_map(single)
      validate_is_list(list)
      validate_is_map(nil_result)
    end

    test "map_to_record/2 returns tuple" do
      result = Utils.map_to_record(:users, %{id: 1, name: "Test", email: "test@example.com"})

      validate_is_tuple(result)
    end

    test "table_key/1 returns atom wrapped in ok tuple or error tuple" do
      {:ok, _} = MnesiaEx.Table.create(:utils_test_table, attributes: [:id, :name])
      result = Utils.table_key(:utils_test_table)

      # Returns {:ok, atom()} or {:error, _}
      validate_is_ok_atom_or_error(result)
    end
  end

  # Helper functions for spec validation
  defp validate_is_ok_tuple_or_error({:ok, _}), do: :ok
  defp validate_is_ok_tuple_or_error({:error, _}), do: :ok
  defp validate_is_ok_tuple_or_error({:fail, _}), do: :ok
  defp validate_is_ok_tuple_or_error(value),
    do: raise("Expected {:ok, _} or {:error, _} but got #{inspect(value)}")

  defp validate_is_ok_or_missing_fields_error(:ok), do: :ok
  defp validate_is_ok_or_missing_fields_error({:error, {:missing_fields, _}}), do: :ok
  defp validate_is_ok_or_missing_fields_error({:fail, _}), do: :ok
  defp validate_is_ok_or_missing_fields_error(value),
    do: raise("Expected :ok or {:error, {:missing_fields, _}} but got #{inspect(value)}")

  defp validate_is_boolean(true), do: :ok
  defp validate_is_boolean(false), do: :ok
  defp validate_is_boolean(value), do: raise("Expected boolean but got #{inspect(value)}")

  defp validate_is_list(value) when is_list(value), do: :ok
  defp validate_is_list(value), do: raise("Expected list but got #{inspect(value)}")

  defp validate_is_map(value) when is_map(value), do: :ok
  defp validate_is_map(value), do: raise("Expected map but got #{inspect(value)}")

  defp validate_is_tuple(value) when is_tuple(value), do: :ok
  defp validate_is_tuple(value), do: raise("Expected tuple but got #{inspect(value)}")

  defp validate_is_ok_atom_or_error({:ok, value}) when is_atom(value), do: :ok
  defp validate_is_ok_atom_or_error({:error, _}), do: :ok
  defp validate_is_ok_atom_or_error({:fail, _}), do: :ok
  defp validate_is_ok_atom_or_error(value),
    do: raise("Expected {:ok, atom()} or {:error, _} but got #{inspect(value)}")
end
