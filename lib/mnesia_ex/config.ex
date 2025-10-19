defmodule MnesiaEx.Config do
  @moduledoc """
  Configuration module for MnesiaEx.
  Provides functions to access application configuration.

  ## Configuration

  The application can be configured through the application configuration:

  ```elixir
  config :mnesia_ex,
    backup_dir: "custom/backups",           # Backup directory (default: "priv/backups")
    export_dir: "custom/exports",           # Export directory (default: "priv/exports")
    counter_table: :custom_counters,        # Counter table name (default: :mnesia_counters)
    ttl_table: :custom_ttl,                 # TTL table name (default: :mnesia_ttl)
    cleanup_interval: {5, :minutes},        # TTL cleanup interval (default: {5, :minutes})
    auto_cleanup: true,                     # Enable automatic TTL cleanup (default: true)
    ttl_process_name: MyApp.TTLCleaner,     # TTL process name (default: MnesiaEx.TTL)
    ttl_persistence: true                   # TTL table persistence (default: true)
  ```
  """

  @default_config [
    backup_dir: "priv/backups",
    export_dir: "priv/exports",
    counter_table: :mnesia_counters,
    ttl_table: :mnesia_ttl,
    cleanup_interval: {5, :minutes},
    auto_cleanup: true,
    ttl_persistence: true
  ]

  @doc """
  Gets all configuration, merging default values with configured ones.
  """
  def all do
    @default_config
    |> Keyword.merge(Application.get_all_env(:mnesia_ex))
  end

  @doc """
  Gets a specific configuration value.
  """
  def get(field), do: all() |> Keyword.get(field)
end
