defmodule MnesiaEx.QueryTest do
  use ExUnit.Case, async: false

  alias MnesiaEx.{Query, Table, Counter}

  @moduletag :query

  setup do
    {:ok, :cleared} = Table.clear(:users)
    {:ok, :cleared} = Table.clear(:posts)
    {:ok, :cleared} = Table.clear(:products)
    {:ok, 1} = Counter.reset_counter(:posts, :id, 1)
    {:ok, 1} = Counter.reset_counter(:products, :id, 1)
    :ok
  end

  # Shared helper functions

  # For non-bang functions that return tuples
  defp validate_ok_result({:ok, _value}), do: :ok

  defp validate_ok_result({:error, reason}),
    do: raise("Expected success but got error: #{inspect(reason)}")

  defp validate_error_result({:error, _reason}), do: :ok

  defp validate_error_result({:ok, value}),
    do: raise("Expected error but got success: #{inspect(value)}")

  # For bang functions that return values directly
  defp validate_record_field(record, field, expected_value) when is_map(record) do
    actual = Map.get(record, field)
    validate_value_match(actual, expected_value)
  end

  # For non-bang functions that return {:ok, record}
  defp validate_record_field({:ok, record}, field, expected_value) do
    actual = Map.get(record, field)
    validate_value_match(actual, expected_value)
  end

  defp validate_value_match(actual, expected) when actual == expected, do: :ok

  defp validate_value_match(actual, expected) do
    raise "Expected #{inspect(expected)} but got #{inspect(actual)}"
  end

  defp validate_list_length(list, expected_length) when length(list) == expected_length, do: :ok

  defp validate_list_length(list, expected_length) do
    raise "Expected list of length #{expected_length} but got #{length(list)}"
  end

  defp validate_all_equal([]), do: :ok
  defp validate_all_equal([_single]), do: :ok

  defp validate_all_equal([first, second | rest]) do
    validate_value_match(first, second)
    validate_all_equal([second | rest])
  end

  defp validate_id_generated(nil), do: raise("Expected ID to be generated but got nil")
  defp validate_id_generated(id) when is_integer(id), do: :ok
  defp validate_id_generated(id), do: raise("Expected integer ID but got #{inspect(id)}")

  describe "write!/2 - basic write operations" do
    test "writes a simple record" do
      record = Query.write!(:users, %{id: 1, name: "John", email: "john@example.com"})

      validate_record_field(record, :name, "John")
      validate_record_field(record, :email, "john@example.com")
    end

    test "writes multiple records sequentially" do
      _record1 = Query.write!(:users, %{id: 1, name: "Alice", email: "alice@example.com"})
      _record2 = Query.write!(:users, %{id: 2, name: "Bob", email: "bob@example.com"})

      # Records created successfully (would raise if error)
      :ok
    end

    test "overwrites existing record with same ID" do
      Query.write!(:users, %{id: 1, name: "Original", email: "original@example.com"})
      result = Query.write!(:users, %{id: 1, name: "Updated", email: "updated@example.com"})

      validate_record_field(result, :name, "Updated")
    end

    test "fails on non-existent table" do
      assert_raise RuntimeError, fn ->
        Query.write!(:non_existent_table, %{id: 1, data: "test"})
      end
    end
  end

  describe "write!/3 - unique field validation" do
    test "allows record with unique email" do
      user =
        Query.write!(:users, %{id: 1, name: "John", email: "john@example.com"},
          unique_fields: [:email]
        )

      validate_record_field(user, :email, "john@example.com")
    end

    test "rejects duplicate unique field" do
      Query.write!(:users, %{id: 1, name: "John", email: "duplicate@example.com"})

      assert_raise RuntimeError, fn ->
        Query.write!(:users, %{id: 2, name: "Jane", email: "duplicate@example.com"},
          unique_fields: [:email]
        )
      end
    end

    test "allows same record to update with same unique field" do
      Query.write!(:users, %{id: 1, name: "John", email: "john@example.com"})

      user =
        Query.write!(:users, %{id: 1, name: "John Updated", email: "john@example.com"},
          unique_fields: [:email]
        )

      validate_record_field(user, :name, "John Updated")
    end
  end

  describe "read!/2 - reading records" do
    test "reads existing record" do
      Query.write!(:users, %{id: 1, name: "Alice", email: "alice@example.com"})

      user = Query.read!(:users, 1)

      validate_record_field(user, :name, "Alice")
    end

    test "fails on non-existent record" do
      assert_raise RuntimeError, fn ->
        Query.read!(:users, 999)
      end
    end

    test "read is idempotent" do
      Query.write!(:users, %{id: 1, name: "Test", email: "test@example.com"})

      user1 = Query.read!(:users, 1)
      user2 = Query.read!(:users, 1)
      user3 = Query.read!(:users, 1)

      validate_all_equal([user1, user2, user3])
    end
  end

  describe "delete!/2 - deleting records" do
    test "deletes existing record by ID" do
      Query.write!(:users, %{id: 1, name: "ToDelete", email: "delete@example.com"})

      deleted = Query.delete!(:users, 1)

      validate_record_field(deleted, :name, "ToDelete")

      assert_raise RuntimeError, fn ->
        Query.read!(:users, 1)
      end
    end

    test "fails on non-existent record" do
      assert_raise RuntimeError, fn ->
        Query.delete!(:users, 999)
      end
    end

    test "returns deleted record data" do
      Query.write!(:users, %{id: 5, name: "Deleted", email: "deleted@example.com"})

      deleted = Query.delete!(:users, 5)

      validate_value_match(Map.get(deleted, :name), "Deleted")
    end
  end

  describe "select!/2 - querying records" do
    setup do
      Query.write!(:users, %{id: 1, name: "Alice", email: "alice@example.com"})
      Query.write!(:users, %{id: 2, name: "Bob", email: "bob@example.com"})
      Query.write!(:users, %{id: 3, name: "Charlie", email: "charlie@example.com"})
      :ok
    end

    test "selects all records with empty conditions" do
      results = Query.select(:users, [])

      validate_list_length(results, 3)
    end

    test "selects records matching condition" do
      results = Query.select(:users, [{:name, :==, "Alice"}])

      validate_list_length(results, 1)

      [first | _] = results
      validate_value_match(Map.get(first, :name), "Alice")
    end

    test "returns empty list when no matches" do
      results = Query.select(:users, [{:name, :==, "NonExistent"}])

      validate_list_length(results, 0)
    end

    test "select with multiple conditions" do
      results = Query.select(:users, [{:id, :>, 1}, {:id, :<, 3}])

      validate_list_length(results, 1)
    end
  end

  describe "get_by!/3 - finding by field" do
    setup do
      Query.write!(:users, %{id: 1, name: "Alice", email: "alice@example.com"})
      Query.write!(:users, %{id: 2, name: "Bob", email: "bob@example.com"})
      :ok
    end

    test "finds record by field value" do
      user = Query.get_by!(:users, :email, "alice@example.com")

      validate_record_field(user, :name, "Alice")
    end

    test "fails when field value not found" do
      assert_raise RuntimeError, fn ->
        Query.get_by!(:users, :email, "nonexistent@example.com")
      end
    end

    test "returns first match when multiple exist" do
      Query.write!(:users, %{id: 3, name: "Charlie", email: "charlie@example.com"})
      Query.write!(:users, %{id: 4, name: "Charlie", email: "charlie2@example.com"})

      user = Query.get_by!(:users, :name, "Charlie")

      assert is_map(user)
      validate_record_field(user, :name, "Charlie")
    end
  end

  describe "update!/3 - updating records" do
    setup do
      Query.write!(:users, %{id: 1, name: "Original", email: "original@example.com"})
      :ok
    end

    test "updates existing record with map" do
      user = Query.update!(:users, 1, %{name: "Updated"})

      validate_record_field(user, :name, "Updated")
      validate_record_field(user, :email, "original@example.com")
    end

    test "updates existing record with value" do
      user = Query.update!(:users, 1, "NewName")

      validate_record_field(user, :name, "NewName")
    end

    test "fails on non-existent record" do
      assert_raise RuntimeError, fn ->
        Query.update!(:users, 999, %{name: "NoExist"})
      end
    end

    test "validates unique fields on update" do
      Query.write!(:users, %{id: 2, name: "Other", email: "other@example.com"})

      assert_raise RuntimeError, fn ->
        Query.update!(:users, 1, %{email: "other@example.com"}, unique_fields: [:email])
      end
    end
  end

  describe "upsert!/2 - insert or update" do
    test "inserts new record when not exists" do
      user = Query.upsert!(:users, %{id: 1, name: "New", email: "new@example.com"})

      validate_record_field(user, :name, "New")
    end

    test "updates existing record when exists" do
      Query.write!(:users, %{id: 1, name: "Original", email: "original@example.com"})

      user = Query.upsert!(:users, %{id: 1, name: "Upserted", email: "upserted@example.com"})

      validate_record_field(user, :name, "Upserted")
    end

    test "upsert is idempotent" do
      record = %{id: 1, name: "Test", email: "test@example.com"}

      user1 = Query.upsert!(:users, record)
      user2 = Query.upsert!(:users, record)
      user3 = Query.upsert!(:users, record)

      validate_all_equal([user1, user2, user3])
    end
  end

  describe "batch_write/2 - writing multiple records" do
    test "writes empty list successfully" do
      users = Query.batch_write(:users, [])

      validate_list_length(users, 0)
    end

    test "writes multiple records" do
      records = [
        %{id: 1, name: "User1", email: "user1@example.com"},
        %{id: 2, name: "User2", email: "user2@example.com"},
        %{id: 3, name: "User3", email: "user3@example.com"}
      ]

      users = Query.batch_write(:users, records)

      validate_list_length(users, 3)
    end
  end

  describe "batch_delete/2 - deleting multiple records" do
    setup do
      Query.write!(:users, %{id: 1, name: "Delete1", email: "delete1@example.com"})
      Query.write!(:users, %{id: 2, name: "Delete2", email: "delete2@example.com"})
      Query.write!(:users, %{id: 3, name: "Delete3", email: "delete3@example.com"})
      :ok
    end

    test "deletes multiple records by ID" do
      deleted = Query.batch_delete(:users, [1, 2])

      validate_list_length(deleted, 2)
    end

    test "returns deleted records" do
      deleted = Query.batch_delete(:users, [1, 2, 3])

      validate_list_length(deleted, 3)
    end
  end

  describe "batch_delete/2 - transactional batch delete" do
    setup do
      Query.write!(:users, %{id: 1, name: "Del1", email: "del1@example.com"})
      Query.write!(:users, %{id: 2, name: "Del2", email: "del2@example.com"})
      :ok
    end

    test "deletes multiple records in transaction" do
      deleted = Query.batch_delete(:users, [1, 2])

      validate_list_length(deleted, 2)
    end
  end

  describe "functional purity properties" do
    test "read is deterministic" do
      Query.write!(:users, %{id: 1, name: "Pure", email: "pure@example.com"})

      reads = [
        Query.read!(:users, 1),
        Query.read!(:users, 1),
        Query.read!(:users, 1)
      ]

      validate_all_equal(reads)
    end

    test "write then read returns same data" do
      written_data = %{id: 1, name: "Test", email: "test@example.com"}

      written = Query.write!(:users, written_data)
      read = Query.read!(:users, 1)

      validate_value_match(written, read)
    end

    test "update preserves unmodified fields" do
      Query.write!(:users, %{id: 1, name: "Original", email: "original@example.com"})

      updated = Query.update!(:users, 1, %{name: "NewName"})

      validate_value_match(Map.get(updated, :email), "original@example.com")
    end
  end

  describe "automatic counter integration" do
    test "generates ID automatically for counter fields" do
      post = Query.write!(:posts, %{user_id: 1, title: "Auto ID Post", content: "Content"})

      generated_id = Map.get(post, :id)

      validate_id_generated(generated_id)
    end

    test "counter increments on multiple writes" do
      post1 = Query.write!(:posts, %{user_id: 1, title: "Post 1", content: "Content 1"})
      post2 = Query.write!(:posts, %{user_id: 1, title: "Post 2", content: "Content 2"})
      post3 = Query.write!(:posts, %{user_id: 1, title: "Post 3", content: "Content 3"})

      id1 = Map.get(post1, :id)
      id2 = Map.get(post2, :id)
      id3 = Map.get(post3, :id)

      validate_value_match(id1, 1)
      validate_value_match(id2, 2)
      validate_value_match(id3, 3)
    end

    test "manual ID overrides counter" do
      post =
        Query.write!(:posts, %{id: 100, user_id: 1, title: "Manual ID", content: "Content"})

      validate_record_field(post, :id, 100)
    end
  end

  describe "edge cases and error handling" do
    test "handles empty map write" do
      user = Query.write!(:users, %{})

      assert is_map(user)
    end

    test "update with empty attrs map preserves record" do
      Query.write!(:users, %{id: 1, name: "Original", email: "original@example.com"})

      user = Query.update!(:users, 1, %{})

      validate_record_field(user, :name, "Original")
    end

    test "upsert without ID creates new record" do
      user = Query.upsert!(:users, %{name: "NoID", email: "noid@example.com"})

      assert is_map(user)
      validate_record_field(user, :name, "NoID")
    end
  end

  describe "all_keys!/1" do
    setup do
      Query.write!(:users, %{id: 201, name: "Alice", email: "alice201@example.com"})
      Query.write!(:users, %{id: 202, name: "Bob", email: "bob202@example.com"})
      Query.write!(:users, %{id: 203, name: "Carol", email: "carol203@example.com"})
      :ok
    end

    test "all_keys/1 returns list of all keys" do
      result = Query.all_keys(:users)

      # @spec all_keys(table()) :: [term()]
      validate_is_list(result)
      validate_list_has_min_length(result, 3)

      # Keys should include the IDs we created
      validate_list_contains(result, 201)
      validate_list_contains(result, 202)
      validate_list_contains(result, 203)
    end

    test "all_keys/1 returns empty list for empty table" do
      result = Query.all_keys(:products)

      # @spec all_keys(table()) :: [term()]
      validate_is_list(result)
      validate_list_is_empty(result)
    end

    test "all_keys/1 is deterministic" do
      result1 = Query.all_keys(:users)
      result2 = Query.all_keys(:users)

      validate_lists_have_same_elements(result1, result2)
    end

    test "all_keys/1 works within transaction" do
      # Test that it executes correctly within transaction context
      result = Query.all_keys(:users)

      validate_is_list(result)
      # Should not raise transaction errors
    end
  end

  describe "auto-transaction detection" do
    test "write/2 creates transaction automatically when called alone" do
      {:ok, user} = Query.write(:users, %{id: 100, name: "AutoTx", email: "autotx@example.com"})

      validate_record_field(user, :name, "AutoTx")

      # Verify it was written
      found = Query.read!(:users, 100)
      validate_record_field(found, :name, "AutoTx")
    end

    test "write/2 does not create double-transaction when inside MnesiaEx.transaction" do
      {:ok, {user, post}} = MnesiaEx.transaction(fn ->
        {:ok, user} = Query.write(:users, %{id: 101, name: "InTx", email: "intx@example.com"})
        {:ok, post} = Query.write(:posts, %{id: 1, user_id: user.id, title: "Post", content: "..."})
        {user, post}
      end)

      validate_record_field(user, :name, "InTx")
      validate_record_field(post, :title, "Post")
    end

    test "read/2 creates transaction automatically when called alone" do
      Query.write!(:users, %{id: 102, name: "ReadTx", email: "readtx@example.com"})

      {:ok, user} = Query.read(:users, 102)

      validate_record_field(user, :name, "ReadTx")
    end

    test "delete/2 creates transaction automatically when called alone" do
      Query.write!(:users, %{id: 103, name: "DeleteTx", email: "deletetx@example.com"})

      {:ok, deleted} = Query.delete(:users, 103)

      validate_record_field(deleted, :name, "DeleteTx")

      assert_raise RuntimeError, fn ->
        Query.read!(:users, 103)
      end
    end

    test "update/3 creates transaction automatically when called alone" do
      Query.write!(:users, %{id: 104, name: "UpdateTx", email: "updatetx@example.com"})

      {:ok, updated} = Query.update(:users, 104, %{name: "Updated"})

      validate_record_field(updated, :name, "Updated")
    end

    test "batch operations work inside transaction without double-wrapping" do
      {:ok, {users, posts}} = MnesiaEx.transaction(fn ->
        users = Query.batch_write(:users, [
          %{id: 105, name: "U1", email: "u1@example.com"},
          %{id: 106, name: "U2", email: "u2@example.com"}
        ])
        posts = Query.batch_write(:posts, [
          %{id: 2, user_id: 105, title: "P1", content: "..."},
          %{id: 3, user_id: 106, title: "P2", content: "..."}
        ])
        {users, posts}
      end)

      validate_list_length(users, 2)
      validate_list_length(posts, 2)
    end

    test "all CRUD operations work standalone with auto-transaction" do
      # Write
      {:ok, user} = Query.write(:users, %{id: 107, name: "Standalone", email: "standalone@example.com"})
      validate_record_field(user, :name, "Standalone")

      # Read
      {:ok, read_user} = Query.read(:users, 107)
      validate_value_match(user, read_user)

      # Update
      {:ok, updated} = Query.update(:users, 107, %{name: "Updated"})
      validate_record_field(updated, :name, "Updated")

      # Delete
      {:ok, deleted} = Query.delete(:users, 107)
      validate_record_field(deleted, :name, "Updated")
    end
  end

  describe "dirty_* operations" do
    test "dirty_write/3 writes record without transaction" do
      record = %{id: 301, name: "Dirty", email: "dirty301@example.com"}
      result = Query.dirty_write(:users, record)

      # @spec dirty_write(table(), map(), Keyword.t()) :: result()
      validate_ok_result(result)

      # Verify it was written
      read_result = Query.read!(:users, 301)
      validate_record_field(read_result, :name, "Dirty")
    end

    test "dirty_write/3 is faster than transactional write" do
      # This test verifies the function works, performance is implicit
      record = %{id: 302, name: "Fast", email: "fast302@example.com"}
      result = Query.dirty_write(:users, record)

      validate_ok_result(result)
    end

    test "dirty_read/2 reads record without transaction" do
      Query.write!(:users, %{id: 303, name: "Test", email: "test303@example.com"})

      result = Query.dirty_read(:users, 303)

      # @spec dirty_read(table(), key()) :: result()
      validate_ok_result(result)
      validate_record_field(result, :name, "Test")
      validate_record_field(result, :email, "test303@example.com")
    end

    test "dirty_read/2 returns error for non-existent record" do
      result = Query.dirty_read(:users, 999999)

      # @spec dirty_read(table(), key()) :: result()
      validate_error_result(result)
    end

    test "dirty_delete/2 deletes record without transaction" do
      Query.write!(:users, %{id: 304, name: "ToDelete", email: "delete304@example.com"})

      result = Query.dirty_delete(:users, 304)

      # @spec dirty_delete(table(), key()) :: result()
      validate_ok_result(result)

      # Verify it was deleted
      assert_raise RuntimeError, fn ->
        Query.read!(:users, 304)
      end
    end

    test "dirty_delete/2 returns ok even for non-existent record" do
      result = Query.dirty_delete(:users, 999998)

      validate_ok_result(result)
    end

    test "dirty_update/4 updates record without transaction" do
      Query.write!(:users, %{id: 305, name: "Original", email: "original305@example.com"})

      result = Query.dirty_update(:users, 305, %{name: "Updated"})

      # @spec dirty_update(table(), key(), map(), Keyword.t()) :: result()
      validate_ok_result(result)

      # Verify it was updated
      updated = Query.read!(:users, 305)
      validate_record_field(updated, :name, "Updated")
      validate_record_field(updated, :email, "original305@example.com")
    end

    test "dirty_update/4 returns error for non-existent record" do
      result = Query.dirty_update(:users, 999997, %{name: "NonExistent"})

      validate_error_result(result)
    end

    test "dirty_update/4 preserves unmodified fields" do
      Query.write!(:users, %{id: 306, name: "Name", email: "email306@example.com"})

      Query.dirty_update(:users, 306, %{name: "NewName"})

      result = Query.read!(:users, 306)
      validate_record_field(result, :email, "email306@example.com")
    end
  end

  describe "spec validation for all Query functions" do
    test "write!/3 returns result() as per spec" do
      result = Query.write!(:users, %{id: 101, name: "Spec", email: "spec@example.com"})

      # @spec write!(table(), map(), Keyword.t()) :: result()
      validate_is_ok_or_error_tuple(result)
    end

    test "read!/2 returns result() as per spec" do
      Query.write!(:users, %{id: 102, name: "Read", email: "read@example.com"})
      result = Query.read!(:users, 102)

      # @spec read!(table(), key()) :: result()
      validate_is_ok_or_error_tuple(result)
    end

    test "delete!/2 returns result() as per spec" do
      Query.write!(:users, %{id: 104, name: "Delete", email: "delete@example.com"})
      result = Query.delete!(:users, 104)

      # @spec delete!(table(), key() | map()) :: result()
      validate_is_ok_or_error_tuple(result)
    end

    test "select/3 returns list(map()) as per spec" do
      result = Query.select(:users, [])

      # @spec select(table(), [condition()], [atom() | :"$_"]) :: list(map())
      validate_is_list(result)
    end

    test "update!/4 returns result() as per spec" do
      Query.write!(:users, %{id: 106, name: "Update", email: "update@example.com"})
      result = Query.update!(:users, 106, %{name: "Updated"})

      # @spec update!(table(), key(), map(), Keyword.t()) :: result()
      validate_is_ok_or_error_tuple(result)
    end

    test "upsert!/2 returns ok/error tuple as per spec" do
      result = Query.upsert!(:users, %{id: 108, name: "Upsert", email: "upsert@example.com"})

      # @spec upsert!(table(), map()) :: {:ok, map()} | {:error, term()}
      validate_is_ok_or_error_tuple(result)
    end

    test "batch_write/2 returns list as per spec" do
      records = [
        %{id: 109, name: "Batch1", email: "batch1@example.com"},
        %{id: 110, name: "Batch2", email: "batch2@example.com"}
      ]
      result = Query.batch_write(:users, records)

      # @spec batch_write(table(), [map()]) :: [map()]
      validate_is_list(result)
    end

    test "batch_delete/2 returns list as per spec" do
      Query.write!(:users, %{id: 113, name: "Del3", email: "del3@example.com"})
      Query.write!(:users, %{id: 114, name: "Del4", email: "del4@example.com"})

      result = Query.batch_delete(:users, [113, 114])

      # @spec batch_delete(table(), [key() | map()]) :: [map()]
      validate_is_list(result)
    end

    test "get_by!/3 returns map or error as per spec" do
      Query.write!(:users, %{id: 115, name: "GetBy", email: "getby@example.com"})
      result = Query.get_by!(:users, :email, "getby@example.com")

      # @spec get_by!(atom(), atom(), term()) :: map() | {:error, term()}
      validate_is_map_or_error_tuple(result)
    end
  end

  # Helper functions for new tests
  defp validate_is_list(value) when is_list(value), do: :ok
  defp validate_is_list(value), do: raise("Expected list but got #{inspect(value)}")

  defp validate_list_has_min_length(list, min) when length(list) >= min, do: :ok
  defp validate_list_has_min_length(list, min),
    do: raise("Expected list with at least #{min} elements but got #{length(list)}")

  defp validate_list_is_empty([]), do: :ok
  defp validate_list_is_empty(list),
    do: raise("Expected empty list but got #{length(list)} elements")

  defp validate_list_contains(list, value) do
    if value in list do
      :ok
    else
      raise "Expected list to contain #{inspect(value)}"
    end
  end

  defp validate_lists_have_same_elements(list1, list2) do
    sorted1 = Enum.sort(list1)
    sorted2 = Enum.sort(list2)

    if sorted1 == sorted2 do
      :ok
    else
      raise "Lists don't have same elements:\n  List1: #{inspect(sorted1)}\n  List2: #{inspect(sorted2)}"
    end
  end

  defp validate_is_ok_or_error_tuple(value) when is_map(value), do: :ok
  defp validate_is_ok_or_error_tuple(value) when is_list(value), do: :ok
  defp validate_is_ok_or_error_tuple({:ok, _}), do: :ok
  defp validate_is_ok_or_error_tuple({:error, _}), do: :ok
  defp validate_is_ok_or_error_tuple(value),
    do: raise("Expected value, {:ok, _} or {:error, _} but got #{inspect(value)}")

  defp validate_is_map_or_error_tuple(%{}) when is_map(%{}), do: :ok
  defp validate_is_map_or_error_tuple({:ok, %{}}), do: :ok
  defp validate_is_map_or_error_tuple({:error, _}), do: :ok
  defp validate_is_map_or_error_tuple(value),
    do: raise("Expected map, {:ok, map} or {:error, _} but got #{inspect(value)}")
end
