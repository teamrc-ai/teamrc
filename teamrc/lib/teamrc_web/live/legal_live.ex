defmodule TeamrcWeb.LegalLive do
  use TeamrcWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    page = socket.assigns.live_action

    title =
      case page do
        :terms -> "Terms of Service"
        :privacy -> "Privacy Policy"
      end

    {:noreply, assign(socket, page_title: title, current_page: page)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <nav class="flex gap-1 border-b border-base-300 pb-3">
        <a
          href={~p"/terms"}
          class={[
            "trc-focus rounded-md px-2.5 py-1.5 text-xs font-medium transition-colors",
            if(@current_page == :terms,
              do: "bg-primary/10 text-primary",
              else: "text-base-content/40 hover:text-base-content/70 hover:bg-base-200/60"
            )
          ]}
        >
          Terms of Service
        </a>
        <a
          href={~p"/privacy"}
          class={[
            "trc-focus rounded-md px-2.5 py-1.5 text-xs font-medium transition-colors",
            if(@current_page == :privacy,
              do: "bg-primary/10 text-primary",
              else: "text-base-content/40 hover:text-base-content/70 hover:bg-base-200/60"
            )
          ]}
        >
          Privacy Policy
        </a>
      </nav>

      <div class="space-y-10">
        <%= case @current_page do %>
          <% :terms -> %>
            <.page_terms />
          <% :privacy -> %>
            <.page_privacy />
        <% end %>
      </div>
    </div>
    """
  end

  # ===========================================================================
  # Terms of Service
  # ===========================================================================

  defp page_terms(assigns) do
    ~H"""
    <div class="space-y-8">
      <div class="space-y-2">
        <h1 class="text-2xl font-bold tracking-tight">Terms of Service</h1>
        <p class="text-sm text-base-content/50">Last updated: March 9, 2026</p>
      </div>

      <div class="rounded-lg border border-amber-500/30 bg-amber-500/5 px-4 py-3">
        <div class="flex items-start gap-3">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="h-5 w-5 text-amber-500 mt-0.5 shrink-0"
            viewBox="0 0 20 20"
            fill="currentColor"
          >
            <path
              fill-rule="evenodd"
              d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z"
              clip-rule="evenodd"
            />
          </svg>
          <div class="space-y-1">
            <p class="text-sm font-semibold text-amber-500">Experimental Software</p>
            <p class="text-sm text-base-content/70">
              teamrc is experimental software in active development. Features may change, break, or be removed without notice. Data loss is possible. Do not rely on teamrc for production-critical workflows.
            </p>
          </div>
        </div>
      </div>

      <.legal_section title="1. Acceptance of Terms">
        <p>
          By accessing or using teamrc ("the Service"), you agree to be bound by these Terms of Service. If you do not agree, do not use the Service.
        </p>
      </.legal_section>

      <.legal_section title="2. Description of Service">
        <p>
          teamrc is an open-source tool for synchronizing AI coding agent team configurations across platforms. The Service includes the CLI tool, web interface, and relay server.
        </p>
      </.legal_section>

      <.legal_section title="3. Experimental Status">
        <p>The Service is provided on an experimental, as-is basis. You acknowledge that:</p>
        <ul>
          <li>The Service is under active development and may contain bugs</li>
          <li>Features, APIs, and data formats may change without notice</li>
          <li>Service availability is not guaranteed</li>
          <li>Data stored on the relay server may be lost or reset</li>
          <li>There are no uptime guarantees or SLAs</li>
        </ul>
      </.legal_section>

      <.legal_section title="4. User Responsibilities">
        <p>You agree to:</p>
        <ul>
          <li>Use the Service only for lawful purposes</li>
          <li>Not attempt to disrupt or compromise the Service</li>
          <li>Not use the Service to distribute malicious agent configurations</li>
          <li>Keep your authentication tokens secure</li>
          <li>Maintain your own backups of team configurations</li>
        </ul>
      </.legal_section>

      <.legal_section title="5. Intellectual Property">
        <p>
          Team configurations, agent definitions, and skills you create remain yours. The teamrc software is open-source and licensed under its respective license. Template catalog content provided by teamrc is available for use under the same license.
        </p>
      </.legal_section>

      <.legal_section title="6. Limitation of Liability">
        <p>
          To the maximum extent permitted by law, teamrc and its maintainers shall not be liable for any indirect, incidental, special, consequential, or punitive damages, including but not limited to loss of data, loss of profits, or service interruption, arising from your use of the Service.
        </p>
        <p>
          The Service is provided "as is" and "as available" without warranties of any kind, express or implied.
        </p>
      </.legal_section>

      <.legal_section title="7. Termination">
        <p>
          We may suspend or terminate access to the Service at any time, for any reason, without prior notice. You may stop using the Service at any time by removing the CLI and deleting your local configuration.
        </p>
      </.legal_section>

      <.legal_section title="8. Changes to Terms">
        <p>
          We may update these Terms at any time. Continued use of the Service after changes constitutes acceptance. Material changes will be communicated through the project repository or CLI.
        </p>
      </.legal_section>

      <.legal_section title="9. Contact">
        <p>
          For questions about these Terms, open an issue on the <a
            href="https://github.com/teamrc-app/teamrc"
            class="text-primary hover:underline"
            target="_blank"
            rel="noopener"
          >teamrc GitHub repository</a>.
        </p>
      </.legal_section>
    </div>
    """
  end

  # ===========================================================================
  # Privacy Policy
  # ===========================================================================

  defp page_privacy(assigns) do
    ~H"""
    <div class="space-y-8">
      <div class="space-y-2">
        <h1 class="text-2xl font-bold tracking-tight">Privacy Policy</h1>
        <p class="text-sm text-base-content/50">Last updated: March 9, 2026</p>
      </div>

      <div class="rounded-lg border border-amber-500/30 bg-amber-500/5 px-4 py-3">
        <div class="flex items-start gap-3">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="h-5 w-5 text-amber-500 mt-0.5 shrink-0"
            viewBox="0 0 20 20"
            fill="currentColor"
          >
            <path
              fill-rule="evenodd"
              d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z"
              clip-rule="evenodd"
            />
          </svg>
          <div class="space-y-1">
            <p class="text-sm font-semibold text-amber-500">Experimental Software</p>
            <p class="text-sm text-base-content/70">
              teamrc is experimental software. Our data practices may evolve as the project matures. We will update this policy accordingly.
            </p>
          </div>
        </div>
      </div>

      <.legal_section title="1. What We Collect">
        <p>teamrc collects minimal data necessary to operate the Service:</p>
        <div class="space-y-3">
          <.data_item
            label="Authentication Tokens"
            description="Ed25519 public keys generated locally on your machine. Private keys never leave your device."
          />
          <.data_item
            label="Team Configurations"
            description="Agent definitions, skill assignments, and team metadata you choose to sync through the relay server."
          />
          <.data_item
            label="Account Information"
            description="If you optionally sign in via Clerk: your email address, for machine management and recovery."
          />
          <.data_item
            label="Invite Codes"
            description="Ephemeral codes generated for team invitations, automatically expired after use or TTL."
          />
        </div>
      </.legal_section>

      <.legal_section title="2. What We Don't Collect">
        <ul>
          <li>Your source code or project files</li>
          <li>AI conversation history or prompts</li>
          <li>File contents from your repositories</li>
          <li>Analytics, tracking, or telemetry data</li>
          <li>Cookies for advertising or cross-site tracking</li>
        </ul>
      </.legal_section>

      <.legal_section title="3. How We Use Your Data">
        <p>Data is used solely to provide the Service:</p>
        <ul>
          <li>Authenticating your CLI requests via signed tokens</li>
          <li>Syncing team configurations between your machines</li>
          <li>Managing team membership and invitations</li>
          <li>Associating machines with optional Clerk accounts</li>
        </ul>
      </.legal_section>

      <.legal_section title="4. Data Storage">
        <p>
          Team configurations and account data are stored on the relay server.
          As experimental software, data retention and backup policies are not guaranteed.
          You should maintain local backups of your team configurations
          via <code class="font-mono text-sm bg-base-200 px-1.5 py-0.5 rounded">teamrc export</code>
          or your <code class="font-mono text-sm bg-base-200 px-1.5 py-0.5 rounded">.teamrc.yaml</code> files.
        </p>
      </.legal_section>

      <.legal_section title="5. Data Sharing">
        <p>
          We do not sell, rent, or share your data with third parties. Team configurations are shared only with other members of your team who have joined via invite code or clone token.
        </p>
      </.legal_section>

      <.legal_section title="6. Third-Party Services">
        <p>The Service integrates with:</p>
        <ul>
          <li>
            <strong>Clerk</strong> — Optional authentication provider. Subject to <a
              href="https://clerk.com/legal/privacy"
              class="text-primary hover:underline"
              target="_blank"
              rel="noopener"
            >Clerk's Privacy Policy</a>
          </li>
        </ul>
      </.legal_section>

      <.legal_section title="7. Your Rights">
        <p>You can:</p>
        <ul>
          <li>
            Delete your local data by removing <code class="font-mono text-sm bg-base-200 px-1.5 py-0.5 rounded">~/.teamrc/</code> and
            your <code class="font-mono text-sm bg-base-200 px-1.5 py-0.5 rounded">.teamrc.yaml</code> files
          </li>
          <li>Revoke machine tokens via the dashboard</li>
          <li>Request deletion of your relay-server data by contacting us</li>
        </ul>
      </.legal_section>

      <.legal_section title="8. Changes to This Policy">
        <p>
          We may update this Privacy Policy as the project evolves. Changes will be reflected in the "Last updated" date above and communicated through the project repository.
        </p>
      </.legal_section>

      <.legal_section title="9. Contact">
        <p>
          For privacy concerns, open an issue on the <a
            href="https://github.com/teamrc-app/teamrc"
            class="text-primary hover:underline"
            target="_blank"
            rel="noopener"
          >teamrc GitHub repository</a>.
        </p>
      </.legal_section>
    </div>
    """
  end

  # ===========================================================================
  # Shared components
  # ===========================================================================

  attr :title, :string, required: true
  slot :inner_block

  defp legal_section(assigns) do
    ~H"""
    <section class="space-y-3">
      <h2 class="text-base font-semibold tracking-tight">{@title}</h2>
      <div class="space-y-2 text-sm text-base-content/70 leading-relaxed [&_ul]:list-disc [&_ul]:pl-5 [&_ul]:space-y-1 [&_p+p]:mt-2">
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end

  attr :label, :string, required: true
  attr :description, :string, required: true

  defp data_item(assigns) do
    ~H"""
    <div class="flex gap-3 items-start">
      <div class="mt-1.5 h-1.5 w-1.5 rounded-full bg-primary/40 shrink-0" />
      <div>
        <span class="font-medium text-base-content/90">{@label}</span>
        <span class="text-base-content/50"> — {@description}</span>
      </div>
    </div>
    """
  end
end
