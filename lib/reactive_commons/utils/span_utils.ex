defmodule ReactiveCommons.Utils.SpanUtils do
  @moduledoc false

  def inject(headers, from) do
    case Code.ensure_compiled(OpentelemetryReactiveCommons.Utils) do
      {:module, _} ->
        apply(OpentelemetryReactiveCommons.Utils, :inject, [headers, from])

      _ ->
        headers
    end
  end
end
