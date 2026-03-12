defmodule TeamrcWeb.HomeLive do
  use TeamrcWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if Application.get_env(:teamrc, :redirect_landing, false) do
      {:ok, push_navigate(socket, to: ~p"/new")}
    else
      {:ok, assign(socket, page_title: nil)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%!-- Hero --%>
    <div class="pt-4 pb-2">
      <p class="text-xs font-mono text-primary/70 mb-3 tracking-wide">open source &middot; self-hostable</p>
      <h1 class="text-3xl sm:text-4xl font-bold tracking-tight leading-tight">
        One team definition.<br />Every AI platform.
      </h1>
      <p class="text-base text-base-content/60 mt-4 max-w-lg leading-relaxed">
        teamrc syncs your AI agent team across Claude Code, Cursor, Codex, Gemini, and
        OpenClaw. Define your agents and skills once, then let teamrc generate the
        platform-native files and keep them in sync across machines.
      </p>
      <div class="flex flex-wrap items-center gap-3 mt-6">
        <a
          href="/guide/get-started"
          class="trc-focus inline-flex items-center gap-2 rounded-md bg-primary px-4 py-2 text-sm font-semibold text-primary-content hover:bg-primary/90 transition-colors"
        >
          Get started
          <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor">
            <path fill-rule="evenodd" d="M10.293 3.293a1 1 0 011.414 0l6 6a1 1 0 010 1.414l-6 6a1 1 0 01-1.414-1.414L14.586 11H3a1 1 0 110-2h11.586l-4.293-4.293a1 1 0 010-1.414z" clip-rule="evenodd" />
          </svg>
        </a>
        <a
          href="https://github.com/teamrc-ai/teamrc"
          target="_blank"
          rel="noopener"
          class="trc-focus inline-flex items-center gap-2 rounded-md border border-base-300 px-4 py-2 text-sm font-medium text-base-content/70 hover:text-base-content/90 hover:border-base-content/20 transition-colors"
        >
          <svg class="h-4 w-4" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true">
            <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z" />
          </svg>
          GitHub
        </a>
      </div>
    </div>

    <%!-- Quick start --%>
    <div class="mt-14">
      <div class="terminal-block rounded-lg overflow-hidden">
        <div class="flex items-center gap-2 px-4 py-2 border-b border-white/5">
          <div class="flex gap-1.5">
            <div class="w-2.5 h-2.5 rounded-full bg-white/10"></div>
            <div class="w-2.5 h-2.5 rounded-full bg-white/10"></div>
            <div class="w-2.5 h-2.5 rounded-full bg-white/10"></div>
          </div>
          <span class="text-[10px] font-mono text-white/25 ml-2">terminal</span>
        </div>
        <div class="p-4 space-y-1.5">
          <div class="flex items-start gap-2">
            <span class="text-white/30 font-mono text-sm select-none">$</span>
            <code class="text-emerald-400 text-sm font-mono">npx @teamrc/cli init</code>
            <span class="text-white/20 text-sm font-mono ml-2"># create a team in this project</span>
          </div>
          <div class="flex items-start gap-2">
            <span class="text-white/30 font-mono text-sm select-none">$</span>
            <code class="text-emerald-400 text-sm font-mono">npx @teamrc/cli sync</code>
            <span class="text-white/20 text-sm font-mono ml-2"># pull latest &amp; regenerate files</span>
          </div>
        </div>
      </div>
    </div>

    <%!-- The problem / why --%>
    <div class="mt-16 space-y-3">
      <h2 class="text-lg font-bold tracking-tight">The problem</h2>
      <p class="text-sm text-base-content/70 leading-relaxed">
        AI coding assistants each expect their own config format. Claude Code uses
        <code class="font-mono bg-base-200 rounded px-1.5 py-0.5 text-xs">.claude/agents/*.md</code>,
        Cursor uses
        <code class="font-mono bg-base-200 rounded px-1.5 py-0.5 text-xs">.cursor/agents/*.md</code>,
        Codex uses TOML, Gemini uses YAML frontmatter, and OpenClaw has its own layout.
      </p>
      <p class="text-sm text-base-content/70 leading-relaxed">
        If you use more than one platform, work across machines, or run multiple agent
        VMs, you end up hand-maintaining duplicate configs that drift apart. Agents on
        different machines can't share what they've learned, and there's no good way to
        keep a team definition consistent across projects and devices.
      </p>
    </div>

    <%!-- How it works --%>
    <div class="mt-12 space-y-4">
      <h2 class="text-lg font-bold tracking-tight">How teamrc works</h2>
      <div class="space-y-3">
        <div class="rounded-lg border border-base-300 bg-base-100 p-4 flex items-start gap-3">
          <span class="text-primary/80 font-mono text-sm font-bold shrink-0 w-5">1.</span>
          <div>
            <p class="text-sm font-semibold">Define your team once</p>
            <p class="text-sm text-base-content/60 mt-0.5">
              Pick from 60+ pre-built agents and 50+ skills, or write your own.
              Your team lives in a single
              <code class="font-mono bg-base-200 rounded px-1.5 py-0.5 text-xs">.teamrc.yaml</code>
              and on the relay.
            </p>
          </div>
        </div>
        <div class="rounded-lg border border-base-300 bg-base-100 p-4 flex items-start gap-3">
          <span class="text-primary/80 font-mono text-sm font-bold shrink-0 w-5">2.</span>
          <div>
            <p class="text-sm font-semibold">Platform files are generated</p>
            <p class="text-sm text-base-content/60 mt-0.5">
              teamrc writes the native config for each platform you use. Claude Code gets
              markdown agents, Codex gets TOML, Gemini gets YAML frontmatter — all from the
              same source.
            </p>
          </div>
        </div>
        <div class="rounded-lg border border-base-300 bg-base-100 p-4 flex items-start gap-3">
          <span class="text-primary/80 font-mono text-sm font-bold shrink-0 w-5">3.</span>
          <div>
            <p class="text-sm font-semibold">Sync through the relay</p>
            <p class="text-sm text-base-content/60 mt-0.5">
              The relay is the coordination point. Push changes from one machine — CLI or web UI — and
              every connected machine, VM, or project pulls the latest with
              <code class="font-mono bg-base-200 rounded px-1.5 py-0.5 text-xs">teamrc sync</code>.
              No Git conflicts over config files.
            </p>
          </div>
        </div>
        <div class="rounded-lg border border-base-300 bg-base-100 p-4 flex items-start gap-3">
          <span class="text-primary/80 font-mono text-sm font-bold shrink-0 w-5">4.</span>
          <div>
            <p class="text-sm font-semibold">Knowledge travels with the team</p>
            <p class="text-sm text-base-content/60 mt-0.5">
              Agents write findings to a shared knowledge doc as they work — architecture
              decisions, debugging insights, gotchas. On sync, knowledge from all machines
              merges together automatically, so every agent on every VM benefits from what
              the others have learned.
            </p>
          </div>
        </div>
      </div>
    </div>

    <%!-- Platforms --%>
    <div class="mt-12 space-y-4">
      <h2 class="text-lg font-bold tracking-tight">Supported platforms</h2>
      <div class="grid grid-cols-2 sm:grid-cols-3 gap-2">
        <.platform_badge name="Claude Code" path=".claude/agents/" />
        <.platform_badge name="Cursor" path=".cursor/agents/" />
        <.platform_badge name="Codex" path=".codex/agents/" />
        <.platform_badge name="Gemini" path=".gemini/agents/" />
        <.platform_badge name="OpenClaw" path="~/.openclaw/agents/" />
      </div>
    </div>

    <%!-- Key features --%>
    <div class="mt-12 space-y-4">
      <h2 class="text-lg font-bold tracking-tight">What you get</h2>
      <div class="grid gap-2 sm:grid-cols-2">
        <div class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-1">
          <p class="text-sm font-semibold">Agent catalog</p>
          <p class="text-xs text-base-content/60">
            60+ pre-built agents across development, infrastructure, quality, research,
            and more. Use them as-is or as a starting point.
          </p>
        </div>
        <div class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-1">
          <p class="text-sm font-semibold">Reusable skills</p>
          <p class="text-xs text-base-content/60">
            50+ skills you assign to agents — testing conventions, code style, security
            rules. Define once, assign to many.
          </p>
        </div>
        <div class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-1">
          <p class="text-sm font-semibold">Shared knowledge</p>
          <p class="text-xs text-base-content/60">
            Agents record what they learn to a shared doc. Sync merges knowledge
            from every machine and VM, so the whole team builds on each other's findings.
          </p>
        </div>
        <div class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-1">
          <p class="text-sm font-semibold">Cross-machine sync</p>
          <p class="text-xs text-base-content/60">
            Use the same team across laptops, cloud VMs, CI, and multiple projects.
            The relay keeps everything consistent without touching Git.
          </p>
        </div>
        <div class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-1">
          <p class="text-sm font-semibold">Shareable &amp; cloneable</p>
          <p class="text-xs text-base-content/60">
            Make your team public and anyone can clone it with one command. Share
            your agent setup the way you'd share a dotfiles repo.
          </p>
        </div>
        <div class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-1 sm:col-span-2">
          <p class="text-sm font-semibold">Open source &amp; self-hostable</p>
          <p class="text-xs text-base-content/60">
            The CLI, relay server, and web UI are all open source. Run the hosted relay
            or deploy your own. No vendor lock-in, no black boxes.
          </p>
        </div>
      </div>
    </div>

    <%!-- Bottom CTA --%>
    <div class="mt-16 mb-4 rounded-lg border border-base-300 bg-base-200/30 p-6 text-center space-y-3">
      <p class="text-sm font-semibold">Ready to try it?</p>
      <div class="flex flex-wrap items-center justify-center gap-3">
        <a
          href="/guide/get-started"
          class="trc-focus inline-flex items-center gap-2 rounded-md bg-primary px-4 py-2 text-sm font-semibold text-primary-content hover:bg-primary/90 transition-colors"
        >
          Read the guide
        </a>
        <a
          href="/new"
          class="trc-focus inline-flex items-center gap-2 rounded-md border border-base-300 px-4 py-2 text-sm font-medium text-base-content/70 hover:text-base-content/90 hover:border-base-content/20 transition-colors"
        >
          Create a team in the browser
        </a>
      </div>
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
end
