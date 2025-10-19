ExUnit.start()

IO.puts("Iniciando configuración de tests...")

# Asegurarse de que Mnesia está detenida y limpiar el esquema anterior
MnesiaEx.stop()
# Dar tiempo a que Mnesia se detenga completamente
Process.sleep(100)
MnesiaEx.Schema.delete([node()])
IO.puts("Mnesia detenida y esquema eliminado")

# Configurar directorio de Mnesia para tests
test_dir = Path.join(System.tmp_dir!(), "mnesia_test_#{:os.system_time(:millisecond)}")
File.rm_rf!(test_dir)
File.mkdir_p!(test_dir)
Application.put_env(:mnesia, :dir, String.to_charlist(test_dir))
IO.puts("Directorio de test creado: #{test_dir}")

# Crear nuevo esquema e iniciar Mnesia
case MnesiaEx.Schema.create([node()]) do
  :ok ->
    IO.puts("Esquema creado correctamente")

  {:ok, _} ->
    IO.puts("Esquema creado correctamente")

  {:error, _} ->
    IO.puts("Esquema ya existe, recreándolo...")
    MnesiaEx.Schema.delete([node()])
    Process.sleep(100)
    MnesiaEx.Schema.create([node()])
    IO.puts("Esquema recreado correctamente")

  error ->
    IO.puts("Error inesperado creando esquema: #{inspect(error)}")
    raise "Error creating schema: #{inspect(error)}"
end

Application.start(:mnesia)
MnesiaEx.start()
IO.puts("Mnesia iniciada")

# Definir las tablas necesarias para los tests
tables = [
  users: [
    attributes: [:id, :name, :email],
    index: [:email],
    type: :set,
    persistence: true
  ],
  posts: [
    attributes: [:id, :user_id, :title, :content],
    index: [:user_id],
    type: :set,
    counter_fields: [:id],
    persistence: true
  ],
  products: [
    attributes: [:id, :sku, :name, :price],
    index: [:name],
    type: :set,
    counter_fields: [:id],
    persistence: true
  ],
  mnesia_ttl_test: [
    attributes: [:id, :value, :ttl],
    type: :set,
    persistence: true
  ],
  counters: [
    attributes: [:key, :value],
    type: :set,
    persistence: true
  ],
  events_test: [
    attributes: [:id, :data],
    type: :set,
    persistence: true
  ]
]

IO.puts("Creando tablas...")

# Crear las tablas necesarias
Enum.each(tables, fn {table, opts} ->
  IO.puts("Creando tabla: #{table}")

  # Eliminar la tabla si existe
  if MnesiaEx.Table.exists?(table) do
    MnesiaEx.Table.drop(table)
  end

  # Crear la tabla con las opciones especificadas
  case MnesiaEx.Table.create(table, opts) do
    {:ok, record} ->
      IO.puts("  - Record: #{inspect(record)}")

    {:error, reason} ->
      IO.puts("Error creating table #{table}: #{inspect(reason)}")
      Application.stop(:mnesia)
      MnesiaEx.stop()
      MnesiaEx.Schema.delete([node()])
      raise "Error creating table #{table}: #{inspect(reason)}"
  end

  # Esperar a que la tabla esté lista
  :mnesia.wait_for_tables([table], 5000)
  IO.puts("  - Tabla #{table} lista")
end)

IO.puts("Todas las tablas creadas exitosamente")

# Configuración básica para tests
Application.put_env(:mnesia_ex, :ttl_table, :mnesia_ttl_test)
Application.put_env(:mnesia_ex, :cleanup_interval, {1, :seconds})
Application.put_env(:mnesia_ex, :auto_cleanup, false)
Application.put_env(:mnesia_ex, :ttl_persistence, false)
Application.put_env(:mnesia_ex, :counter_table, :counters)

# Directorios temporales para tests
tmp_dir = Path.join(System.tmp_dir!(), "mnesia_ex_test")
File.rm_rf!(tmp_dir)
File.mkdir_p!(tmp_dir)

backup_dir = Path.join(tmp_dir, "backup")
export_dir = Path.join(tmp_dir, "export")
File.mkdir_p!(backup_dir)
File.mkdir_p!(export_dir)

Application.put_env(:mnesia_ex, :backup_dir, backup_dir)
Application.put_env(:mnesia_ex, :export_dir, export_dir)

# Limpiar al finalizar
ExUnit.after_suite(fn _stats ->
  IO.puts("Limpiando después de los tests...")

  # Detener Mnesia y limpiar
  MnesiaEx.stop()
  Process.sleep(100)
  MnesiaEx.Schema.delete([node()])
  File.rm_rf!(test_dir)
  File.rm_rf!(tmp_dir)
  IO.puts("Limpieza completada")
end)

IO.puts("Configuración de tests completada")
