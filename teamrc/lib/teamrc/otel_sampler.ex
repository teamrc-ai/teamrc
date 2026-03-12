defmodule Teamrc.OtelSampler do
  @behaviour :otel_sampler

  def setup(excluded_routes) when is_list(excluded_routes), do: excluded_routes
  def setup(_), do: []

  def description(_), do: "HealthCheckFilter"

  def should_sample(_ctx, _trace_id, _links, _span_name, _span_kind, attributes, excluded_routes) do
    route = Map.get(attributes, :"url.path", Map.get(attributes, "url.path"))

    if route in excluded_routes do
      {:drop, [], []}
    else
      {:record_and_sample, [], []}
    end
  end
end
