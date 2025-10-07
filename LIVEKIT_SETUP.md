# LivekitexAgent - Configuración e Integración

## Problema Inicial

La dependencia `livekitex_agent` fallaba al iniciar por las siguientes razones:

1. **Configuración faltante**: `LivekitexAgent.Application` se auto-iniciaba pero no encontraba la configuración requerida (`worker_pool_size`, etc.)
2. **Tipos incorrectos**: La aplicación pasaba listas vacías `[]` a componentes que esperaban mapas o structs con configuración apropiada
3. **Incompatibilidad de tipos**: Algunos componentes esperaban keyword lists mientras que otros esperaban mapas

## Solución Implementada

Se implementó una solución que previene el auto-inicio de la aplicación `livekitex_agent` y la configura manualmente desde nuestra aplicación Phoenix.

### Cambios Realizados

#### 1. `mix.exs` - Prevención de Auto-inicio

```elixir
def application do
  [
    mod: {NvivoAgent.Application, []},
    extra_applications: [:logger, :runtime_tools],
    included_applications: [:livekitex_agent]  # ← Previene auto-inicio
  ]
end
```

**¿Por qué?** Al agregar `:livekitex_agent` a `included_applications`, Elixir NO inicia automáticamente esa aplicación, dándonos control total sobre su configuración e inicio.

#### 2. `config/config.exs` - Configuración Base

```elixir
config :livekitex_agent,
  # Gestión de workers
  worker_pool_size: 8,                    # Número de workers concurrentes para agentes
  max_concurrent_jobs: 100,               # Máximo de sesiones simultáneas

  # Configuración del agente
  agent_name: "dinko",                    # Nombre visible del agente
  server_url: "wss://127.0.0.1:7880",    # URL del servidor LiveKit
  api_key: "devkey",                     # API key de LiveKit
  api_secret: "secret",                  # API secret de LiveKit

  # Opciones de desarrollo
  log_level: :info,                      # Nivel de logging (:debug, :info, :warn, :error)

  # Configuración de infraestructura (opcional)
  health_config: [port: 8081],           # Puerto para health checks
  audio_config: %{}                       # Configuración de procesamiento de audio
```

**Opciones disponibles:**
- `worker_pool_size`: Número de workers que procesarán jobs concurrentemente
- `max_concurrent_jobs`: Límite de trabajos simultáneos en la cola
- `agent_name`: Nombre identificador del agente en LiveKit
- `server_url`: URL WebSocket del servidor LiveKit
- `api_key` y `api_secret`: Credenciales de autenticación
- `log_level`: Verbosidad de los logs
- `health_config`: Configuración del servidor de health checks
- `audio_config`: Configuración del procesador de audio

#### 3. `lib/nvivo_agent/livekit_config.ex` - Helper de Configuración

Este módulo construye las opciones de worker desde la configuración de la aplicación:

```elixir
defmodule NvivoAgent.LivekitConfig do
  @moduledoc """
  Helper module to build LivekitexAgent configuration from application config.
  """

  def build_worker_options do
    config = Application.get_all_env(:livekitex_agent)

    # Construir WorkerOptions struct desde la config
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

    # Convertir a map y agregar configs adicionales para componentes de infraestructura
    worker_options
    |> Map.from_struct()
    |> Map.put(:health_config, config[:health_config] || [port: 8081])
    |> Map.put(:audio_config, config[:audio_config] || %{})
  end

  defp default_entry_point(_job_context) do
    # Entry point por defecto - puede ser sobreescrito en config
    :ok
  end
end
```

**Detalles importantes:**
- `WorkerOptions.new/1` crea un struct con validación de tipos
- `Map.from_struct/1` convierte el struct a map para compatibilidad con `Map.get/3`
- `health_config` debe ser una keyword list (para `Keyword.get/3`)
- `audio_config` debe ser un map (para `Map.get/3`)

#### 4. `lib/nvivo_agent/application.ex` - Inicio Manual

```elixir
defmodule NvivoAgent.Application do
  use Application

  @impl true
  def start(_type, _args) do
    # Construir worker options desde config
    worker_options = NvivoAgent.LivekitConfig.build_worker_options()

    children = [
      NvivoAgentWeb.Telemetry,
      NvivoAgent.Repo,
      {DNSCluster, query: Application.get_env(:nvivo_agent, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: NvivoAgent.PubSub},

      # Iniciar LivekitexAgent.WorkerSupervisor con configuración apropiada
      # Este supervisor iniciará su propia infraestructura (ToolRegistry, WorkerManager, etc.)
      {LivekitexAgent.WorkerSupervisor, worker_options},

      NvivoAgentWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: NvivoAgent.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # ...
end
```

**¿Por qué solo iniciar WorkerSupervisor?** El `WorkerSupervisor` inicia su propio supervisor de infraestructura que incluye todos los componentes necesarios en el orden correcto.

## Arquitectura de LivekitexAgent

### Jerarquía de Supervisión

```
NvivoAgent.Supervisor (one_for_one)
└── LivekitexAgent.WorkerSupervisor (dynamic)
    └── LivekitexAgent.InfrastructureSupervisor (rest_for_one)
        ├── Registry (CircuitBreakerRegistry)
        ├── LivekitexAgent.ToolRegistry
        ├── LivekitexAgent.Media.AudioProcessor
        ├── LivekitexAgent.HealthServer
        └── LivekitexAgent.WorkerManager
```

**Estrategias de supervisión:**
- `one_for_one`: Si un hijo falla, solo ese hijo se reinicia
- `rest_for_one`: Si un hijo falla, ese hijo y todos los que lo siguen se reinician
- `dynamic`: Permite agregar/remover hijos dinámicamente

### Componentes de LivekitexAgent

1. **ToolRegistry**: Registro global de herramientas/tools disponibles para los agentes
2. **CircuitBreakerRegistry**: Registry para circuit breakers de servicios externos
3. **AudioProcessor**: Pipeline de procesamiento de audio en tiempo real
4. **HealthServer**: Servidor HTTP para health checks y métricas (puerto 8081)
5. **WorkerManager**: Coordinación y distribución de jobs entre workers
6. **WorkerSupervisor**: Supervisor dinámico para procesos de agentes individuales

## Configuración de Entry Point

El `entry_point` es la función que se ejecuta cuando se asigna un job a un worker. Puedes personalizarlo en la configuración:

```elixir
# config/config.exs
config :livekitex_agent,
  entry_point: &MyApp.Agent.handle_job/1,
  # ... resto de la config
```

O crear un módulo dedicado:

```elixir
defmodule NvivoAgent.AgentHandler do
  def handle_job(job_context) do
    # job_context contiene información sobre el room, participant, etc.
    # Implementa la lógica de tu agente aquí
    :ok
  end
end

# En config.exs
config :livekitex_agent,
  entry_point: &NvivoAgent.AgentHandler.handle_job/1,
```

## Testing y Verificación

### Iniciar el servidor

```bash
iex -S mix phx.server
```

### Logs esperados en inicio exitoso

```
[info] ToolRegistry started with table: :livekitex_agent_tools
[info] AudioProcessor started with config: %{}
[info] HealthServer listening on port 8081
[info] Worker manager started for agent: dinko with 8 workers
[info] Running NvivoAgentWeb.Endpoint with Bandit 1.5.x at 127.0.0.1:4000 (http)
[info] Access NvivoAgentWeb.Endpoint at http://localhost:4000
```

### Health Check

Verificar que el servidor de salud esté funcionando:

```bash
curl http://localhost:8081/health
```

Respuesta esperada:
```json
{
  "status": "healthy",
  "timestamp": "2025-10-07T...",
  "workers": {
    "active": 8,
    "idle": 8,
    "busy": 0
  }
}
```

### Verificación en IEx

```elixir
# Verificar que el ToolRegistry está disponible
iex> LivekitexAgent.ToolRegistry.list_tools()

# Ver estado de los workers
iex> LivekitexAgent.WorkerManager.get_status()

# Ver métricas
iex> LivekitexAgent.WorkerManager.get_metrics()
```

## Troubleshooting

### Error: `worker_pool_size not found`

**Causa**: La configuración no se está cargando correctamente.

**Solución**: Verificar que `config/config.exs` contenga la configuración de `:livekitex_agent` y que el archivo esté siendo importado correctamente.

### Error: `function_clause Keyword.get [%{}, :port, 8080]`

**Causa**: El `health_config` está configurado como un map en lugar de keyword list.

**Solución**: Asegurar que `health_config` sea una keyword list:
```elixir
health_config: [port: 8081]  # ✓ Correcto
health_config: %{port: 8081}  # ✗ Incorrecto
```

### Error: `expected a map, got: []`

**Causa**: `WorkerSupervisor` está recibiendo una lista vacía en lugar de worker_options.

**Solución**: Verificar que `NvivoAgent.LivekitConfig.build_worker_options()` esté siendo llamado correctamente en `application.ex`.

### Puerto 8081 en uso

**Causa**: Otro proceso está usando el puerto del health server.

**Solución**: Cambiar el puerto en la configuración:
```elixir
config :livekitex_agent,
  health_config: [port: 8082]  # Usar otro puerto
```

## Próximos Pasos

1. **Implementar entry_point personalizado**: Crear la lógica de tu agente específico
2. **Registrar tools personalizadas**: Agregar herramientas que tu agente puede usar
3. **Configurar LiveKit server**: Conectar a un servidor LiveKit real
4. **Implementar manejo de sesiones**: Lógica para conectar con rooms y participants
5. **Agregar tests**: Crear tests para la integración de LiveKit

## Referencias

- [LiveKit Documentation](https://docs.livekit.io/)
- [LiveKit Agents](https://docs.livekit.io/agents/overview/)
- [Elixir Supervision Trees](https://hexdocs.pm/elixir/Supervisor.html)
