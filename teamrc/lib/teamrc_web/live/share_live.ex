defmodule TeamrcWeb.ShareLive do
  use TeamrcWeb, :live_view

  alias Teamrc.Teams

  @impl true
  def mount(%{"clone_token" => clone_token}, _session, socket) do
    case Teams.preview_by_clone_token(clone_token) do
      {:ok, team} ->
        agent_count = length(team["members"] || [])
        skill_count = length(team["skills"] || [])
        url = share_url(clone_token)

        {:ok,
         assign(socket,
           page_title: "#{team["name"]} \u2014 Share",
           team: team,
           clone_token: clone_token,
           agent_count: agent_count,
           skill_count: skill_count,
           share_url: url,
           og_title: "#{team["name"]} \u2014 teamrc",
           og_description: "#{agent_count} agents, #{skill_count} skills \u2014 AI coding agent team",
           og_url: url,
           not_found: false
         ), layout: false}

      :error ->
        {:ok,
         assign(socket,
           page_title: "Not Found",
           not_found: true,
           team: nil,
           clone_token: clone_token
         ), layout: false}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-100 bg-grid flex flex-col">
      <%!-- Minimal header --%>
      <header class="border-b border-base-300/60 bg-base-100/80 backdrop-blur-sm">
        <div class="mx-auto max-w-3xl flex items-center px-4 sm:px-6 h-14">
          <a href="/" class="flex items-center gap-2.5 group" aria-label="teamrc home">
            <div class="text-primary">
              <img src={~p"/images/logo.svg"} width="24" height="24" alt="teamrc" />
            </div>
            <span class="text-sm font-semibold tracking-tight">teamrc</span>
          </a>
        </div>
      </header>

      <main class="flex-1 px-4 py-8 sm:px-8 sm:py-16">
        <div class="mx-auto max-w-2xl">
          <%= if @not_found do %>
            <%!-- Not found state --%>
            <div class="max-w-md mx-auto mt-16 text-center space-y-4">
              <div class="flex justify-center">
                <div class="flex h-12 w-12 items-center justify-center rounded-full bg-base-200">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    class="h-6 w-6 text-base-content/50"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke-width="1.5"
                    stroke="currentColor"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      d="M16.5 10.5V6.75a4.5 4.5 0 1 0-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 0 0 2.25-2.25v-6.75a2.25 2.25 0 0 0-2.25-2.25H6.75a2.25 2.25 0 0 0-2.25 2.25v6.75a2.25 2.25 0 0 0 2.25 2.25Z"
                    />
                  </svg>
                </div>
              </div>
              <h1 class="text-lg font-semibold">This team is private or doesn't exist.</h1>
              <p class="text-sm text-base-content/60">
                The team you're looking for may have been made private, or the link is invalid.
              </p>
              <a
                href={~p"/new"}
                class="trc-focus inline-flex items-center rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-content hover:bg-primary/90 transition-colors"
              >
                Create your own team
              </a>
            </div>
          <% else %>
            <div class="space-y-10">
              <%!-- Team name and stats --%>
              <div>
                <h1 class="text-2xl sm:text-3xl font-bold tracking-tight font-mono">{@team["name"]}</h1>
                <p class="text-sm text-base-content/60 mt-2">
                  {@agent_count} <%= if @agent_count == 1, do: "agent", else: "agents" %> · {@skill_count} <%= if @skill_count == 1, do: "skill", else: "skills" %>
                </p>
              </div>

              <%!-- Member cards --%>
              <section>
                <p class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-3">
                  Agents
                </p>
                <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
                  <div
                    :for={member <- @team["members"]}
                    class="rounded-lg border border-base-300 bg-base-100 p-4"
                  >
                    <span class="font-mono font-semibold text-sm text-base-content">{member["name"]}</span>
                    <p class="text-xs text-base-content/70 mt-0.5">{member["role"]}</p>
                    <p
                      :if={member["soul"]}
                      class="text-xs text-base-content/50 mt-2 line-clamp-2"
                    >
                      {member["soul"]}
                    </p>
                    <div :if={member["skills"] && member["skills"] != []} class="flex flex-wrap gap-1 mt-2">
                      <span
                        :for={skill_id <- member["skills"]}
                        class="inline-flex items-center rounded bg-base-200 px-1.5 py-0.5 text-[10px] font-mono text-base-content/60"
                      >
                        {skill_id}
                      </span>
                    </div>
                  </div>
                </div>
              </section>

              <%!-- Team skills --%>
              <section :if={@team["skills"] && @team["skills"] != []}>
                <p class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-3">
                  Team Skills
                </p>
                <div class="space-y-2">
                  <div
                    :for={skill <- @team["skills"]}
                    class="rounded-lg border border-base-300 bg-base-100 p-3 flex items-start gap-3"
                  >
                    <div>
                      <span class="font-mono text-sm font-medium">{skill["id"]}</span>
                      <span
                        :if={skill["alwaysApply"]}
                        class="ml-1.5 inline-flex items-center rounded bg-primary/10 px-1.5 py-0.5 text-[10px] font-medium text-primary"
                      >
                        auto
                      </span>
                      <p :if={skill["description"]} class="text-xs text-base-content/60 mt-0.5">
                        {skill["description"]}
                      </p>
                    </div>
                  </div>
                </div>
              </section>

              <%!-- Clone CTA --%>
              <section>
                <div class="terminal-block rounded-lg overflow-hidden">
                  <div class="flex items-center justify-between px-4 py-2.5 border-b border-white/5">
                    <div class="flex items-center gap-2">
                      <div class="flex gap-1.5">
                        <div class="w-2.5 h-2.5 rounded-full bg-white/10"></div>
                        <div class="w-2.5 h-2.5 rounded-full bg-white/10"></div>
                        <div class="w-2.5 h-2.5 rounded-full bg-white/10"></div>
                      </div>
                      <span class="text-[10px] font-mono text-white/25 ml-2">terminal</span>
                    </div>
                    <button
                      id="copy-clone-btn"
                      phx-click={
                        Phoenix.LiveView.JS.dispatch("trc:copy",
                          detail: %{text: "npx @teamrc/cli clone #{@clone_token}"}
                        )
                      }
                      class="trc-focus text-[10px] font-mono text-white/30 hover:text-white/60 transition-colors rounded px-1.5 py-0.5 hover:bg-white/5"
                      aria-label="Copy clone command"
                    >
                      copy
                    </button>
                  </div>
                  <div class="p-4">
                    <div class="flex items-start gap-2">
                      <span class="text-white/30 font-mono text-sm select-none">$</span>
                      <code class="text-emerald-400 text-sm font-mono break-all select-all">
                        npx @teamrc/cli clone {@clone_token}
                      </code>
                    </div>
                  </div>
                </div>
                <p class="text-xs text-base-content/50 mt-2">
                  Copies this team to your machine. Run <code class="font-mono">teamrc pull</code> anytime to get the latest updates.
                </p>
              </section>

              <%!-- Share + Secondary CTA --%>
              <div class="flex items-center justify-center gap-4">
                <button
                  id="copy-share-link"
                  phx-click={
                    Phoenix.LiveView.JS.dispatch("trc:copy",
                      detail: %{text: @share_url}
                    )
                  }
                  class="trc-focus inline-flex items-center gap-2 rounded-md border border-base-300 bg-base-100 px-4 py-2.5 text-sm font-medium text-base-content hover:bg-base-200/60 hover:border-base-400 transition-colors"
                  aria-label="Copy share link"
                >
                  <svg class="h-4 w-4 text-base-content/60" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M13.19 8.688a4.5 4.5 0 0 1 1.242 7.244l-4.5 4.5a4.5 4.5 0 0 1-6.364-6.364l1.757-1.757m9.86-2.54a4.5 4.5 0 0 0-1.242-7.244l-4.5-4.5a4.5 4.5 0 0 0-6.364 6.364l1.757 1.757" />
                  </svg>
                  Copy link
                </button>
                <span class="text-base-content/20">|</span>
                <a
                  href={~p"/new"}
                  class="trc-focus inline-flex items-center gap-1.5 text-sm font-medium text-primary hover:text-primary/80 transition-colors"
                >
                  Create your own team
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor">
                    <path fill-rule="evenodd" d="M10.293 3.293a1 1 0 011.414 0l6 6a1 1 0 010 1.414l-6 6a1 1 0 01-1.414-1.414L14.586 11H3a1 1 0 110-2h11.586l-4.293-4.293a1 1 0 010-1.414z" clip-rule="evenodd" />
                  </svg>
                </a>
              </div>
            </div>
          <% end %>
        </div>
      </main>

      <%!-- Minimal footer --%>
      <footer class="border-t border-base-300/40 py-6 mt-auto">
        <div class="mx-auto max-w-2xl px-4 sm:px-8 flex items-center justify-center">
          <p class="text-xs text-base-content/50">
            Powered by <a href="/" class="text-base-content/60 hover:text-base-content/80 transition-colors font-medium">teamrc</a>
          </p>
        </div>
      </footer>
    </div>
    """
  end

  defp share_url(clone_token) do
    TeamrcWeb.Endpoint.url() <> "/t/#{clone_token}"
  end
end
