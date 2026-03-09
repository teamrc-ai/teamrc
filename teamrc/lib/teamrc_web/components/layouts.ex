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

  attr :clerk_email, :string, default: nil
  attr :clerk_user_id, :string, default: nil

  slot :inner_block

  def app(assigns) do
    ~H"""
    <header class="border-b border-base-300/60 bg-base-100/80 backdrop-blur-sm sticky top-0 z-40">
      <nav class="mx-auto max-w-3xl flex items-center justify-between px-4 sm:px-6 h-14">
        <div class="flex items-center gap-6">
          <a href="/" class="flex items-center gap-2.5 group">
            <div class="text-primary">
              <img src={~p"/images/logo.svg"} width="24" height="24" class="text-primary" />
            </div>
            <span class="text-sm font-semibold tracking-tight">teamrc</span>
          </a>
          <nav :if={@clerk_email} class="hidden sm:flex items-center gap-1">
            <a
              href={~p"/dashboard"}
              class="trc-focus rounded-md px-2.5 py-1.5 text-xs font-medium text-base-content/50 hover:text-base-content/80 hover:bg-base-200/60 transition-colors"
            >
              Dashboard
            </a>
            <a
              href={~p"/new"}
              class="trc-focus rounded-md px-2.5 py-1.5 text-xs font-medium text-base-content/50 hover:text-base-content/80 hover:bg-base-200/60 transition-colors"
            >
              Create Team
            </a>
            <a
              href={~p"/guide"}
              class="trc-focus rounded-md px-2.5 py-1.5 text-xs font-medium text-base-content/50 hover:text-base-content/80 hover:bg-base-200/60 transition-colors"
            >
              Guide
            </a>
          </nav>
        </div>
        <div class="flex items-center gap-3">
          <%!-- Auth state: signed in --%>
          <div :if={@clerk_email} class="flex items-center gap-2">
            <div class="flex items-center gap-2 rounded-md bg-base-200/50 px-2.5 py-1.5">
              <div class="flex h-5 w-5 items-center justify-center rounded-full bg-primary/15 text-primary text-[10px] font-bold">
                <%= String.first(@clerk_email) |> String.upcase() %>
              </div>
              <span class="text-xs text-base-content/60 font-mono hidden sm:inline max-w-[140px] truncate">
                <%= @clerk_email %>
              </span>
            </div>
            <a
              href={~p"/auth/sign-out"}
              class="trc-focus rounded-md px-2 py-1.5 text-xs font-medium text-base-content/30 hover:text-base-content/60 transition-colors"
            >
              Sign out
            </a>
          </div>
          <%!-- Auth state: not signed in --%>
          <button
            :if={!@clerk_email}
            phx-click={Phoenix.LiveView.JS.dispatch("trc:sign-in")}
            class="trc-focus inline-flex items-center gap-1.5 rounded-md bg-primary/10 px-3 py-1.5 text-xs font-semibold text-primary hover:bg-primary/20 transition-colors"
          >
            <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor">
              <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-6-3a2 2 0 11-4 0 2 2 0 014 0zm-2 4a5 5 0 00-4.546 2.916A5.986 5.986 0 0010 16a5.986 5.986 0 004.546-2.084A5 5 0 0010 11z" clip-rule="evenodd" />
            </svg>
            Sign in
          </button>
          <.theme_toggle />
        </div>
      </nav>
    </header>

    <main class="flex-1 px-6 py-12 sm:px-8 sm:py-16">
      <div class="mx-auto max-w-2xl">
        <%= if assigns[:inner_content] do %>
          {@inner_content}
        <% else %>
          {render_slot(@inner_block)}
        <% end %>
      </div>
    </main>

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

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
