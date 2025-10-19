defmodule MnesiaEx.Backup do
  @moduledoc """
  Database backup, restore, and multi-format export.

  This module provides comprehensive backup solutions:
  - Full database backup (native Mnesia format)
  - Export tables to JSON (human-readable)
  - Export tables to CSV (Excel-compatible)
  - Import from files
  - Migration between environments

  ## Use Cases

  - 📦 Production backups
  - 🔄 Data migration between environments
  - 📊 Export for analysis (CSV → Excel)
  - 🔧 Debugging (JSON inspection)
  - 💾 Disaster recovery

  ## Quick Start

      # Full database backup
      {:ok, file} = MnesiaEx.Backup.backup("daily_backup.mnesia")

      # Export table to JSON
      MnesiaEx.Backup.export_table(:users, "users.json", :json)

      # Import from JSON
      {:ok, count} = MnesiaEx.Backup.import_table(:users, "users.json", :json)

  ## Key Functions

  - `backup/1` - Full database backup
  - `restore/3` - Restore from backup with options
  - `export_table/3` - Export to JSON/CSV/Terms
  - `import_table/3` - Import from file
  - `list_exported_records/2` - Preview exported data

  ## Supported Formats

  - `:json` - JSON format (human-readable, portable)
  - `:csv` - CSV format (Excel compatible)
  - `:terms` - Erlang terms (efficient, native)

  ## Examples

      # Backup entire database
      MnesiaEx.Backup.backup("backup_#{Date.utc_today()}.mnesia")

      # Export users to JSON for inspection
      MnesiaEx.Backup.export_table(:users, "users.json", :json)

      # Export to CSV for Excel analysis
      MnesiaEx.Backup.export_table(:orders, "orders.csv", :csv)

      # Restore from production to dev
      MnesiaEx.Backup.restore("prod_backup.mnesia", [node()], [
        skip_tables: [:schema]
      ])

  ## Configuration

      config :mnesia_ex,
        backup_dir: "priv/backups",  # Backup directory
        export_dir: "priv/exports"   # Export directory
  """

  require MnesiaEx.Monad, as: Error

  alias MnesiaEx.{Config, Query, Table}

  @type table :: atom()
  @type format :: :json | :csv | :terms
  @type result :: {:ok, term()} | {:error, term()}

  @doc """
  Creates a complete backup of the Mnesia database.

  ## Examples

      iex> MnesiaEx.Backup.backup("backup_20240315.bak")
      {:ok, "backup_20240315.bak"}

  """
  @spec backup(String.t()) :: result()
  def backup(filename) do
    Error.m do
      backup_dir <- safe_get_config(:backup_dir)
      backup_path <- safe_path_join(backup_dir, filename)
      _ <- safe_mkdir_p(backup_dir)
      _ <- safe_mnesia_backup(backup_path)
      Error.return(filename)
    end
  end

  @doc """
  Creates a complete backup of the Mnesia database (raises on error).

  ## Examples

      iex> MnesiaEx.Backup.backup!("backup_20240315.bak")
      "backup_20240315.bak"

  """
  @spec backup!(String.t()) :: String.t() | no_return()
  def backup!(filename) do
    backup(filename)
    |> unwrap_or_raise!("Backup failed")
  end

  @doc """
  Restores a Mnesia database from a backup.

  ## Available options

  - `:skip_tables` - List of tables to skip during restoration
  - `:default_op` - Default operation for tables (:recreate_tables, :clear_tables, :keep_tables)
  - `:keep_tables` - List of tables to keep unmodified
  - `:clear_tables` - List of tables to clear before restoring

  ## Examples

      iex> MnesiaEx.Backup.restore("backup_20240315.bak")
      {:ok, "backup_20240315.bak"}

      iex> MnesiaEx.Backup.restore("backup_20240315.bak", [node()], [
        skip_tables: [:schema],
        default_op: :clear_tables
      ])
      {:ok, "backup_20240315.bak"}

      iex> MnesiaEx.Backup.restore("backup_20240315.bak", [node()], [
        skip_tables: [:schema, :users],
        default_op: :recreate_tables,
        keep_tables: [:config]
      ])
      {:ok, "backup_20240315.bak"}

  """
  @spec restore(String.t(), [node()], Keyword.t()) :: result()
  def restore(filename, nodes \\ [node()], options \\ []) do
    Error.m do
      backup_dir <- safe_get_config(:backup_dir)
      backup_path <- safe_path_join(backup_dir, filename)
      _ <- safe_start_mnesia()
      _ <- safe_file_exists(backup_path)
      _ <- safe_mnesia_restore(backup_path, options)
      _ <- Table.persist_schema(nodes)
      Error.return(filename)
    end
  end

  @doc """
  Restores a Mnesia database from a backup (raises on error).

  ## Examples

      iex> MnesiaEx.Backup.restore!("backup_20240315.bak")
      "backup_20240315.bak"

  """
  @spec restore!(String.t(), [node()], Keyword.t()) :: String.t() | no_return()
  def restore!(filename, nodes \\ [node()], options \\ []) do
    restore(filename, nodes, options)
    |> unwrap_or_raise!("Restore failed")
  end

  @doc """
  Exports a table to a file in the specified format.

  ## Examples

      iex> MnesiaEx.Backup.export_table(:users, "users.json")
      {:ok, "users.json"}

      iex> MnesiaEx.Backup.export_table(:orders, "orders.csv", :csv)
      {:ok, "orders.csv"}

  """
  @spec export_table(table(), String.t(), format()) :: result()
  def export_table(table, filename, format \\ :json) do
    Error.m do
      export_dir <- safe_get_config(:export_dir)
      export_path <- safe_path_join(export_dir, filename)
      _ <- safe_mkdir_p(export_dir)
      formatted_data <- safe_select_and_format(table, format)
      _ <- safe_write_file(export_path, formatted_data)
      Error.return(filename)
    end
  end

  @doc """
  Exports a table to a file in the specified format (raises on error).

  ## Examples

      iex> MnesiaEx.Backup.export_table!(:users, "users.json")
      "users.json"

  """
  @spec export_table!(table(), String.t(), format()) :: String.t() | no_return()
  def export_table!(table, filename, format \\ :json) do
    export_table(table, filename, format)
    |> unwrap_or_raise!("Export failed")
  end

  @doc """
  Imports records from a CSV file into a Mnesia table.
  """
  @spec import_table(table(), String.t()) :: result()
  def import_table(table, file_path) do
    Error.m do
      content <- File.read(file_path)
      records <- parse_data(content, :csv)
      validated_records <- validate_and_process_records(records, table)
      _written_records <- safe_batch_write_list(table, validated_records)
      Error.return(:imported)
    end
  end

  defp safe_batch_write_list(table, records) do
    Query.batch_write(table, records)
    |> Error.return()
  end

  @doc """
  Imports records from a CSV file into a Mnesia table (raises on error).
  """
  @spec import_table!(table(), String.t()) :: :imported | no_return()
  def import_table!(table, file_path) do
    import_table(table, file_path)
    |> unwrap_or_raise!("Import failed")
  end

  @doc """
  Lists records from an exported file.

  ## Examples

      iex> MnesiaEx.Backup.list_exported_records("users.json")
      {:ok, [%{id: 1, name: "John"}, %{id: 2, name: "Jane"}]}

      iex> MnesiaEx.Backup.list_exported_records("orders.csv", :csv)
      {:ok, [%{order_id: "1", total: "100"}, %{order_id: "2", total: "200"}]}

  """
  @spec list_exported_records(String.t(), format()) :: result()
  def list_exported_records(filename, format \\ :json) do
    Error.m do
      export_dir <- safe_get_config(:export_dir)
      export_path <- safe_path_join(export_dir, filename)
      content <- safe_read_file(export_path)
      records <- parse_data(content, format)
      Error.return(records)
    end
  end

  @doc """
  Lists records from an exported file (raises on error).

  ## Examples

      iex> MnesiaEx.Backup.list_exported_records!("users.json")
      [%{id: 1, name: "John"}, %{id: 2, name: "Jane"}]

  """
  @spec list_exported_records!(String.t(), format()) :: [map()] | no_return()
  def list_exported_records!(filename, format \\ :json) do
    list_exported_records(filename, format)
    |> unwrap_or_raise!("Failed to list records")
  end

  # Safe wrappers for non-functor operations

  defp safe_get_config(key) do
    Config.get(key) |> transform_config_result(key)
  end

  defp transform_config_result(nil, key), do: Error.fail({:config_missing, key})
  defp transform_config_result(value, _key), do: Error.return(value)

  defp safe_path_join(dir, file) when is_binary(dir) and is_binary(file) do
    Error.return(Path.join(dir, file))
  end

  defp safe_path_join(nil, _file), do: Error.fail(:invalid_directory)
  defp safe_path_join(_dir, nil), do: Error.fail(:invalid_filename)
  defp safe_path_join(_dir, _file), do: Error.fail(:invalid_path_arguments)

  defp safe_mnesia_backup(path) do
    :mnesia.backup(String.to_charlist(path)) |> transform_mnesia_result()
  end

  defp safe_start_mnesia do
    :mnesia.start() |> transform_start_result()
  end

  defp safe_mnesia_restore(path, options) do
    :mnesia.restore(String.to_charlist(path), build_restore_options(options))
    |> transform_mnesia_result()
  end

  defp safe_file_exists(path) do
    File.exists?(path) |> transform_bool_result(:file_not_found)
  end

  defp safe_read_file(path) do
    File.read(path) |> transform_read_result()
  end

  defp safe_write_file(path, data) do
    File.write(path, data) |> transform_write_result()
  end

  defp safe_mkdir_p(dir) do
    File.mkdir_p(dir) |> transform_mkdir_result()
  end

  defp safe_select_and_format(table, format) do
    Query.select(table, [])
    |> format_data(format)
  end

  # Result transformers for specific operations

  defp transform_mnesia_result(:ok), do: Error.return(:ok)
  defp transform_mnesia_result({:atomic, value}), do: Error.return(value)
  defp transform_mnesia_result({:error, reason}), do: Error.fail(reason)
  defp transform_mnesia_result({:aborted, reason}), do: Error.fail(reason)

  defp transform_start_result(:ok), do: Error.return(:ok)
  defp transform_start_result({:error, {:already_started, _}}), do: Error.return(:ok)
  defp transform_start_result({:error, reason}), do: Error.fail(reason)

  defp transform_bool_result(true, _reason), do: Error.return(:ok)
  defp transform_bool_result(false, reason), do: Error.fail(reason)

  defp transform_read_result({:ok, content}), do: Error.return(content)
  defp transform_read_result({:error, :enoent}), do: Error.fail(:file_not_found)
  defp transform_read_result({:error, reason}), do: Error.fail(reason)

  defp transform_write_result(:ok), do: Error.return(:ok)
  defp transform_write_result({:error, reason}), do: Error.fail(reason)

  defp transform_mkdir_result(:ok), do: Error.return(:ok)
  defp transform_mkdir_result({:ok, _path}), do: Error.return(:ok)
  defp transform_mkdir_result({:error, reason}), do: Error.fail(reason)

  defp build_restore_options(opts) do
    opts
    |> Enum.filter(&valid_restore_option?/1)
  end

  defp valid_restore_option?({:skip_tables, tables}) when is_list(tables), do: true

  defp valid_restore_option?({:default_op, op})
       when op in [:recreate_tables, :clear_tables, :keep_tables],
       do: true

  defp valid_restore_option?({:keep_tables, tables}) when is_list(tables), do: true
  defp valid_restore_option?({:clear_tables, tables}) when is_list(tables), do: true
  defp valid_restore_option?(_), do: false

  # Data formatting
  defp format_data([], _format), do: Error.fail(:empty)

  defp format_data(records, :json) do
    Jason.encode(records)
  end

  defp format_data(records, :csv) do
    Error.m do
      headers <- extract_headers(records)
      rows <- format_csv_rows(records, [])

      Enum.join([headers | rows], "\n")
      |> Error.return()
    end
  end

  defp format_data(records, :terms) do
    records
    |> :erlang.term_to_binary()
    |> Error.return()
  end

  defp extract_headers([first | _]) do
    first
    |> Map.keys()
    |> Enum.join(",")
    |> Error.return()
  end

  defp extract_headers([]), do: Error.fail(:empty)

  defp format_csv_rows([], acc), do: Enum.reverse(acc) |> Error.return()

  defp format_csv_rows([record | rest], acc) do
    row = record |> Map.values() |> Enum.join(",")
    format_csv_rows(rest, [row | acc])
  end

  # Data parsing

  defp parse_data(content, :json) do
    Jason.decode(content)
  end

  defp parse_data(content, :csv) do
    parse_csv_content(content)
  end

  defp parse_data(content, :terms) when is_binary(content) do
    content
    |> :erlang.binary_to_term()
    |> Error.return()
  end

  defp parse_data(_, :terms), do: Error.fail(:invalid_format)

  defp parse_csv_content(content) do
    String.split(content, "\n", trim: true)
    |> parse_csv_lines()
  end

  defp parse_csv_lines([]), do: Error.fail(:empty_file)

  defp parse_csv_lines([headers | rows]) do
    parse_csv_rows(rows, String.split(headers, ","), [])
  end

  defp parse_csv_rows([], _, acc) do
    acc
    |> Enum.reverse()
    |> Error.return()
  end

  defp parse_csv_rows([row | rest], headers, acc) do
    values = String.split(row, ",")
    parsed_row = Enum.zip(headers, values) |> Enum.into(%{})
    parse_csv_rows(rest, headers, [parsed_row | acc])
  end

  # Record validation

  defp validate_and_process_records(records, table) do
    Error.m do
      table_info <- Table.info(table)
      fields <- extract_table_fields(table_info)
      validate_records(records, fields)
    end
  end

  defp extract_table_fields(%{attributes: fields}), do: Error.return(fields)
  defp extract_table_fields(_), do: Error.fail(:no_attributes)

  defp validate_records(records, fields) do
    validate_records_recursive(records, fields, [], [])
  end

  defp validate_records_recursive([], _, valid_acc, []) do
    Error.return(Enum.reverse(valid_acc))
  end

  defp validate_records_recursive([], _, _, invalid_acc) do
    Error.fail({:validation_errors, Enum.reverse(invalid_acc)})
  end

  defp validate_records_recursive([record | rest], fields, valid_acc, invalid_acc) do
    processed = process_record_fields(record, fields)
    missing = fields -- Map.keys(processed)

    validate_record_result(rest, fields, processed, missing, valid_acc, invalid_acc)
  end

  defp validate_record_result(rest, fields, processed, [], valid_acc, invalid_acc) do
    validate_records_recursive(rest, fields, [processed | valid_acc], invalid_acc)
  end

  defp validate_record_result(rest, fields, _, missing, valid_acc, invalid_acc) do
    validate_records_recursive(rest, fields, valid_acc, [
      {:error, {:missing_fields, missing}} | invalid_acc
    ])
  end

  defp process_record_fields(record, fields) do
    fields
    |> Enum.reduce(%{}, fn field, acc ->
      Map.get(record, Atom.to_string(field))
      |> add_field_if_present(field, acc)
    end)
  end

  defp add_field_if_present(nil, _field, acc), do: acc
  defp add_field_if_present(value, field, acc), do: Map.put(acc, field, value)

  # Helper for ! functions
  defp unwrap_or_raise!({:ok, value}, _message), do: value
  defp unwrap_or_raise!({:error, reason}, message), do: raise("#{message}: #{inspect(reason)}")
end
