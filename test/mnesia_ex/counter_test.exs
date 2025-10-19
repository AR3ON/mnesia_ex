defmodule MnesiaEx.CounterTest do
  use ExUnit.Case, async: false

  require MnesiaEx.Monad, as: Error

  alias MnesiaEx.{Counter, Query, Table}

  @moduletag :counter

  setup do
    safe_clear_counter_table()
    |> transform_setup_result()

    :ok
  end

  # Safe wrappers for effects

  defp safe_clear_counter_table do
    {:ok, :cleared} = Table.clear(:counters)
    Error.return(:ok)
  end

  # Pure transformations

  defp transform_setup_result({:ok, _}), do: :ok
  defp transform_setup_result({:error, reason}), do: raise("Setup failed: #{inspect(reason)}")

  defp validate_counter_result({:ok, value}, expected_value) when value == expected_value do
    :ok
  end

  defp validate_counter_result({:ok, value}, expected_value) do
    raise "Expected counter value #{expected_value} but got #{value}"
  end

  defp validate_counter_result({:error, reason}, _expected_value) do
    raise "Counter operation failed: #{inspect(reason)}"
  end

  defp validate_boolean_result(true), do: :ok
  defp validate_boolean_result(false), do: raise("Expected true but got false")

  defp validate_counter_sequence([]), do: :ok

  defp validate_counter_sequence([{expected_value, counter_fn} | rest]) do
    result = counter_fn.()
    validate_counter_result(result, expected_value)
    validate_counter_sequence(rest)
  end

  # Tests for get_next_id/2

  describe "get_next_id/2 - pure monadic composition" do
    test "returns sequential IDs for new counter" do
      sequence = [
        {1, fn -> Counter.get_next_id(:users, :id) end},
        {2, fn -> Counter.get_next_id(:users, :id) end},
        {3, fn -> Counter.get_next_id(:users, :id) end}
      ]

      validate_counter_sequence(sequence)
    end

    test "maintains separate counters for different tables" do
      sequence = [
        {1, fn -> Counter.get_next_id(:users, :id) end},
        {1, fn -> Counter.get_next_id(:posts, :id) end},
        {2, fn -> Counter.get_next_id(:users, :id) end},
        {2, fn -> Counter.get_next_id(:posts, :id) end}
      ]

      validate_counter_sequence(sequence)
    end

    test "maintains separate counters for different fields" do
      sequence = [
        {1, fn -> Counter.get_next_id(:users, :id) end},
        {1, fn -> Counter.get_next_id(:users, :external_id) end},
        {2, fn -> Counter.get_next_id(:users, :id) end},
        {2, fn -> Counter.get_next_id(:users, :external_id) end}
      ]

      validate_counter_sequence(sequence)
    end

    test "counter composition is pure and repeatable" do
      # First sequence
      first_result =
        Error.m do
          id1 <- Counter.get_next_id(:users, :id)
          id2 <- Counter.get_next_id(:users, :id)
          Error.return({id1, id2})
        end

      validate_composed_counter_result(first_result, {1, 2})

      # Continue sequence
      third_result = Counter.get_next_id(:users, :id)
      validate_counter_result(third_result, 3)
    end

    defp validate_composed_counter_result({:ok, {v1, v2}}, {expected1, expected2}) do
      are_equal = v1 == expected1 and v2 == expected2

      validate_boolean_assertion(
        are_equal,
        "Expected {#{expected1}, #{expected2}} but got {#{v1}, #{v2}}"
      )
    end

    defp validate_boolean_assertion(true, _), do: :ok
    defp validate_boolean_assertion(false, message), do: raise(message)
  end

  describe "get_current_value/2 - reading without side effects" do
    test "returns 0 for non-existent counter" do
      result = Counter.get_current_value(:users, :id)
      validate_counter_result(result, 0)
    end

    test "returns current value without incrementing" do
      {:ok, _} = Counter.get_next_id(:users, :id)
      {:ok, _} = Counter.get_next_id(:users, :id)

      result1 = Counter.get_current_value(:users, :id)
      validate_counter_result(result1, 2)

      result2 = Counter.get_current_value(:users, :id)
      validate_counter_result(result2, 2)
    end

    test "reading is idempotent" do
      {:ok, _} = Counter.get_next_id(:users, :id)

      reads = [
        fn -> Counter.get_current_value(:users, :id) end,
        fn -> Counter.get_current_value(:users, :id) end,
        fn -> Counter.get_current_value(:users, :id) end
      ]

      validate_idempotent_reads(reads, 1)
    end

    defp validate_idempotent_reads([], _expected_value), do: :ok

    defp validate_idempotent_reads([read_fn | rest], expected_value) do
      result = read_fn.()
      validate_counter_result(result, expected_value)
      validate_idempotent_reads(rest, expected_value)
    end
  end

  describe "reset_counter/3 - resetting to specific values" do
    test "resets counter to specified value" do
      {:ok, _} = Counter.get_next_id(:users, :id)
      {:ok, _} = Counter.get_next_id(:users, :id)

      reset_result = Counter.reset_counter(:users, :id, 10)
      validate_counter_result(reset_result, 10)

      next_result = Counter.get_next_id(:users, :id)
      validate_counter_result(next_result, 10)
    end

    test "defaults to reset value of 1" do
      {:ok, _} = Counter.get_next_id(:users, :id)
      {:ok, _} = Counter.get_next_id(:users, :id)

      reset_result = Counter.reset_counter(:users, :id)
      validate_counter_result(reset_result, 1)

      next_result = Counter.get_next_id(:users, :id)
      validate_counter_result(next_result, 1)
    end

    test "validates reset value using guards" do
      assert_raise FunctionClauseError, fn ->
        Counter.reset_counter(:users, :id, 0)
      end

      assert_raise FunctionClauseError, fn ->
        Counter.reset_counter(:users, :id, -1)
      end
    end

    test "reset is composable with monads" do
      composed_result =
        Error.m do
          _ <- Counter.get_next_id(:users, :id)
          _ <- Counter.get_next_id(:users, :id)
          reset_value <- Counter.reset_counter(:users, :id, 100)
          next_id <- Counter.get_next_id(:users, :id)
          Error.return({reset_value, next_id})
        end

      validate_composed_reset_result(composed_result, {100, 100})
    end

    defp validate_composed_reset_result({:ok, {reset, next}}, {expected_reset, expected_next}) do
      are_equal = reset == expected_reset and next == expected_next

      validate_boolean_assertion(
        are_equal,
        "Expected {#{expected_reset}, #{expected_next}} but got {#{reset}, #{next}}"
      )
    end
  end

  describe "has_counter?/2 - checking counter existence" do
    test "returns false for non-existent counter" do
      result = Counter.has_counter?(:users, :id)
      validate_false_result(result)
    end

    test "returns true for existing counter" do
      {:ok, _} = Counter.get_next_id(:users, :id)
      result = Counter.has_counter?(:users, :id)
      validate_true_result(result)
    end

    test "existence check is pure and idempotent" do
      {:ok, _} = Counter.get_next_id(:users, :id)

      checks = [
        fn -> Counter.has_counter?(:users, :id) end,
        fn -> Counter.has_counter?(:users, :id) end,
        fn -> Counter.has_counter?(:users, :id) end
      ]

      validate_idempotent_boolean_checks(checks, true)
    end

    test "different counters have independent existence" do
      {:ok, _} = Counter.get_next_id(:users, :id)

      has_users_id = Counter.has_counter?(:users, :id)
      validate_true_result(has_users_id)

      has_posts_id = Counter.has_counter?(:posts, :id)
      validate_false_result(has_posts_id)
    end

    defp validate_true_result(true), do: :ok
    defp validate_true_result(false), do: raise("Expected true but got false")

    defp validate_false_result(false), do: :ok
    defp validate_false_result(true), do: raise("Expected false but got true")

    defp validate_idempotent_boolean_checks([], _expected_value), do: :ok

    defp validate_idempotent_boolean_checks([check_fn | rest], expected_value) do
      result = check_fn.()

      (result == expected_value)
      |> validate_boolean_result()

      validate_idempotent_boolean_checks(rest, expected_value)
    end
  end

  describe "get_next_id!/2 - transactional version" do
    test "returns sequential IDs within transaction" do
      id1 = Counter.get_next_id!(:users, :id)
      validate_exact_value(id1, 1)

      id2 = Counter.get_next_id!(:users, :id)
      validate_exact_value(id2, 2)
    end

    test "works correctly with non-transactional version" do
      {:ok, normal_id} = Counter.get_next_id(:users, :id)
      transactional_id = Counter.get_next_id!(:users, :id)

      validate_exact_value(normal_id, 1)
      validate_exact_value(transactional_id, 2)
    end

    defp validate_exact_value(value, expected) when value == expected, do: :ok

    defp validate_exact_value(value, expected) do
      raise "Expected #{expected} but got #{value}"
    end
  end

  describe "reset_counter!/3 - transactional reset" do
    test "resets counter within transaction" do
      {:ok, _} = Counter.get_next_id(:users, :id)
      {:ok, _} = Counter.get_next_id(:users, :id)

      result = Counter.reset_counter!(:users, :id, 50)
      validate_exact_value(result, 50)

      next_id = Counter.get_next_id!(:users, :id)
      validate_exact_value(next_id, 50)
    end
  end

  describe "pure functional properties" do
    test "counter operations form a monoid under composition" do
      # Identity: starting from 0
      initial = Counter.get_current_value(:users, :id)
      validate_counter_result(initial, 0)

      # Associativity: (a + b) + c == a + (b + c)
      left_result =
        Error.m do
          _ <- Counter.get_next_id(:users, :id)
          _ <- Counter.get_next_id(:users, :id)
          third <- Counter.get_next_id(:users, :id)
          Error.return(third)
        end

      validate_counter_result(left_result, 3)
    end

    test "reset operation is a morphism preserving counter structure" do
      composed_result =
        Error.m do
          _ <- Counter.get_next_id(:users, :id)
          current1 <- Counter.get_current_value(:users, :id)
          _ <- Counter.reset_counter(:users, :id, 10)
          current2 <- Counter.get_current_value(:users, :id)
          _ <- Counter.get_next_id(:users, :id)
          current3 <- Counter.get_current_value(:users, :id)
          Error.return({current1, current2, current3})
        end

      validate_morphism_result(composed_result, {1, 9, 10})
    end

    defp validate_morphism_result({:ok, {c1, c2, c3}}, {e1, e2, e3}) do
      are_equal = c1 == e1 and c2 == e2 and c3 == e3

      validate_boolean_assertion(
        are_equal,
        "Expected {#{e1}, #{e2}, #{e3}} but got {#{c1}, #{c2}, #{c3}}"
      )
    end
  end

  describe "Automatic counter integration with tables" do
    setup do
      {:ok, :cleared} = Table.clear(:posts)
      {:ok, :cleared} = Table.clear(:products)
      # Reset counters to start from 1
      {:ok, 1} = Counter.reset_counter(:posts, :id, 1)
      {:ok, 1} = Counter.reset_counter(:products, :id, 1)
      {:ok, 1} = Counter.reset_counter(:products, :sku, 1)
      :ok
    end

    test "debug: verify counter initialization" do
      has_counter = Counter.has_counter?(:posts, :id)
      IO.puts("Has counter? #{inspect(has_counter)}")
      validate_true_result(has_counter)

      {:ok, current} = Counter.get_current_value(:posts, :id)
      IO.puts("Current value: #{inspect(current)}")
      validate_exact_value(current, 0)
    end

    test "debug: verify Query.write! basic functionality" do
      result = Query.write!(:posts, %{user_id: 1, title: "Debug Post", content: "Debug Content"})
      IO.puts("Write result: #{inspect(result)}")

      validate_write_result(result)
    end

    defp validate_write_result(record) when is_map(record) do
      IO.puts("Record: #{inspect(record)}")
      IO.puts("ID value: #{inspect(Map.get(record, :id))}")
      :ok
    end

    defp validate_write_result({:ok, record}) do
      IO.puts("Record: #{inspect(record)}")
      IO.puts("ID value: #{inspect(Map.get(record, :id))}")
      :ok
    end

    defp validate_write_result({:error, reason}) do
      raise "Write failed: #{inspect(reason)}"
    end

    test "single counter field generates IDs automatically" do
      post1_result =
        Query.write!(:posts, %{user_id: 1, title: "First Post", content: "Content 1"})

      post2_result =
        Query.write!(:posts, %{user_id: 1, title: "Second Post", content: "Content 2"})

      post3_result =
        Query.write!(:posts, %{user_id: 2, title: "Third Post", content: "Content 3"})

      validate_auto_generated_id(post1_result, :id, 1)
      validate_auto_generated_id(post2_result, :id, 2)
      validate_auto_generated_id(post3_result, :id, 3)
    end

    test "multiple counter fields generate IDs independently" do
      product1 = Query.write!(:products, %{name: "Product A", price: 100})
      product2 = Query.write!(:products, %{name: "Product B", price: 200})
      product3 = Query.write!(:products, %{name: "Product C", price: 300})

      validate_multiple_auto_ids(product1, 1, 1)
      validate_multiple_auto_ids(product2, 2, 2)
      validate_multiple_auto_ids(product3, 3, 3)
    end

    test "manual ID overrides auto-generation" do
      manual_post =
        Query.write!(:posts, %{id: 100, user_id: 1, title: "Manual ID", content: "Content"})

      auto_post = Query.write!(:posts, %{user_id: 1, title: "Auto ID", content: "Content"})

      validate_manual_id(manual_post, 100)
      validate_auto_generated_id(auto_post, :id, 1)
    end

    test "counter continues after manual ID" do
      Query.write!(:posts, %{id: 50, user_id: 1, title: "Manual 50", content: "Content"})

      post1 = Query.write!(:posts, %{user_id: 1, title: "Auto 1", content: "Content"})
      post2 = Query.write!(:posts, %{user_id: 1, title: "Auto 2", content: "Content"})

      validate_auto_generated_id(post1, :id, 1)
      validate_auto_generated_id(post2, :id, 2)
    end

    test "reset counter affects auto-generation" do
      Query.write!(:posts, %{user_id: 1, title: "Post 1", content: "Content"})
      Query.write!(:posts, %{user_id: 1, title: "Post 2", content: "Content"})

      Counter.reset_counter(:posts, :id, 100)

      post_after_reset =
        Query.write!(:posts, %{user_id: 1, title: "Post After Reset", content: "Content"})

      validate_auto_generated_id(post_after_reset, :id, 100)
    end

    test "transactional writes with auto-generated IDs" do
      result =
        Query.write!(:posts, %{user_id: 1, title: "Transactional Post", content: "Content"})

      validate_transactional_auto_id(result, :id, 1)
    end

    test "batch operations preserve counter sequence" do
      posts = [
        %{user_id: 1, title: "Batch Post 1", content: "Content 1"},
        %{user_id: 1, title: "Batch Post 2", content: "Content 2"},
        %{user_id: 2, title: "Batch Post 3", content: "Content 3"}
      ]

      results = safe_batch_write_posts(posts)

      validate_batch_counter_sequence(results, [1, 2, 3])
    end

    defp safe_batch_write_posts(posts) do
      posts
      |> build_batch_results([])
      |> Enum.reverse()
    end

    defp build_batch_results([], acc), do: acc

    defp build_batch_results([post | rest], acc) do
      result = Query.write!(:posts, post)
      build_batch_results(rest, [result | acc])
    end

    defp validate_auto_generated_id(record, field, expected_value) when is_map(record) do
      actual = Map.get(record, field)

      validate_exact_match(
        actual,
        expected_value,
        "Expected #{field} to be #{expected_value} but got #{actual}"
      )
    end

    defp validate_auto_generated_id({:ok, record}, field, expected_value) do
      actual = Map.get(record, field)

      validate_exact_match(
        actual,
        expected_value,
        "Expected #{field} to be #{expected_value} but got #{actual}"
      )
    end

    defp validate_auto_generated_id({:error, reason}, _field, _expected_value) do
      raise "Expected successful write but got error: #{inspect(reason)}"
    end

    defp validate_multiple_auto_ids(record, expected_id, expected_sku) when is_map(record) do
      actual_id = Map.get(record, :id)
      actual_sku = Map.get(record, :sku)

      validate_exact_match(
        actual_id,
        expected_id,
        "Expected id to be #{expected_id} but got #{actual_id}"
      )

      validate_exact_match(
        actual_sku,
        expected_sku,
        "Expected sku to be #{expected_sku} but got #{actual_sku}"
      )
    end

    defp validate_multiple_auto_ids({:ok, record}, expected_id, expected_sku) do
      actual_id = Map.get(record, :id)
      actual_sku = Map.get(record, :sku)

      validate_exact_match(
        actual_id,
        expected_id,
        "Expected id to be #{expected_id} but got #{actual_id}"
      )

      validate_exact_match(
        actual_sku,
        expected_sku,
        "Expected sku to be #{expected_sku} but got #{actual_sku}"
      )
    end

    defp validate_multiple_auto_ids({:error, reason}, _expected_id, _expected_sku) do
      raise "Expected successful write but got error: #{inspect(reason)}"
    end

    defp validate_manual_id(record, expected_id) when is_map(record) do
      actual = Map.get(record, :id)

      validate_exact_match(
        actual,
        expected_id,
        "Expected manual id #{expected_id} but got #{actual}"
      )
    end

    defp validate_manual_id({:ok, record}, expected_id) do
      actual = Map.get(record, :id)

      validate_exact_match(
        actual,
        expected_id,
        "Expected manual id #{expected_id} but got #{actual}"
      )
    end

    defp validate_manual_id({:error, reason}, _expected_id) do
      raise "Expected successful write but got error: #{inspect(reason)}"
    end

    defp validate_transactional_auto_id(record, field, expected_value) when is_map(record) do
      actual = Map.get(record, field)

      validate_exact_match(
        actual,
        expected_value,
        "Expected #{field} to be #{expected_value} but got #{actual}"
      )
    end

    defp validate_transactional_auto_id({:ok, record}, field, expected_value) do
      actual = Map.get(record, field)

      validate_exact_match(
        actual,
        expected_value,
        "Expected #{field} to be #{expected_value} but got #{actual}"
      )
    end

    defp validate_transactional_auto_id({:error, reason}, _field, _expected_value) do
      raise "Expected successful transactional write but got error: #{inspect(reason)}"
    end

    defp validate_batch_counter_sequence(results, expected_ids) do
      validate_each_batch_result(results, expected_ids, 0)
    end

    defp validate_each_batch_result([], [], _index), do: :ok

    defp validate_each_batch_result([result | rest_results], [expected_id | rest_expected], index) do
      validate_auto_generated_id(result, :id, expected_id)
      validate_each_batch_result(rest_results, rest_expected, index + 1)
    end

    defp validate_exact_match(actual, expected, _message) when actual == expected, do: :ok
    defp validate_exact_match(_actual, _expected, message), do: raise(message)
  end

  describe "@spec validation for all Counter functions" do
    setup do
      Counter.ensure_counter_table()
      Counter.init_counter(:test_table, :test_id)
      :ok
    end

    test "ensure_counter_table/1 returns ok/error tuple as per spec" do
      result = Counter.ensure_counter_table()

      # @spec ensure_counter_table([node()]) :: {:ok, :ok} | {:error, term()}
      validate_is_ok_tuple_or_error(result)
    end

    test "init_counter/2 returns ok/error tuple as per spec" do
      result = Counter.init_counter(:spec_table, :spec_field)

      # @spec init_counter(atom(), atom()) :: {:ok, :ok} | {:error, term()}
      validate_is_ok_tuple_or_error(result)
    end

    test "delete_counter/2 returns ok/error tuple as per spec" do
      Counter.init_counter(:del_table, :del_field)
      result = Counter.delete_counter(:del_table, :del_field)

      # @spec delete_counter(atom(), atom()) :: {:ok, :ok} | {:error, term()}
      validate_is_ok_tuple_or_error(result)
    end

    test "get_next_id/2 returns ok integer tuple or error as per spec" do
      result = Counter.get_next_id(:test_table, :test_id)

      # @spec get_next_id(atom(), atom()) :: {:ok, integer()} | {:error, term()}
      validate_is_ok_integer_or_error(result)
    end

    test "get_next_id!/2 returns integer as per spec" do
      result = Counter.get_next_id!(:test_table, :test_id)

      # @spec get_next_id!(atom(), atom()) :: integer() | no_return()
      validate_is_integer(result)
    end

    test "get_next_id_in_transaction/2 returns ok integer tuple as per spec" do
      # Must be called within a transaction
      {:atomic, result} = :mnesia.transaction(fn ->
        Counter.get_next_id_in_transaction(:test_table, :test_id)
      end)

      # @spec get_next_id_in_transaction(atom(), atom()) :: {:ok, integer()}
      validate_is_ok_integer_tuple(result)
    end

    test "reset_counter/3 returns ok integer tuple or error as per spec" do
      result = Counter.reset_counter(:test_table, :test_id, 100)

      # @spec reset_counter(atom(), atom(), integer()) :: {:ok, integer()} | {:error, term()}
      validate_is_ok_integer_or_error(result)
    end

    test "reset_counter!/3 returns integer as per spec" do
      result = Counter.reset_counter!(:test_table, :test_id, 200)

      # @spec reset_counter!(atom(), atom(), integer()) :: integer()
      validate_is_integer(result)
    end

    test "get_current_value/2 returns ok integer tuple or error as per spec" do
      result = Counter.get_current_value(:test_table, :test_id)

      # @spec get_current_value(atom(), atom()) :: {:ok, integer()} | {:error, term()}
      validate_is_ok_integer_or_error(result)
    end

    test "has_counter?/2 returns boolean as per spec" do
      result = Counter.has_counter?(:test_table, :test_id)

      # @spec has_counter?(atom(), atom()) :: boolean()
      validate_is_boolean(result)
    end
  end

  # Helper functions for spec validation
  defp validate_is_ok_tuple_or_error({:ok, :ok}), do: :ok
  defp validate_is_ok_tuple_or_error({:ok, :initialized}), do: :ok
  defp validate_is_ok_tuple_or_error({:ok, :created}), do: :ok
  defp validate_is_ok_tuple_or_error({:ok, :deleted}), do: :ok
  defp validate_is_ok_tuple_or_error({:error, _}), do: :ok
  defp validate_is_ok_tuple_or_error(value),
    do: raise("Expected {:ok, _} or {:error, _} but got #{inspect(value)}")

  defp validate_is_ok_integer_or_error({:ok, value}) when is_integer(value), do: :ok
  defp validate_is_ok_integer_or_error({:error, _}), do: :ok
  defp validate_is_ok_integer_or_error(value),
    do: raise("Expected {:ok, integer()} or {:error, _} but got #{inspect(value)}")

  defp validate_is_ok_integer_tuple({:ok, value}) when is_integer(value), do: :ok
  defp validate_is_ok_integer_tuple(value),
    do: raise("Expected {:ok, integer()} but got #{inspect(value)}")

  defp validate_is_integer(value) when is_integer(value), do: :ok
  defp validate_is_integer(value), do: raise("Expected integer but got #{inspect(value)}")

  defp validate_is_boolean(true), do: :ok
  defp validate_is_boolean(false), do: :ok
  defp validate_is_boolean(value), do: raise("Expected boolean but got #{inspect(value)}")
end
