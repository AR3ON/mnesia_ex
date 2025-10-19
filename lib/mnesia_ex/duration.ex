defmodule MnesiaEx.Duration do
  @moduledoc """
  Provides functions for handling time durations.
  Allows converting different time units to milliseconds.

  Accepts both singular and plural forms of time units:
  - `:hour` or `:hours`
  - `:minute` or `:minutes`
  - `:second` or `:seconds`
  - `:day` or `:days`
  - `:week` or `:weeks`
  - `:month` or `:months`
  - `:year` or `:years`
  """

  require MnesiaEx.Monad, as: Error

  @type time_unit ::
          :millisecond | :milliseconds
          | :second | :seconds
          | :minute | :minutes
          | :hour | :hours
          | :day | :days
          | :week | :weeks
          | :month | :months
          | :year | :years
  @type duration :: integer() | {integer(), time_unit()}
  @type result :: {:ok, integer()} | {:error, term()}

  @milliseconds_per_unit %{
    # Singular forms
    millisecond: 1,
    second: 1_000,
    minute: 60_000,
    hour: 3_600_000,
    day: 86_400_000,
    week: 604_800_000,
    month: 2_592_000_000,  # 30 days
    year: 31_536_000_000,  # 365 days
    # Plural forms (aliases)
    milliseconds: 1,
    seconds: 1_000,
    minutes: 60_000,
    hours: 3_600_000,
    days: 86_400_000,
    weeks: 604_800_000,
    months: 2_592_000_000,
    years: 31_536_000_000
  }

  @doc """
  Converts a duration to milliseconds.

  Accepts both singular and plural forms of time units.

  ## Examples

      iex> MnesiaEx.Duration.to_milliseconds(1000)
      {:ok, 1000}

      iex> MnesiaEx.Duration.to_milliseconds({5, :minutes})
      {:ok, 300000}

      iex> MnesiaEx.Duration.to_milliseconds({5, :minute})
      {:ok, 300000}

      iex> MnesiaEx.Duration.to_milliseconds({1, :hour})
      {:ok, 3600000}

      iex> MnesiaEx.Duration.to_milliseconds({1, :day})
      {:ok, 86400000}

      iex> MnesiaEx.Duration.to_milliseconds({2, :invalid})
      {:error, :invalid_unit}
  """
  @spec to_milliseconds(duration()) :: result()
  def to_milliseconds(duration) when is_integer(duration), do: Error.return(duration)

  def to_milliseconds({value, unit}) when is_integer(value) and value > 0 and is_atom(unit) do
    Map.fetch(@milliseconds_per_unit, unit)
    |> transform_multiplier(value)
  end

  def to_milliseconds({_value, _unit}), do: Error.fail(:invalid_duration)

  defp transform_multiplier({:ok, multiplier}, value), do: Error.return(value * multiplier)
  defp transform_multiplier(:error, _value), do: Error.fail(:invalid_unit)

  @doc """
  Converts a duration to milliseconds. Raises an exception if the duration is invalid.

  ## Examples

      iex> MnesiaEx.Duration.to_milliseconds!({5, :minutes})
      300000

      iex> MnesiaEx.Duration.to_milliseconds!({2, :invalid})
      ** (ArgumentError) invalid time unit: :invalid
  """
  @spec to_milliseconds!(duration()) :: integer() | no_return()
  def to_milliseconds!(duration) do
    to_milliseconds(duration)
    |> unwrap_or_raise(duration)
  end

  defp unwrap_or_raise({:ok, milliseconds}, _duration), do: milliseconds

  defp unwrap_or_raise({:error, :invalid_unit}, {_value, unit}) do
    raise ArgumentError, "invalid time unit: #{inspect(unit)}"
  end

  defp unwrap_or_raise({:error, :invalid_duration}, duration) do
    raise ArgumentError, "invalid duration: #{inspect(duration)}"
  end

  defp unwrap_or_raise({:error, :invalid_unit}, duration) do
    raise ArgumentError, "invalid duration: #{inspect(duration)}"
  end

  # Pure functions - no side effects
end
