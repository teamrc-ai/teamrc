defmodule TeamrcWeb.GuideLive do
  use TeamrcWeb, :live_view

  @pages [
    {:get_started, "Get Started", "/guide/get-started"},
    {:overview, "Overview", "/guide"},
    {:concepts, "Core Concepts", "/guide/concepts"},
    {:cli, "CLI Reference", "/guide/cli"},
    {:platforms, "Platforms", "/guide/platforms"},
    {:sync, "Syncing", "/guide/sync"},
    {:web_ui, "Web UI Tour", "/guide/web-ui"},
    {:config, "Configuration", "/guide/config"},
    {:faq, "FAQ", "/guide/faq"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, pages: @pages)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    page = socket.assigns.live_action
    title = Enum.find_value(@pages, "Guide", fn {id, t, _} -> if id == page, do: t end)
    {:noreply, assign(socket, page_title: title, current_page: page)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <%!-- Page nav --%>
      <nav class="flex gap-1 overflow-x-auto pb-3 border-b border-base-300 -mx-4 px-4 sm:mx-0 sm:px-0 scrollbar-hide">
        <a
          :for={{id, label, path} <- @pages}
          href={path}
          aria-current={if(@current_page == id, do: "page")}
          class={[
            "trc-focus rounded-md px-2.5 py-1.5 text-xs font-medium transition-colors whitespace-nowrap",
            if(@current_page == id,
              do: "bg-primary/10 text-primary",
              else: "text-base-content/60 hover:text-base-content/70 hover:bg-base-200/60"
            )
          ]}
        >
          {label}
        </a>
      </nav>

      <%!-- Page content --%>
      <div class="space-y-12">
        <%= case @current_page do %>
          <% :get_started -> %>
            <.page_get_started />
          <% :overview -> %>
            <.page_overview />
          <% :concepts -> %>
            <.page_concepts />
          <% :cli -> %>
            <.page_cli />
          <% :platforms -> %>
            <.page_platforms />
          <% :sync -> %>
            <.page_sync />
          <% :web_ui -> %>
            <.page_web_ui />
          <% :config -> %>
            <.page_config />
          <% :faq -> %>
            <.page_faq />
        <% end %>
      </div>
    </div>
    """
  end

  # ===========================================================================
  # Shared components
  # ===========================================================================

  defp terminal_block(assigns) do
    ~H"""
    <div class="terminal-block rounded-lg overflow-hidden">
      <div class="flex items-center gap-2 px-4 py-2 border-b border-white/5">
        <div class="flex gap-1.5">
          <div class="w-2.5 h-2.5 rounded-full bg-white/10"></div>
          <div class="w-2.5 h-2.5 rounded-full bg-white/10"></div>
          <div class="w-2.5 h-2.5 rounded-full bg-white/10"></div>
        </div>
        <span class="text-[10px] font-mono text-white/25 ml-2">{@title}</span>
      </div>
      <div class="p-4">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp callout(assigns) do
    ~H"""
    <div class="rounded-lg border border-primary/20 bg-primary/5 p-4 space-y-2">
      <p class="text-xs font-semibold text-primary/80">{@title}</p>
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp cmd_line(assigns) do
    ~H"""
    <div class="flex items-start gap-2">
      <span class="text-white/30 font-mono text-sm select-none">$</span>
      <code class="text-emerald-400 text-sm font-mono">{@cmd}</code>
      <span :if={assigns[:comment]} class="text-white/20 text-sm font-mono ml-2">{@comment}</span>
    </div>
    """
  end

  defp code_inline(assigns) do
    ~H"""
    <code class="font-mono bg-base-200 rounded px-1.5 py-0.5 text-xs">
      {render_slot(@inner_block)}
    </code>
    """
  end

  defp section_heading(assigns) do
    ~H"""
    <h2 id={@id} class="text-lg font-bold tracking-tight scroll-mt-20">{@title}</h2>
    """
  end

  defp sub_heading(assigns) do
    ~H"""
    <h3 id={assigns[:id]} class="text-sm font-bold tracking-tight scroll-mt-20">{@title}</h3>
    """
  end

  attr :items, :list, required: true
  attr :title, :string, default: "On this page"

  defp page_toc(assigns) do
    ~H"""
    <div class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-3">
      <p class="text-[10px] font-medium text-base-content/60 uppercase tracking-wider">{@title}</p>
      <div class="grid gap-2 sm:grid-cols-2">
        <a
          :for={{href, label} <- @items}
          href={href}
          class="text-sm text-base-content/70 hover:text-primary transition-colors"
        >
          {label}
        </a>
      </div>
    </div>
    """
  end

  attr :href, :string, required: true
  attr :title, :string, required: true
  attr :desc, :string, required: true

  defp guide_card(assigns) do
    ~H"""
    <a
      href={@href}
      class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-1 hover:border-primary/30 transition-colors group"
    >
      <p class="text-sm font-semibold group-hover:text-primary transition-colors">{@title}</p>
      <p class="text-xs text-base-content/60">{@desc}</p>
    </a>
    """
  end

  # ===========================================================================
  # Page: Get Started
  # ===========================================================================

  defp page_get_started(assigns) do
    ~H"""
    <div>
      <p class="text-sm font-medium text-primary/80 mb-2">Start here</p>
      <h1 class="text-2xl font-bold tracking-tight mb-1">Get Started in 2 Minutes</h1>
      <p class="text-sm text-base-content/60">
        This is the fastest path from an empty repo to a working, synced team. If you want it running
        before you care about the details, do this.
      </p>
    </div>

    <.callout title="Shortest possible version">
      <p class="text-sm text-base-content/70">
        Run <.code_inline>npx @teamrc/cli init</.code_inline>. If the generated team looks good, you are already done.
        The rest of this page is for editing, syncing, or sharing it.
      </p>
    </.callout>

    <section class="space-y-3">
      <.section_heading id="create" title="1. Create a team" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        Start in your project directory:
      </p>
      <.terminal_block title="terminal">
        <.cmd_line cmd="npx @teamrc/cli init" />
      </.terminal_block>
      <p class="text-sm text-base-content/70 leading-relaxed">
        This creates the team on the relay, generates your machine keypair, writes <.code_inline>.teamrc.yaml</.code_inline>, and applies the generated platform files locally.
      </p>
    </section>

    <section class="space-y-3">
      <.section_heading id="edit" title="2. Open the web UI if you want to tweak the team" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        Open the current team directly from the CLI. No account is required.
      </p>
      <.terminal_block title="terminal">
        <.cmd_line cmd="npx @teamrc/cli dashboard" />
      </.terminal_block>
      <p class="text-sm text-base-content/70 leading-relaxed">
        This opens your team in the browser. It also prints the URL as a fallback.
        From there you can add members, assign skills, or edit instructions.
      </p>
    </section>

    <section class="space-y-3">
      <.section_heading id="sync" title="3. Pull the latest version back to your machine" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        After editing in the browser, sync locally:
      </p>
      <.terminal_block title="terminal">
        <.cmd_line cmd="npx @teamrc/cli sync" />
      </.terminal_block>
      <p class="text-sm text-base-content/70 leading-relaxed">
        That fetches the latest team definition from the relay and regenerates platform-native files.
      </p>
    </section>

    <section class="space-y-3">
      <.section_heading id="share" title="4. Connect another machine or project" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        On the first machine, create an invite:
      </p>
      <.terminal_block title="terminal">
        <.cmd_line cmd="npx @teamrc/cli invite" />
      </.terminal_block>
      <p class="text-sm text-base-content/70 leading-relaxed">
        Then on the second machine, or in another repo that should use the same team:
      </p>
      <.terminal_block title="terminal">
        <.cmd_line cmd="npx @teamrc/cli join trc_inv_..." />
      </.terminal_block>
      <p class="text-sm text-base-content/70 leading-relaxed">
        That machine becomes part of the same sync loop and will receive future updates.
      </p>
    </section>

    <section class="space-y-3">
      <.section_heading id="next" title="Where to go next" />
      <div class="grid gap-3 sm:grid-cols-2">
        <.guide_card
          href="/guide/concepts"
          title="Learn the model"
          desc="Understand members, skills, instructions, and shared knowledge."
        />
        <.guide_card
          href="/guide/cli"
          title="See every command"
          desc="Use the CLI reference when you want details, flags, and workflows."
        />
        <.guide_card
          href="/guide/web-ui"
          title="Take the UI tour"
          desc="See what each screen does before you start editing in the browser."
        />
        <.guide_card
          href="/guide/sync"
          title="Understand syncing"
          desc="Read this if you want to know how the relay, invites, and daemon behave."
        />
      </div>
    </section>
    """
  end

  # ===========================================================================
  # Page: Overview
  # ===========================================================================

  defp page_overview(assigns) do
    ~H"""
    <div>
      <p class="text-sm font-medium text-primary/80 mb-2">Documentation</p>
      <h1 class="text-2xl font-bold tracking-tight mb-1">teamrc Guide</h1>
      <p class="text-sm text-base-content/60">
        teamrc lets you define one agent team and apply it across Claude Code, Cursor, Codex, Gemini,
        and OpenClaw. Use this page to choose the shortest path to what you need.
      </p>
    </div>

    <section class="space-y-3">
      <.section_heading id="start" title="Start here" />
      <div class="grid gap-3 sm:grid-cols-2">
        <.guide_card
          href="/guide/get-started"
          title="Get Started in 2 Minutes"
          desc="The shortest path from an empty repo to a working, synced team."
        />
        <.guide_card
          href="/guide/concepts"
          title="Core Concepts"
          desc="Read this if you want the mental model behind members, skills, and knowledge."
        />
        <.guide_card
          href="/guide/cli"
          title="CLI Reference"
          desc="Use this when you want exact commands, flags, and common workflows."
        />
        <.guide_card
          href="/guide/web-ui"
          title="Web UI Tour"
          desc="Take the visual tour if you plan to manage teams from the browser."
        />
      </div>
    </section>

    <section class="space-y-3">
      <.section_heading id="mental-model" title="The mental model" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        There are three moving parts:
      </p>
      <div class="space-y-3">
        <div class="rounded-lg border border-base-300 bg-base-100 p-4 flex items-start gap-3">
          <span class="text-primary/80 font-mono text-sm font-bold shrink-0 w-5">1.</span>
          <div>
            <p class="text-sm font-semibold">Team definition</p>
            <p class="text-sm text-base-content/70 mt-0.5">
              The source of truth. One definition of your agents, rules, and instructions, stored on the relay
              and optionally mirrored locally as <.code_inline>.teamrc.yaml</.code_inline>.
            </p>
          </div>
        </div>
        <div class="rounded-lg border border-base-300 bg-base-100 p-4 flex items-start gap-3">
          <span class="text-primary/80 font-mono text-sm font-bold shrink-0 w-5">2.</span>
          <div>
            <p class="text-sm font-semibold">Platform config files</p>
            <p class="text-sm text-base-content/70 mt-0.5">
              The files each platform actually reads. teamrc generates them from the team definition,
              so you do not need to hand-edit each platform separately.
            </p>
          </div>
        </div>
        <div class="rounded-lg border border-base-300 bg-base-100 p-4 flex items-start gap-3">
          <span class="text-primary/80 font-mono text-sm font-bold shrink-0 w-5">3.</span>
          <div>
            <p class="text-sm font-semibold">The relay</p>
            <p class="text-sm text-base-content/70 mt-0.5">
              The shared coordination point. Changes go up through the CLI or web UI, and machines pull
              them back down with <.code_inline>sync</.code_inline>, <.code_inline>pull</.code_inline>,
              or the background daemon.
            </p>
          </div>
        </div>
      </div>
    </section>

    <section class="space-y-3">
      <.section_heading id="why" title="Why teamrc exists" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        AI agent platforms all expect different file layouts, config formats, and skill models.
        teamrc gives you one shared team definition, then generates the platform-native files and keeps them
        synced across machines without forcing those files into Git.
      </p>
    </section>

    <section class="space-y-3">
      <.section_heading id="learn-more" title="Explore the guide" />
      <div class="grid gap-3 sm:grid-cols-2">
        <.guide_card
          href="/guide/platforms"
          title="Platforms"
          desc="How teamrc writes config for Claude Code, Cursor, Codex, Gemini, and OpenClaw."
        />
        <.guide_card
          href="/guide/sync"
          title="Syncing"
          desc="The relay, invites, multi-project teams, daemon mode, and auth."
        />
        <.guide_card
          href="/guide/config"
          title="Configuration"
          desc="The .teamrc.yaml schema, scope rules, machine config, and validation limits."
        />
        <.guide_card
          href="/guide/faq"
          title="FAQ"
          desc="Short answers about Git, accounts, privacy, syncing, and recovery."
        />
      </div>
    </section>
    """
  end

  # ===========================================================================
  # Page: Core Concepts
  # ===========================================================================

  defp page_concepts(assigns) do
    ~H"""
    <div>
      <h1 class="text-2xl font-bold tracking-tight mb-1">Core Concepts</h1>
      <p class="text-sm text-base-content/60">
        teamrc has four building blocks. Each is simple on its own, but understanding how they
        connect helps you get the most out of them.
      </p>
    </div>

    <%!-- Members --%>
    <section id="members" class="scroll-mt-20 space-y-3">
      <.section_heading id="members" title="Members" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        A member is an AI agent on your team. Each one has three things:
      </p>
      <ul class="text-sm text-base-content/70 space-y-1.5 list-disc list-inside">
        <li>
          A <span class="font-semibold">name</span>, a short identifier like
          <.code_inline>frontend</.code_inline>
          or <.code_inline>reviewer</.code_inline>. Used as a filename, so keep it lowercase and hyphenated.
        </li>
        <li>
          A <span class="font-semibold">role</span>, a one-line description of what the agent does. Shown in platform UIs as the agent's subtitle.
        </li>
        <li>
          Optional <span class="font-semibold">instructions</span>, a detailed markdown block defining the agent's identity and behavior (see <a
            href="#instructions"
            class="text-primary/80 hover:text-primary"
          >below</a>).
        </li>
      </ul>

      <.sub_heading id="member-files" title="What files get generated" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        When you sync, teamrc creates a configuration file for each member on each platform.
        All generated files are prefixed with
        <.code_inline>trc-</.code_inline>
        so they're easy to identify
        and won't collide with files you create manually.
      </p>
      <div class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-2">
        <p class="text-[10px] font-medium text-base-content/60 uppercase tracking-wider">
          A member named "frontend" generates:
        </p>
        <div class="space-y-1.5 text-xs font-mono text-base-content/70">
          <div class="flex items-center gap-3">
            <span class="text-base-content/50 w-20 text-right shrink-0">Claude Code</span>
            <span>.claude/agents/trc-frontend.md</span>
          </div>
          <div class="flex items-center gap-3">
            <span class="text-base-content/50 w-20 text-right shrink-0">Cursor</span>
            <span>.cursor/agents/trc-frontend.md</span>
          </div>
          <div class="flex items-center gap-3">
            <span class="text-base-content/50 w-20 text-right shrink-0">Codex</span>
            <span>.codex/agents/trc-frontend.toml</span>
          </div>
          <div class="flex items-center gap-3">
            <span class="text-base-content/50 w-20 text-right shrink-0">Gemini</span>
            <span>.gemini/agents/trc-frontend.md</span>
          </div>
          <div class="flex items-center gap-3">
            <span class="text-base-content/50 w-20 text-right shrink-0">OpenClaw</span>
            <span>.agents/agents/trc-frontend.md</span>
          </div>
        </div>
      </div>

      <.sub_heading id="member-catalog" title="Catalog vs custom members" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        You don't have to start from scratch. There's a catalog of 60+ pre-built agents
        organized by category: development, infrastructure, quality, research, and more.
        Pick one and it comes with instructions and recommended skills already filled in.
        Tweak it or use it as-is.
      </p>
      <p class="text-sm text-base-content/70 leading-relaxed">
        Or create a fully custom member with just a name and role. Up to you.
      </p>
    </section>

    <%!-- Skills --%>
    <section id="skills" class="scroll-mt-20 space-y-3">
      <.section_heading id="skills" title="Skills" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        Skills are reusable instruction blocks that you write once and assign to the agents that need them.
        Things like "always write tests," "follow our code style," or "review for security vulnerabilities."
        Instead of copying the same rules into every agent's instructions, you define them once at the team level.
      </p>

      <.sub_heading id="skill-assignment" title="How assignment works" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        Skills live on the <span class="font-semibold">team</span>, not on individual agents.
        You explicitly assign each skill to the agents that should use it.
        So your frontend agent might get
        <.code_inline>code-style</.code_inline>
        and <.code_inline>accessibility</.code_inline>,
        while your reviewer gets
        <.code_inline>code-review</.code_inline>
        and <.code_inline>testing</.code_inline>.
        Different agents, different skills.
      </p>

      <.sub_heading id="always-apply" title="Always-apply skills" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        Some rules should apply to everyone. Set
        <.code_inline>alwaysApply: true</.code_inline>
        and the skill
        automatically applies to <span class="font-semibold">every agent</span>
        on the team. You don't need
        to assign it individually.
        This is great for things like commit message formats, security policies, or project-wide style guides.
      </p>

      <.sub_heading id="skill-globs" title="File-targeted skills" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        Skills can also target specific files. Add
        <.code_inline>globs</.code_inline>
        like
        <.code_inline>*.tsx</.code_inline>
        or
        <.code_inline>src/api/**</.code_inline>
        and the skill only activates when the agent
        is working on matching files. Useful for language-specific or directory-specific rules.
      </p>

      <.sub_heading id="skill-properties" title="Skill properties" />
      <div class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-2">
        <div class="space-y-2 text-sm">
          <div class="flex items-start gap-3">
            <.code_inline>id</.code_inline>
            <span class="text-base-content/70">
              Required. A unique identifier like <.code_inline>code-review</.code_inline>. Used as a filename.
            </span>
          </div>
          <div class="flex items-start gap-3">
            <.code_inline>title</.code_inline>
            <span class="text-base-content/70">Optional. A human-readable label.</span>
          </div>
          <div class="flex items-start gap-3">
            <.code_inline>body</.code_inline>
            <span class="text-base-content/70">
              Required. The instructions themselves, written in markdown.
            </span>
          </div>
          <div class="flex items-start gap-3">
            <.code_inline>alwaysApply</.code_inline>
            <span class="text-base-content/70">
              When true, applies to all agents without explicit assignment.
            </span>
          </div>
          <div class="flex items-start gap-3">
            <.code_inline>globs</.code_inline>
            <span class="text-base-content/70">
              File patterns. The skill activates only for matching files (on supported platforms).
            </span>
          </div>
        </div>
      </div>

      <.sub_heading id="skill-catalog" title="Pre-built skills" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        Like agents, there's a catalog of ~50 pre-built skills you can pick from:
        code quality, testing, documentation, security, and more. Use them as-is, tweak them,
        or write your own.
      </p>
    </section>

    <%!-- Instructions --%>
    <section id="instructions" class="scroll-mt-20 space-y-3">
      <.section_heading id="instructions" title="Instructions" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        Each agent can have <span class="font-semibold">instructions</span>:
        a free-form markdown block that tells the agent who it is, how it should behave, and what
        it should focus on. Think of it as the agent's personality and expertise description.
      </p>

      <.callout title="Instructions vs skills">
        <p class="text-sm text-base-content/70 leading-relaxed">
          <span class="font-semibold">Instructions</span>
          are unique to one agent. They define who it is. <span class="font-semibold">Skills</span>
          are shared across agents. They define what rules to follow.
          A frontend agent's instructions might say "you specialize in React and accessibility."
          A skill assigned to that agent might say "always write unit tests for new components."
        </p>
      </.callout>

      <p class="text-sm text-base-content/70 leading-relaxed">
        When you pick a catalog agent, instructions are pre-filled with sections covering:
      </p>
      <ul class="text-sm text-base-content/70 space-y-1.5 list-disc list-inside">
        <li><span class="font-semibold">Identity</span>: who the agent is and its core purpose</li>
        <li><span class="font-semibold">Expertise</span>: what it specializes in</li>
        <li><span class="font-semibold">Principles</span>: how it approaches work</li>
        <li><span class="font-semibold">Communication</span>: how it interacts with you</li>
      </ul>
      <p class="text-sm text-base-content/70 leading-relaxed">
        You can edit these freely after adding the agent, or write your own from scratch.
      </p>
    </section>

    <%!-- Knowledge --%>
    <section id="knowledge" class="scroll-mt-20 space-y-3">
      <.section_heading id="knowledge" title="Knowledge" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        Knowledge is a shared document that every agent on the team can read and write to.
        It's where agents record things they learn while working:
        "the auth service requires header X," "don't touch the legacy module, it's being replaced,"
        "the CI takes 8 minutes, cache the build."
      </p>
      <p class="text-sm text-base-content/70 leading-relaxed">
        Unlike instructions or skills, you don't write knowledge upfront. It builds up naturally
        as agents work on your codebase. When you sync, knowledge from all machines gets merged
        together, so every agent benefits from what the others have learned.
      </p>

      <.sub_heading id="knowledge-merge" title="How knowledge merges" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        Knowledge uses <span class="font-semibold">append-only deduplication</span>.
        When syncing, new lines from the relay are appended to your local knowledge file,
        skipping anything already present. This means knowledge can only grow.
        It never loses information during sync.
      </p>
      <p class="text-sm text-base-content/70 text-xs">
        When syncing through the relay, knowledge is capped at 100,000 bytes to prevent runaway growth.
      </p>
    </section>

    <%!-- How they fit together --%>
    <section id="together" class="scroll-mt-20 space-y-3">
      <.section_heading id="together" title="How they fit together" />
      <div class="rounded-lg border border-base-300 bg-base-100 p-5">
        <div class="space-y-4 text-sm text-base-content/70">
          <div class="flex items-start gap-3">
            <span class="text-primary/80 font-mono text-xs shrink-0 mt-0.5 w-24 text-right">
              Team
            </span>
            <span>Has members and skills. One team definition, many machines.</span>
          </div>
          <div class="flex items-start gap-3">
            <span class="text-primary/80 font-mono text-xs shrink-0 mt-0.5 w-24 text-right">
              Member
            </span>
            <span>An agent with a name, role, and instructions. Gets assigned skills.</span>
          </div>
          <div class="flex items-start gap-3">
            <span class="text-primary/80 font-mono text-xs shrink-0 mt-0.5 w-24 text-right">
              Skill
            </span>
            <span>
              A reusable rule. Defined on the team, assigned to members (or applied to all).
            </span>
          </div>
          <div class="flex items-start gap-3">
            <span class="text-primary/80 font-mono text-xs shrink-0 mt-0.5 w-24 text-right">
              Instructions
            </span>
            <span>An agent's identity. Unique to one member, not shared.</span>
          </div>
          <div class="flex items-start gap-3">
            <span class="text-primary/80 font-mono text-xs shrink-0 mt-0.5 w-24 text-right">
              Knowledge
            </span>
            <span>Shared scratchpad. Every agent reads it, any agent can append to it.</span>
          </div>
        </div>
      </div>
    </section>
    """
  end

  # ===========================================================================
  # Page: CLI Reference
  # ===========================================================================

  defp page_cli(assigns) do
    ~H"""
    <div>
      <h1 class="text-2xl font-bold tracking-tight mb-1">CLI Reference</h1>
      <p class="text-sm text-base-content/60">
        This is a reference page, not a quickstart. Use it when you need exact commands,
        flags, or common workflows.
      </p>
    </div>

    <.page_toc items={[
      {"#install", "Installation"},
      {"#global-flags", "Global flags"},
      {"#getting-started", "Core setup commands"},
      {"#sync-commands", "Sync commands"},
      {"#team-management", "Team management"},
      {"#account-commands", "Account & machine management"},
      {"#background", "Background sync"},
      {"#workflows", "Common workflows"}
    ]} />

    <section class="space-y-3">
      <.section_heading id="install" title="Installation" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        No install needed. Run via <.code_inline>npx</.code_inline>:
      </p>
      <.terminal_block title="terminal">
        <.cmd_line cmd="npx @teamrc/cli <command>" />
      </.terminal_block>
      <p class="text-sm text-base-content/70 leading-relaxed">
        Or install globally:
      </p>
      <.terminal_block title="terminal">
        <.cmd_line cmd="npm install -g teamrc" />
      </.terminal_block>
    </section>

    <section class="space-y-3">
      <.section_heading id="global-flags" title="Global flags" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        These flags work with any command:
      </p>
      <div class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-2 text-sm">
        <div class="flex items-start gap-3">
          <.code_inline>-j, --json</.code_inline>
          <span class="text-base-content/70">Output as JSON (for scripting)</span>
        </div>
        <div class="flex items-start gap-3">
          <.code_inline>-y, --yes</.code_inline>
          <span class="text-base-content/70">Skip confirmation prompts</span>
        </div>
        <div class="flex items-start gap-3">
          <.code_inline>--no-color</.code_inline>
          <span class="text-base-content/70">Disable colored output</span>
        </div>
        <div class="flex items-start gap-3">
          <.code_inline>-v, --verbose</.code_inline>
          <span class="text-base-content/70">Show detailed output</span>
        </div>
      </div>
    </section>

    <%!-- Getting Started --%>
    <section class="space-y-4">
      <.section_heading id="getting-started" title="Core setup commands" />

      <.cli_command
        name="init"
        desc="Create a new team"
        usage="teamrc init"
        flags={[
          {"--relay <url>", "Relay server URL"},
          {"--platform <platform>", "Target platform(s), comma-separated"},
          {"--global", "Create as global team (applies to all projects)"},
          {"--name <name>", "Team name"},
          {"--team <id>", "Start from a catalog template (e.g. fullstack, backend)"}
        ]}
        details="Generates an ed25519 keypair (stored in ~/.teamrc/key), creates a team on the relay, writes .teamrc.yaml to your project, and applies config to detected platforms. The interactive wizard lets you pick a catalog template or build a custom team."
      />

      <.cli_command
        name="join"
        desc="Join an existing team"
        usage="teamrc join <invite-code>"
        flags={[
          {"--relay <url>", "Relay server URL"},
          {"--platform <platform>", "Target platform(s)"},
          {"--global", "Join as global team"}
        ]}
        details="Connects this machine to an existing team using an invite code. Fetches the team definition from the relay, writes .teamrc.yaml, and applies config to all detected platforms. Each machine gets its own keypair. No shared credentials."
      />

      <.cli_command
        name="clone"
        desc="Copy a team locally without joining the relay"
        usage="teamrc clone <invite-code>"
        flags={[
          {"--relay <url>", "Relay server URL"},
          {"--platform <platform>", "Target platform(s)"},
          {"--name <name>", "Override team name"},
          {"--global", "Apply as global team"}
        ]}
        details="Like join, but doesn't register this machine with the relay. You get a local copy of the team that won't receive future updates. Useful for one-off use or forking a team."
      />
    </section>

    <%!-- Sync Commands --%>
    <section class="space-y-4">
      <.section_heading id="sync-commands" title="Sync commands" />

      <.cli_command
        name="sync"
        desc="Two-way sync with the relay"
        usage="teamrc sync"
        flags={[
          {"--platform <platform>", "Target platform(s)"},
          {"--scope <scope>", "project or global"},
          {"--global", "Shorthand for --scope global"}
        ]}
        details="The primary command. Pushes local changes (including knowledge updates) to the relay, pulls the latest team definition, and regenerates all platform config files. Run this after making changes in the web UI, or after another machine has pushed updates."
      />

      <.cli_command
        name="pull"
        desc="Pull from relay and apply locally"
        usage="teamrc pull"
        flags={[
          {"--platform <platform>", "Target platform(s)"},
          {"--scope <scope>", "project or global"},
          {"--global", "Shorthand for --scope global"}
        ]}
        details="One-way: fetches the latest team definition from the relay and writes it to local platform config files. Does not push any local changes. Use when you only want to receive updates."
      />

      <.cli_command
        name="push"
        desc="Push local state to the relay"
        usage="teamrc push"
        flags={[]}
        details="One-way: reads your .teamrc.yaml and knowledge file, and sends them to the relay. Does not pull or apply anything. Use after manually editing .teamrc.yaml."
      />

      <.cli_command
        name="apply"
        desc="Regenerate platform config files from .teamrc.yaml"
        usage="teamrc apply"
        flags={[
          {"--platform <platform>", "Target platform(s)"},
          {"--scope <scope>", "project or global"},
          {"--global", "Shorthand for --scope global"}
        ]}
        details="Offline operation. Does not talk to the relay. Reads .teamrc.yaml and writes platform config files. Useful after editing the YAML directly, or to regenerate files for a newly installed platform."
      />

      <.cli_command
        name="export"
        desc="Export team from relay to .teamrc.yaml"
        usage="teamrc export"
        flags={[]}
        details="Fetches the team definition from the relay and writes it to .teamrc.yaml without applying to any platforms. Use when you want to inspect or backup the remote state."
      />

      <.cli_command
        name="diff"
        desc="Compare local state with relay"
        usage="teamrc diff"
        flags={[
          {"--json", "Output as JSON"}
        ]}
        details="Shows what's different between your local .teamrc.yaml and the relay. Lists added, removed, and modified members. Helpful before pushing changes or debugging sync issues."
      />
    </section>

    <%!-- Team Management --%>
    <section class="space-y-4">
      <.section_heading id="team-management" title="Team management" />

      <.cli_command
        name="dashboard"
        desc="Open the current team in your browser"
        usage="teamrc dashboard"
        flags={[
          {"--ttl <hours>", "Dashboard link expiry in hours (default: 24)"}
        ]}
        details="Creates a short-lived URL for the current team and opens it in your browser. Use this to manage the team in the web UI. Use invite instead when you want to share access with another machine or teammate."
      />

      <.cli_command
        name="invite"
        desc="Generate an invite code"
        usage="teamrc invite"
        flags={[
          {"--ttl <hours>", "Expiry in hours (default: 24)"}
        ]}
        details="Creates a time-limited invite code (trc_inv_...) that can be used with join. Share it with collaborators, use it on a VM, or connect another project to the same team. For opening your own browser session, use dashboard instead."
      />

      <.cli_command
        name="status"
        desc="Show current configuration"
        usage="teamrc status"
        flags={[
          {"--json", "Output as JSON"}
        ]}
        details="Displays your token, relay server, current team info (from .teamrc.yaml), and platform bindings. Quick way to see what's configured."
      />

      <.cli_command
        name="import"
        desc="Import existing platform config"
        usage="teamrc import <platform>"
        flags={[]}
        details="Reads existing agent configuration from a platform's native files and converts them into a .teamrc.yaml. Supported platforms: claude-code, cursor, codex, gemini, openclaw. Useful when migrating agents you've already set up manually."
      />
    </section>

    <%!-- Account Commands --%>
    <section class="space-y-4">
      <.section_heading id="account-commands" title="Account & machine management" />

      <.cli_command
        name="login"
        desc="Link this machine to an account"
        usage="teamrc login"
        flags={[
          {"--name <name>", "Machine name (defaults to hostname)"}
        ]}
        details="Optional. Opens a browser-based device authorization flow (similar to gh auth login). Once confirmed, this machine is linked to your account for recovery and management via the web dashboard. You can use teamrc without logging in. It's only needed for the dashboard."
      />

      <.cli_command
        name="whoami"
        desc="Show identity and config"
        usage="teamrc whoami"
        flags={[
          {"--json", "Output as JSON"}
        ]}
        details="Displays your token, linked account email (if any), machine name, relay server, and current team. Like status but focused on identity."
      />

      <.cli_command
        name="doctor"
        desc="Diagnose setup issues"
        usage="teamrc doctor"
        flags={[]}
        details="Validates your entire setup: checks the keypair exists, config is valid, relay is reachable, and platforms are detected. Run this when something isn't working."
      />

      <.cli_command
        name="delete"
        desc="Remove teamrc from this machine"
        usage="teamrc delete"
        flags={[
          {"-y, --yes", "Skip confirmation"}
        ]}
        details="Removes all teamrc-generated files from all platforms, deletes .teamrc.yaml, and cleans up config. This is destructive and fully uninstalls teamrc from the current project."
      />
    </section>

    <%!-- Background --%>
    <section class="space-y-4">
      <.section_heading id="background" title="Background sync" />

      <.cli_command
        name="daemon"
        desc="Start background sync process"
        usage="teamrc daemon"
        flags={[
          {"--poll-interval <ms>", "Poll interval in milliseconds (default: 120000, min: 5000)"}
        ]}
        details="Runs a background process that watches your .teamrc.yaml for local changes and periodically polls the relay for remote updates. When changes are detected, it automatically applies them to all platforms. Useful in long dev sessions, so you never have to manually sync."
      />
    </section>

    <%!-- Common Workflows --%>
    <section class="space-y-3">
      <.section_heading id="workflows" title="Common workflows" />

      <.sub_heading title="Set up a new project with a template" />
      <.terminal_block title="terminal">
        <div class="space-y-1.5">
          <.cmd_line cmd="npx @teamrc/cli init --team fullstack" />
          <.cmd_line cmd="npx @teamrc/cli dashboard" comment="# opens the team in your browser" />
        </div>
      </.terminal_block>
      <p class="text-sm text-base-content/70 leading-relaxed">
        That takes you straight to the team dashboard in the browser. If you need to connect another machine,
        create a separate invite with <.code_inline>teamrc invite</.code_inline>.
      </p>

      <.sub_heading title="Open the web UI from the CLI" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        <span class="font-semibold">Without an account:</span>
        run <.code_inline>teamrc dashboard</.code_inline>. It creates a short-lived browser link and opens the team directly.
      </p>
      <p class="text-sm text-base-content/70 leading-relaxed">
        <span class="font-semibold">With an account:</span>
        run <.code_inline>teamrc login</.code_inline>,
        then sign in at the relay URL. Your dashboard at
        <.code_inline>/dashboard</.code_inline>
        shows all your teams and machines.
      </p>

      <.sub_heading title="Connect another machine, VM, or project" />
      <.terminal_block title="terminal">
        <div class="space-y-1.5">
          <.cmd_line cmd="npx @teamrc/cli invite" comment="# run on the first machine" />
          <.cmd_line cmd="npx @teamrc/cli join trc_inv_abc123..." comment="# run on the second machine" />
        </div>
      </.terminal_block>

      <.sub_heading title="Edit in the web UI, then apply locally" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        Make your changes in the browser, then pull them down:
      </p>
      <.terminal_block title="terminal">
        <.cmd_line cmd="npx @teamrc/cli pull" comment="# fetch latest from relay" />
      </.terminal_block>

      <.sub_heading title="Edit .teamrc.yaml directly, then push" />
      <.terminal_block title="terminal">
        <div class="space-y-1.5">
          <.cmd_line cmd="vim .teamrc.yaml" comment="# make your changes" />
          <.cmd_line cmd="npx @teamrc/cli push" comment="# send to relay" />
          <.cmd_line cmd="npx @teamrc/cli apply" comment="# regenerate local files" />
        </div>
      </.terminal_block>

      <.sub_heading title="Check what's different before syncing" />
      <.terminal_block title="terminal">
        <div class="space-y-1.5">
          <.cmd_line cmd="npx @teamrc/cli diff" comment="# compare local vs relay" />
          <.cmd_line cmd="npx @teamrc/cli sync" comment="# if it looks good" />
        </div>
      </.terminal_block>
    </section>
    """
  end

  attr :name, :string, required: true
  attr :desc, :string, required: true
  attr :usage, :string, required: true
  attr :flags, :list, default: []
  attr :details, :string, required: true

  defp cli_command(assigns) do
    ~H"""
    <div class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-2.5" id={@name}>
      <div class="flex items-baseline gap-2">
        <code class="font-mono text-sm font-bold text-primary/80">{@name}</code>
        <span class="text-xs text-base-content/60">{@desc}</span>
      </div>
      <div class="bg-base-200/50 rounded px-3 py-1.5">
        <code class="font-mono text-xs text-base-content/70">{@usage}</code>
      </div>
      <p class="text-sm text-base-content/70 leading-relaxed">{@details}</p>
      <div :if={@flags != []} class="space-y-1">
        <p class="text-[10px] font-medium text-base-content/50 uppercase tracking-wider">Options</p>
        <div :for={{flag, desc} <- @flags} class="flex items-start gap-2 text-xs">
          <code class="font-mono text-base-content/60 shrink-0">{flag}</code>
          <span class="text-base-content/60">{desc}</span>
        </div>
      </div>
    </div>
    """
  end

  # ===========================================================================
  # Page: Platforms
  # ===========================================================================

  defp page_platforms(assigns) do
    ~H"""
    <div>
      <h1 class="text-2xl font-bold tracking-tight mb-1">Platforms</h1>
      <p class="text-sm text-base-content/60">
        Every platform has its own way of doing things. Here's how teamrc handles each one.
      </p>
    </div>

    <.page_toc items={[
      {"#overview", "Overview"},
      {"#claude-code", "Claude Code"},
      {"#cursor", "Cursor"},
      {"#codex", "Codex"},
      {"#gemini", "Gemini"},
      {"#openclaw", "OpenClaw"},
      {"#coming-soon", "Coming soon"}
    ]} />

    <section class="space-y-3">
      <.section_heading id="overview" title="Overview" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        teamrc auto-detects which platforms you have installed and generates the right files for all of them.
        You don't need to think about the differences. That's the whole point.
        If you want to target specific platforms only, use the
        <.code_inline>--platform</.code_inline>
        flag.
      </p>
      <.callout title="File naming convention">
        <p class="text-sm text-base-content/70">
          All teamrc-generated files are prefixed with <.code_inline>trc-</.code_inline>.
          This makes them easy to identify and ensures they don't collide with files you create manually.
          When teamrc syncs, it only touches files with this prefix.
        </p>
      </.callout>
    </section>

    <section class="space-y-3">
      <.section_heading id="claude-code" title="Claude Code" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        <span class="font-semibold">Detection:</span>
        <.code_inline>~/.claude/</.code_inline>
        directory exists.
        Supports both project and global scope.
      </p>
      <div class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-2">
        <p class="text-[10px] font-medium text-base-content/60 uppercase tracking-wider">
          Generated files
        </p>
        <div class="space-y-1.5 text-xs font-mono text-base-content/70">
          <div>
            <span class="text-base-content/50">agents →</span> .claude/agents/trc-&#123;name&#125;.md
          </div>
          <div>
            <span class="text-base-content/50">always-apply skills →</span>
            .claude/rules/trc-&#123;id&#125;.md
          </div>
          <div>
            <span class="text-base-content/50">glob skills →</span>
            .claude/rules/trc-&#123;id&#125;.md
          </div>
          <div>
            <span class="text-base-content/50">on-demand skills →</span>
            .claude/skills/trc-&#123;id&#125;/SKILL.md
          </div>
          <div><span class="text-base-content/50">knowledge →</span> teamrc-knowledge.md</div>
          <div><span class="text-base-content/50">team context →</span> updated in CLAUDE.md</div>
        </div>
      </div>
      <p class="text-sm text-base-content/70 leading-relaxed">
        Agent files use YAML frontmatter with name, description, and a skill list.
        Per-agent skills are listed in the frontmatter so Claude Code natively routes them.
        teamrc also appends a team context block to
        <.code_inline>CLAUDE.md</.code_inline>
        describing the team and its members.
      </p>
    </section>

    <section class="space-y-3">
      <.section_heading id="cursor" title="Cursor" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        <span class="font-semibold">Detection:</span>
        <.code_inline>.cursor/</.code_inline>
        directory in the project.
        Project scope only.
      </p>
      <div class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-2">
        <p class="text-[10px] font-medium text-base-content/60 uppercase tracking-wider">
          Generated files
        </p>
        <div class="space-y-1.5 text-xs font-mono text-base-content/70">
          <div>
            <span class="text-base-content/50">agents →</span> .cursor/agents/trc-&#123;name&#125;.md
          </div>
          <div>
            <span class="text-base-content/50">always-apply/glob skills →</span>
            .cursor/rules/trc-&#123;id&#125;.mdc
          </div>
          <div>
            <span class="text-base-content/50">on-demand skills →</span>
            .cursor/skills/trc-&#123;id&#125;/SKILL.md
          </div>
          <div><span class="text-base-content/50">knowledge →</span> teamrc-knowledge.md</div>
          <div><span class="text-base-content/50">routing →</span> .cursor/AGENTS.md</div>
        </div>
      </div>
      <p class="text-sm text-base-content/70 leading-relaxed">
        Rule files use the
        <.code_inline>.mdc</.code_inline>
        format (Markdown Config) with YAML headers for description,
        globs, and alwaysApply. Team routing information is written to <.code_inline>.cursor/AGENTS.md</.code_inline>.
      </p>
    </section>

    <section class="space-y-3">
      <.section_heading id="codex" title="Codex" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        <span class="font-semibold">Detection:</span>
        <.code_inline>.codex/</.code_inline>
        directory.
        Supports both project and global scope.
      </p>
      <div class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-2">
        <p class="text-[10px] font-medium text-base-content/60 uppercase tracking-wider">
          Generated files
        </p>
        <div class="space-y-1.5 text-xs font-mono text-base-content/70">
          <div>
            <span class="text-base-content/50">agents →</span> .codex/agents/trc-&#123;name&#125;.toml
          </div>
          <div>
            <span class="text-base-content/50">team config →</span>
            .codex/config.toml (multi-agent section)
          </div>
          <div><span class="text-base-content/50">routing →</span> AGENTS.md</div>
          <div>
            <span class="text-base-content/50">on-demand skills →</span>
            .agents/skills/trc-&#123;id&#125;/SKILL.md
          </div>
          <div><span class="text-base-content/50">knowledge →</span> teamrc-knowledge.md</div>
        </div>
      </div>
      <p class="text-sm text-base-content/70 leading-relaxed">
        Codex uses TOML-based configuration. Agent instructions are stored as triple-quoted strings.
        Multi-agent mode is automatically enabled in <.code_inline>config.toml</.code_inline>.
        Always-apply and glob-targeted skills are written into <.code_inline>AGENTS.md</.code_inline>.
      </p>
    </section>

    <section class="space-y-3">
      <.section_heading id="gemini" title="Gemini" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        <span class="font-semibold">Detection:</span>
        <.code_inline>.gemini/</.code_inline>
        directory.
        Supports both project and global scope.
      </p>
      <div class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-2">
        <p class="text-[10px] font-medium text-base-content/60 uppercase tracking-wider">
          Generated files
        </p>
        <div class="space-y-1.5 text-xs font-mono text-base-content/70">
          <div>
            <span class="text-base-content/50">agents →</span> .gemini/agents/trc-&#123;name&#125;.md
          </div>
          <div>
            <span class="text-base-content/50">skills →</span>
            .agents/skills/trc-&#123;id&#125;/SKILL.md
          </div>
          <div><span class="text-base-content/50">knowledge →</span> teamrc-knowledge.md</div>
          <div><span class="text-base-content/50">team context →</span> GEMINI.md</div>
        </div>
      </div>
      <p class="text-sm text-base-content/70 leading-relaxed">
        Agent files use YAML frontmatter with a team header section.
        Skills are written to both
        <.code_inline>.agents/skills/</.code_inline>
        and
        <.code_inline>.agent/skills/</.code_inline>
        (or the global config directory) for compatibility.
        Always-apply skills are inlined in <.code_inline>GEMINI.md</.code_inline>.
      </p>
    </section>

    <section class="space-y-3">
      <.section_heading id="openclaw" title="OpenClaw" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        <span class="font-semibold">Detection:</span>
        <.code_inline>.agents/</.code_inline>
        directory.
        Supports both project and global scope.
      </p>
      <div class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-2">
        <p class="text-[10px] font-medium text-base-content/60 uppercase tracking-wider">
          Generated files
        </p>
        <div class="space-y-1.5 text-xs font-mono text-base-content/70">
          <div>
            <span class="text-base-content/50">agents →</span> .agents/agents/trc-&#123;name&#125;.md
          </div>
          <div>
            <span class="text-base-content/50">skills →</span>
            .agents/skills/trc-&#123;id&#125;/SKILL.md
          </div>
          <div><span class="text-base-content/50">knowledge →</span> .agents/teamrc-knowledge.md</div>
          <div><span class="text-base-content/50">routing →</span> AGENTS.md</div>
        </div>
      </div>
      <p class="text-sm text-base-content/70 leading-relaxed">
        Uses the native OpenHands format with YAML frontmatter. Per-agent skill assignments are
        listed in the agent's frontmatter. Team routing is written to <.code_inline>AGENTS.md</.code_inline>.
      </p>
    </section>

    <section class="space-y-3">
      <.section_heading id="coming-soon" title="Coming soon" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        Adapters for these platforms are planned but not yet implemented: <span class="font-semibold">GitHub Copilot</span>, <span class="font-semibold">Amazon Q</span>, <span class="font-semibold">Windsurf</span>, and <span class="font-semibold">Cline</span>.
      </p>
    </section>
    """
  end

  # ===========================================================================
  # Page: Syncing
  # ===========================================================================

  defp page_sync(assigns) do
    ~H"""
    <div>
      <h1 class="text-2xl font-bold tracking-tight mb-1">Syncing</h1>
      <p class="text-sm text-base-content/60">
        Syncing is what makes teamrc useful across multiple machines. Here's how it works.
      </p>
    </div>

    <.page_toc items={[
      {"#relay", "The relay"},
      {"#sync-steps", "What sync does"},
      {"#conflicts", "Conflict resolution"},
      {"#invites", "Invite codes"},
      {"#multi-project", "Multi-project teams"},
      {"#daemon", "Daemon mode"},
      {"#auth", "Authentication"}
    ]} />

    <%!-- The relay model --%>
    <section class="space-y-3">
      <.section_heading id="relay" title="The relay" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        The relay is a server that stores your team's canonical state. Every connected machine
        pushes to and pulls from the relay. The web UI reads and writes to the relay too.
      </p>
      <p class="text-sm text-base-content/70 leading-relaxed">
        Machines don't talk to each other directly. They all go through the relay.
        This keeps the sync model simple: there's always one source of truth, and you always know where it is.
      </p>
      <div class="rounded-lg border border-base-300 bg-base-100 p-4">
        <p class="text-[10px] font-medium text-base-content/60 uppercase tracking-wider mb-3">
          Sync flow
        </p>
        <div class="flex items-center justify-between text-xs text-base-content/70">
          <div class="text-center space-y-1">
            <div class="mx-auto flex h-10 w-10 items-center justify-center rounded-lg bg-base-200">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-5 w-5 text-base-content/60"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M9 17.25v1.007a3 3 0 0 1-.879 2.122L7.5 21h9l-.621-.621A3 3 0 0 1 15 18.257V17.25m6-12V15a2.25 2.25 0 0 1-2.25 2.25H5.25A2.25 2.25 0 0 1 3 15V5.25m18 0A2.25 2.25 0 0 0 18.75 3H5.25A2.25 2.25 0 0 0 3 5.25m18 0V12a2.25 2.25 0 0 1-2.25 2.25H5.25A2.25 2.25 0 0 1 3 12V5.25"
                />
              </svg>
            </div>
            <div>Machine A</div>
          </div>
          <div class="flex-1 flex items-center justify-center px-4">
            <div class="w-full border-t border-dashed border-base-300 relative">
              <span class="absolute -top-2.5 left-1/2 -translate-x-1/2 bg-base-100 px-2 text-[10px] text-base-content/50 font-mono">
                push/pull
              </span>
            </div>
          </div>
          <div class="text-center space-y-1">
            <div class="mx-auto flex h-10 w-10 items-center justify-center rounded-lg bg-primary/10">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-5 w-5 text-primary/80"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M2.25 15a4.5 4.5 0 0 0 4.5 4.5H18a3.75 3.75 0 0 0 1.332-7.257 3 3 0 0 0-3.758-3.848 5.25 5.25 0 0 0-10.233 2.33A4.502 4.502 0 0 0 2.25 15Z"
                />
              </svg>
            </div>
            <div>Relay</div>
          </div>
          <div class="flex-1 flex items-center justify-center px-4">
            <div class="w-full border-t border-dashed border-base-300 relative">
              <span class="absolute -top-2.5 left-1/2 -translate-x-1/2 bg-base-100 px-2 text-[10px] text-base-content/50 font-mono">
                push/pull
              </span>
            </div>
          </div>
          <div class="text-center space-y-1">
            <div class="mx-auto flex h-10 w-10 items-center justify-center rounded-lg bg-base-200">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-5 w-5 text-base-content/60"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M9 17.25v1.007a3 3 0 0 1-.879 2.122L7.5 21h9l-.621-.621A3 3 0 0 1 15 18.257V17.25m6-12V15a2.25 2.25 0 0 1-2.25 2.25H5.25A2.25 2.25 0 0 1 3 15V5.25m18 0A2.25 2.25 0 0 0 18.75 3H5.25A2.25 2.25 0 0 0 3 5.25m18 0V12a2.25 2.25 0 0 1-2.25 2.25H5.25A2.25 2.25 0 0 1 3 12V5.25"
                />
              </svg>
            </div>
            <div>Machine B</div>
          </div>
        </div>
      </div>
    </section>

    <%!-- What sync does --%>
    <section class="space-y-3">
      <.section_heading id="sync-steps" title="What sync actually does" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        When you run <.code_inline>teamrc sync</.code_inline>, the CLI performs these steps in order:
      </p>
      <div class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-3">
        <div class="flex items-start gap-3 text-sm">
          <span class="text-primary/80 font-mono font-bold shrink-0">1</span>
          <div>
            <p class="font-semibold">Read local state</p>
            <p class="text-base-content/70 text-xs mt-0.5">
              Reads
              <.code_inline>.teamrc.yaml</.code_inline>
              and the knowledge file from disk.
            </p>
          </div>
        </div>
        <div class="flex items-start gap-3 text-sm">
          <span class="text-primary/80 font-mono font-bold shrink-0">2</span>
          <div>
            <p class="font-semibold">Push to relay</p>
            <p class="text-base-content/70 text-xs mt-0.5">
              Sends the team definition and knowledge to the relay server.
            </p>
          </div>
        </div>
        <div class="flex items-start gap-3 text-sm">
          <span class="text-primary/80 font-mono font-bold shrink-0">3</span>
          <div>
            <p class="font-semibold">Pull from relay</p>
            <p class="text-base-content/70 text-xs mt-0.5">
              Fetches the latest team state (which may include changes from other machines or the web UI).
            </p>
          </div>
        </div>
        <div class="flex items-start gap-3 text-sm">
          <span class="text-primary/80 font-mono font-bold shrink-0">4</span>
          <div>
            <p class="font-semibold">Merge knowledge</p>
            <p class="text-base-content/70 text-xs mt-0.5">
              Appends any new lines from the remote knowledge to your local copy (deduped).
            </p>
          </div>
        </div>
        <div class="flex items-start gap-3 text-sm">
          <span class="text-primary/80 font-mono font-bold shrink-0">5</span>
          <div>
            <p class="font-semibold">Apply to platforms</p>
            <p class="text-base-content/70 text-xs mt-0.5">
              Regenerates config files for all detected platforms (Claude Code, Cursor, etc.).
            </p>
          </div>
        </div>
      </div>
    </section>

    <%!-- Conflict resolution --%>
    <section class="space-y-3">
      <.section_heading id="conflicts" title="Conflict resolution" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        We deliberately kept this simple: <span class="font-semibold">last write wins</span>.
        The relay always stores the most recent version. No three-way merge, no conflict markers.
      </p>
      <p class="text-sm text-base-content/70 leading-relaxed">
        This works well in practice. Agent config is small, declarative, and changes infrequently.
        If you're worried about stepping on someone's changes, run
        <.code_inline>teamrc diff</.code_inline>
        before pushing.
        If something goes wrong,
        <.code_inline>teamrc pull</.code_inline>
        gets you back to the relay's version.
      </p>
      <p class="text-sm text-base-content/70 leading-relaxed">
        <span class="font-semibold">Knowledge</span> is the one exception. It uses append-only merge,
        so insights from different machines always get combined, never overwritten.
      </p>
    </section>

    <%!-- Invites --%>
    <section class="space-y-3">
      <.section_heading id="invites" title="Invite codes" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        Invite codes are how you connect machines to a team. An invite is a time-limited token
        (format: <.code_inline>trc_inv_...</.code_inline>, default: 24 hours) that grants access
        to join the team on the relay.
      </p>
      <.callout title="Invites are not just for teammates">
        <p class="text-sm text-base-content/70">
          An invite code connects any machine to the same team. Use it for:
        </p>
        <ul class="text-sm text-base-content/70 space-y-1 list-disc list-inside mt-1.5">
          <li>Your own second machine (laptop + desktop)</li>
          <li>A cloud VM or CI runner</li>
          <li>A different project directory that uses the same team</li>
          <li>A collaborator's workstation</li>
          <li>
            An agent on a different platform (e.g., OpenClaw research team alongside Claude Code devs)
          </li>
        </ul>
      </.callout>
    </section>

    <%!-- Multi-project teams --%>
    <section class="space-y-3">
      <.section_heading id="multi-project" title="Multi-project teams" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        A team isn't locked to one project. Run
        <.code_inline>teamrc join</.code_inline>
        from a different project directory and you get the same team. Same agents, same skills,
        same config. Change something, sync, and all projects pick it up.
      </p>
      <p class="text-sm text-base-content/70 leading-relaxed">
        The reverse is also true. Two people on the same project can use different teams.
        You might work with a fullstack team while your colleague has a research team
        on OpenClaw. Same repo, different agent setups, no conflict.
        Teams and repos are independent by design.
      </p>
    </section>

    <%!-- Daemon --%>
    <section class="space-y-3">
      <.section_heading id="daemon" title="Daemon mode" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        The daemon is a background process that keeps your machine synced automatically.
        It does two things:
      </p>
      <ul class="text-sm text-base-content/70 space-y-1.5 list-disc list-inside">
        <li><span class="font-semibold">Polls the relay</span> on an interval (default: 2 minutes).
          When the remote team has changed, it pulls and applies locally.</li>
        <li>
          <span class="font-semibold">
            Watches
            <.code_inline>.teamrc.yaml</.code_inline>
          </span>
          for local changes.
          When you edit the file, it immediately regenerates platform config files.
        </li>
      </ul>
      <.terminal_block title="terminal">
        <div class="space-y-1.5">
          <.cmd_line cmd="npx @teamrc/cli daemon" comment="# default 2-minute poll" />
          <.cmd_line cmd="npx @teamrc/cli daemon --poll-interval 30000" comment="# poll every 30 seconds" />
        </div>
      </.terminal_block>
      <p class="text-sm text-base-content/70 leading-relaxed">
        The daemon merges knowledge on each poll and preserves local metadata (teamId, relay, platforms)
        when updating <.code_inline>.teamrc.yaml</.code_inline>.
      </p>
    </section>

    <%!-- Auth --%>
    <section class="space-y-3">
      <.section_heading id="auth" title="Authentication" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        There's no signup. When you run
        <.code_inline>teamrc init</.code_inline>
        or <.code_inline>teamrc join</.code_inline>,
        the CLI generates an ed25519 keypair and stores it in <.code_inline>~/.teamrc/key</.code_inline>.
        That's your identity. Every request to the relay is signed with your private key.
        No passwords, no cookies, no session tokens.
      </p>

      <.sub_heading id="tokens" title="Tokens" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        Your token (<.code_inline>trc_ak_...</.code_inline>) is just your public key with a prefix.
        It identifies your machine. The relay verifies every request by checking the signature against this key.
      </p>

      <.sub_heading id="accounts" title="Optional accounts" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        You can optionally link your machine to an account with <.code_inline>teamrc login</.code_inline>.
        It works like <.code_inline>gh auth login</.code_inline>. Opens a browser, you confirm, done.
        This gives you:
      </p>
      <ul class="text-sm text-base-content/70 space-y-1 list-disc list-inside">
        <li>A web dashboard to manage your machines and teams</li>
        <li>Recovery if you lose a keypair</li>
        <li>A single view of all your teams</li>
      </ul>
      <p class="text-sm text-base-content/70 leading-relaxed">
        But it's optional. Everything works without it.
      </p>
    </section>
    """
  end

  # ===========================================================================
  # Page: Web UI
  # ===========================================================================

  defp page_web_ui(assigns) do
    ~H"""
    <div>
      <h1 class="text-2xl font-bold tracking-tight mb-1">Web UI Tour</h1>
      <p class="text-sm text-base-content/60">
        A visual walkthrough of each screen. This is a tour, not the quickest onboarding path. If you just
        want to get running, start with <a
          href="/guide/get-started"
          class="text-primary/80 hover:text-primary"
        >Get Started in 2 Minutes</a>.
      </p>
    </div>

    <.page_toc
      items={[
        {"#create", "Create a team"},
        {"#visibility", "Visibility"},
        {"#dashboard", "Team dashboard"},
        {"#add-member", "Adding a member"},
        {"#member-detail", "Editing a member"},
        {"#add-skill", "Adding a skill"},
        {"#invites", "Sharing your team"},
        {"#machines", "Connected machines"},
        {"#knowledge", "Team knowledge"},
        {"#flow", "The full flow"}
      ]}
      title="Tour stops"
    />

    <%!-- Step 1: Creating a team --%>
    <section class="space-y-4">
      <.section_heading id="create" title="1. Creating a team" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        Go to
        <.code_inline>/new</.code_inline>
        (or click "Create Team" in the nav).
        You'll see a list of templates. Each one creates a team with agents and skills
        already configured. Pick one and you're done.
      </p>

      <%!-- Mockup: template picker --%>
      <div class="rounded-xl border border-base-300 bg-base-100 overflow-hidden">
        <div class="px-5 pt-5 pb-3 space-y-1">
          <p class="text-[10px] font-medium text-primary/80 uppercase tracking-wider">Screen</p>
          <p class="text-sm font-bold">Template picker</p>
        </div>
        <div class="px-5 pb-5 space-y-2.5">
          <.mock_template_card
            icon="code"
            label="Fullstack"
            desc="Frontend, backend, and QA"
            agents={["frontend-dev", "backend-dev", "qa-engineer"]}
            highlighted={true}
          />
          <.mock_template_card
            icon="server"
            label="Backend"
            desc="API development and data engineering"
            agents={["backend-dev", "api-dev", "db-engineer"]}
          />
          <.mock_template_card
            icon="shield"
            label="Security"
            desc="Security auditing and compliance"
            agents={["security-auditor", "devops-engineer"]}
          />
        </div>
        <div class="px-5 py-3 border-t border-base-300/60 bg-base-200/20">
          <p class="text-xs text-base-content/60">
            Click a template to create the team instantly.
          </p>
        </div>
      </div>
    </section>

    <%!-- Step 2: Visibility --%>
    <section class="space-y-4">
      <.section_heading id="visibility" title="2. Visibility" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        Teams are <span class="font-semibold">private by default</span>. Only participants
        (machines that joined with an invite code) can view a private team's page. If someone without
        access visits the URL, they see a "This team is private" message.
      </p>
      <p class="text-sm text-base-content/70 leading-relaxed">
        You can toggle a team to <span class="font-semibold">public</span> if you want anyone with the
        link to view and clone the config. Public teams show a read-only view of members,
        skills, and knowledge. Invites, participants, and edit controls stay hidden from non-participants.
      </p>
      <p class="text-sm text-base-content/70 leading-relaxed">
        The visibility toggle lives on the team dashboard, right next to the team name.
      </p>

      <%!-- Mockup: visibility toggle --%>
      <div class="rounded-xl border border-base-300 bg-base-100 overflow-hidden">
        <div class="px-5 pt-5 pb-3 space-y-1">
          <p class="text-[10px] font-medium text-primary/80 uppercase tracking-wider">Screen</p>
          <p class="text-sm font-bold">Visibility toggle</p>
        </div>
        <div class="px-5 pb-5">
          <div class="flex items-center gap-2">
            <span class="text-sm font-mono font-bold">my-team</span>
            <span class="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-medium bg-base-200 text-base-content/60">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-2.5 w-2.5"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="2"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M16.5 10.5V6.75a4.5 4.5 0 1 0-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 0 0 2.25-2.25v-6.75a2.25 2.25 0 0 0-2.25-2.25H6.75a2.25 2.25 0 0 0-2.25 2.25v6.75a2.25 2.25 0 0 0 2.25 2.25Z"
                />
              </svg>
              private
            </span>
            <span class="text-[10px] text-primary font-medium cursor-pointer">Make public</span>
          </div>
        </div>
      </div>

      <.callout title="When to use public vs. private">
        <p>
          Use <span class="font-semibold">private</span>
          for teams with proprietary instructions or
          internal workflows. Use <span class="font-semibold">public</span>
          when you want to share your
          team setup with the community or let others clone your config without needing an invite.
        </p>
      </.callout>
    </section>

    <%!-- Step 3: Team dashboard --%>
    <section class="space-y-4">
      <.section_heading id="dashboard" title="3. Team dashboard" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        After creating a team, you land on the dashboard.
        This is where you manage members, skills, and invites.
        Invite links open a read-only preview &mdash; join via the CLI to get edit access.
      </p>

      <%!-- Mockup: dashboard --%>
      <div class="rounded-xl border border-base-300 bg-base-100 overflow-hidden">
        <div class="px-5 pt-5 pb-3 space-y-1">
          <p class="text-[10px] font-medium text-primary/80 uppercase tracking-wider">Screen</p>
          <p class="text-sm font-bold">Team dashboard</p>
        </div>
        <div class="px-5 pb-5 space-y-5">
          <%!-- Team name --%>
          <div>
            <p class="text-lg font-bold font-mono">my-project</p>
            <p class="text-[10px] font-mono text-base-content/50 mt-0.5">team_abc123</p>
          </div>

          <%!-- Join command --%>
          <div class="terminal-block rounded-lg overflow-hidden">
            <div class="flex items-center justify-between px-3 py-1.5 border-b border-white/5">
              <span class="text-[10px] font-mono text-white/25">terminal</span>
              <span class="text-[10px] font-mono text-white/30">copy</span>
            </div>
            <div class="px-3 py-2">
              <code class="text-emerald-400 text-xs font-mono">npx @teamrc/cli join trc_inv_a1b2c3</code>
            </div>
          </div>

          <%!-- Members --%>
          <div class="space-y-2">
            <div class="flex items-center gap-2">
              <p class="text-xs font-semibold">Members</p>
              <span class="text-[10px] font-mono text-base-content/50 bg-base-200 rounded px-1.5 py-0.5">
                3
              </span>
            </div>
            <div class="space-y-1.5">
              <.mock_member_card
                name="frontend-dev"
                role="Frontend development"
                skills={["code-style", "testing"]}
              />
              <.mock_member_card
                name="backend-dev"
                role="Backend development"
                skills={["write-tests"]}
              />
              <.mock_member_card name="qa-engineer" role="Quality assurance" skills={[]} />
            </div>
            <button class="w-full rounded-lg border border-dashed border-base-300 py-2 text-xs text-base-content/50 hover:text-base-content/60 hover:border-base-content/20 transition-colors">
              + Add team member
            </button>
          </div>

          <%!-- Skills --%>
          <div class="space-y-2">
            <div class="flex items-center gap-2">
              <p class="text-xs font-semibold">Skills</p>
              <span class="text-[10px] font-mono text-base-content/50 bg-base-200 rounded px-1.5 py-0.5">
                2
              </span>
            </div>
            <div class="space-y-1.5">
              <.mock_skill_card id="code-style" title="Code Style Guide" always_apply={true} />
              <.mock_skill_card id="write-tests" title="Testing Requirements" />
            </div>
          </div>
        </div>
        <div class="px-5 py-3 border-t border-base-300/60 bg-base-200/20">
          <p class="text-xs text-base-content/60">
            Click any member card to edit their instructions and skills.
            Click a skill to edit its body.
          </p>
        </div>
      </div>
    </section>

    <%!-- Step 4: Adding members --%>
    <section class="space-y-4">
      <.section_heading id="add-member" title="4. Adding a member" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        Click "Add team member" on the dashboard. You'll see the agent catalog,
        grouped by category. Pick a pre-built agent or create a custom one.
      </p>

      <%!-- Mockup: agent picker --%>
      <div class="rounded-xl border border-base-300 bg-base-100 overflow-hidden">
        <div class="px-5 pt-5 pb-3 space-y-1">
          <p class="text-[10px] font-medium text-primary/80 uppercase tracking-wider">Screen</p>
          <p class="text-sm font-bold">Agent catalog picker</p>
        </div>
        <div class="px-5 pb-5 space-y-3">
          <%!-- Custom option --%>
          <button class="w-full rounded-lg border border-dashed border-base-300 p-3 text-left hover:border-primary/30 transition-colors">
            <p class="text-xs font-semibold">+ Create custom agent</p>
            <p class="text-[10px] text-base-content/60 mt-0.5">Define a new agent from scratch</p>
          </button>

          <%!-- Category --%>
          <div class="space-y-1.5">
            <p class="text-[10px] font-medium text-base-content/50 uppercase tracking-wider">
              Core Development
            </p>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-1.5">
              <.mock_catalog_agent name="frontend-dev" role="Frontend development" highlighted={true} />
              <.mock_catalog_agent name="backend-dev" role="Backend development" />
              <.mock_catalog_agent name="fullstack-dev" role="Full-stack development" />
              <.mock_catalog_agent name="mobile-dev" role="Mobile development" />
            </div>
          </div>
          <div class="space-y-1.5">
            <p class="text-[10px] font-medium text-base-content/50 uppercase tracking-wider">
              Quality
            </p>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-1.5">
              <.mock_catalog_agent name="qa-engineer" role="Quality assurance" />
              <.mock_catalog_agent name="code-reviewer" role="Code review" />
            </div>
          </div>
        </div>
        <div class="px-5 py-3 border-t border-base-300/60 bg-base-200/20">
          <p class="text-xs text-base-content/60">
            Picking a catalog agent pre-fills their instructions and recommended skills.
          </p>
        </div>
      </div>

      <p class="text-sm text-base-content/70 leading-relaxed">
        After picking an agent, you see a confirmation with the name, role, and a preview
        of what's included. Click "Add" and the agent joins your team.
      </p>

      <%!-- Mockup: member form with preview --%>
      <div class="rounded-xl border border-base-300 bg-base-100 overflow-hidden">
        <div class="px-5 pt-5 pb-3 space-y-1">
          <p class="text-[10px] font-medium text-primary/80 uppercase tracking-wider">Screen</p>
          <p class="text-sm font-bold">Add member confirmation</p>
        </div>
        <div class="px-5 pb-5 space-y-3">
          <div class="flex gap-2">
            <div class="flex-1">
              <p class="text-[10px] text-base-content/50 uppercase tracking-wider mb-1">Name</p>
              <div class="rounded border border-base-300 bg-base-200/30 px-2.5 py-1.5 text-xs font-mono">
                frontend-dev
              </div>
            </div>
            <div class="flex-[2]">
              <p class="text-[10px] text-base-content/50 uppercase tracking-wider mb-1">Role</p>
              <div class="rounded border border-base-300 bg-base-200/30 px-2.5 py-1.5 text-xs">
                Frontend development
              </div>
            </div>
          </div>
          <div class="flex flex-wrap items-center gap-x-3 gap-y-1 text-[11px] text-base-content/60">
            <span class="inline-flex items-center gap-1">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-3 w-3 text-emerald-500/60"
                viewBox="0 0 20 20"
                fill="currentColor"
              >
                <path
                  fill-rule="evenodd"
                  d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                  clip-rule="evenodd"
                />
              </svg>
              Includes instructions
            </span>
            <span class="inline-flex items-center gap-1">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-3 w-3 text-emerald-500/60"
                viewBox="0 0 20 20"
                fill="currentColor"
              >
                <path
                  fill-rule="evenodd"
                  d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                  clip-rule="evenodd"
                />
              </svg>
              2 skills:
            </span>
            <span class="inline-flex rounded bg-base-200 px-1.5 py-0.5 text-[10px] font-mono text-base-content/60">
              code-style
            </span>
            <span class="inline-flex rounded bg-base-200 px-1.5 py-0.5 text-[10px] font-mono text-base-content/60">
              write-tests
            </span>
          </div>
          <div class="flex items-center gap-2">
            <div class="rounded-md bg-primary px-3 py-1.5 text-xs font-semibold text-primary-content">
              Add
            </div>
            <div class="rounded-md px-3 py-1.5 text-xs text-base-content/60">Cancel</div>
          </div>
        </div>
      </div>
    </section>

    <%!-- Step 5: Member detail --%>
    <section class="space-y-4">
      <.section_heading id="member-detail" title="5. Editing a member" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        Click a member card on the dashboard to open their detail page.
        Here you can edit their name, role, and instructions. You can also toggle which skills are assigned to them.
      </p>

      <%!-- Mockup: member detail --%>
      <div class="rounded-xl border border-base-300 bg-base-100 overflow-hidden">
        <div class="px-5 pt-5 pb-3 space-y-1">
          <p class="text-[10px] font-medium text-primary/80 uppercase tracking-wider">Screen</p>
          <p class="text-sm font-bold">Member detail</p>
        </div>
        <div class="px-5 pb-5 space-y-4">
          <%!-- Name + Role --%>
          <div class="space-y-2">
            <div>
              <p class="text-[10px] text-base-content/50 uppercase tracking-wider mb-1">Name</p>
              <div class="rounded border border-base-300 px-2.5 py-1.5 text-sm font-mono font-bold">
                frontend-dev
              </div>
            </div>
            <div>
              <p class="text-[10px] text-base-content/50 uppercase tracking-wider mb-1">Role</p>
              <div class="rounded border border-base-300 px-2.5 py-1.5 text-xs">
                Frontend development
              </div>
            </div>
          </div>

          <%!-- Instructions --%>
          <div>
            <div class="flex items-center gap-2 mb-1">
              <p class="text-[10px] text-base-content/50 uppercase tracking-wider">Instructions</p>
            </div>
            <div class="rounded border border-base-300 bg-base-200/20 px-3 py-2 text-[11px] font-mono text-base-content/60 leading-relaxed h-20 overflow-hidden">
              ## Identity
              You are the frontend specialist...

              ## Expertise
              React, TypeScript, CSS, accessibility...
            </div>
          </div>

          <%!-- Skills toggles --%>
          <div>
            <div class="flex items-center gap-2 mb-1.5">
              <p class="text-[10px] text-base-content/50 uppercase tracking-wider">Skills</p>
              <span class="text-[10px] font-mono text-base-content/50 bg-base-200 rounded px-1.5 py-0.5">
                2
              </span>
            </div>
            <div class="space-y-1.5">
              <div class="rounded-lg border border-primary/20 bg-primary/5 px-3 py-2 flex items-center gap-2">
                <div class="w-3.5 h-3.5 rounded border-2 border-primary/60 bg-primary/20 flex items-center justify-center">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    class="h-2.5 w-2.5 text-primary"
                    viewBox="0 0 20 20"
                    fill="currentColor"
                  >
                    <path
                      fill-rule="evenodd"
                      d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                      clip-rule="evenodd"
                    />
                  </svg>
                </div>
                <span class="text-xs font-mono font-semibold">code-style</span>
                <span class="text-[10px] text-base-content/60">Code Style Guide</span>
              </div>
              <div class="rounded-lg border border-base-300 bg-base-200/30 px-3 py-2 flex items-center gap-2">
                <div class="w-3.5 h-3.5 rounded border-2 border-base-300"></div>
                <span class="text-xs font-mono font-semibold text-base-content/60">write-tests</span>
                <span class="text-[10px] text-base-content/50">Testing Requirements</span>
              </div>
              <div class="rounded-lg border border-primary/10 bg-primary/5 px-3 py-2 flex items-center gap-2 opacity-60">
                <div class="w-3.5 h-3.5 rounded border-2 border-primary/30 bg-primary/10 flex items-center justify-center">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    class="h-2.5 w-2.5 text-primary/80"
                    viewBox="0 0 20 20"
                    fill="currentColor"
                  >
                    <path
                      fill-rule="evenodd"
                      d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                      clip-rule="evenodd"
                    />
                  </svg>
                </div>
                <span class="text-xs font-mono font-semibold text-base-content/60">
                  security-policy
                </span>
                <span class="text-[10px] text-base-content/50">all agents</span>
              </div>
            </div>
          </div>
        </div>
        <div class="px-5 py-3 border-t border-base-300/60 bg-base-200/20 space-y-1">
          <p class="text-xs text-base-content/60">
            Click a skill to toggle it on or off for this member.
            Skills marked "all agents" are always active and cannot be toggled.
          </p>
        </div>
      </div>
    </section>

    <%!-- Step 6: Adding skills --%>
    <section class="space-y-4">
      <.section_heading id="add-skill" title="6. Adding a skill" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        Click "Add skill" on the dashboard. You can pick from the catalog or write one from scratch.
        Skills are defined at the team level, then assigned to individual members on their detail pages.
      </p>

      <%!-- Mockup: skill form --%>
      <div class="rounded-xl border border-base-300 bg-base-100 overflow-hidden">
        <div class="px-5 pt-5 pb-3 space-y-1">
          <p class="text-[10px] font-medium text-primary/80 uppercase tracking-wider">Screen</p>
          <p class="text-sm font-bold">Skill editor</p>
        </div>
        <div class="px-5 pb-5 space-y-3">
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
            <div>
              <p class="text-[10px] text-base-content/50 uppercase tracking-wider mb-1">ID</p>
              <div class="rounded border border-base-300 px-2.5 py-1.5 text-xs font-mono">
                code-review
              </div>
            </div>
            <div>
              <p class="text-[10px] text-base-content/50 uppercase tracking-wider mb-1">Title</p>
              <div class="rounded border border-base-300 px-2.5 py-1.5 text-xs">
                Code Review Guidelines
              </div>
            </div>
          </div>
          <div>
            <p class="text-[10px] text-base-content/50 uppercase tracking-wider mb-1">Body</p>
            <div class="rounded border border-base-300 bg-base-200/20 px-3 py-2 text-[11px] font-mono text-base-content/60 leading-relaxed h-16 overflow-hidden">
              Review all code changes for:
              - Correctness and edge cases
              - Security vulnerabilities
              - Performance implications
            </div>
          </div>
          <div class="flex items-center gap-2 text-xs">
            <div class="w-8 h-4 rounded-full bg-base-300 relative">
              <div class="w-3.5 h-3.5 rounded-full bg-base-content/30 absolute top-0.5 left-0.5">
              </div>
            </div>
            <span class="text-base-content/60">Apply to all agents</span>
          </div>
          <div class="flex items-center gap-2">
            <div class="rounded-md bg-primary px-3 py-1.5 text-xs font-semibold text-primary-content">
              Add skill
            </div>
            <div class="rounded-md px-3 py-1.5 text-xs text-base-content/60">Cancel</div>
          </div>
        </div>
        <div class="px-5 py-3 border-t border-base-300/60 bg-base-200/20">
          <p class="text-xs text-base-content/60">
            The body is markdown. Write whatever instructions you want the agent to follow.
            Enable "Apply to all agents" for team-wide rules.
          </p>
        </div>
      </div>
    </section>

    <%!-- Step 7: Sharing --%>
    <section class="space-y-4">
      <.section_heading id="invites" title="7. Sharing your team" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        There are two ways to share a team. They work differently.
      </p>

      <.sub_heading id="invite-codes" title="Invite codes (sync access)" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        Invite codes create an <span class="font-semibold">ongoing sync connection</span> when used via the CLI.
        Running <code class="text-xs font-mono bg-base-200 px-1 py-0.5 rounded">teamrc join &lt;code&gt;</code>
        makes a machine a participant that receives updates and can push changes back.
        Opening an invite link in a browser shows a read-only preview of the team.
        Invite codes expire after 24 hours.
      </p>
      <p class="text-sm text-base-content/70 leading-relaxed">
        Team owners can find the Invites section on the dashboard. Click "Generate invite" to create a new code.
        Share it as a CLI command or as a URL.
      </p>

      <%!-- Mockup: invite section --%>
      <div class="rounded-xl border border-base-300 bg-base-100 overflow-hidden">
        <div class="px-5 pt-5 pb-3 space-y-1">
          <p class="text-[10px] font-medium text-primary/80 uppercase tracking-wider">Screen</p>
          <p class="text-sm font-bold">Invites section</p>
        </div>
        <div class="px-5 pb-5 space-y-3">
          <div class="flex items-center justify-between">
            <p class="text-xs font-semibold">Invites</p>
            <span class="text-xs text-primary font-medium cursor-pointer">Generate invite</span>
          </div>
          <div class="rounded-lg border border-primary/20 bg-primary/5 p-3 space-y-2">
            <div class="terminal-block rounded-lg overflow-hidden">
              <div class="px-3 py-2 flex items-center justify-between">
                <code class="text-emerald-400 text-xs font-mono">npx @teamrc/cli join trc_inv_x7y8z9</code>
                <span class="text-[10px] font-mono text-white/30">copy</span>
              </div>
            </div>
            <p class="text-[10px] text-base-content/60">Expires in 24 hours</p>
          </div>
          <p class="text-xs text-base-content/60 leading-relaxed">
            To open this team in a browser, visit:
            <.code_inline>/invite/trc_inv_x7y8z9</.code_inline>
          </p>
        </div>
      </div>

      <.sub_heading id="clone-tokens" title="Clone tokens (read-only copy)" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        Clone tokens let someone
        <span class="font-semibold">copy your team config as a snapshot</span>. They do not create a sync connection.
        Clone tokens are only available for public teams. Unlike invite codes,
        they do not expire and do not grant write access or ongoing updates.
      </p>
      <p class="text-sm text-base-content/70 leading-relaxed">
        When your team is public, the clone token and command appear on the dashboard. Visitors to
        your public team page also see a "Clone this team" section with the CLI command.
      </p>

      <%!-- Mockup: clone token section --%>
      <div class="rounded-xl border border-base-300 bg-base-100 overflow-hidden">
        <div class="px-5 pt-5 pb-3 space-y-1">
          <p class="text-[10px] font-medium text-primary/80 uppercase tracking-wider">Screen</p>
          <p class="text-sm font-bold">Clone token (public teams only)</p>
        </div>
        <div class="px-5 pb-5 space-y-3">
          <div class="flex items-center gap-2">
            <p class="text-xs font-semibold">Clone</p>
            <span class="inline-flex items-center rounded-full px-2 py-0.5 text-[10px] font-medium bg-emerald-500/10 text-emerald-600">
              public
            </span>
          </div>
          <div class="terminal-block rounded-lg overflow-hidden">
            <div class="px-3 py-2 flex items-center justify-between">
              <code class="text-emerald-400 text-xs font-mono">npx @teamrc/cli clone trc_cl_r4s5t6</code>
              <span class="text-[10px] font-mono text-white/30">copy</span>
            </div>
          </div>
          <p class="text-[10px] text-base-content/60">
            This copies the current team config. No ongoing sync. Use an invite code for that.
          </p>
        </div>
      </div>

      <.callout title="Clone vs. join">
        <p>
          <span class="font-semibold">Clone</span>
          (<.code_inline>trc_cl_...</.code_inline>): one-time
          snapshot, no sync, no expiry. Good for sharing templates or letting others try your setup.
          <span class="font-semibold">Join</span>
          (<.code_inline>trc_inv_...</.code_inline>): ongoing
          sync, full participation, expires in 24 hours. Good for teammates.
        </p>
      </.callout>
    </section>

    <%!-- Step 8: Connected machines --%>
    <section class="space-y-4">
      <.section_heading id="machines" title="8. Connected machines" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        Your connected machines are listed on your
        <span class="font-semibold">personal dashboard</span>
        at <.code_inline>/dashboard</.code_inline>, not on the team page. Only you can see your machines.
        Other participants cannot see your machine names, hostnames, or tokens.
      </p>
      <p class="text-sm text-base-content/70 leading-relaxed">
        Each card shows the machine name (your computer's hostname), whether it's scoped to a specific
        project or global, and when it last synced. Machine names only appear for machines that have
        run <.code_inline>teamrc login</.code_inline>. The CLI warns you before sharing your hostname.
      </p>

      <%!-- Mockup: machines section on /dashboard --%>
      <div class="rounded-xl border border-base-300 bg-base-100 overflow-hidden">
        <div class="px-5 pt-5 pb-3 space-y-1">
          <p class="text-[10px] font-medium text-primary/80 uppercase tracking-wider">Screen</p>
          <p class="text-sm font-bold">Dashboard: active machines</p>
        </div>
        <div class="px-5 pb-5 space-y-1.5">
          <div class="flex items-center justify-between mb-2">
            <p class="text-xs font-medium text-base-content/60 uppercase tracking-wider">
              Active Machines <span class="font-mono text-base-content/50 ml-1">3</span>
            </p>
          </div>

          <%!-- Machine 1 --%>
          <div class="flex items-center gap-3 rounded-md border border-base-300 bg-base-100 px-3 py-2.5">
            <div class="flex h-6 w-6 shrink-0 items-center justify-center rounded bg-base-200 text-base-content/50">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-3.5 w-3.5"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M9 17.25v1.007a3 3 0 0 1-.879 2.122L7.5 21h9l-.621-.621A3 3 0 0 1 15 18.257V17.25m6-12V15a2.25 2.25 0 0 1-2.25 2.25H5.25A2.25 2.25 0 0 1 3 15V5.25m18 0A2.25 2.25 0 0 0 18.75 3H5.25A2.25 2.25 0 0 0 3 5.25m18 0V12a2.25 2.25 0 0 1-2.25 2.25H5.25A2.25 2.25 0 0 1 3 12V5.25"
                />
              </svg>
            </div>
            <div class="min-w-0 flex-1">
              <div class="flex items-center gap-2">
                <span class="text-sm font-medium truncate">MacBook Pro</span>
                <code class="text-[10px] font-mono text-base-content/50">trc_ak_x7...q2</code>
              </div>
              <div class="flex items-center gap-2 text-xs text-base-content/50 mt-0.5">
                <span class="font-mono">my-project</span>
                <span>2 minutes ago</span>
              </div>
            </div>
          </div>

          <%!-- Machine 2 --%>
          <div class="flex items-center gap-3 rounded-md border border-base-300 bg-base-100 px-3 py-2.5">
            <div class="flex h-6 w-6 shrink-0 items-center justify-center rounded bg-base-200 text-base-content/50">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-3.5 w-3.5"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M9 17.25v1.007a3 3 0 0 1-.879 2.122L7.5 21h9l-.621-.621A3 3 0 0 1 15 18.257V17.25m6-12V15a2.25 2.25 0 0 1-2.25 2.25H5.25A2.25 2.25 0 0 1 3 15V5.25m18 0A2.25 2.25 0 0 0 18.75 3H5.25A2.25 2.25 0 0 0 3 5.25m18 0V12a2.25 2.25 0 0 1-2.25 2.25H5.25A2.25 2.25 0 0 1 3 12V5.25"
                />
              </svg>
            </div>
            <div class="min-w-0 flex-1">
              <div class="flex items-center gap-2">
                <span class="text-sm font-medium truncate">GitHub Actions Runner</span>
                <code class="text-[10px] font-mono text-base-content/50">trc_ak_m3...k8</code>
              </div>
              <div class="flex items-center gap-2 text-xs text-base-content/50 mt-0.5">
                <span class="font-mono">global</span>
                <span>15 minutes ago</span>
              </div>
            </div>
          </div>

          <%!-- Machine 3 --%>
          <div class="flex items-center gap-3 rounded-md border border-base-300 bg-base-100 px-3 py-2.5">
            <div class="flex h-6 w-6 shrink-0 items-center justify-center rounded bg-base-200 text-base-content/50">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-3.5 w-3.5"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M9 17.25v1.007a3 3 0 0 1-.879 2.122L7.5 21h9l-.621-.621A3 3 0 0 1 15 18.257V17.25m6-12V15a2.25 2.25 0 0 1-2.25 2.25H5.25A2.25 2.25 0 0 1 3 15V5.25m18 0A2.25 2.25 0 0 0 18.75 3H5.25A2.25 2.25 0 0 0 3 5.25m18 0V12a2.25 2.25 0 0 1-2.25 2.25H5.25A2.25 2.25 0 0 1 3 12V5.25"
                />
              </svg>
            </div>
            <div class="min-w-0 flex-1">
              <div class="flex items-center gap-2">
                <span class="text-sm font-medium truncate">Unnamed</span>
                <code class="text-[10px] font-mono text-base-content/50">trc_ak_p1...w5</code>
              </div>
              <div class="flex items-center gap-2 text-xs text-base-content/50 mt-0.5">
                <span class="font-mono">my-project</span>
                <span>3 hours ago</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <.callout title="Privacy note">
        <p>
          Machine names come from your computer's hostname. They are only shared when you
          run <.code_inline>teamrc login</.code_inline>. The CLI warns you before sending it.
          If a machine has not logged in, it shows as "Unnamed." Machines are only visible to you
          on your personal dashboard. They never appear on the team page. Other participants
          cannot see them.
        </p>
      </.callout>
    </section>

    <%!-- Step 9: Knowledge --%>
    <section class="space-y-4">
      <.section_heading id="knowledge" title="9. Team knowledge" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        The knowledge section shows shared notes that your agents have written during their work.
        When an agent discovers something important (an architecture decision, a debugging insight,
        a gotcha), it appends to the team knowledge file. That knowledge syncs to every
        machine on the next pull.
      </p>
      <p class="text-sm text-base-content/70 leading-relaxed">
        Knowledge is managed through the CLI and your agents. You cannot edit it in the web UI.
        The dashboard shows you what's there.
      </p>

      <%!-- Mockup: knowledge section (populated) --%>
      <div class="rounded-xl border border-base-300 bg-base-100 overflow-hidden">
        <div class="px-5 pt-5 pb-3 space-y-1">
          <p class="text-[10px] font-medium text-primary/80 uppercase tracking-wider">Screen</p>
          <p class="text-sm font-bold">Knowledge (populated)</p>
        </div>
        <div class="px-5 pb-5 space-y-2">
          <p class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-3">
            Knowledge
          </p>
          <div class="rounded-lg border border-base-300 bg-base-100 px-4 py-3">
            <pre class="text-xs font-mono text-base-content/70 whitespace-pre-wrap break-words"><%= "## Database\n- Using Postgres 18, connection pool size is 10\n- Migrations run automatically on deploy\n\n## Auth\n- Ed25519 keypairs, one per machine\n- Tokens are base64url-encoded public keys\n- Never log private keys\n\n## Frontend\n- Tailwind CSS with DaisyUI, no custom CSS files\n- All components in lib/teamrc_web/components/" %></pre>
          </div>
        </div>
      </div>

      <%!-- Mockup: knowledge section (empty) --%>
      <div class="rounded-xl border border-base-300 bg-base-100 overflow-hidden mt-4">
        <div class="px-5 pt-5 pb-3 space-y-1">
          <p class="text-[10px] font-medium text-primary/80 uppercase tracking-wider">Screen</p>
          <p class="text-sm font-bold">Knowledge (empty)</p>
        </div>
        <div class="px-5 pb-5 space-y-2">
          <p class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-3">
            Knowledge
          </p>
          <div class="rounded-md border border-dashed border-base-300 bg-base-200/20 p-4 text-center">
            <p class="text-xs text-base-content/60">
              No knowledge yet. Knowledge is managed via the CLI.
            </p>
          </div>
        </div>
      </div>

      <.callout title="How does knowledge get written?">
        <p>
          Your agents write to the knowledge file during their work. In your team config,
          tell agents to append findings to
          <.code_inline>.claude/teamrc-knowledge.md</.code_inline>
          (or wherever your platform stores it).
          On the next <.code_inline>teamrc push</.code_inline>, that content uploads to the relay.
          On <.code_inline>teamrc pull</.code_inline>, every machine gets the merged result.
          Duplicates are removed automatically.
        </p>
      </.callout>
    </section>

    <%!-- Putting it together --%>
    <section class="space-y-3">
      <.section_heading id="flow" title="The full flow" />
      <div class="rounded-lg border border-base-300 bg-base-100 p-5">
        <div class="space-y-3 text-sm text-base-content/70">
          <div class="flex items-start gap-3">
            <span class="text-primary/80 font-mono font-bold shrink-0">1</span>
            <span>
              Create a team from a template (web) or
              <.code_inline>teamrc init</.code_inline>
              (CLI)
            </span>
          </div>
          <div class="flex items-start gap-3">
            <span class="text-primary/80 font-mono font-bold shrink-0">2</span>
            <span>Add or tweak members and skills on the dashboard</span>
          </div>
          <div class="flex items-start gap-3">
            <span class="text-primary/80 font-mono font-bold shrink-0">3</span>
            <span>
              Run
              <.code_inline>teamrc pull</.code_inline>
              on your machine to apply changes
            </span>
          </div>
          <div class="flex items-start gap-3">
            <span class="text-primary/80 font-mono font-bold shrink-0">4</span>
            <span>Share the invite code to connect more machines or people</span>
          </div>
          <div class="flex items-start gap-3">
            <span class="text-primary/80 font-mono font-bold shrink-0">5</span>
            <span>
              Keep editing. Run
              <.code_inline>teamrc sync</.code_inline>
              whenever you want the latest
            </span>
          </div>
        </div>
      </div>
    </section>
    """
  end

  # Mockup components for web UI guide

  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :desc, :string, required: true
  attr :agents, :list, required: true
  attr :highlighted, :boolean, default: false

  defp mock_template_card(assigns) do
    ~H"""
    <div class={[
      "rounded-lg border p-3 flex items-center gap-3 transition-colors",
      if(@highlighted,
        do: "border-primary/30 bg-primary/5",
        else: "border-base-300 hover:border-primary/20"
      )
    ]}>
      <div class={[
        "w-8 h-8 rounded-md flex items-center justify-center shrink-0",
        if(@highlighted, do: "bg-primary/10", else: "bg-base-200")
      ]}>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          class={["h-4 w-4", if(@highlighted, do: "text-primary/80", else: "text-base-content/50")]}
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M17.25 6.75 22.5 12l-5.25 5.25m-10.5 0L1.5 12l5.25-5.25m7.5-3-4.5 16.5"
          />
        </svg>
      </div>
      <div class="flex-1 min-w-0">
        <div class="flex items-center gap-2">
          <p class="text-xs font-semibold">{@label}</p>
          <span class="text-[10px] font-mono text-base-content/50">{length(@agents)} agents</span>
        </div>
        <p class="text-[10px] text-base-content/60 mt-0.5">{@desc}</p>
        <div class="flex gap-1 mt-1">
          <span
            :for={name <- @agents}
            class="inline-flex rounded bg-base-200 px-1.5 py-0.5 text-[9px] font-mono text-base-content/60"
          >
            {name}
          </span>
        </div>
      </div>
      <svg
        xmlns="http://www.w3.org/2000/svg"
        class="h-4 w-4 text-base-content/50 shrink-0"
        fill="none"
        viewBox="0 0 24 24"
        stroke-width="1.5"
        stroke="currentColor"
      >
        <path stroke-linecap="round" stroke-linejoin="round" d="m8.25 4.5 7.5 7.5-7.5 7.5" />
      </svg>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :role, :string, required: true
  attr :skills, :list, default: []

  defp mock_member_card(assigns) do
    ~H"""
    <div class="rounded-lg border border-base-300 p-2.5 flex items-center gap-2.5 hover:border-primary/20 transition-colors cursor-pointer">
      <div class="flex-1 min-w-0">
        <p class="text-xs font-mono font-semibold">{@name}</p>
        <p class="text-[10px] text-base-content/60 mt-0.5">{@role}</p>
        <div :if={@skills != []} class="flex gap-1 mt-1">
          <span
            :for={s <- @skills}
            class="inline-flex rounded bg-base-200 px-1.5 py-0.5 text-[9px] font-mono text-base-content/60"
          >
            {s}
          </span>
        </div>
      </div>
      <svg
        xmlns="http://www.w3.org/2000/svg"
        class="h-3.5 w-3.5 text-base-content/50 shrink-0"
        fill="none"
        viewBox="0 0 24 24"
        stroke-width="1.5"
        stroke="currentColor"
      >
        <path stroke-linecap="round" stroke-linejoin="round" d="m8.25 4.5 7.5 7.5-7.5 7.5" />
      </svg>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, default: nil
  attr :always_apply, :boolean, default: false

  defp mock_skill_card(assigns) do
    ~H"""
    <div class="rounded-lg border border-base-300 p-2.5 flex items-center gap-2.5">
      <div class="flex-1 min-w-0">
        <div class="flex items-center gap-2">
          <p class="text-xs font-mono font-semibold">{@id}</p>
          <span
            :if={@always_apply}
            class="text-[9px] font-mono text-primary/80 bg-primary/10 rounded px-1.5 py-0.5"
          >
            all agents
          </span>
        </div>
        <p :if={@title} class="text-[10px] text-base-content/60 mt-0.5">{@title}</p>
      </div>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :role, :string, required: true
  attr :highlighted, :boolean, default: false

  defp mock_catalog_agent(assigns) do
    ~H"""
    <div class={[
      "rounded border p-2 text-left transition-colors cursor-pointer",
      if(@highlighted,
        do: "border-primary/30 bg-primary/5",
        else: "border-base-300 hover:border-primary/20"
      )
    ]}>
      <p class="text-[10px] font-mono font-semibold">{@name}</p>
      <p class="text-[9px] text-base-content/60 mt-0.5">{@role}</p>
    </div>
    """
  end

  # ===========================================================================
  # Page: Configuration
  # ===========================================================================

  @yaml_full """
  version: 1
  name: my-project

  # Optional: link to a relay team
  teamId: team_abc123
  relay: https://relay.teamrc.dev
  platforms:
    - claude-code
    - cursor

  members:
    - name: frontend
      role: Frontend development
      soul: |
        You are the frontend specialist...
      skills:
        - code-style
        - testing

    - name: reviewer
      role: Code review
      skills:
        - code-review

  skills:
    - id: code-style
      title: Code Style Guide
      alwaysApply: true
      body: |
        Follow the project's existing patterns.
        Use TypeScript strict mode.

    - id: testing
      title: Testing Requirements
      globs:
        - "*.test.ts"
        - "*.spec.ts"
      body: |
        Write tests for all new functions.

    - id: code-review
      title: Code Review
      body: |
        Review for correctness, readability,
        and security vulnerabilities.
  """

  defp page_config(assigns) do
    assigns = assign(assigns, yaml_full: @yaml_full)

    ~H"""
    <div>
      <h1 class="text-2xl font-bold tracking-tight mb-1">Configuration</h1>
      <p class="text-sm text-base-content/60">
        Everything lives in one YAML file. Here's every field and option.
      </p>
    </div>

    <.page_toc items={[
      {"#teamrc-yaml", ".teamrc.yaml"},
      {"#top-level", "Top-level fields"},
      {"#member-fields", "Member fields"},
      {"#skill-fields", "Skill fields"},
      {"#global-config", "Global config"},
      {"#scopes", "Project vs global"},
      {"#env-vars", "Environment variables"},
      {"#validation", "Validation limits"}
    ]} />

    <%!-- .teamrc.yaml --%>
    <section class="space-y-3">
      <.section_heading id="teamrc-yaml" title="The .teamrc.yaml file" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        This is your team definition. It lives in your project root and describes your entire team.
        You can edit it directly, or let the web UI and CLI manage it.
        Here's a complete example:
      </p>

      <.terminal_block title=".teamrc.yaml">
        <pre class="text-sm font-mono text-emerald-400 leading-relaxed"><%= @yaml_full %></pre>
      </.terminal_block>
    </section>

    <%!-- Top-level fields --%>
    <section class="space-y-3">
      <.section_heading id="top-level" title="Top-level fields" />
      <div class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-3 text-sm">
        <div class="flex items-start gap-3">
          <.code_inline>version</.code_inline>
          <span class="text-base-content/70">
            Always <.code_inline>1</.code_inline>. Reserved for future schema changes.
          </span>
        </div>
        <div class="flex items-start gap-3">
          <.code_inline>name</.code_inline>
          <span class="text-base-content/70">
            Your team name. 1-64 characters, alphanumeric with spaces, hyphens, and underscores.
          </span>
        </div>
        <div class="flex items-start gap-3">
          <.code_inline>teamId</.code_inline>
          <span class="text-base-content/70">
            Optional. The relay team ID. Set automatically by
            <.code_inline>init</.code_inline>
            and <.code_inline>join</.code_inline>.
          </span>
        </div>
        <div class="flex items-start gap-3">
          <.code_inline>relay</.code_inline>
          <span class="text-base-content/70">
            Optional. Relay server URL. Defaults to the URL in <.code_inline>~/.teamrc/config.json</.code_inline>.
          </span>
        </div>
        <div class="flex items-start gap-3">
          <.code_inline>platforms</.code_inline>
          <span class="text-base-content/70">
            Optional. List of platforms to target. If omitted, all detected platforms are used.
          </span>
        </div>
        <div class="flex items-start gap-3">
          <.code_inline>members</.code_inline>
          <span class="text-base-content/70">List of team members (see below).</span>
        </div>
        <div class="flex items-start gap-3">
          <.code_inline>skills</.code_inline>
          <span class="text-base-content/70">List of team skills (see below).</span>
        </div>
      </div>
    </section>

    <%!-- Member fields --%>
    <section class="space-y-3">
      <.section_heading id="member-fields" title="Member fields" />
      <div class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-3 text-sm">
        <div class="flex items-start gap-3">
          <.code_inline>name</.code_inline>
          <span class="text-base-content/70">
            Required. Lowercase, hyphenated identifier. Used as the filename (e.g. <.code_inline>trc-frontend.md</.code_inline>).
          </span>
        </div>
        <div class="flex items-start gap-3">
          <.code_inline>role</.code_inline>
          <span class="text-base-content/70">
            Required. One-line description of what the agent does.
          </span>
        </div>
        <div class="flex items-start gap-3">
          <.code_inline>soul</.code_inline>
          <span class="text-base-content/70">
            Optional. Markdown instructions that define the agent's identity and behavior.
          </span>
        </div>
        <div class="flex items-start gap-3">
          <.code_inline>skills</.code_inline>
          <span class="text-base-content/70">
            Optional. List of skill IDs to assign to this member. Must reference skills defined at the team level.
          </span>
        </div>
      </div>
    </section>

    <%!-- Skill fields --%>
    <section class="space-y-3">
      <.section_heading id="skill-fields" title="Skill fields" />
      <div class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-3 text-sm">
        <div class="flex items-start gap-3">
          <.code_inline>id</.code_inline>
          <span class="text-base-content/70">Required. Unique identifier. Used as a filename.</span>
        </div>
        <div class="flex items-start gap-3">
          <.code_inline>title</.code_inline>
          <span class="text-base-content/70">Optional. Human-readable label.</span>
        </div>
        <div class="flex items-start gap-3">
          <.code_inline>description</.code_inline>
          <span class="text-base-content/70">
            Optional. Short explanation of what the skill does.
          </span>
        </div>
        <div class="flex items-start gap-3">
          <.code_inline>body</.code_inline>
          <span class="text-base-content/70">
            Required. The instructions, written in markdown. You can also reference an external file with a source path.
          </span>
        </div>
        <div class="flex items-start gap-3">
          <.code_inline>alwaysApply</.code_inline>
          <span class="text-base-content/70">
            Optional boolean. When true, applies to all agents automatically.
          </span>
        </div>
        <div class="flex items-start gap-3">
          <.code_inline>globs</.code_inline>
          <span class="text-base-content/70">
            Optional list of file patterns. The skill activates only for matching files.
          </span>
        </div>
      </div>
    </section>

    <%!-- Global config --%>
    <section class="space-y-3">
      <.section_heading id="global-config" title="Global config (~/.teamrc/)" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        The
        <.code_inline>~/.teamrc/</.code_inline>
        directory stores machine-level configuration:
      </p>
      <div class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-2 text-xs font-mono text-base-content/70">
        <div class="flex items-start gap-3">
          <span class="text-base-content/50 shrink-0 w-28 text-right">key</span>
          <span>Ed25519 keypair (JSON, mode 0600)</span>
        </div>
        <div class="flex items-start gap-3">
          <span class="text-base-content/50 shrink-0 w-28 text-right">config.json</span>
          <span>Token, relay URL, account email, machine name</span>
        </div>
        <div class="flex items-start gap-3">
          <span class="text-base-content/50 shrink-0 w-28 text-right">team.yaml</span>
          <span>Global team definition (when using --global scope)</span>
        </div>
      </div>
    </section>

    <%!-- Scopes --%>
    <section class="space-y-3">
      <.section_heading id="scopes" title="Project vs global scope" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        Teams can be scoped to a <span class="font-semibold">project</span>
        (default) or <span class="font-semibold">global</span>.
      </p>
      <div class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-3 text-sm">
        <div class="flex items-start gap-3">
          <span class="font-semibold shrink-0 w-16">Project</span>
          <span class="text-base-content/70">
            <.code_inline>.teamrc.yaml</.code_inline>
            in the project root. Config files written to the project directory.
            This is the default for most workflows.
          </span>
        </div>
        <div class="flex items-start gap-3">
          <span class="font-semibold shrink-0 w-16">Global</span>
          <span class="text-base-content/70">
            <.code_inline>~/.teamrc/team.yaml</.code_inline>. Config files written to global platform directories
            (e.g. <.code_inline>~/.claude/agents/</.code_inline>). Applies to all projects on the machine.
            Use
            <.code_inline>--global</.code_inline>
            flag.
          </span>
        </div>
      </div>
      <p class="text-sm text-base-content/70 leading-relaxed">
        Project scope takes precedence when both exist. The CLI resolves scope automatically:
        if
        <.code_inline>.teamrc.yaml</.code_inline>
        exists in the current directory, it uses project scope.
      </p>
    </section>

    <%!-- Environment variables --%>
    <section class="space-y-3">
      <.section_heading id="env-vars" title="Environment variables" />
      <div class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-2 text-sm">
        <div class="flex items-start gap-3">
          <.code_inline>TEAMRC_RELAY</.code_inline>
          <span class="text-base-content/70">
            Override the relay server URL. Takes precedence over config.json and .teamrc.yaml.
          </span>
        </div>
      </div>
    </section>

    <%!-- Validation --%>
    <section class="space-y-3">
      <.section_heading id="validation" title="Validation limits" />
      <p class="text-sm text-base-content/70 leading-relaxed">
        The relay enforces these limits for the web UI and sync endpoints:
      </p>
      <div class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-1.5 text-xs text-base-content/70">
        <div class="flex items-center gap-3">
          <span class="text-base-content/50 shrink-0 w-32 text-right">Team name</span>
          <span>1-64 chars, alphanumeric + spaces/hyphens/underscores</span>
        </div>
        <div class="flex items-center gap-3">
          <span class="text-base-content/50 shrink-0 w-32 text-right">Agent name</span>
          <span>1-64 chars, alphanumeric + hyphens/underscores</span>
        </div>
        <div class="flex items-center gap-3">
          <span class="text-base-content/50 shrink-0 w-32 text-right">Max members</span>
          <span>20 per team</span>
        </div>
        <div class="flex items-center gap-3">
          <span class="text-base-content/50 shrink-0 w-32 text-right">Max skills</span>
          <span>50 per team</span>
        </div>
        <div class="flex items-center gap-3">
          <span class="text-base-content/50 shrink-0 w-32 text-right">YAML size</span>
          <span>256 KB max</span>
        </div>
        <div class="flex items-center gap-3">
          <span class="text-base-content/50 shrink-0 w-32 text-right">Knowledge</span>
          <span>100,000 bytes max</span>
        </div>
        <div class="flex items-center gap-3">
          <span class="text-base-content/50 shrink-0 w-32 text-right">Skill body</span>
          <span>10,000 bytes max per inline body</span>
        </div>
      </div>
      <p class="text-sm text-base-content/70 leading-relaxed">
        The local CLI can accept larger YAML files in some cases. But anything sent to the relay
        must fit within these limits.
      </p>
    </section>
    """
  end

  # ===========================================================================
  # Page: FAQ
  # ===========================================================================

  defp page_faq(assigns) do
    ~H"""
    <div>
      <h1 class="text-2xl font-bold tracking-tight mb-1">FAQ</h1>
      <p class="text-sm text-base-content/60">
        Common questions. If yours is not listed here, reach out.
      </p>
    </div>

    <div class="space-y-4">
      <.faq_item question="Why not just use Git for this?">
        <p class="text-sm text-base-content/70 leading-relaxed">
          Teams and repos are different things. Different people on the same project might use
          different teams. One developer uses a fullstack team while another uses a
          research team. You might also want the same team across multiple repos. Or agents on
          different platforms (for example, an OpenClaw research team alongside Claude Code developers)
          working in parallel on the same codebase.
        </p>
        <p class="text-sm text-base-content/70 leading-relaxed mt-2">
          Git cannot model any of this. It also means committing platform-specific config files
          (<.code_inline>.claude/agents/*.md</.code_inline>, <.code_inline>.cursor/agents/*.mdc</.code_inline>, <.code_inline>codex.md</.code_inline>, etc.)
          into your repo. That pollutes version history with files that are not source code.
          teamrc generates them locally from a single definition and keeps them out of version control.
        </p>
      </.faq_item>

      <.faq_item question="How does syncing work?">
        <p class="text-sm text-base-content/70 leading-relaxed">
          Your team's source of truth lives on the teamrc relay (a hosted server).
          When you run <.code_inline>teamrc sync</.code_inline>,
          the CLI pushes your local state, pulls the latest from the relay, merges knowledge,
          and regenerates platform config files.
          There is no merge for the team definition. Last write wins. This keeps things
          simple and predictable.
          See the <a href="/guide/sync" class="text-primary/80 hover:text-primary">Syncing page</a>
          for full details.
        </p>
      </.faq_item>

      <.faq_item question="Do I need an account?">
        <p class="text-sm text-base-content/70 leading-relaxed">
          No.
          <.code_inline>teamrc init</.code_inline>
          and
          <.code_inline>teamrc join</.code_inline>
          work without any signup.
          Each machine gets an ed25519 keypair automatically. You can optionally link an account later
          for recovery and machine management via <.code_inline>teamrc login</.code_inline>.
        </p>
      </.faq_item>

      <.faq_item question="What happens if two machines push conflicting changes?">
        <p class="text-sm text-base-content/70 leading-relaxed">
          Last write wins. teamrc does not do three-way merges. The relay always stores the most recent
          version. Agent config is declarative and small, so conflicts
          are rare and easy to resolve. To see what changed, use
          <.code_inline>teamrc diff</.code_inline>
          to compare your local state against the relay.
        </p>
        <p class="text-sm text-base-content/70 leading-relaxed mt-2">
          Knowledge is the exception. It uses append-only deduplication, so knowledge from
          different machines is always combined, never overwritten.
        </p>
      </.faq_item>

      <.faq_item question="Which platforms are supported?">
        <p class="text-sm text-base-content/70 leading-relaxed">
          Claude Code, Cursor, Codex, Gemini, and OpenClaw are fully supported. Each has an adapter that
          writes config in the platform's native format. The CLI auto-detects installed platforms
          and generates files for all of them. GitHub Copilot, Amazon Q, Windsurf, and Cline are planned.
          See the
          <a href="/guide/platforms" class="text-primary/80 hover:text-primary">Platforms page</a>
          for details on each.
        </p>
      </.faq_item>

      <.faq_item question="Can I use teamrc across multiple projects?">
        <p class="text-sm text-base-content/70 leading-relaxed">
          Yes. A single team can be joined from multiple projects on the same machine or across
          different machines. Run
          <.code_inline>teamrc join &lt;invite-code&gt;</.code_inline>
          in each project directory. Each project gets its own generated config files but shares the same
          team definition. Changes sync across all of them.
        </p>
      </.faq_item>

      <.faq_item question="Can different people on the same project use different teams?">
        <p class="text-sm text-base-content/70 leading-relaxed">
          Yes. Teams are per-machine, not per-repo. One developer might use a fullstack team with
          frontend and backend agents, while another uses a research team with specialized analysis agents.
          They work in the same codebase but with different AI configurations. Each person runs
          <.code_inline>teamrc init</.code_inline>
          or
          <.code_inline>teamrc join</.code_inline>
          independently.
        </p>
      </.faq_item>

      <.faq_item question="Can I mix platforms on the same team?">
        <p class="text-sm text-base-content/70 leading-relaxed">
          Yes, that's the point. One machine might use Claude Code and Cursor, while another uses Gemini and OpenClaw.
          The team definition is the same. teamrc generates the right files for whatever platforms
          are detected on each machine. You can also restrict platforms per machine with the
          <.code_inline>--platform</.code_inline>
          flag or the
          <.code_inline>platforms</.code_inline>
          field in your YAML.
        </p>
      </.faq_item>

      <.faq_item question="What's the difference between instructions and skills?">
        <p class="text-sm text-base-content/70 leading-relaxed">
          <span class="font-semibold">Instructions</span>
          are unique to one agent. They define
          that agent's identity, personality, and specific directives.
          <span class="font-semibold">Skills</span>
          are reusable blocks defined at the team level and
          assigned to one or more agents. Use instructions for "who this agent is" and skills for
          "what rules this agent follows."
          See
          <a href="/guide/concepts#instructions" class="text-primary/80 hover:text-primary">
            Core Concepts
          </a>
          for more.
        </p>
      </.faq_item>

      <.faq_item question="Is my team config stored securely?">
        <p class="text-sm text-base-content/70 leading-relaxed">
          All requests to the relay are authenticated with ed25519 signatures. Only machines
          with valid tokens (from
          <.code_inline>init</.code_inline>
          or <.code_inline>join</.code_inline>) can access your team's data.
          The relay stores your team configuration. It does not store source code or anything
          beyond what's in your <.code_inline>.teamrc.yaml</.code_inline>.
          See <a href="/guide/sync#auth" class="text-primary/80 hover:text-primary">Authentication</a>
          for details.
        </p>
      </.faq_item>

      <.faq_item question="What's the difference between public and private teams?">
        <p class="text-sm text-base-content/70 leading-relaxed">
          <span class="font-semibold">Private</span> teams (the default) are only visible to
          authenticated participants. If someone visits the team page URL without access, they see
          a "This team is private" message. <span class="font-semibold">Public</span> teams can be
          viewed by anyone with the link. Visitors see a read-only view of the team config (members,
          skills, knowledge) and can clone it. They still cannot edit anything or see invites.
        </p>
        <p class="text-sm text-base-content/70 leading-relaxed mt-2">
          You can toggle visibility on the team dashboard at any time. Making a team public also
          generates a clone token that anyone can use to copy the config.
          See the
          <a href="/guide/web-ui#visibility" class="text-primary/80 hover:text-primary">
            Visibility section
          </a>
          for more.
        </p>
      </.faq_item>

      <.faq_item question="What's the difference between cloning and joining?">
        <p class="text-sm text-base-content/70 leading-relaxed">
          <span class="font-semibold">Cloning</span>
          (<.code_inline>teamrc clone trc_cl_...</.code_inline>)
          copies the current team config as a one-time snapshot. You get the YAML and generated files,
          but there is no ongoing connection to the original team. Clone tokens do not expire.
        </p>
        <p class="text-sm text-base-content/70 leading-relaxed mt-2">
          <span class="font-semibold">Joining</span>
          (<.code_inline>teamrc join trc_inv_...</.code_inline>)
          creates an ongoing sync connection. Your machine becomes a participant and receives updates
          whenever the team changes. You can also push changes back. Invite codes expire after 24 hours.
        </p>
        <p class="text-sm text-base-content/70 leading-relaxed mt-2">
          Use clone to try out someone's setup or use it as a starting point for your own team.
          Use join when you want to stay in sync with collaborators.
        </p>
      </.faq_item>

      <.faq_item question="Can someone see my machine name?">
        <p class="text-sm text-base-content/70 leading-relaxed">
          No. Your machines are only visible to you, on your personal dashboard
          (<.code_inline>/dashboard</.code_inline>). Other participants cannot see your machine names,
          hostnames, or tokens. Machine names come from your computer's hostname and are only shared
          when you run <.code_inline>teamrc login</.code_inline>. The CLI warns you before sending it.
        </p>
      </.faq_item>

      <.faq_item question="What if I lose my keypair?">
        <p class="text-sm text-base-content/70 leading-relaxed">
          Without a linked account, you need a new invite code from someone who still
          has access to the team. If you have linked an account (via <.code_inline>teamrc login</.code_inline>),
          you can manage your machines from the web dashboard and recover access.
        </p>
      </.faq_item>

      <.faq_item question="Can I edit .teamrc.yaml directly instead of using the web UI?">
        <p class="text-sm text-base-content/70 leading-relaxed">
          Yes. The YAML file is the source of truth. Edit it with any text editor, then run
          <.code_inline>teamrc push</.code_inline>
          to send changes to the relay and
          <.code_inline>teamrc apply</.code_inline>
          to regenerate local platform files.
          Or use
          <.code_inline>teamrc sync</.code_inline>
          to do both.
        </p>
      </.faq_item>

      <.faq_item question="What does the daemon do?">
        <p class="text-sm text-base-content/70 leading-relaxed">
          <.code_inline>teamrc daemon</.code_inline>
          runs a background process that polls the relay for changes (every 2 minutes by default) and watches your
          <.code_inline>.teamrc.yaml</.code_inline>
          for local edits. When anything changes,
          it regenerates platform config files. This saves you from running
          <.code_inline>teamrc sync</.code_inline>
          manually.
          See <a href="/guide/sync#daemon" class="text-primary/80 hover:text-primary">Daemon mode</a>
          for details.
        </p>
      </.faq_item>

      <.faq_item question="How big can my team be?">
        <p class="text-sm text-base-content/70 leading-relaxed">
          When syncing through the relay, teams are currently limited to 20 members and 50 skills.
          The request payload is capped at 256 KB, knowledge at 100,000 bytes, and inline skill bodies
          at 10,000 bytes. Most teams have 3-8 members and 10-20 skills, so you're unlikely to hit these.
        </p>
      </.faq_item>

      <.faq_item question="Can I use teamrc without the relay (offline only)?">
        <p class="text-sm text-base-content/70 leading-relaxed">
          Partially. You can write a
          <.code_inline>.teamrc.yaml</.code_inline>
          and run
          <.code_inline>teamrc apply</.code_inline>
          to generate platform files without ever
          connecting to the relay. But syncing, invites, and multi-machine support require the relay.
          You can also use
          <.code_inline>teamrc clone</.code_inline>
          to grab a one-time copy of a
          team without staying connected.
        </p>
      </.faq_item>
    </div>
    """
  end

  attr :question, :string, required: true
  slot :inner_block, required: true

  defp faq_item(assigns) do
    ~H"""
    <div class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-2">
      <p class="text-sm font-semibold">{@question}</p>
      {render_slot(@inner_block)}
    </div>
    """
  end
end
