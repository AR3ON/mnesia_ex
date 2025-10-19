import Config

# Configuración por defecto para MnesiaEx
config :mnesia_ex,
  # Nombre de la tabla TTL
  ttl_table: :mnesia_ttl,

  # Intervalo de limpieza (5 minutos por defecto)
  cleanup_interval: :timer.minutes(5),

  # Habilitar/deshabilitar limpieza automática
  auto_cleanup: true,

  # Nombre del proceso TTL
  ttl_process_name: MnesiaEx.TTL,

  # Persistencia de la tabla TTL
  ttl_persistence: true
