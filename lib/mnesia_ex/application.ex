defmodule MnesiaEx.Application do
  use Application

  def start(_type, _args) do
    children = [
      MnesiaEx.TTL
    ]

    # When one process fails we restart all of them to ensure a valid state. Jobs are then
    # re-loaded from redis. Supervisor docs: http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    opts = [
      strategy: :one_for_all,
      name: MnesiaEx.Supervisor,
      max_seconds: 15,
      max_restarts: 3
    ]

    Supervisor.start_link(children, opts)
  end
end
