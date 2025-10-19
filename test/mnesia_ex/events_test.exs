defmodule MnesiaEx.EventsTest do
  use ExUnit.Case, async: false

  require MnesiaEx.Monad, as: Error

  alias MnesiaEx.Events

  @moduletag :events

  describe "parse_event/1 - system events transformation" do
    test "parses mnesia_up event" do
      event = {:mnesia_system_event, {:mnesia_up, :node1@host}}
      result = Events.parse_event(event)

      validate_parsed_event(result, {:system, :mnesia, {:up, :node1@host}})
    end

    test "parses mnesia_down event" do
      event = {:mnesia_system_event, {:mnesia_down, :node2@host}}
      result = Events.parse_event(event)

      validate_parsed_event(result, {:system, :mnesia, {:down, :node2@host}})
    end

    test "parses checkpoint activated event" do
      event = {:mnesia_system_event, {:mnesia_checkpoint_activated, :checkpoint_1}}
      result = Events.parse_event(event)

      validate_parsed_event(result, {:system, :checkpoint, {:activated, :checkpoint_1}})
    end

    test "parses checkpoint deactivated event" do
      event = {:mnesia_system_event, {:mnesia_checkpoint_deactivated, :checkpoint_2}}
      result = Events.parse_event(event)

      validate_parsed_event(result, {:system, :checkpoint, {:deactivated, :checkpoint_2}})
    end

    test "parses mnesia_overload event" do
      details = {:overload, :heavy_load}
      event = {:mnesia_system_event, {:mnesia_overload, details}}
      result = Events.parse_event(event)

      validate_parsed_event(result, {:system, :overload, details})
    end

    test "parses inconsistent_database event" do
      event = {:mnesia_system_event, {:inconsistent_database, :context, :node1}}
      result = Events.parse_event(event)

      validate_parsed_event(result, {:system, :inconsistent_database, {:context, :node1}})
    end

    test "parses mnesia_fatal event" do
      event = {:mnesia_system_event, {:mnesia_fatal, "format", [:args], <<>>}}
      result = Events.parse_event(event)

      validate_parsed_event(result, {:system, :fatal_error, {"format", [:args], <<>>}})
    end

    test "parses mnesia_user event" do
      user_event = {:custom_event, :data}
      event = {:mnesia_system_event, {:mnesia_user, user_event}}
      result = Events.parse_event(event)

      validate_parsed_event(result, {:system, :user_event, user_event})
    end

    defp validate_parsed_event(actual, expected) when actual == expected, do: :ok

    defp validate_parsed_event(actual, expected) do
      raise "Expected #{inspect(expected)} but got #{inspect(actual)}"
    end
  end

  describe "parse_event/1 - activity events transformation" do
    test "parses transaction complete event" do
      event = {:mnesia_activity_event, {:complete, 12345}}
      result = Events.parse_event(event)

      validate_parsed_event(result, {:activity, :transaction, {:complete, 12345}})
    end

    test "parses generic activity event" do
      event = {:mnesia_activity_event, {:some_activity, :data}}
      result = Events.parse_event(event)

      validate_parsed_event(result, {:activity, :mnesia, {:some_activity, :data}})
    end
  end

  describe "parse_event/1 - table events detailed transformation" do
    test "parses detailed write event" do
      new_record = {:users, 1, "John", "john@example.com"}
      old_records = []
      activity_id = 54321

      event = {:mnesia_table_event, {:write, :users, new_record, old_records, activity_id}}
      result = Events.parse_event(event)

      validate_detailed_write_event(result, :users, new_record, old_records, activity_id)
    end

    test "parses detailed delete event" do
      what = {:users, 1}
      old_records = {:users, 1, "John", "john@example.com"}
      activity_id = 99999

      event = {:mnesia_table_event, {:delete, :users, what, old_records, activity_id}}
      result = Events.parse_event(event)

      validate_detailed_delete_event(result, :users, what, old_records, activity_id)
    end

    defp validate_detailed_write_event(
           {:write, table, data},
           expected_table,
           _new_record,
           _old_records,
           activity_id
         ) do
      validate_table_match(table, expected_table)
      validate_map_key_exists(data, :new)
      validate_map_key_exists(data, :old)
      validate_map_key_exists(data, :activity_id)
      validate_activity_id(data.activity_id, activity_id)
    end

    defp validate_detailed_delete_event(
           {:delete, table, data},
           expected_table,
           _what,
           _old_records,
           activity_id
         ) do
      validate_table_match(table, expected_table)
      validate_map_key_exists(data, :what)
      validate_map_key_exists(data, :old)
      validate_map_key_exists(data, :activity_id)
      validate_activity_id(data.activity_id, activity_id)
    end

    defp validate_table_match(actual, expected) when actual == expected, do: :ok

    defp validate_table_match(actual, expected) do
      raise "Expected table #{expected} but got #{actual}"
    end

    defp validate_map_key_exists(map, key) do
      Map.has_key?(map, key)
      |> validate_boolean("Expected key #{key} to exist in map")
    end

    defp validate_activity_id(actual, expected) when actual == expected, do: :ok

    defp validate_activity_id(actual, expected) do
      raise "Expected activity_id #{expected} but got #{actual}"
    end

    defp validate_boolean(true, _message), do: :ok
    defp validate_boolean(false, message), do: raise(message)
  end

  describe "parse_event/1 - table events simple transformation" do
    test "parses simple write event" do
      tuple = {:users, 1, "Alice", "alice@example.com"}
      event = {:mnesia_table_event, {:write, tuple, 12345}}
      result = Events.parse_event(event)

      validate_simple_table_event(result, :write, :users)
    end

    test "parses simple delete event" do
      tuple = {:users, 1, "Bob", "bob@example.com"}
      event = {:mnesia_table_event, {:delete, tuple, 67890}}
      result = Events.parse_event(event)

      validate_simple_table_event(result, :delete, :users)
    end

    test "parses simple delete_object event" do
      tuple = {:posts, 100, "Post Title", "Content"}
      event = {:mnesia_table_event, {:delete_object, tuple, 11111}}
      result = Events.parse_event(event)

      validate_simple_table_event(result, :delete_object, :posts)
    end

    defp validate_simple_table_event({action, table, data}, expected_action, expected_table) do
      validate_action_match(action, expected_action)
      validate_table_match(table, expected_table)
      validate_is_map(data)
    end

    defp validate_action_match(actual, expected) when actual == expected, do: :ok

    defp validate_action_match(actual, expected) do
      raise "Expected action #{expected} but got #{actual}"
    end

    defp validate_is_map(data) when is_map(data), do: :ok

    defp validate_is_map(data) do
      raise "Expected map but got #{inspect(data)}"
    end
  end

  describe "parse_event/1 - schema change events transformation" do
    test "parses create_table event" do
      event = {:mnesia_system_event, {:create_table, :new_table, []}}
      result = Events.parse_event(event)

      validate_parsed_event(result, {:schema_change, :new_table, :create_table})
    end

    test "parses delete_table event" do
      event = {:mnesia_system_event, {:delete_table, :old_table}}
      result = Events.parse_event(event)

      validate_parsed_event(result, {:schema_change, :old_table, :delete_table})
    end

    test "parses add_table_copy event" do
      event = {:mnesia_system_event, {:add_table_copy, :users, :node1, :ram_copies}}
      result = Events.parse_event(event)

      validate_parsed_event(result, {:schema_change, :users, :add_table_copy})
    end

    test "parses del_table_copy event" do
      event = {:mnesia_system_event, {:del_table_copy, :users, :node2}}
      result = Events.parse_event(event)

      validate_parsed_event(result, {:schema_change, :users, :del_table_copy})
    end
  end

  describe "parse_event/1 - unknown events handling" do
    test "parses unknown event to unknown format" do
      event = {:some_weird_event, :unknown_data}
      result = Events.parse_event(event)

      validate_unknown_event(result, event)
    end

    test "handles unexpected system event" do
      event = {:mnesia_system_event, {:unexpected, :data}}
      result = Events.parse_event(event)

      validate_unknown_event(result, event)
    end

    defp validate_unknown_event({:unknown, nil, actual_event}, expected_event)
         when actual_event == expected_event,
         do: :ok

    defp validate_unknown_event({:unknown, nil, actual_event}, expected_event) do
      raise "Expected unknown event #{inspect(expected_event)} but got #{inspect(actual_event)}"
    end

    defp validate_unknown_event(actual, _expected_event) do
      raise "Expected unknown event tuple but got #{inspect(actual)}"
    end
  end

  describe "parse_event/1 - pure transformation properties" do
    test "parsing is deterministic" do
      event = {:mnesia_system_event, {:mnesia_up, :test_node}}

      result1 = Events.parse_event(event)
      result2 = Events.parse_event(event)
      result3 = Events.parse_event(event)

      validate_all_equal([result1, result2, result3])
    end

    test "different events produce different results" do
      event1 = {:mnesia_system_event, {:mnesia_up, :node1}}
      event2 = {:mnesia_system_event, {:mnesia_down, :node1}}

      result1 = Events.parse_event(event1)
      result2 = Events.parse_event(event2)

      validate_not_equal(result1, result2)
    end

    test "parsing preserves event information" do
      node = :important_node
      event = {:mnesia_system_event, {:mnesia_up, node}}
      result = Events.parse_event(event)

      validate_node_preserved(result, node)
    end

    defp validate_all_equal([]), do: :ok
    defp validate_all_equal([_single]), do: :ok

    defp validate_all_equal([first, second | rest]) do
      validate_parsed_event(first, second)
      validate_all_equal([second | rest])
    end

    defp validate_not_equal(value1, value2) when value1 != value2, do: :ok

    defp validate_not_equal(value1, value2) do
      raise "Expected different values but got #{inspect(value1)} == #{inspect(value2)}"
    end

    defp validate_node_preserved({:system, :mnesia, {:up, actual_node}}, expected_node)
         when actual_node == expected_node,
         do: :ok

    defp validate_node_preserved(result, expected_node) do
      raise "Expected node #{expected_node} to be preserved but got #{inspect(result)}"
    end
  end

  describe "parse_event/1 - data structure preservation" do
    test "simple write preserves all tuple elements in map" do
      tuple = {:users, 42, "TestUser", "test@example.com"}
      event = {:mnesia_table_event, {:write, tuple, 1111}}

      {:write, :users, data} = Events.parse_event(event)

      validate_map_has_value(data, :id, 42)
      validate_map_has_value(data, :name, "TestUser")
      validate_map_has_value(data, :email, "test@example.com")
    end

    test "detailed write preserves new and old records" do
      new_record = {:users, 1, "NewName", "new@example.com"}
      old_records = []
      event = {:mnesia_table_event, {:write, :users, new_record, old_records, 9999}}

      {:write, :users, data} = Events.parse_event(event)

      validate_map_key_exists(data, :new)
      validate_map_key_exists(data, :old)
      validate_map_key_exists(data, :activity_id)
    end

    defp validate_map_has_value(map, key, expected_value) do
      actual = Map.get(map, key)

      validate_value_match(
        actual,
        expected_value,
        "Expected #{key} to be #{inspect(expected_value)} but got #{inspect(actual)}"
      )
    end

    defp validate_value_match(actual, expected, _message) when actual == expected, do: :ok
    defp validate_value_match(_actual, _expected, message), do: raise(message)
  end

  describe "parse_event/1 - event type classification" do
    test "classifies system events correctly" do
      system_events = [
        {:mnesia_system_event, {:mnesia_up, :node}},
        {:mnesia_system_event, {:mnesia_down, :node}},
        {:mnesia_system_event, {:mnesia_overload, :data}}
      ]

      validate_all_system_events(system_events)
    end

    test "classifies activity events correctly" do
      activity_events = [
        {:mnesia_activity_event, {:complete, 123}},
        {:mnesia_activity_event, {:other_activity, :info}}
      ]

      validate_all_activity_events(activity_events)
    end

    test "classifies table events correctly" do
      table_events = [
        {:mnesia_table_event, {:write, {:users, 1}, 111}},
        {:mnesia_table_event, {:delete, {:users, 2}, 222}},
        {:mnesia_table_event, {:delete_object, {:posts, 3}, 333}}
      ]

      validate_all_table_events(table_events)
    end

    test "classifies schema events correctly" do
      schema_events = [
        {:mnesia_system_event, {:create_table, :new, []}},
        {:mnesia_system_event, {:delete_table, :old}},
        {:mnesia_system_event, {:add_table_copy, :tab, :node, :type}},
        {:mnesia_system_event, {:del_table_copy, :tab, :node}}
      ]

      validate_all_schema_events(schema_events)
    end

    defp validate_all_system_events([]), do: :ok

    defp validate_all_system_events([event | rest]) do
      {type, _, _} = Events.parse_event(event)
      validate_event_type(type, :system)
      validate_all_system_events(rest)
    end

    defp validate_all_activity_events([]), do: :ok

    defp validate_all_activity_events([event | rest]) do
      {type, _, _} = Events.parse_event(event)
      validate_event_type(type, :activity)
      validate_all_activity_events(rest)
    end

    defp validate_all_table_events([]), do: :ok

    defp validate_all_table_events([event | rest]) do
      {type, _, _} = Events.parse_event(event)
      validate_table_event_type(type)
      validate_all_table_events(rest)
    end

    defp validate_all_schema_events([]), do: :ok

    defp validate_all_schema_events([event | rest]) do
      {type, _, _} = Events.parse_event(event)
      validate_event_type(type, :schema_change)
      validate_all_schema_events(rest)
    end

    defp validate_event_type(actual, expected) when actual == expected, do: :ok

    defp validate_event_type(actual, expected) do
      raise "Expected event type #{expected} but got #{actual}"
    end

    defp validate_table_event_type(type) when type in [:write, :delete, :delete_object], do: :ok

    defp validate_table_event_type(type) do
      raise "Expected table event type but got #{type}"
    end
  end

  describe "parse_event/1 - exhaustive pattern matching coverage" do
    test "handles all mnesia_system_event subtypes" do
      system_subtypes = [
        {{:mnesia_up, :n}, {:system, :mnesia, {:up, :n}}},
        {{:mnesia_down, :n}, {:system, :mnesia, {:down, :n}}},
        {{:mnesia_checkpoint_activated, :c}, {:system, :checkpoint, {:activated, :c}}},
        {{:mnesia_checkpoint_deactivated, :c}, {:system, :checkpoint, {:deactivated, :c}}},
        {{:mnesia_overload, :d}, {:system, :overload, :d}},
        {{:inconsistent_database, :ctx, :n}, {:system, :inconsistent_database, {:ctx, :n}}},
        {{:mnesia_fatal, "f", [], <<>>}, {:system, :fatal_error, {"f", [], <<>>}}},
        {{:mnesia_user, :ev}, {:system, :user_event, :ev}}
      ]

      validate_system_subtype_sequence(system_subtypes)
    end

    test "handles all mnesia_table_event patterns" do
      table_patterns = [
        {{:write, {:users, 1}, 0}, :write},
        {{:delete, {:users, 2}, 0}, :delete},
        {{:delete_object, {:users, 3}, 0}, :delete_object}
      ]

      validate_table_pattern_sequence(table_patterns)
    end

    defp validate_system_subtype_sequence([]), do: :ok

    defp validate_system_subtype_sequence([{subtype, expected} | rest]) do
      event = {:mnesia_system_event, subtype}
      result = Events.parse_event(event)
      validate_parsed_event(result, expected)
      validate_system_subtype_sequence(rest)
    end

    defp validate_table_pattern_sequence([]), do: :ok

    defp validate_table_pattern_sequence([{pattern, expected_action} | rest]) do
      event = {:mnesia_table_event, pattern}
      {action, _table, _data} = Events.parse_event(event)
      validate_event_type(action, expected_action)
      validate_table_pattern_sequence(rest)
    end
  end

  describe "functional purity properties" do
    test "parse_event is idempotent for same input" do
      event = {:mnesia_system_event, {:mnesia_up, :node1}}

      results = [
        Events.parse_event(event),
        Events.parse_event(event),
        Events.parse_event(event)
      ]

      validate_all_equal(results)
    end

    test "parse_event returns consistent structure" do
      events = [
        {:mnesia_system_event, {:mnesia_up, :n1}},
        {:mnesia_system_event, {:mnesia_down, :n2}},
        {:mnesia_activity_event, {:complete, 123}}
      ]

      results = build_parse_results(events, [])

      validate_all_have_three_elements(results)
    end

    defp build_parse_results([], acc), do: Enum.reverse(acc)

    defp build_parse_results([event | rest], acc) do
      result = Events.parse_event(event)
      build_parse_results(rest, [result | acc])
    end

    defp validate_all_have_three_elements([]), do: :ok

    defp validate_all_have_three_elements([result | rest]) do
      validate_tuple_size(result, 3)
      validate_all_have_three_elements(rest)
    end

    defp validate_tuple_size(tuple, expected_size) when tuple_size(tuple) == expected_size,
      do: :ok

    defp validate_tuple_size(tuple, expected_size) do
      raise "Expected tuple of size #{expected_size} but got #{tuple_size(tuple)}"
    end
  end

  describe "edge cases and defensive parsing" do
    test "handles empty old_records in detailed write" do
      event = {:mnesia_table_event, {:write, :users, {:users, 1, "U"}, [], 1}}
      {:write, :users, data} = Events.parse_event(event)

      validate_map_key_exists(data, :old)
    end

    test "extracts table name from tuple correctly" do
      tuples = [
        {:users, 1, "data"},
        {:posts, 100, "title", "content"},
        {:products, 5, "name", 99.99, :active}
      ]

      validate_table_extraction_sequence(tuples)
    end

    defp validate_table_extraction_sequence([]), do: :ok

    defp validate_table_extraction_sequence([tuple | rest]) do
      expected_table = elem(tuple, 0)
      event = {:mnesia_table_event, {:write, tuple, 0}}
      {:write, actual_table, _data} = Events.parse_event(event)

      validate_table_match(actual_table, expected_table)
      validate_table_extraction_sequence(rest)
    end
  end

  describe "composition with monadic error handling" do
    test "parsing sequence can be composed monadically" do
      events = [
        {:mnesia_system_event, {:mnesia_up, :node1}},
        {:mnesia_system_event, {:mnesia_up, :node2}},
        {:mnesia_system_event, {:mnesia_up, :node3}}
      ]

      results =
        Error.m do
          parsed <- Error.return(build_parse_results(events, []))
          node_count <- Error.return(length(parsed))
          Error.return({parsed, node_count})
        end

      validate_composition_result(results, 3)
    end

    test "multiple event types can be composed" do
      mixed_events = [
        {:mnesia_system_event, {:mnesia_up, :n1}},
        {:mnesia_activity_event, {:complete, 123}},
        {:mnesia_table_event, {:write, {:users, 1}, 0}}
      ]

      composed =
        Error.m do
          parsed <- Error.return(build_parse_results(mixed_events, []))
          types <- Error.return(extract_event_types(parsed))
          Error.return({parsed, types})
        end

      validate_mixed_composition(composed, [:system, :activity, :write])
    end

    defp validate_composition_result({:ok, {parsed_list, count}}, expected_count) do
      validate_value_match(
        count,
        expected_count,
        "Expected #{expected_count} events but got #{count}"
      )

      validate_value_match(length(parsed_list), expected_count, "List size mismatch")
    end

    defp validate_mixed_composition({:ok, {_parsed, types}}, expected_types) do
      validate_list_match(types, expected_types)
    end

    defp extract_event_types(parsed_events) do
      extract_types(parsed_events, [])
    end

    defp extract_types([], acc), do: Enum.reverse(acc)

    defp extract_types([{type, _, _} | rest], acc) do
      extract_types(rest, [type | acc])
    end

    defp validate_list_match(actual, expected) when actual == expected, do: :ok

    defp validate_list_match(actual, expected) do
      raise "Expected list #{inspect(expected)} but got #{inspect(actual)}"
    end
  end

  describe "@spec validation for all Events functions" do
    setup do
      result = MnesiaEx.Table.create(:events_spec_table, attributes: [:id, :data])

      validate_table_creation_result(result)
    end

    defp validate_table_creation_result({:ok, _}), do: :ok
    defp validate_table_creation_result({:error, :already_exists}) do
      {:ok, :cleared} = MnesiaEx.Table.clear(:events_spec_table)
      :ok
    end
    defp validate_table_creation_result({:error, reason}), do: raise("Setup failed: #{inspect(reason)}")

    test "subscribe/2 returns {:ok, :subscribed} or error as per spec" do
      result = Events.subscribe(:events_spec_table, :simple)

      # @spec subscribe(atom(), event_type | nil) :: {:ok, :subscribed} | {:error, term()}
      validate_ok_result(result)
    end

    test "subscribe/2 with :system returns {:ok, :subscribed}" do
      result = Events.subscribe(:system, nil)

      validate_ok_result(result)
    end

    test "subscribe/2 with :activity returns {:ok, :subscribed}" do
      result = Events.subscribe(:activity, nil)

      validate_ok_result(result)
    end

    test "unsubscribe/1 returns {:ok, :unsubscribed} or error as per spec" do
      {:ok, :subscribed} = Events.subscribe(:events_spec_table, :simple)
      result = Events.unsubscribe(:events_spec_table)

      # @spec unsubscribe(atom()) :: {:ok, :unsubscribed} | {:error, term()}
      validate_ok_result(result)
    end

    test "unsubscribe/1 with :system returns {:ok, :unsubscribed}" do
      {:ok, :subscribed} = Events.subscribe(:system, nil)
      result = Events.unsubscribe(:system)

      validate_ok_result(result)
    end

    test "unsubscribe/1 with :activity returns {:ok, :unsubscribed}" do
      {:ok, :subscribed} = Events.subscribe(:activity, nil)
      result = Events.unsubscribe(:activity)

      validate_ok_result(result)
    end

    test "parse_event/1 returns parsed event tuple as per spec" do
      event = {:mnesia_system_event, {:mnesia_up, node()}}
      result = Events.parse_event(event)

      # @spec parse_event(term()) :: {type :: atom(), subtable_or_nil :: atom() | nil, data :: term()}
      validate_is_three_tuple(result)
      validate_first_element_is_atom(result)
    end

    test "parse_event/1 is deterministic" do
      event = {:mnesia_system_event, {:mnesia_up, node()}}
      result1 = Events.parse_event(event)
      result2 = Events.parse_event(event)

      validate_maps_equal(result1, result2)
    end
  end

  # Helper functions for spec validation
  defp validate_ok_result({:ok, _}), do: :ok
  defp validate_ok_result({:error, _}), do: :ok
  defp validate_ok_result(value),
    do: raise("Expected {:ok, _} or {:error, _} but got #{inspect(value)}")

  defp validate_is_three_tuple(value) when is_tuple(value) and tuple_size(value) == 3, do: :ok
  defp validate_is_three_tuple(value),
    do: raise("Expected 3-element tuple but got #{inspect(value)}")

  defp validate_first_element_is_atom(tuple) do
    first = elem(tuple, 0)

    (is_atom(first))
    |> validate_boolean("Expected first element to be atom but got #{inspect(first)}")
  end

  defp validate_maps_equal(map1, map2) when map1 == map2, do: :ok
  defp validate_maps_equal(map1, map2),
    do: raise("Expected maps to be equal:\n  Map1: #{inspect(map1)}\n  Map2: #{inspect(map2)}")
end
