defmodule Teamrc.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime
    field :authenticated_at, :utc_datetime, virtual: true

    # ToS acceptance
    field :accepted_terms_at, :utc_datetime
    field :terms_version_accepted, :string

    # OAuth provider info
    field :provider, :string
    field :provider_uid, :string
    field :avatar_url, :string

    has_many :machine_tokens, Teamrc.Accounts.MachineToken
    has_one :user_profile, Teamrc.Accounts.UserProfile

    timestamps(type: :utc_datetime)
  end

  @doc """
  A user changeset for registering or changing the email.

  It requires the email to change otherwise an error is added.

  ## Options

    * `:validate_unique` - Set to false if you don't want to validate the
      uniqueness of the email, useful when displaying live validations.
      Defaults to `true`.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
  end

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> validate_required([:email])
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
        message: "must have the @ sign and no spaces"
      )
      |> validate_length(:email, max: 160)

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, Teamrc.Repo)
      |> unique_constraint(:email)
      |> validate_email_changed()
    else
      changeset
    end
  end

  defp validate_email_changed(changeset) do
    if get_field(changeset, :email) && get_change(changeset, :email) == nil do
      add_error(changeset, :email, "did not change")
    else
      changeset
    end
  end

  @doc """
  A user changeset for changing the password.

  It is important to validate the length of the password, as long passwords may
  be very expensive to hash for certain algorithms.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      # If using Bcrypt, then further validate it is at most 72 bytes long
      |> validate_length(:password, max: 72, count: :bytes)
      # Hashing could be done with `Ecto.Changeset.prepare_changes/2`, but that
      # would keep the database transaction open longer and hurt performance.
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  A changeset for creating users via OAuth (no password required).
  """
  def oauth_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :provider, :provider_uid, :avatar_url, :confirmed_at])
    |> validate_required([:email, :provider, :provider_uid])
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> validate_length(:email, max: 160)
    # M3 fix: validate provider_uid length
    |> validate_length(:provider_uid, max: 255)
    |> unique_constraint(:email)
    |> unique_constraint([:provider, :provider_uid])
  end

  @doc """
  A changeset for recording terms of service acceptance.
  """
  def terms_changeset(user, attrs) do
    user
    |> cast(attrs, [:accepted_terms_at, :terms_version_accepted])
    |> validate_required([:accepted_terms_at, :terms_version_accepted])
  end

  @doc """
  Validates that terms of service have been accepted during registration.
  Designed to be piped after `email_changeset/2` in the registration flow.

  Stamps `accepted_terms_at` and `terms_version_accepted` server-side only.
  These values are never cast from user input to prevent bypass attacks.
  Expects `"terms_accepted" => "true"` in attrs.
  """
  def registration_terms_changeset(changeset, %{"terms_accepted" => "true"}) do
    now = DateTime.utc_now(:second)

    changeset
    |> put_change(:accepted_terms_at, now)
    |> put_change(:terms_version_accepted, Teamrc.Accounts.current_terms_version())
  end

  def registration_terms_changeset(changeset, _attrs) do
    add_error(changeset, :terms_accepted, "terms of service must be accepted to register")
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = DateTime.utc_now(:second)
    change(user, confirmed_at: now)
  end

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Bcrypt.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%Teamrc.Accounts.User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end
end
