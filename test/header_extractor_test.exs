defmodule HeaderExtractorTest do
  use ExUnit.Case
  doctest HeaderExtractor

  test "should extract x_deaths count" do
    headers = [
      {"sourceApplication", :longstr, "message-extractor"},
      {"x-death", :array,
       [
         table: [
           {"count", :long, 6},
           {"exchange", :longstr, "sample5.domainEvents.DLQ"},
           {"time", :timestamp, 1_617_027_623}
         ],
         table: [
           {"count", :long, 6},
           {"exchange", :longstr, "domainEvents"}
         ]
       ]},
      {"x-first-death-exchange", :longstr, "domainEvents"}
    ]

    assert HeaderExtractor.get_x_death_count(headers) == 6
  end

  test "should get default value for x_deaths count" do
    headers0 = [
      {"sourceApplication", :longstr, "message-extractor"},
      {"x-first-death-exchange", :longstr, "domainEvents"}
    ]

    headers1 = [
      {"sourceApplication", :longstr, "message-extractor"},
      {"x-death", :array,
       [
         table: [
           {"exchange", :longstr, "sample5.domainEvents.DLQ"},
           {"time", :timestamp, 1_617_027_623}
         ],
         table: [
           {"exchange", :longstr, "domainEvents"}
         ]
       ]},
      {"x-first-death-exchange", :longstr, "domainEvents"}
    ]

    assert HeaderExtractor.get_x_death_count(headers0) == 0
    assert HeaderExtractor.get_x_death_count(headers1) == 0
  end

  test "Should extract header value" do
    headers0 = [
      {"sourceApplication", :longstr, "message-extractor"},
      {"x-first-death-exchange", :longstr, "domainEvents"}
    ]

    assert HeaderExtractor.get_header_value(headers0, "sourceApplication") == "message-extractor"
  end

  test "Should return default value for non-existent header" do
    headers0 = [
      {"sourceApplication", :longstr, "message-extractor"},
      {"x-first-death-exchange", :longstr, "domainEvents"}
    ]

    assert HeaderExtractor.get_header_value(headers0, "non-existent") == nil
    assert HeaderExtractor.get_header_value(headers0, "non-existent", 0) == 0
  end
end
