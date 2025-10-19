# Event Subscriptions - Real-time Notifications
#
# Run with: elixir examples/04_events.exs

Mix.install([
  {:mnesia_ex, path: "."}
])

defmodule MyApp.Products do
  use MnesiaEx, table: :products
end

# Event handler function
defmodule EventHandler do
  def start_listening do
    Task.start_link(fn -> listen_for_events() end)
  end

  defp listen_for_events do
    receive do
      event ->
        parsed = MyApp.Products.parse_event(event)
        IO.inspect(parsed, label: "📢 Event received")
        listen_for_events()
    after
      1000 ->
        # Timeout to prevent infinite blocking
        listen_for_events()
    end
  end
end

IO.puts("Starting MnesiaEx...")
MnesiaEx.start()

IO.puts("Creating schema...")
{:ok, :created} = MnesiaEx.Schema.create([node()])

IO.puts("Creating products table...")
MyApp.Products.create(
  attributes: [:id, :sku, :name, :price, :stock],
  type: :set,
  persistence: false
)

IO.puts("\n=== Event Subscriptions ===\n")

# Start event listener
{:ok, listener_pid} = EventHandler.start_listening()
IO.puts("Event listener started with PID: #{inspect(listener_pid)}")

# Subscribe to products table events
IO.puts("Subscribing to products events...")
{:ok, :subscribed} = MyApp.Products.subscribe(:detailed)

# Give a moment for subscription to register
Process.sleep(100)

IO.puts("\n=== Trigger Events ===\n")

# WRITE event
IO.puts("Writing a product (should trigger write event)...")
MyApp.Products.write!(%{
  id: 1,
  sku: "LAPTOP-001",
  name: "Laptop Pro",
  price: 1299.99,
  stock: 10
})
Process.sleep(100)

# UPDATE event
IO.puts("\nUpdating product (should trigger write event)...")
MyApp.Products.update!(1, %{price: 1199.99, stock: 8})
Process.sleep(100)

# DELETE event
IO.puts("\nDeleting product (should trigger delete event)...")
MyApp.Products.delete!(1)
Process.sleep(100)

# Multiple operations
IO.puts("\n=== Batch Operations ===\n")

IO.puts("Creating multiple products...")
products = [
  %{id: 2, sku: "MOUSE-001", name: "Gaming Mouse", price: 79.99, stock: 50},
  %{id: 3, sku: "KEYBOARD-001", name: "Mechanical Keyboard", price: 129.99, stock: 30},
  %{id: 4, sku: "MONITOR-001", name: "4K Monitor", price: 599.99, stock: 15}
]

MyApp.Products.batch_write(products)
Process.sleep(300)

IO.puts("\nDeleting products 2 and 3...")
MyApp.Products.batch_delete([2, 3])
Process.sleep(200)

# Unsubscribe
IO.puts("\n=== Unsubscribe ===\n")
IO.puts("Unsubscribing from events...")
{:ok, :unsubscribed} = MyApp.Products.unsubscribe()

# These operations should NOT trigger events
IO.puts("\nWriting product after unsubscribe (no event should appear)...")
MyApp.Products.write!(%{
  id: 5,
  sku: "HEADSET-001",
  name: "Wireless Headset",
  price: 149.99,
  stock: 25
})
Process.sleep(100)

IO.puts("No event received (as expected)")

# Cleanup
IO.puts("\n=== Cleanup ===\n")

# Note: We already unsubscribed earlier in the example
# The table will be cleaned up when schema is deleted
# No need to manually kill the listener - it will die with Mnesia

IO.puts("Deleting schema and stopping Mnesia...")
{:ok, :deleted} = MnesiaEx.Schema.delete([node()])
MnesiaEx.stop()

# Give a moment for everything to shut down cleanly
Process.sleep(100)

IO.puts("Done!")
