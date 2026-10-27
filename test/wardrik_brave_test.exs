defmodule WardrikBraveTest do
  use ExUnit.Case, async: true

  setup context do
    name = :"brave #{context.test}"
    key = Map.get(context, :key, "k3y")

    start_supervised!(
      {WardrikBrave,
       name: name, api_key: key, req_options: [plug: {Req.Test, name}, retry_delay: 0]}
    )

    [tool] = WardrikBrave.tools(nil, brave: name)
    %{name: name, tool: tool}
  end

  defp search(tool, args), do: tool.run.(args, WardrikCore.Context.new(agent_id: "acme/triage"))

  test "answers the passages of each page found, with its date", %{name: name, tool: tool} do
    test = self()

    Req.Test.stub(name, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      send(
        test,
        {:searched, Plug.Conn.get_req_header(conn, "x-subscription-token"), JSON.decode!(body)}
      )

      Req.Test.json(conn, %{
        "grounding" => %{
          "generic" => [
            %{"url" => "https://a.test", "title" => "A", "snippets" => ["one"]},
            %{"url" => "https://b.test"}
          ]
        },
        "sources" => %{"https://a.test" => %{"age" => ["October 1, 2026", "2026-10-01"]}}
      })
    end)

    assert search(tool, %{query: "elixir", freshness: "pw"}) ==
             {:ok,
              %{
                "count" => 2,
                "results" => [
                  %{
                    "url" => "https://a.test",
                    "title" => "A",
                    "snippets" => ["one"],
                    "age" => "October 1, 2026"
                  },
                  %{"url" => "https://b.test", "snippets" => []}
                ]
              }}

    assert_received {:searched, ["k3y"],
                     %{
                       "q" => "elixir",
                       "count" => 10,
                       "maximum_number_of_tokens" => 4096,
                       "freshness" => "pw"
                     }}
  end

  test "asks for an exact window, and refuses one that doesn't read", %{name: name, tool: tool} do
    Req.Test.stub(name, &Req.Test.json(&1, %{}))

    assert {:ok, %{"count" => 0}} =
             search(tool, %{
               query: "q",
               published_between: "2025-01-01to2025-06-30",
               count: 5,
               max_tokens: 2048
             })

    assert {:error, "Give freshness" <> _} =
             search(tool, %{query: "q", freshness: "pd", published_between: "x"})

    assert {:error, "published_between is" <> _} =
             search(tool, %{query: "q", published_between: "last week"})
  end

  test "tries a search that failed for a while again", %{name: name, tool: tool} do
    {:ok, tries} = Agent.start_link(fn -> 0 end)

    Req.Test.stub(name, fn conn ->
      case Agent.get_and_update(tries, &{&1, &1 + 1}) do
        0 -> Plug.Conn.send_resp(conn, 503, "")
        _later -> Req.Test.json(conn, %{"grounding" => %{"generic" => []}})
      end
    end)

    assert {:ok, %{"count" => 0}} = search(tool, %{query: "q"})
    assert Agent.get(tries, & &1) == 2
  end

  test "says why a search failed", %{name: name, tool: tool} do
    Req.Test.stub(name, &Plug.Conn.send_resp(&1, 429, ""))
    assert {:error, "Brave is limiting" <> _} = search(tool, %{query: "q"})

    Req.Test.stub(name, &Plug.Conn.send_resp(&1, 500, ""))
    assert {:error, "Brave's search answered 500."} = search(tool, %{query: "q"})

    Req.Test.stub(name, &Req.Test.transport_error(&1, :econnrefused))
    assert {:error, "Brave's search didn't answer" <> _} = search(tool, %{query: "q"})

    Req.Test.stub(name, &Req.Test.text(&1, "not json"))
    assert {:ok, %{"count" => 0}} = search(tool, %{query: "q"})
  end

  @tag key: nil
  test "says the key is missing", %{tool: tool} do
    assert {:error, "Web search has no key." <> _} = search(tool, %{query: "q"})
  end

  test "marks the tool as reaching the open world", %{tool: tool} do
    assert WardrikCore.Tool.annotation(tool, :open_world)
    assert WardrikCore.Tool.annotation(tool, :labels) == ["outside"]
  end

  test "says which one isn't started" do
    assert_raise ArgumentError, ~r/isn't started/, fn -> WardrikBrave.settings(:nowhere) end
  end
end
