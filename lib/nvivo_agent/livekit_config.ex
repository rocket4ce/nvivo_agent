defmodule NvivoAgent.LivekitConfig do
  @moduledoc """
  Helper module to build LivekitexAgent configuration from application config.
  """

  def build_worker_options do
    config = Application.get_all_env(:livekitex_agent)

    # Build WorkerOptions struct first
    worker_options = LivekitexAgent.WorkerOptions.new(
      entry_point: config[:entry_point] || (&default_entry_point/1),
      worker_pool_size: config[:worker_pool_size] || 8,
      max_concurrent_jobs: config[:max_concurrent_jobs] || 100,
      agent_name: config[:agent_name] || "dinko",
      server_url: config[:server_url] || "wss://127.0.0.1:7880",
      api_key: config[:api_key] || "devkey",
      api_secret: config[:api_secret] || "secret",
      log_level: config[:log_level] || :info
    )

    # Convert struct to map and add additional configs for infrastructure components
    worker_options
    |> Map.from_struct()
    |> Map.put(:health_config, config[:health_config] || [port: 8081])
    |> Map.put(:audio_config, config[:audio_config] || %{})
  end

  defp default_entry_point(_job_context) do
    # Default entry point - can be overridden in config
    :ok
  end
end
