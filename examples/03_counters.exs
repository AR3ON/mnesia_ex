# Auto-Increment Counters
#
# Run with: elixir examples/03_counters.exs

Mix.install([
  {:mnesia_ex, path: "."}
])

defmodule MyApp.Posts do
  use MnesiaEx, table: :posts
end

alias MnesiaEx.Query

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

# --- Subsection 1: Automatic (Recommended) ---
IO.puts("📌 1. Automatic (Recommended) - Just omit the ID field:\n")

IO.puts("Creating posts without passing ID...")
post_auto1 = MyApp.Posts.write!(%{
  user_id: 100,
  title: "First Post",
  content: "Hello World",
  views: 0
})
IO.puts("   ✅ ID auto-generated: #{post_auto1.id}")

post_auto2 = MyApp.Posts.write!(%{
  user_id: 100,
  title: "Second Post",
  content: "Mnesia is great!",
  views: 0
})
IO.puts("   ✅ ID auto-generated: #{post_auto2.id}")

post_auto3 = MyApp.Posts.write!(%{
  user_id: 101,
  title: "Third Post",
  content: "Elixir rocks!",
  views: 0
})
IO.puts("   ✅ ID auto-generated: #{post_auto3.id}")

{:ok, current_id} = MyApp.Posts.get_current_value(:id)
IO.puts("   📊 Counter value: #{current_id}")

# --- Subsection 2: Manual (Advanced) ---
IO.puts("\n📌 2. Manual (Advanced) - When you need the ID beforehand:\n")
IO.puts("   ⚠️  Only use when you NEED the ID before creating the record")
IO.puts("   Use cases:")
IO.puts("      • Generate slug with ID: post-123-my-title")
IO.puts("      • Create related records with same ID")
IO.puts("      • Log ID before insertion")
IO.puts("      • Complex transactional logic\n")

IO.puts("Getting next ID manually...")
{:ok, manual_id} = MyApp.Posts.get_next_id(:id)
IO.puts("   🔢 Got ID: #{manual_id}")

# Use the ID for something BEFORE writing
slug = "post-#{manual_id}-hello-advanced"
IO.puts("   🏷️  Generated slug BEFORE insert: #{slug}")

# Now write with that ID
# ⚠️ NOTE: This works because get_next_id incremented the counter
# and the ID doesn't exist yet. The validation will pass.
post_manual = MyApp.Posts.write!(%{
  id: manual_id,
  user_id: 100,
  title: "Advanced Post",
  content: "This post needed its ID first for the slug: #{slug}",
  views: 0
})
IO.puts("   ✅ Created with manual ID: #{post_manual.id}")
IO.puts("   💡 Pattern: get_next_id → use ID → write with ID")

{:ok, current_id2} = MyApp.Posts.get_current_value(:id)
IO.puts("   📊 Counter value: #{current_id2}")
IO.puts("\n   ⚡ Recommended: Use automatic unless you have a specific reason")

IO.puts("\n=== Counter for Views ===\n")

# Simulate incrementing views using counter
IO.puts("Using counter for view tracking (post #{post_auto1.id})...")
{:ok, views1} = MyApp.Posts.get_next_id(:views)
updated1 = MyApp.Posts.update!(post_auto1.id, %{views: views1})
IO.puts("   📊 Views: #{updated1.views}")

{:ok, views2} = MyApp.Posts.get_next_id(:views)
updated2 = MyApp.Posts.update!(post_auto1.id, %{views: views2})
IO.puts("   📊 Views: #{updated2.views}")

{:ok, views3} = MyApp.Posts.get_next_id(:views)
updated3 = MyApp.Posts.update!(post_auto1.id, %{views: views3})
IO.puts("   📊 Views: #{updated3.views}")

{:ok, current_views} = MyApp.Posts.get_current_value(:views)
IO.puts("\n   📊 Current views counter value: #{current_views}")

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

IO.puts("\n=== Get Counter Fields (NEW) ===\n")

# Get all counter fields configured for the table
counter_fields = MyApp.Posts.get_counter_fields()
IO.puts("Counter fields configured: #{inspect(counter_fields)}")

# Check specific field
IO.puts("Is :id a counter field? #{:id in counter_fields}")
IO.puts("Is :title a counter field? #{:title in counter_fields}")

# Useful for dynamic validation
IO.puts("\n💡 Use case: Dynamic validation")
IO.puts("   if :id in MyApp.Posts.get_counter_fields() do")
IO.puts("     # Auto-generation available")
IO.puts("   else")
IO.puts("     # Must provide ID manually")
IO.puts("   end")

# NEW: Auto-Generation and Counter Auto-Adjust
IO.puts("\n=== 🎯 Auto-Generation & Counter Auto-Adjust ===\n")

# Clean table for fresh start
MyApp.Posts.drop()
MyApp.Posts.create(
  attributes: [:id, :title, :content],
  counter_fields: [:id],
  type: :set,
  persistence: false
)

# Example 1: Auto-generation (no ID passed)
IO.puts("1️⃣  Auto-generation (no ID passed):")
post_auto1 = MyApp.Posts.write!(%{title: "Auto 1", content: "Content 1"})
IO.puts("   ✅ Created: id=#{post_auto1.id}, title=\"#{post_auto1.title}\"")

post_auto2 = MyApp.Posts.write!(%{title: "Auto 2", content: "Content 2"})
IO.puts("   ✅ Created: id=#{post_auto2.id}, title=\"#{post_auto2.title}\"")

post_auto3 = MyApp.Posts.write!(%{title: "Auto 3", content: "Content 3"})
IO.puts("   ✅ Created: id=#{post_auto3.id}, title=\"#{post_auto3.title}\"")

{:ok, counter_before} = MyApp.Posts.get_current_value(:id)
IO.puts("   📊 Counter value: #{counter_before}")

# Example 2: Manual ID higher than counter → Auto-adjusts
IO.puts("\n2️⃣  Manual ID higher than counter (auto-adjust):")
IO.puts("   Passing ID=100 (counter=3)...")
post_manual = MyApp.Posts.write!(%{id: 100, title: "Manual 100", content: "Content"})
IO.puts("   ✅ Created: id=#{post_manual.id}, title=\"#{post_manual.title}\"")

{:ok, counter_after} = MyApp.Posts.get_current_value(:id)
IO.puts("   📊 Counter auto-adjusted to: #{counter_after}")

# Example 3: Next auto-generated uses adjusted counter
IO.puts("\n3️⃣  Next auto-generated after manual ID:")
post_next = MyApp.Posts.write!(%{title: "Auto After Manual", content: "Content"})
IO.puts("   ✅ Created: id=#{post_next.id}, title=\"#{post_next.title}\"")
IO.puts("   ✨ No collision! Counter was adjusted automatically")

# Example 4: Manual ID in a "gap" (useful for reserved IDs or migrations)
IO.puts("\n4️⃣  Manual ID in a gap (doesn't exist, lower than counter):")
IO.puts("   Current state: IDs [1,2,3,100,101], counter=101")
IO.puts("   Passing ID=50 (50 doesn't exist, 50 < counter)...")
post_50 = MyApp.Posts.write!(%{id: 50, title: "Reserved ID 50", content: "Content"})
IO.puts("   ✅ Created: id=#{post_50.id}, title=\"#{post_50.title}\"")

{:ok, counter_unchanged} = MyApp.Posts.get_current_value(:id)
IO.puts("   📊 Counter unchanged: #{counter_unchanged}")
IO.puts("   💡 Useful for: reserved ID blocks, partial migrations, gaps")

# Example 5: Prevention of duplicates
IO.puts("\n5️⃣  Prevention of duplicates:")
IO.puts("   Trying to create another post with ID=100...")
case MyApp.Posts.write(%{id: 100, title: "Duplicate", content: "Should fail"}) do
  {:ok, _} ->
    IO.puts("   ⚠️  Unexpected: Should have failed!")
  {:error, {:id_already_exists, :id, 100}} ->
    IO.puts("   ✅ Error prevented! {:id_already_exists, :id, 100}")
    IO.puts("   ✨ Original record with ID=100 is protected")
end

# Example 6: write vs update
IO.puts("\n6️⃣  write (insert) vs update (modify):")
IO.puts("   Creating new post with ID=200...")
{:ok, post_200} = MyApp.Posts.write(%{id: 200, title: "Original", content: "Original content"})
IO.puts("   ✅ Created: id=#{post_200.id}, title=\"#{post_200.title}\"")

IO.puts("\n   Trying to modify with write (same ID)...")
case MyApp.Posts.write(%{id: 200, title: "Modified", content: "New content"}) do
  {:ok, _} ->
    IO.puts("   ⚠️  Unexpected: Should have failed!")
  {:error, {:id_already_exists, :id, 200}} ->
    IO.puts("   ❌ Error! write cannot update existing records")
    IO.puts("   💡 Tip: Use update for modifications")
end

IO.puts("\n   Using update to modify...")
{:ok, updated} = MyApp.Posts.update(200, %{title: "Modified", content: "New content"})
IO.puts("   ✅ Updated: id=#{updated.id}, title=\"#{updated.title}\"")

# Example 7: Batch operations with auto-adjust
IO.puts("\n7️⃣  Batch operations with auto-adjust:")
batch_posts = MyApp.Posts.batch_write([
  %{title: "Batch 1", content: "Content"},
  %{title: "Batch 2", content: "Content"},
  %{title: "Batch 3", content: "Content"}
])
batch_ids = Enum.map(batch_posts, & &1.id)
IO.puts("   ✅ Created batch: IDs=#{inspect(batch_ids)}")

IO.puts("\n   Inserting manual ID=500...")
{:ok, post_500} = MyApp.Posts.write(%{id: 500, title: "Manual 500", content: "Content"})
IO.puts("   ✅ Created: id=#{post_500.id}")

IO.puts("\n   Next batch uses adjusted counter...")
next_batch = MyApp.Posts.batch_write([
  %{title: "Batch After Manual 1", content: "Content"},
  %{title: "Batch After Manual 2", content: "Content"}
])
next_batch_ids = Enum.map(next_batch, & &1.id)
IO.puts("   ✅ Created batch: IDs=#{inspect(next_batch_ids)}")
IO.puts("   ✨ Started from 501 (counter was adjusted to 501)")

# Example 8: Tables WITHOUT counter (original Mnesia behavior)
IO.puts("\n8️⃣  Tables without counter_fields (original behavior):")

# Create a table WITHOUT counter
MnesiaEx.Table.create(:sessions,
  attributes: [:id, :user_id, :token],
  type: :set,
  persistence: false
)

IO.puts("   Table :sessions has NO counter_fields configured")

# Write with ID → Works
{:ok, session1} = Query.write(:sessions, %{id: 1, user_id: 100, token: "abc"})
IO.puts("   ✅ Created: id=#{session1.id}")

# Write with SAME ID → Overwrites (original Mnesia behavior)
{:ok, session2} = Query.write(:sessions, %{id: 1, user_id: 100, token: "xyz"})
IO.puts("   ✅ Overwritten: id=#{session2.id}, token=#{session2.token}")
IO.puts("   ⚠️  No duplicate prevention (no counter configured)")

# Read to verify
{:ok, current} = Query.read(:sessions, 1)
IO.puts("   📖 Current token: #{current.token}")

# Write WITHOUT ID → Creates record with id=nil (problematic)
IO.puts("\n   Testing write without ID (table without counter)...")
{:ok, session3} = Query.write(:sessions, %{user_id: 200, token: "aaa"})
session3_id = Map.get(session3, :id)
IO.puts("   ⚠️  Created with id=#{inspect(session3_id)} (nil)")

{:ok, session4} = Query.write(:sessions, %{user_id: 200, token: "bbb"})
session4_id = Map.get(session4, :id)
IO.puts("   ⚠️  Created with id=#{inspect(session4_id)} (nil)")
IO.puts("   ⚠️  Previous nil-id record was OVERWRITTEN")

# Verify: only one record with id=nil exists
{:ok, nil_session} = Query.read(:sessions, nil)
IO.puts("   📖 Record with id=nil has token: #{nil_session.token} (latest)")
IO.puts("   💡 Recommendation: Always pass unique ID or use counter_fields")

MnesiaEx.Table.drop(:sessions)

# Summary
IO.puts("\n📊 Summary of Features:")
IO.puts("   ✅ Auto-generation: Just omit the ID field")
IO.puts("   ✅ Counter auto-adjust: Prevents future collisions")
IO.puts("   ✅ Duplicate prevention: ONLY for counter_fields")
IO.puts("   ✅ Clear separation: write=insert, update=modify")
IO.puts("   ✅ Thread-safe: Works in distributed clusters")
IO.puts("   ℹ️  Tables WITHOUT counter_fields behave like original Mnesia")

# Cleanup
IO.puts("\n=== Cleanup ===\n")
MyApp.Posts.drop()
{:ok, :deleted} = MnesiaEx.Schema.delete([node()])
MnesiaEx.stop()
IO.puts("Done!")
