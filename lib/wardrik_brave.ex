defmodule WardrikBrave do
  @moduledoc """
  Web search for agents, through Brave's LLM Context API: a search answers with the passages of each
  page that bear on the query, not a list of links, so one call is usually enough to ground an
  answer.

  Start it with the key it searches with, under a name of your own, and give agents the capability
  by that name:

      children = [{WardrikBrave, name: MyApp.Brave, api_key: System.fetch_env!("BRAVE_API_KEY")}]

      WardrikCore.start_agent(agent_id: "acme/triage", model: "...", capabilities: [{WardrikBrave, brave: MyApp.Brave}])

  The key is held by the process, never by an agent, so it's never kept in the store with the
  agent's state. Without a key, a search answers that the key is missing. It takes `:req_options`,
  merged into every request, and `:base_url`.

  The pages a search finds are ones anyone could have written, so the tool is marked as reaching
  the open world.

  Reach for this when agents need what happened after their training, or facts they'd guess at.
  """

  use GenServer

  @behaviour WardrikCore.Capability

  @doc "Starts holding the settings searches use: `:name`, `:api_key`, `:req_options` and `:base_url`."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    opts =
      Keyword.validate!(opts, [
        :name,
        :api_key,
        req_options: [],
        base_url: "https://api.search.brave.com"
      ])

    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  @impl WardrikCore.Capability
  def tools(_context, opts), do: [WardrikBrave.WebSearch.tool(Keyword.fetch!(opts, :brave))]

  @doc "Returns the settings `brave` holds."
  @spec settings(atom()) :: map()
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
