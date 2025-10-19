defmodule MnesiaEx.SchemaTest do
  use ExUnit.Case, async: false

  alias MnesiaEx.Schema

  @moduletag :schema

  # Shared helper functions

  defp validate_schema_info_result({:ok, info}) when is_map(info) do
    validate_has_key(info, :directory)
    validate_has_key(info, :nodes)
    validate_has_key(info, :tables)
    validate_has_key(info, :version)
    validate_has_key(info, :running)
  end

  defp validate_schema_info_result({:error, reason}) do
    raise "Expected schema info but got error: #{inspect(reason)}"
  end

  defp validate_has_key(map, key) do
    Map.has_key?(map, key)
    |> validate_boolean("Expected map to have key #{inspect(key)}")
  end

  defp validate_boolean(true, _message), do: :ok
  defp validate_boolean(false, message), do: raise(message)

  defp validate_is_string(value) when is_binary(value), do: :ok

  defp validate_is_string(value) do
    raise "Expected string but got #{inspect(value)}"
  end

  defp validate_is_list(value) when is_list(value), do: :ok

  defp validate_is_list(value) do
    raise "Expected list but got #{inspect(value)}"
  end

  defp validate_is_boolean(value) when is_boolean(value), do: :ok

  defp validate_is_boolean(value) do
    raise "Expected boolean but got #{inspect(value)}"
  end

  describe "info/0 - schema information retrieval" do
    test "returns schema information when mnesia is running" do
      result = Schema.info()

      validate_schema_info_result(result)
    end

    test "schema info contains directory as string" do
      {:ok, info} = Schema.info()

      validate_is_string(info.directory)
    end

    test "schema info contains nodes list" do
      {:ok, info} = Schema.info()

      validate_is_list(info.nodes)
    end

    test "schema info contains tables list" do
      {:ok, info} = Schema.info()

      validate_is_list(info.tables)
    end

    test "schema info contains version as string" do
      {:ok, info} = Schema.info()

      validate_is_string(info.version)
    end

    test "schema info contains running status as boolean" do
      {:ok, info} = Schema.info()

      validate_is_boolean(info.running)
    end

    test "schema info shows mnesia as running" do
      {:ok, info} = Schema.info()

      validate_boolean(info.running, "Expected Mnesia to be running")
    end

    test "schema info is idempotent" do
      result1 = Schema.info()
      result2 = Schema.info()
      result3 = Schema.info()

      validate_all_schema_info_equal([result1, result2, result3])
    end

    defp validate_all_schema_info_equal([]), do: :ok
    defp validate_all_schema_info_equal([_single]), do: :ok

    defp validate_all_schema_info_equal([{:ok, first}, {:ok, second} | rest]) do
      validate_same_directory(first.directory, second.directory)
      validate_all_schema_info_equal([{:ok, second} | rest])
    end

    defp validate_same_directory(dir1, dir2) when dir1 == dir2, do: :ok

    defp validate_same_directory(dir1, dir2) do
      raise "Schema directories differ: #{dir1} vs #{dir2}"
    end
  end

  describe "exists?/1 - schema existence checking" do
    test "returns true when schema exists on current node" do
      result = Schema.exists?([node()])

      validate_boolean(result, "Expected schema to exist on current node")
    end

    test "returns boolean value" do
      result = Schema.exists?([node()])

      validate_is_boolean(result)
    end

    test "checks all nodes in list" do
      result = Schema.exists?([node()])

      validate_is_boolean(result)
    end

    test "existence check is idempotent" do
      result1 = Schema.exists?([node()])
      result2 = Schema.exists?([node()])
      result3 = Schema.exists?([node()])

      validate_all_boolean_equal([result1, result2, result3])
    end

    defp validate_all_boolean_equal([]), do: :ok
    defp validate_all_boolean_equal([_single]), do: :ok

    defp validate_all_boolean_equal([first, second | rest]) do
      validate_value_match(first, second)
      validate_all_boolean_equal([second | rest])
    end

    defp validate_value_match(actual, expected) when actual == expected, do: :ok

    defp validate_value_match(actual, expected) do
      raise "Expected #{inspect(expected)} but got #{inspect(actual)}"
    end
  end

  describe "functional purity properties" do
    test "info retrieval is deterministic" do
      {:ok, info1} = Schema.info()
      {:ok, info2} = Schema.info()

      validate_same_directory(info1.directory, info2.directory)
      validate_same_version(info1.version, info2.version)
    end

    test "exists check is pure" do
      nodes = [node()]

      result1 = Schema.exists?(nodes)
      result2 = Schema.exists?(nodes)

      validate_value_match(result1, result2)
    end

    test "info returns consistent structure" do
      {:ok, info} = Schema.info()

      keys = Map.keys(info) |> Enum.sort()
      expected_keys = [:directory, :nodes, :running, :tables, :version]

      validate_value_match(keys, expected_keys)
    end

    defp validate_same_version(v1, v2) when v1 == v2, do: :ok

    defp validate_same_version(v1, v2) do
      raise "Versions differ: #{v1} vs #{v2}"
    end
  end

  describe "schema information details" do
    test "directory is non-empty string" do
      {:ok, info} = Schema.info()

      validate_non_empty_string(info.directory)
    end

    test "nodes contains at least current node" do
      {:ok, info} = Schema.info()

      validate_contains_node(info.nodes, node())
    end

    test "tables is a list" do
      {:ok, info} = Schema.info()

      validate_is_list(info.tables)
    end

    test "version is non-empty string" do
      {:ok, info} = Schema.info()

      validate_non_empty_string(info.version)
    end

    test "tables does not include schema table" do
      {:ok, info} = Schema.info()

      validate_not_contains(info.tables, :schema)
    end

    defp validate_non_empty_string(value) when is_binary(value) and byte_size(value) > 0, do: :ok

    defp validate_non_empty_string(value) do
      raise "Expected non-empty string but got #{inspect(value)}"
    end

    defp validate_contains_node(nodes, expected_node) do
      Enum.member?(nodes, expected_node)
      |> validate_boolean("Expected nodes to contain #{expected_node}")
    end

    defp validate_not_contains(list, item) do
      not Enum.member?(list, item)
      |> validate_boolean("Expected list not to contain #{inspect(item)}")
    end
  end

  describe "edge cases and error handling" do
    test "exists? handles empty node list" do
      result = Schema.exists?([])

      validate_boolean(result, "Empty node list should return true (all check)")
    end

    test "info provides current state" do
      {:ok, info} = Schema.info()

      validate_boolean(info.running, "Mnesia should be running during tests")
    end
  end
end
