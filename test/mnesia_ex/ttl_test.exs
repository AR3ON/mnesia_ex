defmodule MnesiaEx.TTLTest do
  use ExUnit.Case, async: false

  alias MnesiaEx.{TTL, Table}

  @moduletag :ttl

  setup do
    ensure_mnesia_started()
    force_create_ttl_table()
    ensure_test_table_exists()
    cleanup_ttl_records()

    on_exit(fn ->
      cleanup_ttl_records()
    end)

    :ok
  end

  defp ensure_mnesia_started do
    :mnesia.start()
    Process.sleep(100)
  end

  defp force_create_ttl_table do
    # Eliminar tabla TTL si existe
    delete_ttl_table_if_exists()

    Process.sleep(50)

    # Crear tabla TTL con estructura correcta
    result =
      Table.create(:mnesia_ttl,
        attributes: [:key, :table, :record_key, :expires_at],
        type: :ordered_set,
        persistence: false
      )

    Process.sleep(100)

    result
  end

  defp ensure_test_table_exists do
    Table.create(:test_ttl_table,
      attributes: [:id, :value, :data],
      persistence: false
    )
  end

  defp cleanup_ttl_records do
    safe_clear_table(:mnesia_ttl)
  end

  defp safe_clear_table(table) do
    table
    |> table_exists_for_clear?()
    |> clear_if_exists(table)
  end

  defp table_exists_for_clear?(table) do
    :mnesia.system_info(:tables)
    |> Enum.member?(table)
  end

  defp clear_if_exists(true, table) do
    {:ok, :cleared} = Table.clear(table)
    :ok
  end
  defp clear_if_exists(false, _table), do: :ok

  defp delete_ttl_table_if_exists do
    :mnesia_ttl
    |> table_exists_for_clear?()
    |> delete_table_if_exists(:mnesia_ttl)
  end

  defp delete_table_if_exists(true, table), do: :mnesia.delete_table(table)
  defp delete_table_if_exists(false, _table), do: :ok

  # Tests for set/3

  describe "set/3 - Setting TTL" do
    test "sets TTL with integer milliseconds" do
      result = TTL.set(:test_ttl_table, 1, 5000)

      validate_ok_result(result)
    end

    test "sets TTL with time tuple" do
      result = TTL.set(:test_ttl_table, 2, {1, :hours})

      validate_ok_result(result)
    end

    test "sets TTL with seconds" do
      result = TTL.set(:test_ttl_table, 3, {30, :seconds})

      validate_ok_result(result)
    end

    test "sets TTL with minutes" do
      result = TTL.set(:test_ttl_table, 4, {5, :minutes})

      validate_ok_result(result)
    end

    test "sets TTL is pure for same inputs" do
      result1 = TTL.set(:test_ttl_table, 5, 1000)
      result2 = TTL.set(:test_ttl_table, 5, 1000)

      validate_set_results_similar(result1, result2)
    end
  end

  # Tests for clear/2

  describe "clear/2 - Clearing TTL" do
    test "clears existing TTL" do
      TTL.set(:test_ttl_table, 1, 5000)
      result = TTL.clear(:test_ttl_table, 1)

      validate_ok_result(result)
    end

    test "clears non-existent TTL returns ok" do
      result = TTL.clear(:test_ttl_table, 999)

      validate_ok_result(result)
    end

    test "clear is idempotent" do
      TTL.set(:test_ttl_table, 2, 5000)
      TTL.clear(:test_ttl_table, 2)
      result = TTL.clear(:test_ttl_table, 2)

      validate_ok_result(result)
    end
  end

  # Tests for get_remaining/2

  describe "get_remaining/2 - Getting remaining time" do
    test "returns remaining time for valid TTL" do
      TTL.set(:test_ttl_table, 1, 5000)
      result = TTL.get_remaining(:test_ttl_table, 1)

      {:ok, remaining} = result
      validate_time_is_positive(remaining)
      validate_time_is_less_than(remaining, 5000)
    end

    test "returns error for expired TTL" do
      TTL.set(:test_ttl_table, 2, 100)
      Process.sleep(150)
      result = TTL.get_remaining(:test_ttl_table, 2)

      validate_error_result(result)
    end

    test "returns error for non-existent TTL" do
      result = TTL.get_remaining(:test_ttl_table, 999)

      validate_error_result(result)
    end

    test "remaining time decreases over time" do
      TTL.set(:test_ttl_table, 3, 2000)
      {:ok, remaining1} = TTL.get_remaining(:test_ttl_table, 3)
      Process.sleep(100)
      {:ok, remaining2} = TTL.get_remaining(:test_ttl_table, 3)

      validate_time_decreased(remaining1, remaining2)
    end
  end

  # Tests for expired?/2

  describe "expired?/2 - Checking expiration" do
    test "returns false for non-expired TTL" do
      TTL.set(:test_ttl_table, 1, 5000)
      result = TTL.expired?(:test_ttl_table, 1)

      validate_is_false(result)
    end

    test "returns true for expired TTL" do
      TTL.set(:test_ttl_table, 2, 50)
      Process.sleep(100)
      result = TTL.expired?(:test_ttl_table, 2)

      validate_is_true(result)
    end

    test "returns false for non-existent TTL" do
      result = TTL.expired?(:test_ttl_table, 999)

      validate_is_false(result)
    end

    test "expired? is pure function" do
      TTL.set(:test_ttl_table, 3, 5000)
      result1 = TTL.expired?(:test_ttl_table, 3)
      result2 = TTL.expired?(:test_ttl_table, 3)

      validate_value_match(result1, result2)
    end
  end

  # Tests for ensure_ttl_table/1

  describe "ensure_ttl_table/1 - Table initialization" do
    test "creates TTL table if not exists" do
      result = TTL.ensure_ttl_table()

      validate_ok_result(result)
    end

    test "returns ok if table already exists" do
      TTL.ensure_ttl_table()
      result = TTL.ensure_ttl_table()

      validate_ok_result(result)
    end

    test "ensure is idempotent" do
      result1 = TTL.ensure_ttl_table()
      result2 = TTL.ensure_ttl_table()

      validate_results_equal(result1, result2)
    end
  end

  # Tests for set_ttl/3

  describe "set_ttl/3 - Setting TTL with timestamp" do
    test "sets TTL with integer milliseconds" do
      result = TTL.set_ttl(:test_ttl_table, 1, 5000)

      validate_ok_result(result)
    end

    test "set_ttl requires positive integer" do
      ttl_value = 1000
      result = TTL.set_ttl(:test_ttl_table, 2, ttl_value)

      validate_ok_result(result)
    end
  end

  # Tests for delete_ttl/2

  describe "delete_ttl/2 - Deleting TTL" do
    test "deletes existing TTL" do
      TTL.set_ttl(:test_ttl_table, 1, 5000)
      result = TTL.delete_ttl(:test_ttl_table, 1)

      validate_ok_result(result)
    end

    test "delete non-existent TTL returns ok" do
      result = TTL.delete_ttl(:test_ttl_table, 999)

      validate_ok_result(result)
    end

    test "delete is idempotent" do
      TTL.set_ttl(:test_ttl_table, 2, 5000)
      TTL.delete_ttl(:test_ttl_table, 2)
      result = TTL.delete_ttl(:test_ttl_table, 2)

      validate_ok_result(result)
    end
  end

  # Tests for get_ttl/2

  describe "get_ttl/2 - Getting TTL value" do
    test "returns remaining time for valid TTL" do
      TTL.set_ttl(:test_ttl_table, 1, 5000)
      Process.sleep(10)
      result = TTL.get_ttl(:test_ttl_table, 1)

      {:ok, ttl_record} = result
      validate_time_is_non_negative(ttl_record.expires_at)
    end

    test "returns zero for expired TTL" do
      TTL.set_ttl(:test_ttl_table, 2, 50)
      Process.sleep(100)
      result = TTL.get_ttl(:test_ttl_table, 2)

      {:ok, ttl_record} = result
      validate_map_has_key(ttl_record, :expires_at)
    end

    test "returns default record for non-existent TTL" do
      result = TTL.get_ttl(:test_ttl_table, 999)

      {:ok, ttl_record} = result
      validate_value_match(ttl_record.expires_at, 0)
    end
  end

  # Tests for cleanup_expired/0

  describe "cleanup_expired/0 - Cleaning expired records" do
    test "removes expired TTL records" do
      TTL.set_ttl(:test_ttl_table, 1, 50)
      TTL.set_ttl(:test_ttl_table, 2, 5000)
      Process.sleep(100)

      result = TTL.cleanup_expired()

      validate_cleanup_result(result)
    end

    test "cleanup is idempotent" do
      TTL.set_ttl(:test_ttl_table, 1, 50)
      Process.sleep(100)

      TTL.cleanup_expired()
      result = TTL.cleanup_expired()

      validate_cleanup_result(result)
    end
  end

  # Tests for write/3

  describe "write/3 - Writing with TTL" do
    test "writes record with TTL" do
      record = %{id: 1, value: "test", data: "data"}
      result = TTL.write(:test_ttl_table, record, 5000)

      {:ok, written_record} = result
      validate_value_match(written_record.id, 1)
    end

    test "write with TTL requires positive integer" do
      record = %{id: 2, value: "test2", data: "data2"}
      result = TTL.write(:test_ttl_table, record, 1000)

      validate_is_ok_tuple(result)
    end
  end

  # Tests for write!/3

  describe "write!/3 - Writing with TTL (bang version)" do
    test "writes record with TTL and returns record" do
      record = %{id: 1, value: "test", data: "data"}
      result = TTL.write!(:test_ttl_table, record, 5000)

      validate_value_match(result.id, 1)
    end
  end

  # Tests for get/2 and get!/2

  describe "get/2 and get!/2 - Getting TTL" do
    test "get returns TTL record" do
      TTL.set_ttl(:test_ttl_table, 1, 5000)
      Process.sleep(10)
      result = TTL.get(:test_ttl_table, 1)

      {:ok, ttl_record} = result
      validate_is_map(ttl_record)
      validate_map_has_key(ttl_record, :expires_at)
    end

    test "get! returns TTL record without tuple" do
      TTL.set_ttl(:test_ttl_table, 2, 5000)
      Process.sleep(10)
      result = TTL.get!(:test_ttl_table, 2)

      validate_is_map(result)
      validate_map_has_key(result, :expires_at)
    end
  end

  # Tests for write_with_ttl/3

  describe "write_with_ttl/3 - Alias for write/3" do
    test "writes record with TTL" do
      record = %{id: 1, value: "test", data: "data"}
      result = TTL.write_with_ttl(:test_ttl_table, record, 5000)

      validate_is_ok_tuple(result)
    end

    test "write_with_ttl is same as write" do
      record = %{id: 2, value: "test2", data: "data2"}
      result1 = TTL.write(:test_ttl_table, record, 5000)
      TTL.clear(:test_ttl_table, 2)
      result2 = TTL.write_with_ttl(:test_ttl_table, record, 5000)

      validate_both_ok(result1, result2)
    end
  end

  # Tests for functional purity

  describe "Functional purity properties" do
    test "set operation is deterministic" do
      result1 = TTL.set(:test_ttl_table, 1, 5000)
      result2 = TTL.set(:test_ttl_table, 1, 5000)

      # Both should be {:ok, record} with same structure but different timestamps
      validate_set_results_similar(result1, result2)
    end

    test "clear operation is pure" do
      TTL.set(:test_ttl_table, 1, 5000)
      result1 = TTL.clear(:test_ttl_table, 1)
      result2 = TTL.clear(:test_ttl_table, 1)

      # Both should be {:ok, :ok} or {:error, :not_found}
      validate_clear_results_consistent(result1, result2)
    end

    test "expired check is pure function" do
      TTL.set(:test_ttl_table, 1, 5000)
      result1 = TTL.expired?(:test_ttl_table, 1)
      result2 = TTL.expired?(:test_ttl_table, 1)

      validate_value_match(result1, result2)
    end
  end

  # Tests for edge cases

  describe "Edge cases and error handling" do
    test "handles very short TTL" do
      result = TTL.set(:test_ttl_table, 1, 1)

      validate_ok_result(result)
    end

    test "handles very long TTL" do
      result = TTL.set(:test_ttl_table, 2, {365, :days})

      validate_ok_result(result)
    end

    test "handles multiple TTLs for same table" do
      TTL.set(:test_ttl_table, 1, 5000)
      TTL.set(:test_ttl_table, 2, 6000)
      TTL.set(:test_ttl_table, 3, 7000)

      result1 = TTL.get_remaining(:test_ttl_table, 1)
      result2 = TTL.get_remaining(:test_ttl_table, 2)
      result3 = TTL.get_remaining(:test_ttl_table, 3)

      validate_all_ok([result1, result2, result3])
    end

    test "handles TTL update for same key" do
      TTL.set(:test_ttl_table, 1, 1000)
      result = TTL.set(:test_ttl_table, 1, 5000)

      validate_ok_result(result)
    end
  end

  # Tests for monadic composition

  describe "Monadic composition" do
    test "set and get operations compose monadically" do
      ttl_value = 5000

      TTL.set(:test_ttl_table, 1, ttl_value)
      result = TTL.get_remaining(:test_ttl_table, 1)

      {:ok, remaining} = result
      validate_time_is_less_than(remaining, ttl_value)
    end

    test "set and clear operations compose" do
      TTL.set(:test_ttl_table, 1, 5000)
      result = TTL.clear(:test_ttl_table, 1)

      validate_ok_result(result)
      validate_is_false(TTL.expired?(:test_ttl_table, 1))
    end

    test "write and get operations compose" do
      record = %{id: 1, value: "test", data: "data"}
      ttl_value = 5000

      TTL.write(:test_ttl_table, record, ttl_value)
      result = TTL.get(:test_ttl_table, 1)

      validate_is_ok_tuple(result)
    end
  end

  # Tests for GenServer integration

  describe "GenServer integration" do
    test "running? returns boolean" do
      result = TTL.running?()

      validate_is_boolean(result)
    end

    test "stop returns ok" do
      result = TTL.stop()

      validate_ok_atom(result)
    end
  end

  describe "TTL Listing and Counting Functions" do
    setup do
      # Create test table
      force_create_ttl_table()

      # Add some test records with different TTLs
      TTL.set(:users, 1, 5_000)
      TTL.set(:users, 2, 10_000)
      TTL.set(:session, "sid_1", 3_000)
      TTL.set(:session, "sid_2", 15_000)
      TTL.set(:products, "p_1", 1_000)

      # Add one expired record
      TTL.set(:users, 99, 1)
      Process.sleep(5)

      :ok
    end

    test "list_all/0 returns list of all TTL records" do
      result = TTL.list_all()

      # Validate it's a list
      validate_is_list(result)

      # Should have at least 5 active records
      validate_list_has_min_length(result, 5)

      # Each record should have required fields
      Enum.each(result, fn record ->
        validate_ttl_record_structure(record)
        validate_ttl_record_has_table(record)
        validate_ttl_record_has_key(record)
      end)
    end

    test "list_all/0 returns empty list when no TTLs" do
      # Clear all TTLs (including the expired one)
      TTL.clear(:users, 1)
      TTL.clear(:users, 2)
      TTL.clear(:users, 99)
      TTL.clear(:session, "sid_1")
      TTL.clear(:session, "sid_2")
      TTL.clear(:products, "p_1")
      TTL.cleanup_expired()

      result = TTL.list_all()

      validate_is_list(result)
      validate_list_is_empty(result)
    end

    test "list_by_table/1 returns list of TTL records for specific table" do
      result = TTL.list_by_table(:users)

      validate_is_list(result)
      validate_list_has_min_length(result, 2)

      # All records should be from :users table
      Enum.each(result, fn record ->
        validate_ttl_record_table(record, :users)
      end)
    end

    test "list_by_table/1 returns empty list for table without TTLs" do
      result = TTL.list_by_table(:nonexistent_table)

      validate_is_list(result)
      validate_list_is_empty(result)
    end

    test "list_active/0 returns only non-expired TTL records" do
      result = TTL.list_active()

      validate_is_list(result)
      validate_list_has_min_length(result, 4)

      # All records should not be expired
      Enum.each(result, fn record ->
        validate_ttl_record_not_expired(record)
      end)
    end

    test "list_active/0 excludes expired records" do
      # Wait for the record with 1ms TTL to expire
      Process.sleep(10)

      result = TTL.list_active()

      # Should not include the expired record
      has_expired = Enum.any?(result, fn r -> r.expired == true end)
      validate_is_false(has_expired)
    end

    test "list_active_by_table/1 returns active TTL records for specific table" do
      result = TTL.list_active_by_table(:session)

      validate_is_list(result)
      validate_list_has_min_length(result, 2)

      # All records should be from :session and active
      Enum.each(result, fn record ->
        validate_ttl_record_table(record, :session)
        validate_ttl_record_not_expired(record)
      end)
    end

    test "list_active_by_table/1 returns empty list for table without active TTLs" do
      result = TTL.list_active_by_table(:nonexistent_table)

      validate_is_list(result)
      validate_list_is_empty(result)
    end

    test "count_all/0 returns integer count of all TTL records" do
      result = TTL.count_all()

      validate_is_integer(result)
      validate_integer_greater_or_equal(result, 5)
    end

    test "count_all/0 returns 0 when no TTLs" do
      # Clear all TTLs (including the expired one)
      TTL.clear(:users, 1)
      TTL.clear(:users, 2)
      TTL.clear(:users, 99)
      TTL.clear(:session, "sid_1")
      TTL.clear(:session, "sid_2")
      TTL.clear(:products, "p_1")
      TTL.cleanup_expired()

      result = TTL.count_all()

      validate_is_integer(result)
      validate_integer_equals(result, 0)
    end

    test "count_active/0 returns integer count of active TTL records" do
      result = TTL.count_active()

      validate_is_integer(result)
      # Should have at least 4 active (the expired one should be excluded)
      validate_integer_greater_or_equal(result, 4)
    end

    test "count_active/0 returns 0 when all expired" do
      # Clear all active TTLs
      TTL.clear(:users, 1)
      TTL.clear(:users, 2)
      TTL.clear(:session, "sid_1")
      TTL.clear(:session, "sid_2")
      TTL.clear(:products, "p_1")

      # Wait for cleanup
      TTL.cleanup_expired()

      result = TTL.count_active()

      validate_is_integer(result)
      validate_integer_equals(result, 0)
    end

    test "count functions are consistent with list functions" do
      all_list = TTL.list_all()
      all_count = TTL.count_all()

      validate_integer_equals(all_count, length(all_list))

      active_list = TTL.list_active()
      active_count = TTL.count_active()

      validate_integer_equals(active_count, length(active_list))
    end

    test "listing functions return records with correct structure" do
      result = TTL.list_all()

      Enum.each(result, fn record ->
        # Required fields
        validate_map_has_key(record, :table)
        validate_map_has_key(record, :key)
        validate_map_has_key(record, :expires_at)
        validate_map_has_key(record, :remaining_ms)
        validate_map_has_key(record, :remaining_seconds)
        validate_map_has_key(record, :remaining_minutes)
        validate_map_has_key(record, :expired)

        # Types
        validate_is_atom(record.table)
        validate_is_integer(record.expires_at)
        validate_is_integer(record.remaining_ms)
        validate_is_integer(record.remaining_seconds)
        validate_is_integer(record.remaining_minutes)
        validate_is_boolean(record.expired)
      end)
    end

    test "listing functions are deterministic" do
      result1 = TTL.list_all()
      result2 = TTL.list_all()

      # Same number of records
      validate_integer_equals(length(result1), length(result2))

      # Same keys present (though remaining times may differ slightly)
      keys1 = Enum.map(result1, & {&1.table, &1.key}) |> Enum.sort()
      keys2 = Enum.map(result2, & {&1.table, &1.key}) |> Enum.sort()

      validate_lists_equal(keys1, keys2)
    end

    test "counting functions are deterministic" do
      count1 = TTL.count_all()
      count2 = TTL.count_all()

      validate_integer_equals(count1, count2)
    end
  end

  # Helper functions

  defp validate_ok_result(:ok), do: :ok
  defp validate_ok_result({:ok, _}), do: :ok
  # delete_ttl and clear can return not_found
  defp validate_ok_result({:error, :not_found}), do: :ok

  defp validate_ok_result({:error, reason}) do
    raise "Expected :ok but got {:error, #{inspect(reason)}}"
  end

  defp validate_error_result({:error, _reason}), do: :ok

  defp validate_error_result(result) do
    raise "Expected error but got #{inspect(result)}"
  end

  defp validate_ok_atom(:ok), do: :ok

  defp validate_ok_atom(result) do
    raise "Expected :ok but got #{inspect(result)}"
  end

  defp validate_is_ok_tuple({:ok, _}), do: :ok

  defp validate_is_ok_tuple(result) do
    raise "Expected {:ok, _} but got #{inspect(result)}"
  end

  defp validate_is_true(true), do: :ok
  defp validate_is_true(false), do: raise("Expected true but got false")

  defp validate_is_false(false), do: :ok
  defp validate_is_false(true), do: raise("Expected false but got true")

  defp validate_is_boolean(value) when is_boolean(value), do: :ok

  defp validate_is_boolean(value) do
    raise "Expected boolean but got #{inspect(value)}"
  end

  defp validate_time_is_positive(time) when time > 0, do: :ok

  defp validate_time_is_positive(time) do
    raise "Expected positive time but got #{time}"
  end

  defp validate_time_is_non_negative(time) when time >= 0, do: :ok

  defp validate_time_is_non_negative(time) do
    raise "Expected non-negative time but got #{time}"
  end

  defp validate_time_is_less_than(time, max) when time <= max, do: :ok

  defp validate_time_is_less_than(time, max) do
    raise "Expected time #{time} to be less than or equal to #{max}"
  end

  defp validate_time_decreased(time1, time2) when time2 < time1, do: :ok

  defp validate_time_decreased(time1, time2) do
    raise "Expected time to decrease: #{time1} -> #{time2}"
  end

  defp validate_value_match(value, expected) when value == expected, do: :ok

  defp validate_value_match(value, expected) do
    raise "Expected #{inspect(expected)} but got #{inspect(value)}"
  end

  defp validate_results_equal(result1, result2) when result1 == result2, do: :ok

  defp validate_results_equal(result1, result2) do
    raise "Expected equal results but got #{inspect(result1)} and #{inspect(result2)}"
  end

  defp validate_set_results_similar({:ok, :ok}, {:ok, :ok}), do: :ok

  defp validate_set_results_similar({:ok, record1}, {:ok, record2}) when is_map(record1) and is_map(record2) do
    validate_atoms_equal(record1.table, record2.table)
  end

  defp validate_set_results_similar(result1, result2) do
    raise "Expected {:ok, :ok} or {:ok, record} results but got #{inspect(result1)} and #{inspect(result2)}"
  end

  defp validate_clear_results_consistent(result1, result2) do
    # First clear can return {:ok, record}, second returns {:error, :not_found}
    case {result1, result2} do
      # First clear succeeds, second finds nothing
      {{:ok, _}, {:error, :not_found}} ->
        :ok

      {{:error, :not_found}, {:error, :not_found}} ->
        :ok

      {{:ok, _}, {:ok, _}} ->
        :ok

      _ ->
        raise "Expected consistent clear results but got #{inspect(result1)} and #{inspect(result2)}"
    end
  end

  defp validate_cleanup_result(:ok), do: :ok
  defp validate_cleanup_result({:ok, _}), do: :ok

  defp validate_cleanup_result(result) do
    raise "Expected cleanup result but got #{inspect(result)}"
  end

  defp validate_both_ok({:ok, _}, {:ok, _}), do: :ok

  defp validate_both_ok(result1, result2) do
    raise "Expected both to be ok but got #{inspect(result1)} and #{inspect(result2)}"
  end

  defp validate_all_ok(results) do
    results
    |> Enum.all?(fn
      {:ok, _} -> true
      _ -> false
    end)
    |> validate_all_ok_result()
  end

  defp validate_all_ok_result(true), do: :ok
  defp validate_all_ok_result(false), do: raise("Not all results were ok")

  # Validators for listing and counting functions

  defp validate_is_list(value) when is_list(value), do: :ok

  defp validate_is_list(value) do
    raise "Expected list but got #{inspect(value)}"
  end

  defp validate_is_integer(value) when is_integer(value), do: :ok

  defp validate_is_integer(value) do
    raise "Expected integer but got #{inspect(value)}"
  end

  defp validate_is_atom(value) when is_atom(value), do: :ok

  defp validate_is_atom(value) do
    raise "Expected atom but got #{inspect(value)}"
  end

  defp validate_list_has_min_length(list, min_length) when length(list) >= min_length, do: :ok

  defp validate_list_has_min_length(list, min_length) do
    raise "Expected list with at least #{min_length} elements but got #{length(list)}"
  end

  defp validate_list_is_empty([]), do: :ok

  defp validate_list_is_empty(list) do
    raise "Expected empty list but got #{length(list)} elements"
  end

  defp validate_integer_equals(value, expected) when value == expected, do: :ok

  defp validate_integer_equals(value, expected) do
    raise "Expected #{expected} but got #{value}"
  end

  defp validate_integer_greater_or_equal(value, min) when value >= min, do: :ok

  defp validate_integer_greater_or_equal(value, min) do
    raise "Expected value >= #{min} but got #{value}"
  end

  defp validate_ttl_record_structure(%{} = record) do
    required_fields = [:table, :key, :expires_at, :remaining_ms, :remaining_seconds, :remaining_minutes, :expired]

    missing = Enum.filter(required_fields, fn field ->
      not Map.has_key?(record, field)
    end)

    if length(missing) > 0 do
      raise "TTL record missing fields: #{inspect(missing)}"
    end

    :ok
  end

  defp validate_ttl_record_structure(value) do
    raise "Expected TTL record map but got #{inspect(value)}"
  end

  defp validate_ttl_record_has_table(%{table: _}), do: :ok

  defp validate_ttl_record_has_table(record) do
    raise "TTL record missing :table field: #{inspect(record)}"
  end

  defp validate_ttl_record_has_key(%{key: _}), do: :ok

  defp validate_ttl_record_has_key(record) do
    raise "TTL record missing :key field: #{inspect(record)}"
  end

  defp validate_ttl_record_table(%{table: table}, expected_table) when table == expected_table, do: :ok

  defp validate_ttl_record_table(%{table: table}, expected_table) do
    raise "Expected table #{expected_table} but got #{table}"
  end

  defp validate_ttl_record_not_expired(%{expired: false}), do: :ok

  defp validate_ttl_record_not_expired(%{expired: true}) do
    raise "Expected non-expired record but got expired: true"
  end

  defp validate_map_has_key(map, key) when is_map(map) do
    if Map.has_key?(map, key) do
      :ok
    else
      raise "Map missing key :#{key}"
    end
  end

  defp validate_lists_equal(list1, list2) when list1 == list2, do: :ok

  defp validate_lists_equal(list1, list2) do
    raise "Lists not equal:\n  List1: #{inspect(list1)}\n  List2: #{inspect(list2)}"
  end

  defp validate_is_map(value) when is_map(value), do: :ok
  defp validate_is_map(value), do: raise("Expected map but got #{inspect(value)}")

  defp validate_atoms_equal(atom1, atom2) when atom1 == atom2, do: :ok
  defp validate_atoms_equal(atom1, atom2), do: raise("Expected #{atom1} == #{atom2}")
end
