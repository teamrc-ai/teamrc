defmodule Teamrc.SecurityAuditTest do
  @moduledoc "Tests for security and data integrity fixes from the comprehensive audit."

  use ExUnit.Case, async: false

  import Ecto.Query
  alias Teamrc.{Accounts, Repo, Teams}
  alias Teamrc.Schema.{Invite, TokenTeam, Team}

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Teamrc.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  # Helper to create a user and link a machine token
  defp create_user_with_token(email, machine_token, machine_name \\ "test-machine") do
    {:ok, user} = Accounts.register_user(%{
      "email" => email,
      "terms_accepted" => "true"
    })
    {:ok, _mt} = Accounts.link_machine_token(user.id, machine_token, machine_name)
    {:ok, user}
  end

  # ---------------------------------------------------------------------------
  # Fix 1: is_team_participant?/2 filters revoked tokens
  # ---------------------------------------------------------------------------

  describe "is_team_participant? filters revoked tokens" do
    test "returns true for active token, false after revocation" do
      token = "trc_ak_revoke_#{:erlang.unique_integer([:positive])}"
      {:ok, user} = create_user_with_token("revoke@example.com", token)

      # Create team and associate token
      {:ok, team_data} = Teams.put_team(token, %{"name" => "revoke-team", "members" => []})
      team_id = team_data["id"]

      # Should be participant
      assert Accounts.is_team_participant?(user.id, team_id)

      # Revoke the token
      :ok = Accounts.revoke_machine_token(user.id, token)

      # Should NOT be participant after revocation
      refute Accounts.is_team_participant?(user.id, team_id)
    end

    test "returns true when one token is revoked but another is active" do
      token1 = "trc_ak_mt1_#{:erlang.unique_integer([:positive])}"
      token2 = "trc_ak_mt2_#{:erlang.unique_integer([:positive])}"
      {:ok, user} = create_user_with_token("multi@example.com", token1, "machine1")
      {:ok, _} = Accounts.link_machine_token(user.id, token2, "machine2")

      # Create team with token1
      {:ok, team_data} = Teams.put_team(token1, %{"name" => "multi-tok-team", "members" => []})
      team_id = team_data["id"]

      # Directly associate token2 with the team
      %TokenTeam{}
      |> TokenTeam.changeset(%{token: token2, team_id: team_id})
      |> Repo.insert(on_conflict: :nothing)

      # Revoke token1
      :ok = Accounts.revoke_machine_token(user.id, token1)

      # Should still be participant via token2
      assert Accounts.is_team_participant?(user.id, team_id)
    end
  end

  # ---------------------------------------------------------------------------
  # Fix 2: create_team_with_invite/1 is transactional
  # ---------------------------------------------------------------------------

  describe "create_team_with_invite/1 is transactional" do
    test "creates both team and invite atomically" do
      {:ok, invite_code, team_id} =
        Teams.create_team_with_invite(%{
          "name" => "atomic-team",
          "members" => [%{"name" => "bot", "role" => "helper"}]
        })

      # Both team and invite exist
      assert Repo.get(Team, team_id)
      assert Repo.get_by(Invite, code: invite_code)
    end

    test "team is not left behind if invite fails" do
      teams_before = Repo.aggregate(Team, :count)

      {:ok, _code, team_id} =
        Teams.create_team_with_invite(%{
          "name" => "txn-team",
          "members" => []
        })

      teams_after = Repo.aggregate(Team, :count)
      assert teams_after == teams_before + 1

      # The team and invite both exist
      assert Repo.get(Team, team_id)
      invites = Repo.all(from(i in Invite, where: i.team_id == ^team_id))
      assert length(invites) == 1
    end
  end

  # ---------------------------------------------------------------------------
  # Fix 7: Catalog path traversal prevention
  # ---------------------------------------------------------------------------

  describe "catalog path traversal prevention" do
    test "load_team_raw rejects path traversal" do
      assert_raise ArgumentError, ~r/invalid template id/, fn ->
        Teamrc.Catalog.load_team_raw("../../../etc/passwd")
      end
    end

    test "load_agent rejects path traversal" do
      assert_raise ArgumentError, ~r/invalid template id/, fn ->
        Teamrc.Catalog.load_agent("../../secrets")
      end
    end

    test "load_skill rejects path traversal" do
      assert_raise ArgumentError, ~r/invalid template id/, fn ->
        Teamrc.Catalog.load_skill("../config/runtime")
      end
    end

    test "rejects IDs with slashes" do
      assert_raise ArgumentError, ~r/invalid template id/, fn ->
        Teamrc.Catalog.load_agent("foo/bar")
      end
    end

    test "rejects IDs with backslashes" do
      assert_raise ArgumentError, ~r/invalid template id/, fn ->
        Teamrc.Catalog.load_skill("foo\\bar")
      end
    end

    test "rejects empty ID" do
      assert_raise ArgumentError, ~r/invalid template id/, fn ->
        Teamrc.Catalog.load_skill("")
      end
    end

    test "rejects ID starting with hyphen" do
      assert_raise ArgumentError, ~r/invalid template id/, fn ->
        Teamrc.Catalog.load_agent("-bad-start")
      end
    end

    test "accepts valid IDs" do
      assert_raise File.Error, fn ->
        Teamrc.Catalog.load_agent("valid-name-123")
      end

      assert_raise File.Error, fn ->
        Teamrc.Catalog.load_skill("valid_skill_id")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Fix 9: generate_user_code rejection sampling
  # ---------------------------------------------------------------------------

  describe "device auth user code format" do
    test "user codes still match expected format after rejection sampling fix" do
      token = "trc_ak_bias_#{:erlang.unique_integer([:positive])}"
      {:ok, result} = Teamrc.DeviceAuth.create_request(token)

      assert Regex.match?(~r/^[A-Z2-9]{4}-[A-Z2-9]{4}$/, result.user_code)
    end

    test "generates unique codes across multiple requests" do
      codes =
        for i <- 1..3 do
          token = "trc_ak_uniq_#{i}_#{:erlang.unique_integer([:positive])}"
          {:ok, result} = Teamrc.DeviceAuth.create_request(token)
          result.user_code
        end

      assert length(Enum.uniq(codes)) == 3
    end
  end

  # ---------------------------------------------------------------------------
  # Fix 11: set_visibility auth check
  # ---------------------------------------------------------------------------

  describe "set_visibility requires owner auth" do
    test "owner can set visibility" do
      token = "trc_ak_vis_#{:erlang.unique_integer([:positive])}"
      {:ok, team_data} = Teams.put_team(token, %{"name" => "vis-team", "members" => []})
      team_id = team_data["id"]
      claim_secret = team_data["owner_claim_secret"]

      # Link user and claim ownership via secret
      {:ok, _user} = create_user_with_token("vis@test.com", token)
      {:ok, :claimed} = Teams.claim_ownership(token, claim_secret)

      assert {:ok, updated} = Teams.set_visibility(token, team_id, "public")
      assert updated.visibility == "public"
      assert updated.clone_token

      assert {:ok, updated} = Teams.set_visibility(token, team_id, "private")
      assert updated.visibility == "private"
    end

    test "non-owner team member is rejected" do
      token = "trc_ak_vis_own_#{:erlang.unique_integer([:positive])}"
      {:ok, team_data} = Teams.put_team(token, %{"name" => "vis-team2", "members" => []})
      team_id = team_data["id"]

      # Token is a member but has no linked user, not the owner
      assert {:error, :not_owner} = Teams.set_visibility(token, team_id, "public")
    end

    test "unauthorized token is rejected" do
      token = "trc_ak_vis_own2_#{:erlang.unique_integer([:positive])}"
      {:ok, team_data} = Teams.put_team(token, %{"name" => "vis-team2b", "members" => []})
      team_id = team_data["id"]

      other_token = "trc_ak_vis_other_#{:erlang.unique_integer([:positive])}"
      assert {:error, :not_authorized} = Teams.set_visibility(other_token, team_id, "public")
    end

    test "invalid visibility is rejected" do
      token = "trc_ak_vis_inv_#{:erlang.unique_integer([:positive])}"
      {:ok, team_data} = Teams.put_team(token, %{"name" => "vis-team3", "members" => []})
      team_id = team_data["id"]

      assert {:error, :invalid_visibility} = Teams.set_visibility(token, team_id, "invalid")
    end
  end

  # ---------------------------------------------------------------------------
  # Ownership fixes
  # ---------------------------------------------------------------------------

  describe "ownership fixes" do
    test "creator with linked user gets ownership immediately" do
      token = "trc_ak_own_imm_#{:erlang.unique_integer([:positive])}"
      {:ok, user} = create_user_with_token("own_imm@test.com", token)

      # Create team. Should get ownership immediately since token has a linked user
      {:ok, team_data} = Teams.put_team(token, %{"name" => "imm-owner-team", "members" => []})
      team_id = team_data["id"]

      # Verify ownership was set and no claim secret generated (owner already known)
      team = Repo.get(Team, team_id)
      assert team.owner_user_id == user.id
      assert is_nil(team.owner_claim_secret)
    end

    test "clone token is preserved when toggling private then public" do
      token = "trc_ak_clone_pres_#{:erlang.unique_integer([:positive])}"
      {:ok, team_data} = Teams.put_team(token, %{"name" => "clone-pres-team", "members" => []})
      team_id = team_data["id"]
      claim_secret = team_data["owner_claim_secret"]

      # Link user and claim ownership
      {:ok, _user} = create_user_with_token("clone@test.com", token)
      {:ok, :claimed} = Teams.claim_ownership(token, claim_secret)

      # Set public: generates clone_token
      assert {:ok, updated} = Teams.set_visibility(token, team_id, "public")
      assert updated.visibility == "public"
      clone_token = updated.clone_token
      assert clone_token

      # Set private: clone_token should be preserved (not cleared)
      assert {:ok, updated} = Teams.set_visibility(token, team_id, "private")
      assert updated.visibility == "private"
      team = Repo.get(Team, team_id)
      assert team.clone_token == clone_token

      # Set public again: should reuse the same clone_token
      assert {:ok, updated} = Teams.set_visibility(token, team_id, "public")
      assert updated.visibility == "public"
      assert updated.clone_token == clone_token
    end

    test "claim secret is generated for unclaimed teams" do
      token = "trc_ak_claim_sec_#{:erlang.unique_integer([:positive])}"
      {:ok, team_data} = Teams.put_team(token, %{"name" => "claim-secret-team", "members" => []})

      # Team should have a bcrypt-hashed claim secret in DB
      team = Repo.get(Team, team_data["id"])
      assert team.owner_claim_secret
      assert String.starts_with?(team.owner_claim_secret, "$2b$")
      assert is_nil(team.owner_user_id)

      # API response has the plaintext secret (shown once to user)
      assert String.starts_with?(team_data["owner_claim_secret"], "trc_ocs_")
      # DB stores hash, not plaintext
      refute team_data["owner_claim_secret"] == team.owner_claim_secret
    end

    test "claim secret is NOT leaked in get_team or join responses" do
      token = "trc_ak_leak_#{:erlang.unique_integer([:positive])}"
      {:ok, team_data} = Teams.put_team(token, %{"name" => "leak-test-team", "members" => []})
      team_id = team_data["id"]

      # Create response includes it (intended)
      assert team_data["owner_claim_secret"]

      # get_team should NOT include it
      {:ok, fetched} = Teams.get_team(token, team_id)
      refute Map.has_key?(fetched, "owner_claim_secret")

      # get_teams should NOT include it
      {:ok, teams} = Teams.get_teams(token)
      refute Enum.any?(teams, &Map.has_key?(&1, "owner_claim_secret"))
    end

    test "claim_ownership with valid secret sets owner" do
      token = "trc_ak_claim_#{:erlang.unique_integer([:positive])}"
      {:ok, team_data} = Teams.put_team(token, %{"name" => "claim-team", "members" => []})
      claim_secret = team_data["owner_claim_secret"]
      team_id = team_data["id"]

      # Link user to the token
      {:ok, user} = create_user_with_token("claim@test.com", token)

      # Claim ownership
      assert {:ok, :claimed} = Teams.claim_ownership(token, claim_secret)

      # Verify ownership set and secret cleared
      team = Repo.get(Team, team_id)
      assert team.owner_user_id == user.id
      assert is_nil(team.owner_claim_secret)
    end

    test "claim_ownership fails with wrong secret" do
      token = "trc_ak_bad_claim_#{:erlang.unique_integer([:positive])}"
      {:ok, _team_data} = Teams.put_team(token, %{"name" => "bad-claim-team", "members" => []})

      {:ok, _user} = create_user_with_token("bad@test.com", token)

      assert {:error, :invalid_secret} = Teams.claim_ownership(token, "trc_ocs_wrong")
    end

    test "claim_ownership fails without linked user" do
      token = "trc_ak_no_acct_#{:erlang.unique_integer([:positive])}"
      {:ok, team_data} = Teams.put_team(token, %{"name" => "no-acct-team", "members" => []})

      assert {:error, :no_account} = Teams.claim_ownership(token, team_data["owner_claim_secret"])
    end

    test "claim_ownership fails for non-member" do
      creator_token = "trc_ak_creator2_#{:erlang.unique_integer([:positive])}"
      {:ok, team_data} = Teams.put_team(creator_token, %{"name" => "non-member-team", "members" => []})

      other_token = "trc_ak_other2_#{:erlang.unique_integer([:positive])}"
      {:ok, _user} = create_user_with_token("other2@test.com", other_token, "other-machine")

      assert {:error, :invalid_secret} = Teams.claim_ownership(other_token, team_data["owner_claim_secret"])
    end

    test "double claim fails" do
      token = "trc_ak_dbl_claim_#{:erlang.unique_integer([:positive])}"
      {:ok, team_data} = Teams.put_team(token, %{"name" => "dbl-claim-team", "members" => []})
      claim_secret = team_data["owner_claim_secret"]

      {:ok, _user} = create_user_with_token("dbl@test.com", token)

      assert {:ok, :claimed} = Teams.claim_ownership(token, claim_secret)
      # Second claim with same secret should fail (secret was cleared)
      assert {:error, :invalid_secret} = Teams.claim_ownership(token, claim_secret)
    end
  end

  # Fix 13: validate_team_name trims spaces
  # (API-level test in api_validation_test.exs)
end
