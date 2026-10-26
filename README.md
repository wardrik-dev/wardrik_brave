# WardrikBrave

Web search for agents, through Brave's LLM Context API: a search answers with the passages of each
page that bear on the query, not a list of links, so one call is usually enough to ground an answer.

```elixir
def deps do
  [
    {:wardrik_brave, "~> 0.1"}
  ]
end
```

Start it with the key, under a name of your own, and give agents the capability by that name:

```elixir
children = [{WardrikBrave, name: MyApp.Brave, api_key: System.fetch_env!("BRAVE_API_KEY")}]

WardrikCore.start_agent(
  agent_id: "acme/triage",
  model: "anthropic:claude-haiku-4-5",
  capabilities: [{WardrikBrave, brave: MyApp.Brave}]
)
```

In a [Wardrik](https://hexdocs.pm/wardrik), offer it by name, and a definition names it in its
`tools`:

```elixir
config :my_app, MyApp.Wardrik, capabilities: [web_search: {WardrikBrave, brave: MyApp.Brave}]
```

The daemon does this for you from `config.yaml`'s `brave.api_key`, which `wardrik vault put
BRAVE_API_KEY` can hold.

The key is held by the process, never by an agent, so it's never kept in the store with an agent's
state. Without one, a search answers that the key is missing, and the agent says so. Results are
kept small, 10 results and about 4,096 tokens, since each becomes part of the turn that asked.
