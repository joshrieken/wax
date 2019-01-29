defmodule Wax.AttestationStatementFormat.FIDOU2F do
  require Logger

  @behaviour Wax.AttestationStatementFormat

  @impl Wax.AttestationStatementFormat
  def verify(att_stmt, auth_data, client_data_hash) do
    with :ok <- valid_cbor?(att_stmt),
         {:ok, pub_key} <- extract_and_verify_certificate(att_stmt),
         public_key_u2f <- get_raw_cose_key(auth_data),
         verification_data <- get_verification_data(auth_data, client_data_hash, public_key_u2f),
         :ok <- valid_signature?(att_stmt["sig"], verification_data, pub_key)
    do
      {:ok, {:basic, att_stmt["x5c"]}}
    else
      error ->
        error
    end
  end

  @spec valid_cbor?(Wax.Attestation.statement()) :: :ok | {:error, any()}
  defp valid_cbor?(att_stmt) do
    if is_binary(att_stmt["sig"])
    and is_list(att_stmt["x5c"])
    and length(Map.keys(att_stmt)) == 2 # only these two keys
    do
      :ok
    else
      {:error, :invalid_attestation_statement_cbor}
    end
  end

  @spec extract_and_verify_certificate(Wax.Attestation.statement()) ::
  {:ok, any()} | {:error, any()} #FIXME any()
  defp extract_and_verify_certificate(att_stmt) do
    case att_stmt["x5c"] do
      [der] ->
        pub_key =
          der
          |> X509.Certificate.from_der!()
          |> X509.Certificate.public_key()

        case pub_key do
          {:PublicKeyAlgorithm, {1, 2, 840, 10045, 2, 1},
            {:namedCurve, {1, 2, 840, 10045, 3, 1, 7}}} ->
              {:ok, pub_key}

          _ ->
            {:error, :fido_u2f_attestation_invalid_public_key_algorithm}
        end

        _ ->
          {:error, :fido_u2f_attestation_multiple_x5c}
    end
  end

  @spec get_raw_cose_key(Wax.AuthenticatorData.t()) :: binary()
  def get_raw_cose_key(auth_data) do
    x = auth_data.attested_credential_data.credential_public_key[-2]
    y = auth_data.attested_credential_data.credential_public_key[-3]

    <<04>> <> x <> y
  end

  @spec get_verification_data(Wax.AuthenticatorData.t(), Wax.ClientData.hash(), binary())
    :: binary()
  def get_verification_data(auth_data, client_data_hash, public_key_u2f) do
    <<0>>
    <> auth_data.rp_id_hash
    <> client_data_hash
    <> auth_data.attested_credential_data.credential_id
    <> public_key_u2f
  end

  @spec valid_signature?(binary(), binary(), X509.PublicKey.t()) :: :ok | {:error, any()}
  def valid_signature?(sig, verification_data, pub_key) do
    #FIXME: use X509 module instead
    if :public_key.verify(verification_data, :sha256, sig, pub_key) do
      :ok
    else
      {:error, :fido_u2f_invalid_attestation_signature}
    end
  end
end
