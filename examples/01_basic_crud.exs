# Basic CRUD Operations with MnesiaEx
#
# Run with: elixir examples/01_basic_crud.exs

Mix.install([
  {:mnesia_ex, path: "."}
])

# Define a Users table module
defmodule MyApp.Users do
  use MnesiaEx, table: :users
end

# Start MnesiaEx
IO.puts("Starting MnesiaEx...")
MnesiaEx.start()

# Create schema
IO.puts("Creating schema...")
{:ok, :created} = MnesiaEx.Schema.create([node()])

# Create users table
IO.puts("Creating users table...")
MyApp.Users.create(
  attributes: [:id, :name, :email, :age],
  index: [:email],
  type: :set,
  persistence: false
)

IO.puts("\n=== CRUD Operations ===\n")

# CREATE - Write records (two ways)
IO.puts("Writing users with ! (convenience)...")
user1 = MyApp.Users.write!(%{id: 1, name: "Alice", email: "alice@example.com", age: 30})
IO.inspect(user1, label: "Created with !")

IO.puts("\nWriting users without ! (auto-transaction)...")
{:ok, user2} = MyApp.Users.write(%{id: 2, name: "Bob", email: "bob@example.com", age: 25})
{:ok, _user3} = MyApp.Users.write(%{id: 3, name: "Carol", email: "carol@example.com", age: 35})
IO.inspect(user2, label: "Created with auto-transaction")

# READ - Get a single record
IO.puts("\nReading user with id 1...")
user = MyApp.Users.read!(1)
IO.inspect(user, label: "Read user")

# READ - Find by field
IO.puts("\nFinding user by email...")
found = MyApp.Users.get_by!(:email, "bob@example.com")
IO.inspect(found, label: "Found by email")

# READ - Select with conditions
IO.puts("\nSelecting users older than 28...")
users = MyApp.Users.select([{:age, :>, 28}])
IO.inspect(users, label: "Users > 28")

# READ - Get all records
IO.puts("\nGetting all users...")
all_users = MyApp.Users.select([])
IO.inspect(all_users, label: "All users")

# UPDATE - Modify a record
IO.puts("\nUpdating user 1...")
updated = MyApp.Users.update!(1, %{age: 31})
IO.inspect(updated, label: "Updated user")

# UPSERT - Insert or update
IO.puts("\nUpserting user 4 (new)...")
upserted1 = MyApp.Users.upsert!(%{id: 4, name: "Dave", email: "dave@example.com", age: 40})
IO.inspect(upserted1, label: "Upserted (new)")

IO.puts("\nUpserting user 1 (existing)...")
upserted2 = MyApp.Users.upsert!(%{id: 1, name: "Alice Updated", email: "alice@example.com", age: 32})
IO.inspect(upserted2, label: "Upserted (existing)")

# DELETE - Remove a record
IO.puts("\nDeleting user 4...")
deleted = MyApp.Users.delete!(4)
IO.inspect(deleted, label: "Deleted user")

# Verify deletion
IO.puts("\nVerifying deletion...")
all_keys = MyApp.Users.all_keys()
IO.inspect(all_keys, label: "Remaining user IDs")

# Batch operations
IO.puts("\n=== Batch Operations ===\n")

IO.puts("Batch write with ! (convenience)...")
new_users = [
  %{id: 5, name: "Eve", email: "eve@example.com", age: 28},
  %{id: 6, name: "Frank", email: "frank@example.com", age: 45}
]
batch_created = MyApp.Users.batch_write(new_users)
IO.inspect(batch_created, label: "Batch created")

IO.puts("\nBatch write without ! (also auto-transaction, returns list directly)...")
more_users = MyApp.Users.batch_write([
  %{id: 7, name: "Grace", email: "grace@example.com", age: 32},
  %{id: 8, name: "Henry", email: "henry@example.com", age: 29}
])
IO.inspect(more_users, label: "Batch created with auto-transaction")

IO.puts("\nBatch delete...")
batch_deleted = MyApp.Users.batch_delete([5, 6, 7, 8])
IO.inspect(batch_deleted, label: "Batch deleted")

# Manual transaction composing multiple operations
IO.puts("\n=== Manual Transaction (Composing Operations) ===\n")

IO.puts("Creating user and related data in one transaction...")
{:ok, {user, keys}} = MnesiaEx.transaction(fn ->
  # All these operations run in the SAME transaction
  {:ok, user} = MyApp.Users.write(%{id: 10, name: "Composed", email: "composed@example.com", age: 40})
  {:ok, _user2} = MyApp.Users.write(%{id: 11, name: "Also", email: "also@example.com", age: 41})
  {:ok, _user3} = MyApp.Users.write(%{id: 12, name: "InSame", email: "insame@example.com", age: 42})

  {:ok, keys} = MyApp.Users.all_keys()
  {user, keys}
end)

IO.inspect(user, label: "Created in transaction")
IO.inspect(keys, label: "All keys after transaction")
IO.puts("All operations committed atomically!")

# Cleanup
IO.puts("\n=== Cleanup ===\n")
MyApp.Users.drop()
{:ok, :deleted} = MnesiaEx.Schema.delete([node()])
MnesiaEx.stop()
IO.puts("Done!")
