defmodule Teamrc.DeviceAuth.Request do
  @moduledoc "Ephemeral struct representing a device authorization request."

  defstruct [
    :device_code,
    :user_code,
    :token,
    :status,
    :user_id,
    :email,
    :expires_at,
    :inserted_at,
    failed_attempts: 0
  ]
end
