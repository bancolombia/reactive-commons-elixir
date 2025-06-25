defmodule ReactiveCommons.Utils.SpanUtils do
  @moduledoc false
  def inject(headers, from) do
    if Code.ensure_loaded?(OpentelemetryReactiveCommons.Utils) do
      OpentelemetryReactiveCommons.Utils.inject(headers, from)
    else
      headers
    end
  end
end
