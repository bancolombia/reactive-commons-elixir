defmodule ReactiveCommons.Utils.SpanUtils do
  @moduledoc false
  def inject(headers, from) do
    if Code.ensure_loaded?(OpentelemetryReactiveCommons.Utils) and
         function_exported?(OpentelemetryReactiveCommons.Utils, :inject, 2) do
      apply(OpentelemetryReactiveCommons.Utils, :inject, [headers, from])
    else
      headers
    end
  end
end
