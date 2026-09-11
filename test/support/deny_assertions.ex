defmodule Lotus.ClickHouse.Test.DenyAssertions do
  @moduledoc """
  Helpers to assert on `builtin_denies/1` entries.

  Regex structs cannot be compared with `==` on OTP 29 and later. `:re.compile/2`
  gives a unique reference for each call, so two regexes with the same source are
  never equal. Compare the source instead.
  """

  @doc """
  Returns true if `denies` has an entry for `schema` with a regex of `source`.
  """
  def denies_pattern?(denies, schema, source \\ ".*") do
    Enum.any?(denies, fn
      {^schema, %Regex{} = re} -> Regex.source(re) == source
      _ -> false
    end)
  end
end
