[![Scorecards supply-chain security](https://github.com/bancolombia/reactive-commons-elixir/actions/workflows/scorecards-analysis.yml/badge.svg)](https://github.com/bancolombia/reactive-commons-elixir/actions/workflows/scorecards-analysis.yml)
# ReactiveCommons

[![hex.pm version](https://img.shields.io/hexpm/v/reactive_commons.svg?style=flat)](https://hex.pm/packages/reactive_commons)
[![hex.pm downloads](https://img.shields.io/hexpm/dt/reactive_commons.svg?style=flat)](https://hex.pm/packages/reactive_commons)

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

Releases are published at [Hex](https://hex.pm/packages/reactive_commons), the package can be installed by adding
`reactive_commons` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:reactive_commons, "~> 0.1.0"}
  ]
end
```

## Setup

Add `MessageRuntime` to your applications children passing the `AsyncConfig` parameter struct as arguments.

```elixir
  async_config = AsyncConfig.new("my-app-name")
  ...
  children = [
    {MessageRuntime, async_config},
  ]
```

## Semantic Main Components Definition

There are three semantic structures:

- `DomainEvent`
  This structure lets you represent an Event in the system. It accepts a `name`, any `data` that will be the information
  to transport for that event (should be JSON serializable), and an optional `message_id`.

- `Command`
  Another basic structure is the Command. This structure lets you represent a Command in the system. It accepts a
  `name`, any `data` that will be the information to transport for that command (should be JSON serializable), and an
  optional `command_id`.

- `AsyncQuery`
  Another basic structure is the AsyncQuery. This class lets you represent a Query in the system. It accepts a JSON
  serializable called `data` that will be the information for that query and a `resource` name for thw query.

There are three main modules:

- `HandlerRegistry`
- `DomainEventBus`
- `DirectAsyncGateway`

These modules allow the next communication models:

- `DomainEvent` emission through `DomainEventBus` and Event subscription with `HandlerRegistry` from any stakeholder.
- `Command` emission through `DirectAsyncGateway` to a specific application target and handle this command from the
  target through `HandlerRegistry`.
- `AsyncQuery` request through `DirectAsyncGateway` to a specific application target and handle this query from the
  target through `HandlerRegistry`.

## Usage

This section describes the reactive API for producing and consuming messages using Reactive Commons

1. Sending Domain Events, Commands and Async Queries

   1.1. Sending Commands

    ```elixir
    @command_name "RegisterPerson"
    data = Person.new_sample() # any data map
    ...
    command = Command.new(@command_name, data)
    :ok = DirectAsyncGateway.send_command(command, @target) # use any control structure to handle errors
   ```

   1.2. Sending Async Queries

    ```elixir
    @query_path "GetPerson"
    data = PersonDataReq.new_sample() # any data map
    ...
    query = AsyncQuery.new(@query_path, data)
    {:ok, person} = DirectAsyncGateway.request_reply_wait(query, @target) # use any control structure to handle errors
   ```

   1.3. Sending Domain Events

    ```elixir
    @event_name "PersonRegistered"
    data = PersonRegistered.new_sample() # any data map
    ...
    event = DomainEvent.new(@event_name, data)
    :ok = DomainEventBus.emit(event) # use any control structure to handle errors {:emit_fail, error}
   ```
   
    **See sample project for further details** [Sender](https://github.com/bancolombia/reactive-commons-elixir/blob/main/samples/query-client/lib/query_client/rest_controller.ex)


2. Listening and handling for Domain Events, Commands and Async Queries

   ```elixir
    defmodule QueryServer.SubsConfig do
        use GenServer
    
        @query_name "GetPerson"
        @command_name "RegisterPerson"
        @event_name "PersonRegistered"
    
        def start_link(_) do
          GenServer.start_link(__MODULE__, [], name: __MODULE__)
        end
    
        @impl true
        def init(_) do
          HandlerRegistry.serve_query(@query_name, &get_person/1) # serve a query, should pass query_name and the function which will handle the request.
          |> HandlerRegistry.handle_command(@command_name, &register_person/1) # listen for a command, should pass command_name and the function which will handle the command.
          |> HandlerRegistry.listen_event(@event_name, &person_registered/1) # listen for an event, should pass event_name and the function which will handle the event.
          |> HandlerRegistry.commit_config() # finally should commit the config to configure the listeners.
          {:ok, nil}
        end
    
        # Sample functions (should be in a separated module)
        def get_person(%{} = request) do
          IO.puts "Handling async query #{inspect(request)}"
          Process.sleep(150)
          Person.new_sample()
        end
    
        def register_person(%{} = command) do
          IO.puts "Handling command #{inspect(command)}"
          event = DomainEvent.new(@event_name, PersonRegistered.new_sample(command["data"]))
          Process.sleep(150)
          :ok = DomainEventBus.emit(event)
        end
    
        def person_registered(%{} = event) do
          IO.puts "Handling event #{inspect(event)}"
        end
    end
   ```

    **See sample project for further details** [Receiver](https://github.com/bancolombia/reactive-commons-elixir/blob/main/samples/query-server/lib/query_server/subs_config.ex)

