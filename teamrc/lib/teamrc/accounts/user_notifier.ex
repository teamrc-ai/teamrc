defmodule Teamrc.Accounts.UserNotifier do
  @moduledoc """
  Delivers transactional emails for user account operations.

  Each email is sent in both HTML and plain text formats. The HTML
  uses table-based layout with inline styles for broad email client
  compatibility (Gmail, Outlook, Apple Mail, Fastmail).
  """

  import Swoosh.Email
  alias Teamrc.Mailer

  # -- Delivery ------------------------------------------------------------

  defp deliver(recipient, subject, text_body, html_body) do
    email =
      new()
      |> to(recipient)
      |> from({"teamrc", "no-reply@notifications.teamrc.ai"})
      |> subject(subject)
      |> text_body(text_body)
      |> html_body(html_body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  # -- Public API -----------------------------------------------------------

  @doc """
  Delivers login instructions via magic link.

  For unconfirmed users, delivers confirmation instructions instead.
  """
  def deliver_login_instructions(%{confirmed_at: nil} = user, url) do
    deliver_confirmation_instructions(user, url)
  end

  def deliver_login_instructions(user, url) do
    text =
      text_layout("""
      Click the link below to log in to your account.

      #{url}

      If you didn't request this email, ignore it.\
      """)

    html =
      html_layout(
        html_paragraph("Click the button below to log in to your account.") <>
          html_button("Log in", url) <>
          html_fallback_url(url) <>
          html_muted_paragraph("If you didn't request this email, ignore it.")
      )

    deliver(user.email, "Log in to teamrc", text, html)
  end

  @doc """
  Delivers email confirmation instructions to the given user.
  """
  def deliver_confirmation_instructions(user, url) do
    text =
      text_layout("""
      Click the link below to confirm your email address.

      #{url}

      If you didn't create an account, ignore this email.\
      """)

    html =
      html_layout(
        html_paragraph("Click the button below to confirm your email address.") <>
          html_button("Confirm email", url) <>
          html_fallback_url(url) <>
          html_muted_paragraph("If you didn't create an account, ignore this email.")
      )

    deliver(user.email, "Confirm your teamrc account", text, html)
  end

  @doc """
  Delivers password reset instructions to the given user.
  """
  def deliver_reset_password_instructions(user, url) do
    text =
      text_layout("""
      Someone requested a password reset for your account. If this
      wasn't you, ignore this email.

      #{url}

      This link expires in 24 hours.\
      """)

    html =
      html_layout(
        html_paragraph(
          "Someone requested a password reset for your account. " <>
            "If this wasn't you, ignore this email."
        ) <>
          html_button("Reset password", url) <>
          html_fallback_url(url) <>
          html_muted_paragraph("This link expires in 24 hours.")
      )

    deliver(user.email, "Reset your teamrc password", text, html)
  end

  @doc """
  Delivers instructions to confirm a new email address.
  """
  def deliver_update_email_instructions(user, url) do
    text =
      text_layout("""
      Click the link below to confirm changing your email address.

      #{url}

      If you didn't request this change, ignore this email.\
      """)

    html =
      html_layout(
        html_paragraph("Click the button below to confirm changing your email address.") <>
          html_button("Confirm new email", url) <>
          html_fallback_url(url) <>
          html_muted_paragraph("If you didn't request this change, ignore this email.")
      )

    deliver(user.email, "Confirm your new email address", text, html)
  end

  @doc """
  Delivers a welcome email after sign-up with getting started instructions.
  """
  def deliver_welcome(user) do
    guide_url = "https://teamrc.dev/guide/get-started"
    new_team_url = "https://teamrc.dev/new"

    text =
      text_layout("""
      Welcome to teamrc! Your account is ready.

      Here's how to get started:

      1. Create your first team
         Visit #{new_team_url} or run:

          npx @teamrc/cli init

      2. Invite your teammates
         After creating a team, share the invite command:

          npx @teamrc/cli join <invite-code>

      3. Sync across platforms
         teamrc works with Claude Code, Cursor, Codex, Gemini,
         and more. Run `npx @teamrc/cli sync` to push your team
         config to all connected platforms.

      For a full walkthrough, visit the guide:

      #{guide_url}\
      """)

    html =
      html_layout(
        html_paragraph("Welcome to teamrc! Your account is ready.") <>
          html_paragraph("Here's how to get started:") <>
          html_step("1", "Create your first team",
            "Visit the web UI or run the CLI to set up your team with agents and skills.") <>
          html_code_block("npx @teamrc/cli init") <>
          html_step("2", "Invite your teammates",
            "After creating a team, share the invite command with your team.") <>
          html_code_block("npx @teamrc/cli join &lt;invite-code&gt;") <>
          html_step("3", "Sync across platforms",
            "teamrc works with Claude Code, Cursor, Codex, Gemini, and more. " <>
            "Run <code style=\"font-family: monospace; font-size: 13px; background-color: #f4f4f5; padding: 1px 4px; border-radius: 3px;\">teamrc sync</code> to push your team config to all connected platforms.") <>
          html_button("Get started", guide_url) <>
          html_fallback_url(guide_url) <>
          html_muted_paragraph("Or <a href=\"#{new_team_url}\" style=\"color: #4f46e5; text-decoration: underline;\">create a team</a> directly from the web.")
      )

    deliver(user.email, "Welcome to teamrc", text, html)
  end

  # -- Plain text helpers ---------------------------------------------------

  defp text_layout(body) do
    """
    teamrc
    ======

    #{String.trim(body)}

    --
    teamrc - https://teamrc.dev
    """
  end

  # -- HTML helpers ---------------------------------------------------------

  @font_body ~s(-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif)
  @font_mono ~s('SFMono-Regular', Consolas, 'Liberation Mono', Menlo, Courier, monospace)

  @color_bg "#f4f4f5"
  @color_card "#ffffff"
  @color_text "#52525b"
  @color_text_muted "#a1a1aa"
  @color_border "#e4e4e7"
  @color_primary "#4f46e5"
  @color_code_bg "#f4f4f5"

  defp html_layout(content) do
    """
    <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
    <html xmlns="http://www.w3.org/1999/xhtml" lang="en">
    <head>
      <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      <title>teamrc</title>
      <!--[if mso]>
      <noscript>
        <xml>
          <o:OfficeDocumentSettings>
            <o:PixelsPerInch>96</o:PixelsPerInch>
          </o:OfficeDocumentSettings>
        </xml>
      </noscript>
      <![endif]-->
    </head>
    <body style="margin: 0; padding: 0; background-color: #{@color_bg}; font-family: #{@font_body}; -webkit-text-size-adjust: 100%; -ms-text-size-adjust: 100%;">
      <!-- Outer wrapper -->
      <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="background-color: #{@color_bg};">
        <tr>
          <td align="center" style="padding: 40px 16px;">
            <!-- Card -->
            <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="480" style="max-width: 480px; width: 100%; background-color: #{@color_card}; border-radius: 8px; border: 1px solid #{@color_border};">
              <tr>
                <td style="padding: 32px 32px 0 32px;">
                  <!-- Header -->
                  <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%">
                    <tr>
                      <td style="font-family: #{@font_mono}; font-size: 18px; font-weight: 700; color: #18181b; padding-bottom: 16px;">
                        teamrc
                      </td>
                    </tr>
                    <tr>
                      <td style="border-top: 1px solid #{@color_border}; padding-bottom: 24px; line-height: 0; font-size: 0;">&nbsp;</td>
                    </tr>
                  </table>
                </td>
              </tr>
              <tr>
                <td style="padding: 0 32px 32px 32px; color: #{@color_text}; font-size: 15px; line-height: 24px;">
                  #{content}
                </td>
              </tr>
            </table>
            <!-- Footer -->
            <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="480" style="max-width: 480px; width: 100%;">
              <tr>
                <td align="center" style="padding: 24px 32px 0 32px; font-family: #{@font_body}; font-size: 12px; line-height: 18px; color: #{@color_text_muted};">
                  Sent by teamrc &middot; <a href="https://teamrc.dev" style="color: #{@color_text_muted}; text-decoration: underline;">teamrc.dev</a>
                </td>
              </tr>
            </table>
          </td>
        </tr>
      </table>
    </body>
    </html>
    """
  end

  defp html_paragraph(text) do
    """
    <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%">
      <tr>
        <td style="font-family: #{@font_body}; font-size: 15px; line-height: 24px; color: #{@color_text}; padding-bottom: 16px;">
          #{text}
        </td>
      </tr>
    </table>
    """
  end

  defp html_muted_paragraph(text) do
    """
    <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%">
      <tr>
        <td style="font-family: #{@font_body}; font-size: 13px; line-height: 20px; color: #{@color_text_muted}; padding-bottom: 8px;">
          #{text}
        </td>
      </tr>
    </table>
    """
  end

  defp html_button(label, url) do
    """
    <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="padding-bottom: 16px;">
      <tr>
        <td align="left">
          <!--[if mso]>
          <v:roundrect xmlns:v="urn:schemas-microsoft-com:vml" xmlns:w="urn:schemas-microsoft-com:office:word" href="#{url}" style="height: 40px; v-text-anchor: middle; width: 200px;" arcsize="15%" strokecolor="#{@color_primary}" fillcolor="#{@color_primary}">
            <w:anchorlock/>
            <center style="color: #ffffff; font-family: #{@font_body}; font-size: 14px; font-weight: 600;">#{label}</center>
          </v:roundrect>
          <![endif]-->
          <!--[if !mso]><!-->
          <a href="#{url}" target="_blank" style="display: inline-block; background-color: #{@color_primary}; color: #ffffff; font-family: #{@font_body}; font-size: 14px; font-weight: 600; line-height: 40px; text-align: center; text-decoration: none; border-radius: 6px; padding: 0 24px; -webkit-text-size-adjust: none; mso-hide: all;">
            #{label}
          </a>
          <!--<![endif]-->
        </td>
      </tr>
    </table>
    """
  end

  defp html_fallback_url(url) do
    """
    <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%">
      <tr>
        <td style="font-family: #{@font_body}; font-size: 12px; line-height: 18px; color: #{@color_text_muted}; padding-bottom: 16px;">
          Or copy this link:<br />
          <a href="#{url}" style="font-family: #{@font_mono}; font-size: 12px; color: #{@color_primary}; text-decoration: underline; word-break: break-all;">#{url}</a>
        </td>
      </tr>
    </table>
    """
  end

  defp html_step(number, title, description) do
    """
    <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="padding-bottom: 8px;">
      <tr>
        <td width="28" valign="top" style="padding-top: 2px;">
          <div style="width: 22px; height: 22px; border-radius: 50%; background-color: #{@color_primary}; color: #ffffff; font-family: #{@font_body}; font-size: 12px; font-weight: 700; line-height: 22px; text-align: center;">
            #{number}
          </div>
        </td>
        <td style="padding-left: 10px; font-family: #{@font_body}; font-size: 15px; line-height: 24px; color: #{@color_text};">
          <strong style="color: #18181b;">#{title}</strong><br />
          <span style="font-size: 14px; color: #{@color_text};">#{description}</span>
        </td>
      </tr>
    </table>
    """
  end

  defp html_code_block(code) do
    """
    <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="padding-bottom: 16px;">
      <tr>
        <td style="background-color: #{@color_code_bg}; border: 1px solid #{@color_border}; border-radius: 6px; padding: 12px 16px; font-family: #{@font_mono}; font-size: 14px; line-height: 20px; color: #18181b;">
          #{code}
        </td>
      </tr>
    </table>
    """
  end
end
