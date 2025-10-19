# Backup and Export - Save data to JSON/CSV
#
# Run with: elixir examples/05_backup_export.exs

Mix.install([
  {:mnesia_ex, path: "."},
  {:jason, "~> 1.4"}
])

defmodule MyApp.Customers do
  use MnesiaEx, table: :customers
end

IO.puts("Starting MnesiaEx...")
MnesiaEx.start()

IO.puts("Creating schema...")
{:ok, :created} = MnesiaEx.Schema.create([node()])

# Configure backup/export directories
tmp_dir = Path.join(System.tmp_dir!(), "mnesia_ex_examples")
File.rm_rf!(tmp_dir)
File.mkdir_p!(tmp_dir)

backup_dir = Path.join(tmp_dir, "backups")
export_dir = Path.join(tmp_dir, "exports")
File.mkdir_p!(backup_dir)
File.mkdir_p!(export_dir)

Application.put_env(:mnesia_ex, :backup_dir, backup_dir)
Application.put_env(:mnesia_ex, :export_dir, export_dir)

IO.puts("Backup directory: #{backup_dir}")
IO.puts("Export directory: #{export_dir}")

IO.puts("\nCreating customers table...")
MyApp.Customers.create(
  attributes: [:id, :name, :email, :company, :country],
  index: [:email, :country],
  type: :set,
  persistence: true
)

# Add sample data
IO.puts("\nAdding sample customers...")
customers = [
  %{id: 1, name: "Alice Johnson", email: "alice@example.com", company: "Tech Corp", country: "USA"},
  %{id: 2, name: "Bob Smith", email: "bob@example.com", company: "Data Inc", country: "UK"},
  %{id: 3, name: "Carol White", email: "carol@example.com", company: "AI Labs", country: "Canada"},
  %{id: 4, name: "David Brown", email: "david@example.com", company: "Cloud Co", country: "USA"},
  %{id: 5, name: "Eve Martinez", email: "eve@example.com", company: "Web Solutions", country: "Spain"}
]

MyApp.Customers.batch_write(customers)
IO.puts("Added #{length(customers)} customers")

IO.puts("\n=== Mnesia Backup ===\n")

# Create Mnesia backup
IO.puts("Creating Mnesia backup...")
{:ok, backup_file} = MnesiaEx.Backup.backup("customers_backup.mnesia")
backup_path = Path.join(backup_dir, backup_file)
IO.puts("Backup created: #{backup_path}")
IO.puts("Backup size: #{File.stat!(backup_path).size} bytes")

# Note: list_backups/0 is not implemented yet
# The backup was saved to the configured backup directory
IO.puts("\nBackup successfully created in: #{backup_dir}")

IO.puts("\n=== JSON Export ===\n")

# Export to JSON
IO.puts("Exporting customers to JSON...")
{:ok, json_file} = MnesiaEx.Backup.export_table(:customers, "customers.json", :json)
json_path = Path.join(export_dir, json_file)
IO.puts("JSON export created: #{json_path}")

# Read and display JSON content
json_content = File.read!(json_path)
IO.puts("\nJSON content preview:")
IO.puts(String.slice(json_content, 0..200) <> "...")

# Parse and count records
{:ok, json_records} = Jason.decode(json_content)
IO.puts("\nJSON records count: #{length(json_records)}")

IO.puts("\n=== CSV Export ===\n")

# Export to CSV
IO.puts("Exporting customers to CSV...")
{:ok, csv_file} = MnesiaEx.Backup.export_table(:customers, "customers.csv", :csv)
csv_path = Path.join(export_dir, csv_file)
IO.puts("CSV export created: #{csv_path}")

# Read and display CSV content
csv_content = File.read!(csv_path)
IO.puts("\nCSV content:")
IO.puts(csv_content)

IO.puts("\n=== Erlang Terms Export ===\n")

# Export to Erlang terms
IO.puts("Exporting customers to Erlang terms...")
{:ok, erl_file} = MnesiaEx.Backup.export_table(:customers, "customers.terms", :terms)
erl_path = Path.join(export_dir, erl_file)
IO.puts("Erlang terms export created: #{erl_path}")

# Note: list_exports/0 is not implemented yet
IO.puts("\nAll exports saved to: #{export_dir}")

IO.puts("\n=== List Exported Records ===\n")

# List records from JSON export
IO.puts("Reading records from JSON export...")
{:ok, json_records_list} = MnesiaEx.Backup.list_exported_records(json_file, :json)
IO.puts("Records in JSON: #{length(json_records_list)}")
IO.inspect(List.first(json_records_list), label: "First JSON record")

# List records from CSV export
IO.puts("\nReading records from CSV export...")
{:ok, csv_records_list} = MnesiaEx.Backup.list_exported_records(csv_file, :csv)
IO.puts("Records in CSV: #{length(csv_records_list)}")
IO.inspect(List.first(csv_records_list), label: "First CSV record")

IO.puts("\n=== Restore from Backup ===\n")

# Clear the table
IO.puts("Clearing customers table...")
MyApp.Customers.clear()
all_after_clear = MyApp.Customers.select([])
IO.puts("Records after clear: #{length(all_after_clear)}")

# Restore from backup
IO.puts("\nRestoring from backup...")
{:ok, restored_file} = MnesiaEx.Backup.restore(backup_file, [node()], default_op: :clear_tables)
IO.puts("Backup restored successfully from: #{restored_file}")

# Verify restoration
all_after_restore = MyApp.Customers.select([])
IO.puts("Records after restore: #{length(all_after_restore)}")
IO.inspect(List.first(all_after_restore), label: "First restored record")

# Cleanup
IO.puts("\n=== Cleanup ===\n")
MyApp.Customers.drop()
{:ok, :deleted} = MnesiaEx.Schema.delete([node()])
File.rm_rf!(tmp_dir)
MnesiaEx.stop()
IO.puts("Done!")
