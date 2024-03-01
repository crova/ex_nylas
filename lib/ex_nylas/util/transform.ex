defmodule ExNylas.Transform do
  @moduledoc """
  Generic transform functions for data returned by the Nylas API
  """

  alias ExNylas.Common.Response
  import Ecto.Changeset
  import ExNylas, only: [format_module_name: 1]
  require Logger

  @status_codes %{
    200 => :ok,
    201 => :created,
    202 => :accepted,
    204 => :no_content,
    400 => :bad_request,
    401 => :unauthorized,
    403 => :forbidden,
    404 => :not_found,
    405 => :method_not_allowed,
    406 => :not_acceptable,
    409 => :conflict,
    410 => :gone,
    411 => :length_required,
    412 => :precondition_failed,
    413 => :payload_too_large,
    414 => :uri_too_long,
    415 => :unsupported_media_type,
    418 => :im_a_teapot,
    429 => :too_many_requests,
    500 => :internal_server_error,
    501 => :not_implemented,
    502 => :bad_gateway,
    503 => :service_unavailable,
    504 => :gateway_timeout
  }

  def transform(body, status, model, true = _use_common, true = _transform) do
    %Response{}
    |> Response.changeset(preprocess_body(model, body, status))
    |> apply_changes()
  end

  def transform(body, _status, model, false = _use_common, true = _transform) do
    preprocess_data(model, body)
  end

  def transform(body, _status, _model, _use_common, false = _transform), do: body

  def transfrom_stream({:data, data}, {req, %{status: status} = resp}, fun) when status in 200..299 do
    ~r/\{.*?\}/
    |> Regex.scan(data)
    |> List.first("{}")
    |> Jason.decode!()
    |> Map.get("suggestion")
    |> fun.()

    {:cont, {req, resp}}
  end

  def transfrom_stream({:data, data}, {req, resp}, _fun) do
    resp = Map.put(resp, :body, data)
    {:cont, {req, resp}}
  end

  defp preprocess_body(model, body, status) do
    body
    |> Map.put("data", preprocess_data(model, body["data"]))
    |> Map.put("status", status_to_atom(status))
  end

  defp preprocess_data(nil, data), do: data

  defp preprocess_data(model, data) when is_map(data) do
    model.__struct__
    |> model.changeset(remove_nil_values(data))
    |> log_validations(model)
    |> apply_changes()
  end

  defp preprocess_data(model, data) when is_list(data) do
    Enum.map(data, &preprocess_data(model, &1))
  end

  defp preprocess_data(_model, data), do: data

  defp log_validations(%{valid?: true} = changeset, _model), do: changeset

  defp log_validations(changeset, model) do
    traverse_errors(changeset, fn _changeset, field, {msg, opts} ->
      Logger.warning("Validation error while transforming #{format_module_name(model)}: #{field} #{msg} #{inspect(opts)}")
    end)

    changeset
  end

  defp status_to_atom(status), do: Map.get(@status_codes, status, :unknown)

  # Nylas sometimes returns a nil value for a field where a list is expected,
  # which causes an Ecto validation error.
  defp remove_nil_values(data), do: Map.reject(data, fn {_k, v} -> v == nil end)
end
