defmodule TeamrcWeb.GuideLive do
  use TeamrcWeb, :live_view

  @yaml_example """
  version: 1
  name: my-project

  members:
    - name: frontend
      role: Frontend development
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
      body: |
        Follow the project's existing patterns...
  """

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Guide", yaml_example: @yaml_example)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-12">
      <%!-- Header --%>
      <div>
        <p class="text-sm font-medium text-primary/70 mb-2">How it works</p>
        <h1 class="text-2xl font-bold tracking-tight mb-1">teamrc Guide</h1>
        <p class="text-sm text-base-content/50">
          Everything you need to know about setting up and managing your agent team.
        </p>
      </div>

      <%!-- Table of contents --%>
      <nav class="rounded-lg border border-base-300 bg-base-200/20 p-4">
        <p class="text-[10px] font-medium text-base-content/40 uppercase tracking-wider mb-2">On this page</p>
        <ol class="space-y-1 text-sm">
          <li><a href="#overview" class="text-primary/80 hover:text-primary transition-colors">What is teamrc?</a></li>
          <li><a href="#members" class="text-primary/80 hover:text-primary transition-colors">Members</a></li>
          <li><a href="#skills" class="text-primary/80 hover:text-primary transition-colors">Skills</a></li>
          <li><a href="#instructions" class="text-primary/80 hover:text-primary transition-colors">Instructions</a></li>
          <li><a href="#knowledge" class="text-primary/80 hover:text-primary transition-colors">Knowledge</a></li>
          <li><a href="#sync" class="text-primary/80 hover:text-primary transition-colors">How syncing works</a></li>
          <li><a href="#teamrc-yaml" class="text-primary/80 hover:text-primary transition-colors">The .teamrc.yaml file</a></li>
        </ol>
      </nav>

      <%!-- Overview --%>
      <section id="overview" class="scroll-mt-20 space-y-3">
        <h2 class="text-lg font-bold tracking-tight">What is teamrc?</h2>
        <p class="text-sm text-base-content/70 leading-relaxed">
          teamrc keeps your AI coding agents in sync across every platform you use &mdash;
          Claude Code, Cursor, Codex, Gemini, and more. Define your team once, and teamrc
          generates the right configuration files for each platform automatically.
        </p>
        <p class="text-sm text-base-content/70 leading-relaxed">
          The <span class="font-semibold">CLI</span> is the primary interface. You use it to create teams,
          join existing ones, and sync changes. The <span class="font-semibold">web UI</span> (what you're looking at)
          is for team setup, onboarding, and management &mdash; it supports the CLI, not the other way around.
        </p>
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
              <code class="text-emerald-400 text-sm font-mono">npx teamrc init</code>
              <span class="text-white/20 text-sm font-mono ml-2"># create a new team</span>
            </div>
            <div class="flex items-start gap-2">
              <span class="text-white/30 font-mono text-sm select-none">$</span>
              <code class="text-emerald-400 text-sm font-mono">npx teamrc join &lt;invite-code&gt;</code>
              <span class="text-white/20 text-sm font-mono ml-2"># join an existing team</span>
            </div>
            <div class="flex items-start gap-2">
              <span class="text-white/30 font-mono text-sm select-none">$</span>
              <code class="text-emerald-400 text-sm font-mono">npx teamrc sync</code>
              <span class="text-white/20 text-sm font-mono ml-2"># pull + apply latest config</span>
            </div>
          </div>
        </div>
      </section>

      <%!-- Members --%>
      <section id="members" class="scroll-mt-20 space-y-3">
        <h2 class="text-lg font-bold tracking-tight">Members</h2>
        <p class="text-sm text-base-content/70 leading-relaxed">
          Members are the AI agents on your team. Each member has a <span class="font-semibold">name</span>
          (a short identifier like <code class="font-mono bg-base-200 rounded px-1.5 py-0.5 text-xs">frontend</code> or
          <code class="font-mono bg-base-200 rounded px-1.5 py-0.5 text-xs">reviewer</code>),
          a <span class="font-semibold">role</span> description, and optional
          <span class="font-semibold">instructions</span>.
        </p>
        <p class="text-sm text-base-content/70 leading-relaxed">
          When you sync, teamrc creates a configuration file for each member on each platform.
          For example, a member named <code class="font-mono bg-base-200 rounded px-1.5 py-0.5 text-xs">frontend</code>
          becomes <code class="font-mono bg-base-200 rounded px-1.5 py-0.5 text-xs">.claude/agents/trc-frontend.md</code>
          in Claude Code, and a matching agent file in Cursor, Codex, etc.
        </p>
        <div class="rounded-lg border border-base-300 bg-base-100 p-4">
          <p class="text-[10px] font-medium text-base-content/40 uppercase tracking-wider mb-2">Example member</p>
          <div class="space-y-1.5 text-sm">
            <div class="flex items-center gap-3">
              <span class="text-base-content/40 w-16 text-xs text-right shrink-0">Name</span>
              <span class="font-mono font-medium">reviewer</span>
            </div>
            <div class="flex items-center gap-3">
              <span class="text-base-content/40 w-16 text-xs text-right shrink-0">Role</span>
              <span class="text-base-content/70">Code review and quality assurance</span>
            </div>
            <div class="flex items-start gap-3">
              <span class="text-base-content/40 w-16 text-xs text-right shrink-0 mt-0.5">Skills</span>
              <div class="flex gap-1">
                <span class="inline-flex items-center rounded bg-base-200 px-1.5 py-0.5 text-[10px] font-mono text-base-content/50">code-review</span>
                <span class="inline-flex items-center rounded bg-base-200 px-1.5 py-0.5 text-[10px] font-mono text-base-content/50">testing</span>
              </div>
            </div>
          </div>
        </div>
      </section>

      <%!-- Skills --%>
      <section id="skills" class="scroll-mt-20 space-y-3">
        <h2 class="text-lg font-bold tracking-tight">Skills</h2>
        <p class="text-sm text-base-content/70 leading-relaxed">
          Skills are <span class="font-semibold">reusable instruction blocks</span> that you define at the team level
          and assign to individual agents. Think of them as shared rules or guidelines &mdash;
          like "always write tests" or "follow our code style guide" &mdash; that multiple agents can use.
        </p>

        <div class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-3">
          <p class="text-[10px] font-medium text-base-content/40 uppercase tracking-wider">Skill properties</p>
          <div class="space-y-2 text-sm">
            <div class="flex items-start gap-3">
              <code class="font-mono text-xs bg-base-200 rounded px-1.5 py-0.5 shrink-0 mt-0.5">id</code>
              <span class="text-base-content/70">A unique identifier like <code class="font-mono bg-base-200 rounded px-1 py-0.5 text-xs">code-review</code>. Used as a filename and reference.</span>
            </div>
            <div class="flex items-start gap-3">
              <code class="font-mono text-xs bg-base-200 rounded px-1.5 py-0.5 shrink-0 mt-0.5">title</code>
              <span class="text-base-content/70">A human-readable label. Optional.</span>
            </div>
            <div class="flex items-start gap-3">
              <code class="font-mono text-xs bg-base-200 rounded px-1.5 py-0.5 shrink-0 mt-0.5">body</code>
              <span class="text-base-content/70">The actual instructions, written in markdown. This is what gets injected into agent config files.</span>
            </div>
            <div class="flex items-start gap-3">
              <code class="font-mono text-xs bg-base-200 rounded px-1.5 py-0.5 shrink-0 mt-0.5">alwaysApply</code>
              <span class="text-base-content/70">
                When enabled, the skill is automatically included for <span class="font-semibold">every agent</span> on the team.
                You don't need to assign it individually. Use this for team-wide rules like style guides or security policies.
              </span>
            </div>
          </div>
        </div>

        <div class="rounded-lg border border-primary/20 bg-primary/5 p-4 space-y-2">
          <p class="text-xs font-semibold text-primary/80">How assignment works</p>
          <ul class="text-sm text-base-content/70 space-y-1.5 list-disc list-inside">
            <li>Skills are defined on the <span class="font-semibold">team dashboard</span> (shared by all agents)</li>
            <li>By default, a skill must be explicitly assigned to each agent on their <span class="font-semibold">detail page</span></li>
            <li>Enable <span class="font-semibold font-mono text-xs">alwaysApply</span> to skip assignment &mdash; the skill applies to everyone automatically</li>
            <li>You can choose from <span class="font-semibold">pre-built skills</span> in our catalog or write your own</li>
          </ul>
        </div>
      </section>

      <%!-- Instructions --%>
      <section id="instructions" class="scroll-mt-20 space-y-3">
        <h2 class="text-lg font-bold tracking-tight">Instructions</h2>
        <p class="text-sm text-base-content/70 leading-relaxed">
          Each agent has an <span class="font-semibold">instructions</span> field (sometimes called "soul") &mdash;
          a free-form markdown block that defines the agent's personality, behavioral guidelines, and specific directives.
          This is the agent's core identity beyond its name and role.
        </p>
        <p class="text-sm text-base-content/70 leading-relaxed">
          Instructions are different from skills: instructions are <span class="font-semibold">unique to one agent</span>,
          while skills are <span class="font-semibold">shared across agents</span>. Use instructions for things like
          "you are the frontend specialist, always consider accessibility" and skills for team-wide rules like
          "follow our commit message format."
        </p>
        <div class="rounded-lg border border-base-300 bg-base-200/30 p-4">
          <p class="text-[10px] font-medium text-base-content/40 uppercase tracking-wider mb-2">Example instructions</p>
          <pre class="text-xs font-mono text-base-content/60 leading-relaxed whitespace-pre-wrap"><%= "You are the frontend specialist for this project.\n\nWhen making changes:\n- Always consider accessibility (WCAG AA)\n- Prefer CSS-only solutions over JavaScript when possible\n- Write component tests for new UI elements\n- Follow the existing component patterns in src/components/" %></pre>
        </div>
      </section>

      <%!-- Knowledge --%>
      <section id="knowledge" class="scroll-mt-20 space-y-3">
        <h2 class="text-lg font-bold tracking-tight">Knowledge</h2>
        <p class="text-sm text-base-content/70 leading-relaxed">
          Knowledge is a <span class="font-semibold">shared document</span> that every agent on the team can read.
          It's designed for accumulated context &mdash; architecture decisions, debugging insights, project-specific
          gotchas &mdash; that agents discover while working and want to share with the rest of the team.
        </p>
        <p class="text-sm text-base-content/70 leading-relaxed">
          Knowledge is managed via the CLI and synced automatically. Agents can append to it during their work sessions,
          building up a shared understanding of the codebase over time.
        </p>
      </section>

      <%!-- Sync --%>
      <section id="sync" class="scroll-mt-20 space-y-3">
        <h2 class="text-lg font-bold tracking-tight">How syncing works</h2>
        <p class="text-sm text-base-content/70 leading-relaxed">
          teamrc uses a <span class="font-semibold">relay server</span> to keep all your machines in sync.
          When you run <code class="font-mono bg-base-200 rounded px-1.5 py-0.5 text-xs">teamrc sync</code>, the CLI:
        </p>
        <ol class="text-sm text-base-content/70 space-y-1.5 list-decimal list-inside">
          <li><span class="font-semibold">Pulls</span> the latest team configuration from the relay</li>
          <li><span class="font-semibold">Applies</span> it to your local platform config files (Claude Code, Cursor, etc.)</li>
          <li><span class="font-semibold">Pushes</span> any local changes (like knowledge updates) back to the relay</li>
        </ol>
        <p class="text-sm text-base-content/70 leading-relaxed">
          Changes made in the web UI are stored on the relay immediately. They take effect on your
          machines the next time you run <code class="font-mono bg-base-200 rounded px-1.5 py-0.5 text-xs">teamrc sync</code>
          or <code class="font-mono bg-base-200 rounded px-1.5 py-0.5 text-xs">teamrc pull</code>.
        </p>
        <div class="rounded-lg border border-base-300 bg-base-100 p-4">
          <p class="text-[10px] font-medium text-base-content/40 uppercase tracking-wider mb-3">Sync flow</p>
          <div class="flex items-center justify-between text-xs text-base-content/60">
            <div class="text-center space-y-1">
              <div class="mx-auto flex h-10 w-10 items-center justify-center rounded-lg bg-base-200">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-base-content/40" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M9 17.25v1.007a3 3 0 0 1-.879 2.122L7.5 21h9l-.621-.621A3 3 0 0 1 15 18.257V17.25m6-12V15a2.25 2.25 0 0 1-2.25 2.25H5.25A2.25 2.25 0 0 1 3 15V5.25m18 0A2.25 2.25 0 0 0 18.75 3H5.25A2.25 2.25 0 0 0 3 5.25m18 0V12a2.25 2.25 0 0 1-2.25 2.25H5.25A2.25 2.25 0 0 1 3 12V5.25" />
                </svg>
              </div>
              <div>Your machine</div>
            </div>
            <div class="flex-1 flex items-center justify-center px-4">
              <div class="w-full border-t border-dashed border-base-300 relative">
                <span class="absolute -top-2.5 left-1/2 -translate-x-1/2 bg-base-100 px-2 text-[10px] text-base-content/30 font-mono">sync</span>
              </div>
            </div>
            <div class="text-center space-y-1">
              <div class="mx-auto flex h-10 w-10 items-center justify-center rounded-lg bg-primary/10">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-primary/60" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M2.25 15a4.5 4.5 0 0 0 4.5 4.5H18a3.75 3.75 0 0 0 1.332-7.257 3 3 0 0 0-3.758-3.848 5.25 5.25 0 0 0-10.233 2.33A4.502 4.502 0 0 0 2.25 15Z" />
                </svg>
              </div>
              <div>Relay</div>
            </div>
            <div class="flex-1 flex items-center justify-center px-4">
              <div class="w-full border-t border-dashed border-base-300 relative">
                <span class="absolute -top-2.5 left-1/2 -translate-x-1/2 bg-base-100 px-2 text-[10px] text-base-content/30 font-mono">sync</span>
              </div>
            </div>
            <div class="text-center space-y-1">
              <div class="mx-auto flex h-10 w-10 items-center justify-center rounded-lg bg-base-200">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-base-content/40" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M9 17.25v1.007a3 3 0 0 1-.879 2.122L7.5 21h9l-.621-.621A3 3 0 0 1 15 18.257V17.25m6-12V15a2.25 2.25 0 0 1-2.25 2.25H5.25A2.25 2.25 0 0 1 3 15V5.25m18 0A2.25 2.25 0 0 0 18.75 3H5.25A2.25 2.25 0 0 0 3 5.25m18 0V12a2.25 2.25 0 0 1-2.25 2.25H5.25A2.25 2.25 0 0 1 3 12V5.25" />
                </svg>
              </div>
              <div>Teammate's machine</div>
            </div>
          </div>
        </div>
      </section>

      <%!-- .teamrc.yaml --%>
      <section id="teamrc-yaml" class="scroll-mt-20 space-y-3">
        <h2 class="text-lg font-bold tracking-tight">The .teamrc.yaml file</h2>
        <p class="text-sm text-base-content/70 leading-relaxed">
          Everything about your team is stored in a single
          <code class="font-mono bg-base-200 rounded px-1.5 py-0.5 text-xs">.teamrc.yaml</code> file in your project root.
          This file is the source of truth &mdash; the web UI and CLI both read from and write to it via the relay.
        </p>
        <p class="text-sm text-base-content/70 leading-relaxed">
          You can also edit this file directly and push changes with
          <code class="font-mono bg-base-200 rounded px-1.5 py-0.5 text-xs">teamrc push</code>. The CLI will validate
          the format and sync it to all connected machines.
        </p>
        <div class="terminal-block rounded-lg overflow-hidden">
          <div class="flex items-center gap-2 px-4 py-2 border-b border-white/5">
            <div class="flex gap-1.5">
              <div class="w-2.5 h-2.5 rounded-full bg-white/10"></div>
              <div class="w-2.5 h-2.5 rounded-full bg-white/10"></div>
              <div class="w-2.5 h-2.5 rounded-full bg-white/10"></div>
            </div>
            <span class="text-[10px] font-mono text-white/25 ml-2">.teamrc.yaml</span>
          </div>
          <pre class="p-4 text-sm font-mono text-emerald-400 leading-relaxed"><%= @yaml_example %></pre>
        </div>
      </section>

      <%!-- Footer CTA --%>
      <div class="rounded-lg border border-base-300 bg-base-200/20 p-6 text-center space-y-3">
        <p class="text-sm text-base-content/60">Ready to get started?</p>
        <div class="flex items-center justify-center gap-3">
          <a
            href={~p"/new"}
            class="trc-focus inline-flex items-center gap-2 rounded-md bg-primary px-4 py-2 text-sm font-semibold text-primary-content hover:brightness-110 transition-all"
          >
            Create a team
          </a>
          <span class="text-xs text-base-content/30">or</span>
          <div class="terminal-block rounded-md px-3 py-1.5">
            <code class="text-emerald-400 text-sm font-mono">npx teamrc init</code>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
