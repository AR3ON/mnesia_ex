# TTL (Time To Live) - Auto-expiring Records
#
# Run with: elixir examples/02_ttl.exs

Mix.install([
  {:mnesia_ex, path: "."}
])

defmodule MyApp.Sessions do
  use MnesiaEx, table: :sessions
end

IO.puts("Starting MnesiaEx...")
MnesiaEx.start()

IO.puts("Creating schema...")
{:ok, :created} = MnesiaEx.Schema.create([node()])

# Create sessions table with TTL support
IO.puts("Creating sessions table...")
MyApp.Sessions.create(
  attributes: [:id, :user_id, :token, :data],
  type: :set,
  persistence: false
)

# Ensure TTL table exists
MnesiaEx.TTL.ensure_ttl_table()

IO.puts("\n=== TTL Operations ===\n")

# Write a session with 30 seconds TTL
IO.puts("Writing session with 30 seconds TTL...")
session = MyApp.Sessions.write_with_ttl!(
  %{id: "session_1", user_id: 1, token: "abc123", data: "some data"},
  {30, :seconds}
)
IO.inspect(session, label: "Created session")

# Get remaining time
case MyApp.Sessions.get_remaining("session_1") do
  {:ok, remaining_ms} ->
    IO.puts("Remaining TTL: ~#{div(remaining_ms, 1000)} seconds (#{remaining_ms} ms)")
  {:error, :expired} ->
    IO.puts("⚠️  Warning: Session expired immediately (check system time)")
end

# Read the session (should exist)
IO.puts("\nReading session immediately...")
found = MyApp.Sessions.read!("session_1")
IO.inspect(found, label: "Session found")

# Wait 3 seconds
IO.puts("\nWaiting 3 seconds...")
Process.sleep(3000)

# Check TTL again - handle potential expiration
IO.puts("\nChecking TTL after 3 seconds...")
case MyApp.Sessions.get_remaining("session_1") do
  {:ok, remaining2_ms} ->
    IO.puts("Remaining TTL: ~#{div(remaining2_ms, 1000)} seconds (#{remaining2_ms} ms)")
  {:error, :expired} ->
    IO.puts("⚠️  Session has expired!")
end

# Session should still exist
case MyApp.Sessions.read("session_1") do
  {:ok, record} -> IO.inspect(record, label: "Session still exists")
  {:error, :not_found} -> IO.puts("⚠️  Session not found (may have been cleaned)")
end

# Wait another 28 seconds (total 31 seconds, past 30s TTL)
IO.puts("\nWaiting another 28 seconds (past TTL)...")
Process.sleep(28000)

# Run cleanup to expire records
IO.puts("Running cleanup...")
MnesiaEx.TTL.cleanup_expired()

# Try to read (should fail - session expired and cleaned)
IO.puts("\nTrying to read expired session...")
case MyApp.Sessions.read("session_1") do
  {:ok, record} -> IO.puts("Session still exists: #{inspect(record)}")
  {:error, :not_found} -> IO.puts("✓ Session not found (correctly expired and cleaned)")
end

# Write multiple sessions with different TTLs
IO.puts("\n=== Multiple Sessions with Different TTLs ===\n")

MyApp.Sessions.write_with_ttl!(
  %{id: "short", user_id: 2, token: "short_token", data: "expires soon"},
  {2, :seconds}
)

MyApp.Sessions.write_with_ttl!(
  %{id: "medium", user_id: 3, token: "medium_token", data: "expires later"},
  {10, :seconds}
)

MyApp.Sessions.write_with_ttl!(
  %{id: "long", user_id: 4, token: "long_token", data: "lasts long"},
  {1, :hour}
)

# List all TTL records
IO.puts("All TTL records:")
all_ttls = MnesiaEx.TTL.list_all()
IO.inspect(all_ttls, label: "All TTLs")

# List only active TTLs
IO.puts("\nActive TTL records:")
active = MnesiaEx.TTL.list_active()
IO.inspect(active, label: "Active TTLs")

# Wait 3 seconds and cleanup
IO.puts("\nWaiting 3 seconds and cleaning up...")
Process.sleep(3000)
MnesiaEx.TTL.cleanup_expired()

# Check which sessions still exist
IO.puts("\nChecking remaining sessions...")
all_sessions = MyApp.Sessions.select([])
IO.inspect(all_sessions, label: "Remaining sessions")

# Cleanup
IO.puts("\n=== Cleanup ===\n")
MyApp.Sessions.drop()
{:ok, :deleted} = MnesiaEx.Schema.delete([node()])
MnesiaEx.stop()
IO.puts("Done!")
