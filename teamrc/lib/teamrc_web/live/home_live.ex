defmodule TeamrcWeb.HomeLive do
  use TeamrcWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Keep Your AI Agents in Sync Across Machines and VMs",
       og_description:
         "Claude Code on your laptop, OpenClaw on a VM? teamrc keeps your agent configs in sync across machines, platforms, and projects. Open-source CLI.",
       hero_tab: "new",
       bottom_tab: "new"
     )}
  end

  @impl true
  def handle_event("set_hero_tab", %{"tab" => tab}, socket) when tab in ["new", "clone", "local"] do
    {:noreply, assign(socket, :hero_tab, tab)}
  end

  @impl true
  def handle_event("set_bottom_tab", %{"tab" => tab}, socket) when tab in ["new", "clone", "local"] do
    {:noreply, assign(socket, :bottom_tab, tab)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%!-- Hero --%>
    <div class="pt-4 pb-2">
      <div class="flex items-center gap-3 mb-4">
        <span class="inline-flex items-center gap-1.5 rounded-full bg-base-200/60 border border-base-300 px-2.5 py-1 text-[11px] font-mono text-base-content/50">
          open source
        </span>
        <a
          href="https://github.com/teamrc-ai/teamrc"
          target="_blank"
          rel="noopener"
          class="trc-focus inline-flex items-center text-base-content/40 hover:text-base-content/70 transition-colors"
          aria-label="GitHub"
        >
          <svg class="h-4 w-4" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true">
            <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z" />
          </svg>
        </a>
      </div>
      <h1 class="text-3xl sm:text-4xl font-bold tracking-tight leading-tight">
        Keep your AI agents in sync<br />across every machine.
      </h1>
      <p class="text-base text-base-content/60 mt-4 max-w-lg leading-relaxed">
        Claude Code on your laptop. OpenClaw on a VM. Cursor in the cloud. teamrc
        keeps your agents, skills, and shared knowledge in sync across all of them.
        Change something on one machine. Every other machine picks it up.
      </p>
      <p class="text-sm text-base-content/50 mt-2">
        No account required for local use. Open source. Self-host or use the hosted relay.
      </p>

      <%!-- Primary CTA --%>
      <div class="mt-8">
        <.terminal_cta tab={@hero_tab} event="set_hero_tab" id_suffix="hero" />
      </div>

      <%!-- Secondary CTA --%>
      <p class="mt-4 text-sm text-base-content/50">
        or
        <a href="/new" class="trc-focus text-primary/80 hover:text-primary underline underline-offset-2 transition-colors">
          build your team on the web
        </a>
      </p>
    </div>

    <%!-- How it works --%>
    <section class="mt-16 space-y-4">
      <h2 class="text-lg font-bold tracking-tight">How it works</h2>
      <ol class="space-y-3 list-none p-0">
        <li class="rounded-lg border border-base-300 bg-base-100 p-4 flex items-start gap-3">
          <span class="text-primary/80 font-mono text-sm font-bold shrink-0 w-5">1.</span>
          <div>
            <h3 class="text-sm font-semibold">Define your agents once</h3>
            <p class="text-sm text-base-content/60 mt-0.5">
              A single
              <code class="font-mono bg-base-200 rounded px-1.5 py-0.5 text-xs">.teamrc.yaml</code>
              describes your team: agents, skills, and how they're wired together.
              Pick from 60+ pre-built agents and 50+ skills, or write your own.
            </p>
          </div>
        </li>
        <li class="rounded-lg border border-base-300 bg-base-100 p-4 flex items-start gap-3">
          <span class="text-primary/80 font-mono text-sm font-bold shrink-0 w-5">2.</span>
          <div>
            <h3 class="text-sm font-semibold">Each platform gets native files</h3>
            <p class="text-sm text-base-content/60 mt-0.5">
              teamrc generates the right format for each platform. Claude Code gets
              <code class="font-mono bg-base-200 rounded px-1.5 py-0.5 text-xs">.claude/agents/*.md</code>,
              OpenClaw gets
              <code class="font-mono bg-base-200 rounded px-1.5 py-0.5 text-xs">.agents/agents/*.md</code>,
              Codex gets TOML. All from the same source.
            </p>
          </div>
        </li>
        <li class="rounded-lg border border-base-300 bg-base-100 p-4 flex items-start gap-3">
          <span class="text-primary/80 font-mono text-sm font-bold shrink-0 w-5">3.</span>
          <div>
            <h3 class="text-sm font-semibold">Sync across every machine</h3>
            <p class="text-sm text-base-content/60 mt-0.5">
              Run
              <code class="font-mono bg-base-200 rounded px-1.5 py-0.5 text-xs">teamrc sync</code>
              on your laptop, your VM, or any project directory. The relay pushes
              config changes and merges knowledge from all machines automatically.
            </p>
          </div>
        </li>
      </ol>
    </section>

    <%!-- Knowledge sync --%>
    <section class="mt-12 space-y-3">
      <h2 class="text-lg font-bold tracking-tight">Your agents learn once. Every machine remembers.</h2>
      <p class="text-sm text-base-content/70 leading-relaxed">
        As agents work, they write findings to a shared knowledge file: build quirks,
        architectural decisions, environment-specific fixes. When you sync, knowledge
        from every machine merges automatically. The agent on your VM benefits from
        what the agent on your laptop discovered an hour ago.
      </p>
      <p class="text-sm text-base-content/70 leading-relaxed">
        With the daemon running, this happens in real time over WebSocket. No manual
        copying. No stale context.
      </p>
    </section>

    <%!-- The real scenario --%>
    <section class="mt-12 space-y-3">
      <h2 class="text-lg font-bold tracking-tight">Built for how people actually work</h2>
      <p class="text-sm text-base-content/70 leading-relaxed">
        You have Claude Code on your laptop and OpenClaw running on a VM. Cursor
        in another project. Each platform has its own config format, and
        every machine has its own copy. You tweak an agent on one machine and the
        others fall behind.
      </p>
      <p class="text-sm text-base-content/70 leading-relaxed">
        teamrc is the sync layer. Change your team from any machine, CLI or web,
        and every other machine picks it up on the next sync. Agents, skills,
        knowledge. All of it.
      </p>
    </section>

    <%!-- Use cases --%>
    <section class="mt-12 space-y-4">
      <h2 class="text-lg font-bold tracking-tight">Useful when</h2>
      <div class="grid gap-2 sm:grid-cols-2">
        <div class="rounded-lg border border-base-300 bg-base-100 px-4 py-3 space-y-0.5">
          <p class="text-sm font-semibold">Multiple machines</p>
          <p class="text-xs text-base-content/60">Claude Code on your laptop, OpenClaw on a VM, Cursor in CI</p>
        </div>
        <div class="rounded-lg border border-base-300 bg-base-100 px-4 py-3 space-y-0.5">
          <p class="text-sm font-semibold">Mixed platforms</p>
          <p class="text-xs text-base-content/60">Your team uses Cursor, Codex, and Gemini across different projects</p>
        </div>
        <div class="rounded-lg border border-base-300 bg-base-100 px-4 py-3 space-y-0.5">
          <p class="text-sm font-semibold">Fast onboarding</p>
          <p class="text-xs text-base-content/60">New machine or new teammate gets the full agent setup in one command</p>
        </div>
        <div class="rounded-lg border border-base-300 bg-base-100 px-4 py-3 space-y-0.5">
          <p class="text-sm font-semibold">Consistent behavior</p>
          <p class="text-xs text-base-content/60">Same agents, same skills, same knowledge — everywhere they run</p>
        </div>
      </div>
    </section>

    <%!-- Platforms --%>
    <section class="mt-12 space-y-4">
      <h2 class="text-lg font-bold tracking-tight">Supported platforms</h2>
      <ul class="grid grid-cols-2 sm:grid-cols-3 gap-2 list-none p-0">
        <li><.platform_badge name="Claude Code" path=".claude/agents/" /></li>
        <li><.platform_badge name="Cursor" path=".cursor/agents/" /></li>
        <li><.platform_badge name="Codex" path=".codex/agents/" /></li>
        <li><.platform_badge name="Gemini" path=".gemini/agents/" /></li>
        <li><.platform_badge name="OpenClaw" path=".agents/agents/" /></li>
      </ul>
    </section>

    <%!-- Key differentiators --%>
    <section class="mt-12 space-y-4">
      <h2 class="text-lg font-bold tracking-tight">What you get</h2>
      <div class="grid gap-2 sm:grid-cols-2">
        <div class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-1">
          <h3 class="text-sm font-semibold">Relay sync</h3>
          <p class="text-xs text-base-content/60">
            Use the same team across different repos and projects. The relay
            keeps everything aligned across machines and environments, no shared
            repo required.
          </p>
        </div>
        <div class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-1">
          <h3 class="text-sm font-semibold">Shared knowledge, not siloed notes</h3>
          <p class="text-xs text-base-content/60">
            Without teamrc, each machine's agents start from scratch. With teamrc,
            an agent that discovers your project uses a custom ORM pattern writes it
            down once. Every agent on every machine knows it by the next sync.
          </p>
        </div>
        <div class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-1">
          <h3 class="text-sm font-semibold">Format conversion built in</h3>
          <p class="text-xs text-base-content/60">
            One YAML definition, five native output formats. No need to translate
            between Claude Code's markdown, Codex's TOML, or Gemini's YAML
            frontmatter yourself.
          </p>
        </div>
        <div class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-1">
          <h3 class="text-sm font-semibold">60+ agents, 50+ skills</h3>
          <p class="text-xs text-base-content/60">
            Pre-built catalog across development, infrastructure, quality, and
            research. Use them as-is, customize them, or start from scratch.
          </p>
        </div>
      </div>
    </section>

    <%!-- Bottom CTA --%>
    <div class="mt-16 mb-4 rounded-lg border border-base-300 bg-base-200/30 p-6 text-center space-y-4">
      <p class="text-sm font-semibold">Try it in the project you're working on right now.</p>
      <.terminal_cta tab={@bottom_tab} event="set_bottom_tab" id_suffix="bottom" />
      <p class="text-sm text-base-content/50">
        or
        <a href="/new" class="trc-focus text-primary/80 hover:text-primary underline underline-offset-2 transition-colors">
          build your team on the web
        </a>
      </p>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :path, :string, required: true

  defp platform_badge(assigns) do
    ~H"""
    <div class="rounded-lg border border-base-300 bg-base-100 px-3 py-2.5 space-y-0.5">
      <p class="text-sm font-semibold">{@name}</p>
      <p class="text-[11px] font-mono text-base-content/50">{@path}</p>
    </div>
    """
  end

  defp tab_command("new"), do: "npx @teamrc/cli init"
  defp tab_command("clone"), do: "npx @teamrc/cli clone trc_cl_NtxNUMHh0WfvS5HOkPpbT_ND"
  defp tab_command("local"), do: "npx @teamrc/cli init --local"

  defp tab_description("new"), do: "Creates a .teamrc.yaml and walks you through setup."
  defp tab_description("clone"), do: "Clones an existing team config into your project."
  defp tab_description("local"), do: "Local only, no relay sync. Define everything in-project."

  attr :tab, :string, required: true
  attr :event, :string, required: true
  attr :id_suffix, :string, required: true

  defp terminal_cta(assigns) do
    ~H"""
    <div class="inline-flex flex-col">
      <div class="flex rounded-md border border-base-300 bg-base-200/50 p-0.5 mb-2">
        <button
          phx-click={@event}
          phx-value-tab="new"
          class={"trc-focus px-3 py-1 text-xs font-mono rounded transition-colors " <> if(@tab == "new", do: "bg-white text-base-content shadow-sm", else: "text-base-content/50 hover:text-base-content/70")}
        >
          New team
        </button>
        <button
          phx-click={@event}
          phx-value-tab="clone"
          class={"trc-focus px-3 py-1 text-xs font-mono rounded transition-colors " <> if(@tab == "clone", do: "bg-white text-base-content shadow-sm", else: "text-base-content/50 hover:text-base-content/70")}
        >
          Clone a team
        </button>
        <button
          phx-click={@event}
          phx-value-tab="local"
          class={"trc-focus px-3 py-1 text-xs font-mono rounded transition-colors " <> if(@tab == "local", do: "bg-white text-base-content shadow-sm", else: "text-base-content/50 hover:text-base-content/70")}
        >
          Local only
        </button>
      </div>
      <div class="terminal-block rounded-lg overflow-hidden">
        <div class="flex items-center justify-between gap-6 px-4 py-3">
          <div class="flex items-center gap-2">
            <span class="text-white/30 font-mono text-sm select-none">$</span>
            <code class="text-emerald-400 text-sm font-mono whitespace-nowrap">
              {tab_command(@tab)}
            </code>
          </div>
          <button
            id={"copy-init-" <> @id_suffix}
            phx-click={JS.dispatch("trc:copy", detail: %{text: tab_command(@tab)})}
            class="trc-focus text-white/25 hover:text-white/60 transition-colors rounded p-1 hover:bg-white/5"
            aria-label="Copy command"
          >
            <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 17.25v3.375c0 .621-.504 1.125-1.125 1.125h-9.75a1.125 1.125 0 0 1-1.125-1.125V7.875c0-.621.504-1.125 1.125-1.125H6.75a9.06 9.06 0 0 1 1.5.124m7.5 10.376h3.375c.621 0 1.125-.504 1.125-1.125V11.25c0-4.46-3.243-8.161-7.5-8.876a9.06 9.06 0 0 0-1.5-.124H9.375c-.621 0-1.125.504-1.125 1.125v3.5m7.5 10.375H9.375a1.125 1.125 0 0 1-1.125-1.125v-9.25m12 6.625v-1.875a3.375 3.375 0 0 0-3.375-3.375h-1.5a1.125 1.125 0 0 1-1.125-1.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H9.75" />
            </svg>
          </button>
        </div>
      </div>
      <p class="text-xs text-base-content/40 mt-2.5 font-mono">
        {tab_description(@tab)}
      </p>
    </div>
    """
  end
end
