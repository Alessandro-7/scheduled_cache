alias Credo.Check.{Consistency, Design, Readability, Refactor, Warning}

%{
  # You can have as many configs as you like in the `configs:` field.
  configs: [
    %{
      name: "default",

      # These are the files included in the analysis:
      files: %{
        # included: ["lib/", "src/", "web/", "apps/"],

        # You can give explicit globs or simply directories.
        # In the latter case `**/*.{ex,exs}` will be used.
        excluded: [~r"/_build/", ~r"/deps/", ~r"/priv/"]
      },

      # If you create your own checks, you must specify the source files for
      # them here, so they can be loaded by Credo before running the analysis.
      requires: [],

      #
      # Credo automatically checks for updates, like e.g. Hex does.
      # You can disable this behaviour below:
      check_for_updates: true,

      strict: true,
      color: true,

      #
      # You can customize the parameters of any check by adding a second element
      # to the tuple.
      #
      # To disable a check put `false` as second element:
      #
      #     {Credo.Check.Design.DuplicatedCode, false}
      #
      checks: [
        {Readability.Specs, priority: :low},
        {Design.TagTODO, exit_status: 0},
        {Design.TagFIXME, exit_status: 0},

        {Readability.RedundantBlankLines, max_blank_lines: 2},
        {Readability.MaxLineLength, priority: :low,
         max_length: 100}
      ]
    }
  ]
}
