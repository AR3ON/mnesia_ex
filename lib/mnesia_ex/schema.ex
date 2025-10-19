defmodule MnesiaEx.Schema do
  @moduledoc """
  Mnesia schema management across nodes.

  The schema is Mnesia's database directory structure on disk. It must be
  created before any tables can be used with persistence.

  ## Quick Start

      # Create schema (one-time setup)
      MnesiaEx.Schema.create([node()])
      MnesiaEx.start()

      # Now you can create tables
      MnesiaEx.Table.create(:users, attributes: [:id, :name], disc_copies: [node()])

  ## Key Functions

  - `create/1` - Initialize Mnesia schema on disk
  - `delete/1` - Remove schema (destructive)
  - `info/0` - Get schema information
  - `exists?/1` - Check if schema exists

  ## When to Use

  **Create schema:**
  - First deployment
  - New node joining cluster
  - Development setup

  **Delete schema:**
  - Reset database completely
  - Remove node from cluster

  ## Examples

      # Single node
      MnesiaEx.Schema.create([node()])

      # Distributed cluster
      nodes = [:"app@node1", :"app@node2", :"app@node3"]
      MnesiaEx.Schema.create(nodes)

      # Check status
      {:ok, info} = MnesiaEx.Schema.info()
      # => %{nodes: [...], tables: [...], running: true, ...}

  ## Important Notes

  - Schema creation is a **one-time operation** per node
  - Mnesia must be **stopped** before creating schema
  - All nodes should have schema for distributed tables
  """

  require MnesiaEx.Monad, as: Error

  alias MnesiaEx.Table

  @type result :: {:ok, :created | :deleted} | {:error, term()}
  @type schema_info :: %{
          directory: String.t(),
          nodes: [node()],
          tables: [atom()],
          version: String.t(),
          running: boolean()
        }

  @doc """
  Creates a new Mnesia schema on the specified nodes.

  ## Examples

      iex> MnesiaEx.Schema.create([node()])
      {:ok, :created}

      iex> MnesiaEx.Schema.create([:"node1@host", :"node2@host"])
      {:ok, :created}
  """
  @spec create([node()]) :: result()
  def create(nodes) when is_list(nodes) do
    Error.m do
      _ <- validate_nodes(nodes)
      _ <- safe_stop_and_wait()
      _ <- safe_delete_schema(nodes)
      _ <- safe_create_schema(nodes)
      _ <- safe_start_mnesia()
      _ <- Table.persist_schema(nodes)
      Error.return(:created)
    end
  end

  @doc """
  Creates a new Mnesia schema on the specified nodes (raises on error).

  ## Examples

      iex> MnesiaEx.Schema.create!([node()])
      :created

  """
  @spec create!([node()]) :: :created | no_return()
  def create!(nodes) when is_list(nodes) do
    create(nodes)
    |> unwrap_or_raise!("Schema creation failed")
  end

  @doc """
  Deletes the Mnesia schema on the specified nodes.

  ## Examples

      iex> MnesiaEx.Schema.delete([node()])
      {:ok, :deleted}
  """
  @spec delete([node()]) :: result()
  def delete(nodes) when is_list(nodes) do
    Error.m do
      _ <- validate_nodes(nodes)
      _ <- safe_stop_and_wait()
      _ <- safe_delete_schema(nodes)
      Error.return(:deleted)
    end
  end

  @doc """
  Deletes the Mnesia schema on the specified nodes (raises on error).

  ## Examples

      iex> MnesiaEx.Schema.delete!([node()])
      :deleted
  """
  @spec delete!([node()]) :: :deleted | no_return()
  def delete!(nodes) when is_list(nodes) do
    delete(nodes)
    |> unwrap_or_raise!("Schema deletion failed")
  end

  @doc """
  Gets information about the current schema.

  ## Examples

      iex> MnesiaEx.Schema.info()
      {:ok, %{
        directory: "/path/to/mnesia",
        nodes: [:"node1@host"],
        tables: [:users, :roles],
        version: "4.20.0",
        running: true
      }}
  """
  @spec info() :: {:ok, schema_info()} | {:error, term()}
  def info do
    Error.m do
      _ <- safe_ensure_mnesia_running()

      Error.return(%{
        directory: safe_get_mnesia_directory(),
        nodes: safe_get_mnesia_nodes(),
        tables: safe_get_mnesia_tables(),
        version: safe_get_mnesia_version(),
        running: safe_check_mnesia_running()
      })
    end
  end

  @doc """
  Gets information about the current schema (raises on error).

  ## Examples

      iex> MnesiaEx.Schema.info!()
      %{
        directory: "/path/to/mnesia",
        nodes: [:"node1@host"],
        tables: [:users, :roles],
        version: "4.20.0",
        running: true
      }
  """
  @spec info!() :: schema_info() | no_return()
  def info! do
    info()
    |> unwrap_or_raise!("Failed to get schema info")
  end

  @doc """
  Checks if the schema exists on the specified nodes.

  ## Examples

      iex> MnesiaEx.Schema.exists?([node()])
      true
  """
  @spec exists?([node()]) :: boolean()
  def exists?(nodes) when is_list(nodes) do
    Enum.all?(nodes, &schema_exists?/1)
  end

  # Validation

  defp validate_nodes([]), do: Error.fail(:no_nodes)

  defp validate_nodes(nodes) when is_list(nodes) do
    Enum.all?(nodes, &is_atom/1)
    |> to_validation_result()
  end

  defp to_validation_result(true), do: Error.return(:ok)
  defp to_validation_result(false), do: Error.fail(:invalid_nodes)

  # Safe wrappers for impure operations

  defp safe_ensure_mnesia_running do
    :mnesia.system_info(:is_running) |> transform_running_status()
  end

  defp safe_stop_and_wait do
    :mnesia.stop()
    safe_wait_for_stop()
  end

  defp safe_wait_for_stop do
    :mnesia.system_info(:is_running) |> transform_stopped_status()
  end

  defp safe_delete_schema(nodes) do
    :mnesia.delete_schema(nodes) |> transform_delete_result()
  end

  defp safe_create_schema(nodes) do
    :mnesia.create_schema(nodes) |> transform_create_result()
  end

  defp safe_start_mnesia do
    :mnesia.start() |> transform_start_result()
  end

  defp safe_get_mnesia_directory do
    :mnesia.system_info(:directory) |> List.to_string()
  end

  defp safe_get_mnesia_nodes do
    :mnesia.system_info(:db_nodes)
  end

  defp safe_get_mnesia_tables do
    :mnesia.system_info(:tables) -- [:schema]
  end

  defp safe_get_mnesia_version do
    :mnesia.system_info(:version) |> List.to_string()
  end

  defp safe_check_mnesia_running do
    :mnesia.system_info(:is_running) == :yes
  end

  # Result transformers for specific operations

  defp transform_running_status(:yes), do: Error.return(:ok)

  defp transform_running_status(:no) do
    :mnesia.start() |> transform_start_result()
  end

  defp transform_running_status(:stopping), do: Error.fail(:mnesia_stopping)

  defp transform_stopped_status(:no), do: Error.return(:ok)

  defp transform_stopped_status(:stopping) do
    Process.sleep(100)
    safe_wait_for_stop()
  end

  defp transform_stopped_status(_), do: Error.fail(:mnesia_not_stopped)

  defp transform_delete_result(:ok), do: Error.return(:ok)
  defp transform_delete_result({:error, reason}), do: Error.fail(reason)

  defp transform_create_result(:ok), do: Error.return(:ok)
  defp transform_create_result({:error, {_, {:already_exists, _}}}), do: Error.return(:ok)
  defp transform_create_result({:error, reason}), do: Error.fail(reason)

  defp transform_start_result(:ok), do: Error.return(:ok)
  defp transform_start_result({:error, {:already_started, _}}), do: Error.return(:ok)
  defp transform_start_result({:error, reason}), do: Error.fail(reason)

  # Schema existence check

  defp schema_exists?(node) do
    :rpc.call(node, :mnesia, :system_info, [:is_running])
    |> check_rpc_result()
  end

  defp check_rpc_result({:badrpc, _}), do: false
  defp check_rpc_result(_), do: true

  # Helper for ! functions
  defp unwrap_or_raise!({:ok, value}, _message), do: value
  defp unwrap_or_raise!({:error, reason}, message), do: raise("#{message}: #{inspect(reason)}")
end
