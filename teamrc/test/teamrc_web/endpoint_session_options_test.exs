defmodule TeamrcWeb.EndpointSessionOptionsTest do
  use ExUnit.Case, async: false

  alias TeamrcWeb.Endpoint

  setup do
    original = Application.get_env(:teamrc, Endpoint, [])

    on_exit(fn ->
      Application.put_env(:teamrc, Endpoint, original)
    end)

    :ok
  end

  test "uses default session options when runtime overrides are absent" do
    config =
      Application.get_env(:teamrc, Endpoint, [])
      |> Keyword.delete(:session_options)

    Application.put_env(:teamrc, Endpoint, config)

    opts = Endpoint.session_options()

    assert opts[:store] == :cookie
    assert opts[:key] == "_teamrc_key"
    assert opts[:signing_salt] == "46xYNHT2"
    assert opts[:encryption_salt] == "k9Pm3xR7"
    assert opts[:same_site] == "Lax"
  end

  test "runtime session overrides replace default salts" do
    config =
      Application.get_env(:teamrc, Endpoint, [])
      |> Keyword.put(:session_options,
        signing_salt: "runtime-sign",
        encryption_salt: "runtime-encrypt",
        same_site: "Strict"
      )

    Application.put_env(:teamrc, Endpoint, config)

    opts = Endpoint.session_options()

    assert opts[:store] == :cookie
    assert opts[:key] == "_teamrc_key"
    assert opts[:signing_salt] == "runtime-sign"
    assert opts[:encryption_salt] == "runtime-encrypt"
    assert opts[:same_site] == "Strict"
  end
end
