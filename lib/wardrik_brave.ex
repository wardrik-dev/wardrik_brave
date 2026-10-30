defmodule WardrikBrave do
  @moduledoc """
  Web search for agents, through Brave's LLM Context API.

  A search returns the relevant passages of each page, not a list of links, so one call is usually
  enough to ground an answer. Use it when agents need facts newer than their training, or facts
  they'd otherwise guess at.

      children = [{WardrikBrave, name: MyApp.Brave, api_key: System.fetch_env!("BRAVE_API_KEY")}]

      WardrikCore.start_agent(
        agent_id: "acme/triage",
        model: "anthropic:claude-haiku-4-5",
        capabilities: [{WardrikBrave, brave: MyApp.Brave}]
      )

  If every agent's keys hold `BRAVE_API_KEY`, nothing needs starting. Give the settings inline:

      capabilities: [{WardrikBrave, []}]

  ## Keys

  Each search takes `BRAVE_API_KEY` from the agent's `WardrikCore.Keys` first, then falls back to
  `:api_key`. Neither is kept in the store with the agent's state. Without a key, the search
  returns an error saying so.

  ## Options

  Given to `start_link/1`, or inline in place of `:brave`:

    * `:api_key` - the key to search with where the agent's keys hold none.
    * `:req_options` - merged into every request. `[]` unless set.
    * `:base_url` - `"https://api.search.brave.com"` unless set.

  The tool is marked `open_world`, since the pages it finds could be written by anyone.
  """

  use GenServer

  @behaviour WardrikCore.Capability

  @settings [api_key: nil, req_options: [], base_url: "https://api.search.brave.com"]

  @doc """
  Starts a process that holds the search settings under `:name`.

  Takes `:name` (required) and the options in the module docs.
  """
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

  @doc """
  Returns the settings started under `brave`, or `brave` itself if it's a map.

  Raises `ArgumentError` if nothing is started under `brave`.
  """
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
