# ReactiveCommons

The purpose of `:reactive_commons` is to provide a set of abstractions and implementations over different patterns and
practices that make the foundation of a reactive microservices' architecture.

Even though the main purpose is to provide such abstractions in a mostly generic way such abstractions would be of
little use without a concrete implementation, so we provide some implementations in a best efforts' manner that aim to
be easy to change, personalize and extend.

The first approach to this work was to release a very simple abstractions, and a corresponding implementation over
asynchronous message driven communication between microservices build on top of amqp for RabbitMQ.

See more about this project at [reactivecommons.org](https://reactivecommons.org/)

## Installation

### Requirements

`elixir ~> 1.10`

### Dependencies

Releases are published through [available in Hex](https://hex.pm/docs/publish), the package can be installed by adding
`reactive_commons` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:reactive_commons, "~> 0.1.0"}
  ]
end
```

## Setup

Add `MessageRuntime` to your applications children

```elixir
  async_config = AsyncConfig.new("my-app-name")
  ...
  children = [
    {MessageRuntime, async_config},
  ]
```

## Main Components

There are three main modules:

- `HandlerRegistry`: This module allows the subscription for events, commands and async queries.
- `DomainEventBus`: This module allows the domain events emission.
- `DirectAsyncGateway`: This module allows the commands' emission and async queries requests.

These modules allow the next communication models:

- Event emission through `DomainEventBus` and Event subscription with `HandlerRegistry` from any stakeholder.
- Command emission through `DirectAsyncGateway` to a specific application target and handle this command from the target
  through `HandlerRegistry`.
- Async Query request through `DirectAsyncGateway` to a specific application target and handle this query from the target
  through `HandlerRegistry`.

## Usage

## Examples

```elixir
  query = AsyncQuery.new("query_path", %{field: "value", field_n: 42})
  {:ok, response} = DirectAsyncGateway.request_reply_wait(query, @target)
```

