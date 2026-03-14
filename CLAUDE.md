## Design Context

### Users
Developers who use AI coding assistants (Claude Code, Cursor, Codex, Gemini). They interact with teamrc primarily through the CLI, using the web UI mainly for team creation and onboarding. They value tools that feel precise, fast, and stay out of their way.

### Brand Personality
Technical, precise, reliable. teamrc is infrastructure: it should feel well-engineered and predictable, like Linear or Raycast. No flash, just confidence.

### Aesthetic Direction
Clean SaaS dashboard with developer-native accents. Light and spacious for the web wizard flow, with monospace typography on code, commands, and identifiers to signal "dev tool." The CLI is the primary interface. The web UI supports it, not the other way around.

- **Neutrals**: Zinc scale as the base palette
- **Primary accent**: Indigo/blue, conveying trust, infrastructure, reliability. Replaces the Phoenix-inherited orange
- **Light theme**: Clean, high-contrast, professional (light-only, no dark mode)
- **Typography**: System sans-serif for UI, monospace for code/commands/agent names
- **Borders & surfaces**: Subtle, layered. Use zinc-200/zinc-800 borders and slight background shifts rather than heavy shadows

### Design Principles
1. **Clarity over cleverness**: Every element should be immediately understandable. No ambiguous icons, no hidden functionality, no clever-but-confusing interactions.
2. **Code-native feel**: Agent names, commands, tokens, and YAML snippets should look and feel like code. Use monospace, terminal-style blocks, and syntax-aware formatting.
3. **Progressive disclosure**: Show the simple path first (templates, one-click creation), reveal complexity only when needed (advanced rules/skills config).
4. **Trust through consistency**: Same patterns, same spacing, same interaction models everywhere. Predictability builds confidence in infrastructure tools.
5. **Accessible by default**: WCAG AA compliance, sufficient contrast ratios, keyboard navigable. No accessibility as an afterthought.

<!-- teamrc -->
## teamrc Team: marketing-team-haze-0bd6

This project has a synced agent team managed by teamrc.

Members:
- **marketing-lead**  --  Marketing lead
- **copywriter**  --  Copywriter
- **seo-specialist**  --  SEO specialist
- **analytics-lead**  --  Analytics lead

Each member is defined as a subagent in `.claude/agents/`. Delegate tasks to them based on their roles.
<!-- /teamrc -->
