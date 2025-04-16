defmodule MCPEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :mcp_ex,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description: "Elixir client for the Model Context Protocol (MCP)",
      name: "MCPEx",
      package: package(),
      aliases: aliases()
    ]
  end

  # Run "mix help compile.app" to learn about applications
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Specifies which paths to compile per environment
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies
  defp deps do
    [
      {:jason, "~> 1.4"},
      {:httpoison, "~> 2.0"},
      {:req, "~> 0.5.0"},
      {:ex_json_schema, "~> 0.10.2"},
      {:ex_doc, "~> 0.29", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      name: "mcp_ex",
      maintainers: ["Mase Graye <mg@mg.dev>"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/masegraye/mcp_ex"}
    ]
  end

  defp aliases do
    [
      test: ["test"]
    ]
  end
end
