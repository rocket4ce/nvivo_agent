# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :livekitex_agent,
  # Worker management
  worker_pool_size: 8,                    # Number of concurrent agent workers
  max_concurrent_jobs: 100,               # Max simultaneous sessions

  # Agent settings
  agent_name: "dinko",         # Display name for your agent
  server_url: "wss://127.0.0.1:7880",   # LiveKit server URL
  api_key: "devkey",                # LiveKit API key
  api_secret: "secret",          # LiveKit API secret

  # Development options
  log_level: :info                        # Logging verbosity

config :nvivo_agent,
  ecto_repos: [NvivoAgent.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :nvivo_agent, NvivoAgentWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: NvivoAgentWeb.ErrorHTML, json: NvivoAgentWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: NvivoAgent.PubSub,
  live_view: [signing_salt: "4Do/Zckk"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :nvivo_agent, NvivoAgent.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  nvivo_agent: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  nvivo_agent: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
