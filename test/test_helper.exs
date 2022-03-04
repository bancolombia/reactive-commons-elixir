ExUnit.configure formatters: [JUnitFormatter, ExUnit.CLIFormatter, ExUnitSonarqube]
ExUnit.start(exclude: [:skip])
