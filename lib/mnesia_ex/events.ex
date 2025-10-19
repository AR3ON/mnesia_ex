defmodule MnesiaEx.Events do
  @moduledoc """
  Provides functionality to subscribe and handle Mnesia events.

  Available subscription types:
  - :system - Mnesia system events
  - :activity - Mnesia activity events
  - {table, table_name, :simple | :detailed} - Specific table events
  """

  alias MnesiaEx.Utils
  require Logger

  @type event_type :: :simple | :detailed
  @type subscription_type :: :system | :activity | {atom(), event_type}

  @doc """
  Subscribes the current process to events of a specific table.
  Event type can be :simple or :detailed.

  ## Examples

      # Subscribe to system events
      MnesiaEx.Events.subscribe(:system)

      # Subscribe to activity events
      MnesiaEx.Events.subscribe(:activity)

      # Subscribe to simple table events
      MnesiaEx.Events.subscribe(:users, :simple)

      # Subscribe to detailed table events
      MnesiaEx.Events.subscribe(:users, :detailed)
  """
  @spec subscribe(atom(), event_type | nil) :: {:ok, :subscribed} | {:error, term()}
  def subscribe(table, event_type \\ :simple)

  def subscribe(:system, _) do
    Logger.info("Subscribing to Mnesia system events")
    :mnesia.subscribe(:system)
    |> transform_subscribe_result()
  end

  def subscribe(:activity, _) do
    Logger.info("Subscribing to Mnesia activity events")
    :mnesia.subscribe(:activity)
    |> transform_subscribe_result()
  end

  def subscribe(table, event_type) when is_atom(table) and event_type in [:simple, :detailed] do
    Logger.info("Subscribing to #{event_type} events for table #{table}")
    :mnesia.subscribe({:table, table, event_type})
    |> transform_subscribe_result()
  end

  defp transform_subscribe_result({:ok, _}), do: {:ok, :subscribed}
  defp transform_subscribe_result(:ok), do: {:ok, :subscribed}
  defp transform_subscribe_result({:error, reason}), do: {:error, reason}

  @doc """
  Subscribes the current process to events of a specific table (raises on error).

  ## Examples

      # Subscribe to system events
      MnesiaEx.Events.subscribe!(:system)

      # Subscribe to table events
      MnesiaEx.Events.subscribe!(:users, :simple)
  """
  @spec subscribe!(atom(), event_type | nil) :: :subscribed | no_return()
  def subscribe!(table, event_type \\ :simple) do
    subscribe(table, event_type)
    |> unwrap_subscribe_result!()
  end

  defp unwrap_subscribe_result!({:ok, :subscribed}), do: :subscribed
  defp unwrap_subscribe_result!({:error, reason}), do: raise("Failed to subscribe: #{inspect(reason)}")

  @doc """
  Unsubscribes the current process from events.

  ## Examples

      # Unsubscribe from system events
      MnesiaEx.Events.unsubscribe(:system)

      # Unsubscribe from activity events
      MnesiaEx.Events.unsubscribe(:activity)

      # Unsubscribe from table events
      MnesiaEx.Events.unsubscribe(:users)
  """
  @spec unsubscribe(atom()) :: {:ok, :unsubscribed} | {:error, term()}
  def unsubscribe(:system) do
    Logger.info("Unsubscribing from Mnesia system events")
    :mnesia.unsubscribe(:system)
    |> transform_unsubscribe_result()
  end

  def unsubscribe(:activity) do
    Logger.info("Unsubscribing from Mnesia activity events")
    :mnesia.unsubscribe(:activity)
    |> transform_unsubscribe_result()
  end

  def unsubscribe(table) when is_atom(table) do
    Logger.info("Unsubscribing from events for table #{table}")
    :mnesia.unsubscribe({:table, table})
    |> transform_unsubscribe_result()
  end

  defp transform_unsubscribe_result({:ok, _}), do: {:ok, :unsubscribed}
  defp transform_unsubscribe_result(:ok), do: {:ok, :unsubscribed}
  defp transform_unsubscribe_result({:error, reason}), do: {:error, reason}

  @doc """
  Unsubscribes the current process from events (raises on error).

  ## Examples

      # Unsubscribe from system events
      MnesiaEx.Events.unsubscribe!(:system)

      # Unsubscribe from table events
      MnesiaEx.Events.unsubscribe!(:users)
  """
  @spec unsubscribe!(atom()) :: :unsubscribed | no_return()
  def unsubscribe!(table) do
    unsubscribe(table)
    |> unwrap_unsubscribe_result!()
  end

  defp unwrap_unsubscribe_result!({:ok, :unsubscribed}), do: :unsubscribed
  defp unwrap_unsubscribe_result!({:error, reason}), do: raise("Failed to unsubscribe: #{inspect(reason)}")

  @doc """
  Parses a Mnesia event to a more friendly format.

  ## Examples

      # Write event
      iex> MnesiaEx.Events.parse_event({:mnesia_table_event, {:write, tuple, _tid}})
      {:write, :users, %{id: id, user: user, data: data, status: status}}

      # Delete event
      iex> MnesiaEx.Events.parse_event({:mnesia_table_event, {:delete, tuple, _tid}})
      {:delete, :users, id}
  """
  @spec parse_event(term()) ::
          {:write | :delete | :delete_object | :schema_change | :system | :activity, atom(),
           term()}
          | {:unknown, term(), term()}
  def parse_event(event) do
    Logger.debug("Parsing Mnesia event: #{inspect(event)}")
    transform_mnesia_event(event)
  end

  # Pure functions - Event transformation with pattern matching

  defp transform_mnesia_event({:mnesia_system_event, {:mnesia_up, node}}) do
    {:system, :mnesia, {:up, node}}
  end

  defp transform_mnesia_event({:mnesia_system_event, {:mnesia_down, node}}) do
    {:system, :mnesia, {:down, node}}
  end

  defp transform_mnesia_event({:mnesia_system_event, {:mnesia_checkpoint_activated, checkpoint}}) do
    {:system, :checkpoint, {:activated, checkpoint}}
  end

  defp transform_mnesia_event(
         {:mnesia_system_event, {:mnesia_checkpoint_deactivated, checkpoint}}
       ) do
    {:system, :checkpoint, {:deactivated, checkpoint}}
  end

  defp transform_mnesia_event({:mnesia_system_event, {:mnesia_overload, details}}) do
    {:system, :overload, details}
  end

  defp transform_mnesia_event({:mnesia_system_event, {:inconsistent_database, context, node}}) do
    {:system, :inconsistent_database, {context, node}}
  end

  defp transform_mnesia_event({:mnesia_system_event, {:mnesia_fatal, format, args, binary_core}}) do
    {:system, :fatal_error, {format, args, binary_core}}
  end

  defp transform_mnesia_event({:mnesia_system_event, {:mnesia_user, event}}) do
    {:system, :user_event, event}
  end

  defp transform_mnesia_event({:mnesia_activity_event, {:complete, activity_id}}) do
    {:activity, :transaction, {:complete, activity_id}}
  end

  defp transform_mnesia_event(
         {:mnesia_table_event, {:write, table, new_record, old_records, activity_id}}
       ) do
    {:write, table, build_detailed_write_data(new_record, old_records, activity_id)}
  end

  defp transform_mnesia_event(
         {:mnesia_table_event, {:delete, table, what, old_records, activity_id}}
       ) do
    {:delete, table, build_detailed_delete_data(what, old_records, activity_id)}
  end

  defp transform_mnesia_event({:mnesia_table_event, {:write, tuple, _activity_id}}) do
    table = extract_table_from_tuple(tuple)
    {:write, table, Utils.tuple_to_map(tuple)}
  end

  defp transform_mnesia_event({:mnesia_table_event, {:delete, tuple, _activity_id}}) do
    table = extract_table_from_tuple(tuple)
    {:delete, table, Utils.tuple_to_map(tuple)}
  end

  defp transform_mnesia_event({:mnesia_table_event, {:delete_object, tuple, _activity_id}}) do
    table = extract_table_from_tuple(tuple)
    {:delete_object, table, Utils.tuple_to_map(tuple)}
  end

  defp transform_mnesia_event({:mnesia_system_event, {:create_table, table, _}}) do
    {:schema_change, table, :create_table}
  end

  defp transform_mnesia_event({:mnesia_system_event, {:delete_table, table}}) do
    {:schema_change, table, :delete_table}
  end

  defp transform_mnesia_event({:mnesia_system_event, {:add_table_copy, table, _node, _type}}) do
    {:schema_change, table, :add_table_copy}
  end

  defp transform_mnesia_event({:mnesia_system_event, {:del_table_copy, table, _node}}) do
    {:schema_change, table, :del_table_copy}
  end

  defp transform_mnesia_event({:mnesia_activity_event, event_info}) do
    {:activity, :mnesia, event_info}
  end

  defp transform_mnesia_event(event) do
    Logger.warning("Unknown Mnesia event received: #{inspect(event)}")
    {:unknown, nil, event}
  end

  # Pure transformation functions

  defp build_detailed_write_data(new_record, old_records, activity_id) do
    %{
      new: Utils.tuple_to_map(new_record),
      old: Utils.tuple_to_map(old_records),
      activity_id: activity_id
    }
  end

  defp build_detailed_delete_data(what, old_records, activity_id) do
    %{
      what: Utils.tuple_to_map(what),
      old: Utils.tuple_to_map(old_records),
      activity_id: activity_id
    }
  end

  defp extract_table_from_tuple(tuple) do
    elem(tuple, 0)
  end
end
