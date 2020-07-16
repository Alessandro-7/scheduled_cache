defmodule ScheduledCache.MixProject do
  use Mix.Project

  def project do
    [
      app: :scheduled_cache,
      version: "0.1.0",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer_opts()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:rocksdb, "~> 1.0"},
      {:crontab, "~> 1.1.2"},
      {:credo, "~> 1.4", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:inch_ex, "~> 2.0", only: [:dev, :test], runtime: false},
      {:propcheck, "~> 1.1", only: [:test, :dev]}
    ]
  end

  def dialyzer_opts do
    [
      flags: [
        :error_handling,
        :race_conditions,
        :underspecs
      ],
      remove_defaults: [:unknown]
    ]
  end
end
