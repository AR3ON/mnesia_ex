import Config

config :mnesia_ex,
  ttl_table: :mnesia_ttl_test,
  cleanup_interval: :timer.seconds(1),
  auto_cleanup: true,
  ttl_persistence: false,
  ttl_process_name: MnesiaEx.TTL.Test
