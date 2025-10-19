# MnesiaEx.transaction - Composable Transactions
#
# This example demonstrates using MnesiaEx.transaction/1
# similar to Ecto's Repo.transaction/1 for composable operations.
#
# Run with: elixir examples/07_transactions.exs

Mix.install([
  {:mnesia_ex, path: "."}
])

defmodule MyApp.Users do
  use MnesiaEx, table: :users
end

defmodule MyApp.Posts do
  use MnesiaEx, table: :posts
end

IO.puts("Starting MnesiaEx...")
MnesiaEx.start()

IO.puts("Creating schema...")
{:ok, :created} = MnesiaEx.Schema.create([node()])

# Create tables
IO.puts("Creating tables...")
MyApp.Users.create(
  attributes: [:id, :name, :email],
  counter_fields: [:id],
  type: :set,
  persistence: false
)

MyApp.Posts.create(
  attributes: [:id, :user_id, :title, :content],
  counter_fields: [:id],
  type: :set,
  persistence: false
)

IO.puts("\n=== Smart Auto-Transaction Detection ===\n")

# Functions work standalone (auto-transaction)
IO.puts("Writing user standalone (auto-transaction)...")
{:ok, standalone_user} = MyApp.Users.write(%{id: 1, name: "Standalone", email: "standalone@example.com"})
IO.inspect(standalone_user, label: "✅ Created with auto-transaction")

# Same function inside transaction (detected, no double-wrap)
IO.puts("\n=== Composing Operations in Manual Transaction ===\n")

IO.puts("Creating user and post in one transaction...")
{:ok, {user, post}} = MnesiaEx.transaction(fn ->
  {:ok, user_id} = MyApp.Users.get_next_id(:id)
  {:ok, user} = MyApp.Users.write(%{id: user_id, name: "Alice", email: "alice@example.com"})
  # ↑ Detects existing transaction, doesn't create another

  {:ok, post_id} = MyApp.Posts.get_next_id(:id)
  {:ok, post} = MyApp.Posts.write(%{id: post_id, user_id: user.id, title: "My First Post", content: "Hello!"})
  # ↑ Detects existing transaction, doesn't create another

  {user, post}
end)

IO.inspect(user, label: "Created user")
IO.inspect(post, label: "Created post")
IO.puts("💡 Both operations in ONE transaction (auto-detected)")

IO.puts("\n=== Transaction with Error Handling ===\n")

# Transaction that might fail
IO.puts("Attempting to create post for non-existent user...")
result = MnesiaEx.transaction(fn ->
  {:ok, post_id} = MyApp.Posts.get_next_id(:id)

  # This will fail because user 999 doesn't exist
  case MyApp.Users.read(999) do
    {:ok, user} ->
      MyApp.Posts.write(%{id: post_id, user_id: user.id, title: "Post", content: "..."})
    {:error, :not_found} ->
      :mnesia.abort(:user_not_found)
  end
end)

case result do
  {:ok, post} ->
    IO.puts("Post created: #{inspect(post)}")
  {:error, :user_not_found} ->
    IO.puts("Transaction aborted: User not found")
end

IO.puts("\n=== Composing Multiple Operations ===\n")

# Create a user with multiple posts
IO.puts("Creating user with 3 posts...")
{:ok, {user, posts}} = MnesiaEx.transaction(fn ->
  {:ok, user_id} = MyApp.Users.get_next_id(:id)
  {:ok, user} = MyApp.Users.write(%{id: user_id, name: "Bob", email: "bob@example.com"})

  post_data = [
    %{user_id: user.id, title: "Post 1", content: "First post"},
    %{user_id: user.id, title: "Post 2", content: "Second post"},
    %{user_id: user.id, title: "Post 3", content: "Third post"}
  ]

  {:ok, posts} = Enum.reduce_while(post_data, {:ok, []}, fn data, {:ok, acc} ->
    {:ok, post_id} = MyApp.Posts.get_next_id(:id)
    case MyApp.Posts.write(Map.put(data, :id, post_id)) do
      {:ok, post} -> {:cont, {:ok, [post | acc]}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end)

  {user, Enum.reverse(posts)}
end)

IO.inspect(user, label: "User")
IO.puts("Created #{length(posts)} posts for user #{user.id}")

IO.puts("\n=== Atomic Update of Multiple Records ===\n")

# Update multiple records atomically
IO.puts("Updating all Bob's posts to mark as published...")
{:ok, updated_posts} = MnesiaEx.transaction(fn ->
  {:ok, bob_posts} = MyApp.Posts.select([{:user_id, :==, user.id}])

  Enum.map(bob_posts, fn post ->
    {:ok, updated} = MyApp.Posts.update(post.id, %{title: "[Published] #{post.title}"})
    updated
  end)
end)

IO.puts("Updated #{length(updated_posts)} posts")
IO.inspect(List.first(updated_posts), label: "First updated post")

IO.puts("\n=== Transaction Rollback on Error ===\n")

# This transaction will fail and rollback all changes
IO.puts("Attempting transaction that will fail...")
result = MnesiaEx.transaction(fn ->
  {:ok, user_id} = MyApp.Users.get_next_id(:id)
  {:ok, _user} = MyApp.Users.write(%{id: user_id, name: "Temp", email: "temp@example.com"})

  {:ok, post_id} = MyApp.Posts.get_next_id(:id)
  {:ok, _post} = MyApp.Posts.write(%{id: post_id, user_id: user_id, title: "Temp Post", content: "..."})

  # Abort the transaction on purpose
  :mnesia.abort(:intentional_failure)
end)

case result do
  {:ok, _} ->
    IO.puts("Transaction succeeded (unexpected)")
  {:error, :intentional_failure} ->
    IO.puts("Transaction rolled back as expected!")

    # Verify the temp user and post were NOT created
    {:ok, temp_users} = MyApp.Users.select([{:name, :==, "Temp"}])

    temp_users
    |> length()
    |> then(fn
      0 -> IO.puts("✅ User was not created (rollback worked)")
      _ -> IO.puts("❌ User was created (rollback failed)")
    end)
end

IO.puts("\n=== Comparison: ! vs transaction ===\n")

IO.puts("Using ! functions (automatic transaction):")
user_with_bang = MyApp.Users.write!(%{id: 100, name: "BangUser", email: "bang@example.com"})
IO.inspect(user_with_bang, label: "User (with !)")

IO.puts("\nUsing transaction manually (composable):")
{:ok, user_manual} = MnesiaEx.transaction(fn ->
  {:ok, user_id} = MyApp.Users.get_next_id(:id)
  MyApp.Users.write(%{id: user_id, name: "ManualUser", email: "manual@example.com"})
end)
IO.inspect(user_manual, label: "User (manual transaction)")

IO.puts("\n=== API Comparison ===\n")

IO.puts("1️⃣  Bang functions (!) - Convenience for single operations:")
IO.puts("   user = MyApp.Users.write!(%{...})")
IO.puts("   ✅ Auto-transaction + returns value")
IO.puts("   ✅ Raises on error")
IO.puts("")

IO.puts("2️⃣  Non-bang standalone - Auto-transaction with error handling:")
IO.puts("   {:ok, user} = MyApp.Users.write(%{...})")
IO.puts("   ✅ Auto-transaction (detected NOT in transaction)")
IO.puts("   ✅ Returns {:ok, value} | {:error, reason}")
IO.puts("")

IO.puts("3️⃣  Non-bang inside MnesiaEx.transaction - Composable:")
IO.puts("   MnesiaEx.transaction(fn ->")
IO.puts("     {:ok, user} = MyApp.Users.write(%{...})")
IO.puts("     {:ok, post} = MyApp.Posts.write(%{...})")
IO.puts("   end)")
IO.puts("   ✅ Detects existing transaction (NO double-wrap)")
IO.puts("   ✅ All operations atomic")
IO.puts("")

IO.puts("4️⃣  dirty_* functions - Speed over consistency:")
IO.puts("   {:ok, cache} = MyApp.Cache.dirty_write(%{...})")
IO.puts("   ✅ No transaction (10x faster)")
IO.puts("   ❌ No ACID guarantees")
IO.puts("")

IO.puts("💡 When to use each:")
IO.puts("- ! functions: Quick operations, prototyping")
IO.puts("- Non-bang standalone: Error handling, pattern matching")
IO.puts("- MnesiaEx.transaction: Composing multiple operations atomically")
IO.puts("- dirty_*: High-performance caching, non-critical data")

# Cleanup
IO.puts("\n=== Cleanup ===\n")
MyApp.Users.drop()
MyApp.Posts.drop()
{:ok, :deleted} = MnesiaEx.Schema.delete([node()])
MnesiaEx.stop()
IO.puts("Done!")
