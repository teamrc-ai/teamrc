defmodule TeamrcWeb.Plugs.VerifyOriginTest do
  use TeamrcWeb.ConnCase, async: false

  alias TeamrcWeb.Plugs.VerifyOrigin

  @app_origin TeamrcWeb.Endpoint.url()

  describe "safe methods" do
    test "GET requests pass through without Origin header", %{conn: conn} do
      conn =
        conn
        |> Map.put(:method, "GET")
        |> VerifyOrigin.call([])

      refute conn.halted
    end

    test "HEAD requests pass through without Origin header", %{conn: conn} do
      conn =
        conn
        |> Map.put(:method, "HEAD")
        |> VerifyOrigin.call([])

      refute conn.halted
    end

    test "OPTIONS requests pass through without Origin header", %{conn: conn} do
      conn =
        conn
        |> Map.put(:method, "OPTIONS")
        |> VerifyOrigin.call([])

      refute conn.halted
    end
  end

  describe "POST requests" do
    test "passes with matching Origin", %{conn: conn} do
      conn =
        conn
        |> Map.put(:method, "POST")
        |> put_req_header("origin", @app_origin)
        |> VerifyOrigin.call([])

      refute conn.halted
    end

    test "rejects with 403 when Origin is missing", %{conn: conn} do
      conn =
        conn
        |> Map.put(:method, "POST")
        |> VerifyOrigin.call([])

      assert conn.halted
      assert conn.status == 403
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "missing_origin"
    end

    test "rejects with 403 when Origin does not match", %{conn: conn} do
      conn =
        conn
        |> Map.put(:method, "POST")
        |> put_req_header("origin", "http://evil.com")
        |> VerifyOrigin.call([])

      assert conn.halted
      assert conn.status == 403
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "origin_mismatch"
    end

    test "rejects prefix-attack Origin (e.g., apphost.evil.com)", %{conn: conn} do
      # The app_origin is "http://localhost:4002". An attacker might try
      # "http://localhost:4002.evil.com" to bypass a naive starts_with? check.
      evil_origin = @app_origin <> ".evil.com"

      conn =
        conn
        |> Map.put(:method, "POST")
        |> put_req_header("origin", evil_origin)
        |> VerifyOrigin.call([])

      assert conn.halted
      assert conn.status == 403
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "origin_mismatch"
    end
  end

  describe "DELETE requests" do
    test "passes with matching Origin", %{conn: conn} do
      conn =
        conn
        |> Map.put(:method, "DELETE")
        |> put_req_header("origin", @app_origin)
        |> VerifyOrigin.call([])

      refute conn.halted
    end

    test "rejects with 403 when Origin is missing", %{conn: conn} do
      conn =
        conn
        |> Map.put(:method, "DELETE")
        |> VerifyOrigin.call([])

      assert conn.halted
      assert conn.status == 403
    end
  end
end
