defmodule WardrikBrave do
  @moduledoc """
  Web search for agents, through Brave's LLM Context API: a search answers with the passages of each
  page that bear on the query, not a list of links, so one call is usually enough to ground an
  answer.

  Start it under a name of your own, with the key it searches with where an agent's keys hold none,
  and give agents the capability by that name:

      children = [{WardrikBrave, name: MyApp.Brave, api_key: System.fetch_env!("BRAVE_API_KEY")}]

      WardrikCore.start_agent(agent_id: "acme/triage", model: "...", capabilities: [{WardrikBrave, brave: MyApp.Brave}])

  Each search takes `BRAVE_API_KEY` from the agent's `WardrikCore.Keys` first, so an org can bring
  its own, and the key it was started with otherwise. Where every agent's keys hold one, nothing
  needs starting: give the capability its settings inline, as `{WardrikBrave, []}`, or with
  `:api_key`, `:req_options` and `:base_url`. Neither is kept in the store with the agent's
  state. Without a key, a search answers that the key is missing. It takes `:req_options`,
  merged into every request, and `:base_url`.

  The pages a search finds are ones anyone could have written, so the tool is marked as reaching
  the open world.

  Reach for this when agents need what happened after their training, or facts they'd guess at.
  """

  use GenServer

  @behaviour WardrikCore.Capability

  @settings [api_key: nil, req_options: [], base_url: "https://api.search.brave.com"]

  @doc "Starts holding the settings searches use: `:name`, `:api_key`, `:req_options` and `:base_url`."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    opts = Keyword.validate!(opts, [:name | @settings])

    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  @impl WardrikCore.Capability
  def tools(_context, opts), do: [WardrikBrave.WebSearch.tool(source(opts))]

  defp source(opts) do
    case Keyword.fetch(opts, :brave) do
      {:ok, brave} -> brave
      :error -> opts |> Keyword.validate!(@settings) |> Map.new()
    end
  end

  @doc "Returns the settings `brave` holds, or the settings given inline."
  @spec settings(atom() | map()) :: map()
  def settings(%{} = settings), do: settings

  def settings(brave) do
    [{:settings, settings}] = :ets.lookup(brave, :settings)
    settings
  rescue
    ArgumentError ->
      reraise ArgumentError,
              "#{inspect(brave)} isn't started. Add {WardrikBrave, name: #{inspect(brave)}, api_key: key} to your supervision tree.",
              __STACKTRACE__
  end

  @impl GenServer
  def init(opts) do
    table =
      :ets.new(Keyword.fetch!(opts, :name), [:named_table, :protected, read_concurrency: true])

    true = :ets.insert(table, {:settings, Map.new(Keyword.delete(opts, :name))})
    {:ok, table}
  end
end
