# Auto-Increment Counters
#
# Run with: elixir examples/03_counters.exs

Mix.install([
  {:mnesia_ex, path: "."}
])

defmodule MyApp.Posts do
  use MnesiaEx, table: :posts
end

IO.puts("Starting MnesiaEx...")
MnesiaEx.start()

IO.puts("Creating schema...")
{:ok, :created} = MnesiaEx.Schema.create([node()])

# Create posts table with auto-increment ID
IO.puts("Creating posts table with counter_fields...")
MyApp.Posts.create(
  attributes: [:id, :user_id, :title, :content, :views],
  counter_fields: [:id, :views],  # Both id and views can auto-increment
  type: :set,
  persistence: false
)

IO.puts("\n=== Auto-Increment ID ===\n")

# Write posts using auto-increment ID
IO.puts("Creating posts with auto-increment ID...")

{:ok, id1} = MyApp.Posts.get_next_id(:id)
IO.puts("Next ID: #{id1}")
post1 = MyApp.Posts.write!(%{
  id: id1,
  user_id: 100,
  title: "First Post",
  content: "Hello World",
  views: 0
})
IO.inspect(post1, label: "Post 1")

{:ok, id2} = MyApp.Posts.get_next_id(:id)
IO.puts("Next ID: #{id2}")
post2 = MyApp.Posts.write!(%{
  id: id2,
  user_id: 100,
  title: "Second Post",
  content: "Mnesia is great!",
  views: 0
})
IO.inspect(post2, label: "Post 2")

{:ok, id3} = MyApp.Posts.get_next_id(:id)
IO.puts("Next ID: #{id3}")
post3 = MyApp.Posts.write!(%{
  id: id3,
  user_id: 101,
  title: "Third Post",
  content: "Elixir rocks!",
  views: 0
})
IO.inspect(post3, label: "Post 3")

# Check current counter value
{:ok, current_id} = MyApp.Posts.get_current_value(:id)
IO.puts("\nCurrent ID counter value: #{current_id}")

IO.puts("\n=== Counter for Views ===\n")

# Simulate incrementing views
IO.puts("Incrementing views for post 1...")
{:ok, views1} = MyApp.Posts.get_next_id(:views)
updated1 = MyApp.Posts.update!(id1, %{views: views1})
IO.inspect(updated1, label: "Post 1 after 1 view")

{:ok, views2} = MyApp.Posts.get_next_id(:views)
updated2 = MyApp.Posts.update!(id1, %{views: views2})
IO.inspect(updated2, label: "Post 1 after 2 views")

{:ok, views3} = MyApp.Posts.get_next_id(:views)
updated3 = MyApp.Posts.update!(id1, %{views: views3})
IO.inspect(updated3, label: "Post 1 after 3 views")

{:ok, current_views} = MyApp.Posts.get_current_value(:views)
IO.puts("\nCurrent views counter value: #{current_views}")

IO.puts("\n=== Reset Counter ===\n")

# Reset the views counter
IO.puts("Resetting views counter to 1...")
{:ok, reset_value} = MyApp.Posts.reset_counter(:views, 1)
IO.puts("Views counter reset to: #{reset_value}")

# Get next view (should be 1)
{:ok, next_view} = MyApp.Posts.get_next_id(:views)
IO.puts("Next view count: #{next_view}")

IO.puts("\n=== Reset ID Counter ===\n")

# Reset ID counter to 100
IO.puts("Resetting ID counter to 100...")
{:ok, reset_id} = MyApp.Posts.reset_counter(:id, 100)
IO.puts("ID counter reset to: #{reset_id}")

# Next IDs should start from 100
{:ok, new_id1} = MyApp.Posts.get_next_id(:id)
IO.puts("Next ID after reset: #{new_id1}")

{:ok, new_id2} = MyApp.Posts.get_next_id(:id)
IO.puts("Next ID: #{new_id2}")

IO.puts("\n=== Check Counter Existence ===\n")

has_id_counter = MyApp.Posts.has_counter?(:id)
has_views_counter = MyApp.Posts.has_counter?(:views)
has_fake_counter = MyApp.Posts.has_counter?(:fake_field)

IO.puts("Has ID counter? #{has_id_counter}")
IO.puts("Has views counter? #{has_views_counter}")
IO.puts("Has fake counter? #{has_fake_counter}")

# Cleanup
IO.puts("\n=== Cleanup ===\n")
MyApp.Posts.drop()
{:ok, :deleted} = MnesiaEx.Schema.delete([node()])
MnesiaEx.stop()
IO.puts("Done!")

