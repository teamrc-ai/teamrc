defmodule TeamrcWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use TeamrcWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block

  def app(assigns) do
    assigns = assign(assigns, :current_user, assigns[:current_scope] && assigns.current_scope.user)

    ~H"""
    <header class="border-b border-base-300/60 bg-base-100/80 backdrop-blur-sm sticky top-0 z-40">
      <a href="#main-content" class="skip-link trc-focus">Skip to content</a>
      <nav class="mx-auto max-w-3xl flex items-center justify-between px-4 sm:px-6 h-14">
        <div class="flex items-center gap-6">
          <a href="/" class="flex items-center gap-2.5 group" aria-label="teamrc home">
            <div class="text-primary">
              <img src={~p"/images/logo.svg"} width="24" height="24" class="text-primary" />
            </div>
            <span class="text-sm font-semibold tracking-tight">teamrc</span>
          </a>
          <nav class="hidden sm:flex items-center gap-1">
            <a
              :if={@current_user}
              href={~p"/dashboard"}
              class="trc-focus rounded-md px-2.5 py-1.5 text-xs font-medium text-base-content/60 hover:text-base-content/90 hover:bg-base-200/60 transition-colors"
            >
              Dashboard
            </a>
            <a
              href={~p"/new"}
              class="trc-focus rounded-md px-2.5 py-1.5 text-xs font-medium text-base-content/60 hover:text-base-content/90 hover:bg-base-200/60 transition-colors"
            >
              Create Team
            </a>
            <a
              href={~p"/guide"}
              class="trc-focus rounded-md px-2.5 py-1.5 text-xs font-medium text-base-content/60 hover:text-base-content/90 hover:bg-base-200/60 transition-colors"
            >
              Guide
            </a>
          </nav>
        </div>
        <div class="flex items-center gap-2 sm:gap-3">
          <%!-- Auth state: signed in --%>
          <div :if={@current_user} class="flex items-center gap-2">
            <div class="hidden sm:flex items-center gap-2 rounded-md bg-base-200/50 px-2.5 py-1.5">
              <div class="flex h-5 w-5 items-center justify-center rounded-full bg-primary/15 text-primary text-[10px] font-bold">
                <%= String.first(@current_user.email) |> String.upcase() %>
              </div>
              <span class="text-xs text-base-content/70 font-mono max-w-[140px] truncate">
                <%= @current_user.email %>
              </span>
            </div>
            <.link
              href={~p"/users/log-out"}
              method="delete"
              class="trc-focus hidden sm:inline-flex rounded-md px-2 py-1.5 text-xs font-medium text-base-content/50 hover:text-base-content/80 transition-colors"
            >
              Sign out
            </.link>
          </div>
          <%!-- Auth state: not signed in --%>
          <.link
            :if={!@current_user}
            href={~p"/users/log-in"}
            class="trc-focus inline-flex items-center gap-1.5 rounded-md bg-primary/10 px-3 py-1.5 text-xs font-semibold text-primary hover:bg-primary/20 transition-colors"
          >
            <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor">
              <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-6-3a2 2 0 11-4 0 2 2 0 014 0zm-2 4a5 5 0 00-4.546 2.916A5.986 5.986 0 0010 16a5.986 5.986 0 004.546-2.084A5 5 0 0010 11z" clip-rule="evenodd" />
            </svg>
            Sign in
          </.link>
          <%!-- Mobile menu button --%>
          <button
            phx-click={JS.toggle(to: "#mobile-menu", in: "fade-in", out: "fade-out")}
            class="trc-focus sm:hidden rounded-md p-1.5 text-base-content/60 hover:text-base-content/80 hover:bg-base-200/60 transition-colors"
            aria-label="Toggle menu"
            aria-expanded="false"
            aria-controls="mobile-menu"
          >
            <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" d="M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25h16.5" />
            </svg>
          </button>
        </div>
      </nav>
      <%!-- Mobile menu dropdown --%>
      <div id="mobile-menu" class="hidden sm:hidden border-t border-base-300/60 bg-base-100/95 backdrop-blur-sm px-4 py-3 space-y-1">
        <a
          :if={@current_user}
          href={~p"/dashboard"}
          class="trc-focus block rounded-md px-3 py-2 text-sm font-medium text-base-content/70 hover:text-base-content/90 hover:bg-base-200/60 transition-colors"
        >
          Dashboard
        </a>
        <a
          href={~p"/new"}
          class="trc-focus block rounded-md px-3 py-2 text-sm font-medium text-base-content/70 hover:text-base-content/90 hover:bg-base-200/60 transition-colors"
        >
          Create Team
        </a>
        <a
          href={~p"/guide"}
          class="trc-focus block rounded-md px-3 py-2 text-sm font-medium text-base-content/70 hover:text-base-content/90 hover:bg-base-200/60 transition-colors"
        >
          Guide
        </a>
        <div :if={@current_user} class="border-t border-base-300/40 pt-2 mt-2">
          <div class="flex items-center gap-2 px-3 py-1.5">
            <div class="flex h-5 w-5 items-center justify-center rounded-full bg-primary/15 text-primary text-[10px] font-bold">
              <%= String.first(@current_user.email) |> String.upcase() %>
            </div>
            <span class="text-xs text-base-content/70 font-mono truncate">
              <%= @current_user.email %>
            </span>
          </div>
          <.link
            href={~p"/users/log-out"}
            method="delete"
            class="trc-focus block rounded-md px-3 py-2 text-sm font-medium text-base-content/50 hover:text-base-content/80 transition-colors"
          >
            Sign out
          </.link>
        </div>
      </div>
    </header>

    <main id="main-content" class="flex-1 px-4 py-8 sm:px-8 sm:py-16">
      <div class="mx-auto max-w-2xl">
        <%= if assigns[:inner_content] do %>
          {@inner_content}
        <% else %>
          {render_slot(@inner_block)}
        <% end %>
      </div>
    </main>

    <footer class="border-t border-base-300/40 py-6 mt-auto">
      <div class="mx-auto max-w-2xl px-4 sm:px-8 flex flex-col sm:flex-row items-center justify-between gap-3">
        <p class="text-xs text-base-content/50">
          teamrc is pre-release software
        </p>
        <nav class="flex items-center gap-4">
          <a
            href={~p"/terms"}
            class="text-xs text-base-content/50 hover:text-base-content/70 transition-colors"
          >
            Terms
          </a>
          <a
            href={~p"/privacy"}
            class="text-xs text-base-content/50 hover:text-base-content/70 transition-colors"
          >
            Privacy
          </a>
          <a
            href="https://github.com/teamrc-ai/teamrc"
            target="_blank"
            rel="noopener"
            class="text-base-content/50 hover:text-base-content/70 transition-colors"
            aria-label="GitHub"
          >
            <svg class="h-4 w-4" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true">
              <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z" />
            </svg>
          </a>
        </nav>
      </div>
    </footer>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

end
