defmodule NvivoAgent.Repo do
  use Ecto.Repo,
    otp_app: :nvivo_agent,
    adapter: Ecto.Adapters.Postgres
end
