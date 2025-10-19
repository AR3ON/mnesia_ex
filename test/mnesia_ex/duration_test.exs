defmodule MnesiaEx.DurationTest do
  use ExUnit.Case, async: true

  require MnesiaEx.Monad, as: Error

  alias MnesiaEx.Duration

  @moduletag :duration

  # Shared helper functions - available to all describe blocks

  defp validate_duration_result({:ok, actual}, expected) when actual == expected, do: :ok

  defp validate_duration_result({:ok, actual}, expected) do
    raise "Expected #{expected} ms but got #{actual} ms"
  end

  defp validate_duration_result({:error, reason}, _expected) do
    raise "Expected successful conversion but got error: #{inspect(reason)}"
  end

  defp validate_error_result({:error, actual_reason}, expected_reason)
       when actual_reason == expected_reason,
       do: :ok

  defp validate_error_result({:error, actual_reason}, expected_reason) do
    raise "Expected error #{inspect(expected_reason)} but got #{inspect(actual_reason)}"
  end

  defp validate_error_result({:ok, value}, expected_reason) do
    raise "Expected error #{inspect(expected_reason)} but got success: #{inspect(value)}"
  end

  defp validate_functor_identity({:ok, v1}, {:ok, v2}) when v1 == v2, do: :ok

  defp validate_functor_identity({:ok, v1}, {:ok, v2}) do
    raise "Functor identity failed: #{v1} != #{v2}"
  end

  defp validate_functor_identity(r1, r2) do
    raise "Functor identity failed: #{inspect(r1)} != #{inspect(r2)}"
  end

  defp validate_exact_value(actual, expected) when actual == expected, do: :ok

  defp validate_exact_value(actual, expected) do
    raise "Expected #{expected} but got #{actual}"
  end

  describe "to_milliseconds/1 - pure functional conversions" do
    test "converts integer directly to milliseconds" do
      result = Duration.to_milliseconds(5000)
      validate_duration_result(result, 5000)
    end

    test "converts seconds to milliseconds" do
      result = Duration.to_milliseconds({5, :seconds})
      validate_duration_result(result, 5_000)
    end

    test "converts minutes to milliseconds" do
      result = Duration.to_milliseconds({10, :minutes})
      validate_duration_result(result, 600_000)
    end

    test "converts hours to milliseconds" do
      result = Duration.to_milliseconds({2, :hours})
      validate_duration_result(result, 7_200_000)
    end

    test "converts days to milliseconds" do
      result = Duration.to_milliseconds({1, :days})
      validate_duration_result(result, 86_400_000)
    end

    test "converts weeks to milliseconds" do
      result = Duration.to_milliseconds({1, :weeks})
      validate_duration_result(result, 604_800_000)
    end

    test "converts months to milliseconds (30 days)" do
      result = Duration.to_milliseconds({1, :months})
      validate_duration_result(result, 2_592_000_000)
    end

    test "converts years to milliseconds (365 days)" do
      result = Duration.to_milliseconds({1, :years})
      validate_duration_result(result, 31_536_000_000)
    end

    test "fails on invalid time unit" do
      result = Duration.to_milliseconds({5, :invalid})
      validate_error_result(result, :invalid_unit)
    end

    test "fails on invalid duration tuple" do
      result = Duration.to_milliseconds({-5, :seconds})
      validate_error_result(result, :invalid_duration)
    end

    test "fails on zero value" do
      result = Duration.to_milliseconds({0, :seconds})
      validate_error_result(result, :invalid_duration)
    end
  end

  describe "to_milliseconds!/1 - bang version with exceptions" do
    test "converts valid duration successfully" do
      result = Duration.to_milliseconds!({5, :minutes})
      validate_exact_value(result, 300_000)
    end

    test "converts integer directly" do
      result = Duration.to_milliseconds!(1000)
      validate_exact_value(result, 1000)
    end

    test "raises on invalid unit" do
      assert_raise ArgumentError, "invalid time unit: :invalid", fn ->
        Duration.to_milliseconds!({5, :invalid})
      end
    end

    test "raises on invalid duration" do
      assert_raise ArgumentError, "invalid duration: {-5, :seconds}", fn ->
        Duration.to_milliseconds!({-5, :seconds})
      end
    end
  end

  describe "pure functional properties - functor laws" do
    test "to_milliseconds respects functor identity law" do
      duration = {5, :minutes}

      result1 = Duration.to_milliseconds(duration)

      result2 =
        Error.m do
          ms <- Duration.to_milliseconds(duration)
          Error.return(ms)
        end

      validate_functor_identity(result1, result2)
    end

    test "to_milliseconds is composable" do
      composed_result =
        Error.m do
          ms1 <- Duration.to_milliseconds({1, :minutes})
          ms2 <- Duration.to_milliseconds({30, :seconds})
          Error.return(ms1 + ms2)
        end

      validate_duration_result(composed_result, 90_000)
    end

    test "multiple conversions compose correctly" do
      composed =
        Error.m do
          hours <- Duration.to_milliseconds({2, :hours})
          minutes <- Duration.to_milliseconds({30, :minutes})
          seconds <- Duration.to_milliseconds({45, :seconds})
          Error.return(hours + minutes + seconds)
        end

      validate_duration_result(composed, 9_045_000)
    end

    test "error propagation in monadic composition" do
      composed =
        Error.m do
          valid <- Duration.to_milliseconds({1, :hours})
          invalid <- Duration.to_milliseconds({5, :invalid})
          Error.return(valid + invalid)
        end

      validate_error_result(composed, :invalid_unit)
    end
  end

  describe "conversion accuracy - mathematical properties" do
    test "seconds conversion is exact" do
      sequence = [
        {1, :seconds, 1_000},
        {60, :seconds, 60_000},
        {3600, :seconds, 3_600_000}
      ]

      validate_conversion_sequence(sequence)
    end

    test "minutes conversion is exact" do
      sequence = [
        {1, :minutes, 60_000},
        {5, :minutes, 300_000},
        {60, :minutes, 3_600_000}
      ]

      validate_conversion_sequence(sequence)
    end

    test "hours conversion is exact" do
      sequence = [
        {1, :hours, 3_600_000},
        {24, :hours, 86_400_000}
      ]

      validate_conversion_sequence(sequence)
    end

    test "days conversion is exact" do
      sequence = [
        {1, :days, 86_400_000},
        {7, :days, 604_800_000},
        {30, :days, 2_592_000_000}
      ]

      validate_conversion_sequence(sequence)
    end

    test "composition maintains precision" do
      hours_result = Duration.to_milliseconds({1, :hours})
      minutes_result = Duration.to_milliseconds({60, :minutes})

      validate_functor_identity(hours_result, minutes_result)
    end

    defp validate_conversion_sequence([]), do: :ok

    defp validate_conversion_sequence([{value, unit, expected_ms} | rest]) do
      result = Duration.to_milliseconds({value, unit})
      validate_duration_result(result, expected_ms)
      validate_conversion_sequence(rest)
    end
  end

  describe "edge cases - boundary conditions" do
    test "handles minimum valid value" do
      result = Duration.to_milliseconds({1, :milliseconds})
      validate_duration_result(result, 1)
    end

    test "handles large values" do
      result = Duration.to_milliseconds({1000, :days})
      validate_duration_result(result, 86_400_000_000)
    end

    test "rejects negative values" do
      result = Duration.to_milliseconds({-1, :seconds})
      validate_error_result(result, :invalid_duration)
    end

    test "rejects zero values" do
      result = Duration.to_milliseconds({0, :minutes})
      validate_error_result(result, :invalid_duration)
    end

    test "rejects non-atom units" do
      result = Duration.to_milliseconds({5, "seconds"})
      validate_error_result(result, :invalid_duration)
    end

    test "direct milliseconds bypass conversion" do
      value = 12345
      result = Duration.to_milliseconds(value)
      validate_duration_result(result, value)
    end
  end

  describe "monadic laws verification" do
    test "left identity: return(x) >>= f === f(x)" do
      duration = {5, :minutes}

      left_side =
        Error.m do
          d <- Error.return(duration)
          Duration.to_milliseconds(d)
        end

      right_side = Duration.to_milliseconds(duration)

      validate_functor_identity(left_side, right_side)
    end

    test "right identity: m >>= return === m" do
      original = Duration.to_milliseconds({10, :seconds})

      composed =
        Error.m do
          ms <- Duration.to_milliseconds({10, :seconds})
          Error.return(ms)
        end

      validate_functor_identity(original, composed)
    end

    test "associativity: (m >>= f) >>= g === m >>= (\\x -> f(x) >>= g)" do
      f = fn ms -> Error.return(ms * 2) end
      g = fn ms -> Error.return(ms + 1000) end

      left_side =
        Error.m do
          ms <- Duration.to_milliseconds({5, :seconds})
          doubled <- f.(ms)
          g.(doubled)
        end

      right_side =
        Error.m do
          ms <- Duration.to_milliseconds({5, :seconds})

          result <-
            Error.m do
              doubled <- f.(ms)
              g.(doubled)
            end

          Error.return(result)
        end

      validate_functor_identity(left_side, right_side)
    end
  end

  describe "error handling - pure error propagation" do
    test "invalid unit propagates error through composition" do
      result =
        Error.m do
          ms <- Duration.to_milliseconds({5, :invalid_unit})
          Error.return(ms * 2)
        end

      validate_error_result(result, :invalid_unit)
    end

    test "invalid duration propagates error" do
      result =
        Error.m do
          ms <- Duration.to_milliseconds({-5, :seconds})
          Error.return(ms + 1000)
        end

      validate_error_result(result, :invalid_duration)
    end

    test "error in chain stops execution" do
      result =
        Error.m do
          valid1 <- Duration.to_milliseconds({1, :hours})
          invalid <- Duration.to_milliseconds({5, :bad_unit})
          valid2 <- Duration.to_milliseconds({30, :minutes})
          Error.return(valid1 + invalid + valid2)
        end

      validate_error_result(result, :invalid_unit)
    end
  end

  describe "integration with real-world use cases" do
    test "calculates timeout values" do
      timeout_sequences = [
        {{5, :seconds}, 5_000},
        {{1, :minutes}, 60_000},
        {{30, :seconds}, 30_000}
      ]

      validate_timeout_sequence(timeout_sequences)
    end

    test "calculates TTL values" do
      ttl_sequences = [
        {{1, :days}, 86_400_000},
        {{7, :days}, 604_800_000},
        {{1, :hours}, 3_600_000}
      ]

      validate_timeout_sequence(ttl_sequences)
    end

    test "composes multiple durations for total time" do
      total_time =
        Error.m do
          processing <- Duration.to_milliseconds({5, :minutes})
          waiting <- Duration.to_milliseconds({30, :seconds})
          buffer <- Duration.to_milliseconds({10, :seconds})
          Error.return(processing + waiting + buffer)
        end

      validate_duration_result(total_time, 340_000)
    end

    defp validate_timeout_sequence([]), do: :ok

    defp validate_timeout_sequence([{duration, expected} | rest]) do
      result = Duration.to_milliseconds(duration)
      validate_duration_result(result, expected)
      validate_timeout_sequence(rest)
    end
  end

  describe "type safety and guards" do
    test "accepts only positive integers" do
      valid_values = [
        {{1, :seconds}, 1_000},
        {{100, :milliseconds}, 100},
        {{999, :hours}, 3_596_400_000}
      ]

      validate_all_valid(valid_values)
    end

    test "rejects non-positive values" do
      invalid_values = [
        {0, :seconds},
        {-1, :minutes},
        {-100, :hours}
      ]

      validate_all_invalid(invalid_values, :invalid_duration)
    end

    test "rejects invalid units" do
      invalid_units = [
        {5, :nanoseconds},
        {10, :fortnight},
        {1, :century}
      ]

      validate_all_invalid(invalid_units, :invalid_unit)
    end

    defp validate_all_valid([]), do: :ok

    defp validate_all_valid([{duration, expected} | rest]) do
      result = Duration.to_milliseconds(duration)
      validate_duration_result(result, expected)
      validate_all_valid(rest)
    end

    defp validate_all_invalid([], _expected_error), do: :ok

    defp validate_all_invalid([duration | rest], expected_error) do
      result = Duration.to_milliseconds(duration)
      validate_error_result(result, expected_error)
      validate_all_invalid(rest, expected_error)
    end
  end

  describe "conversion consistency - mathematical equivalence" do
    test "1 minute equals 60 seconds" do
      minutes_result = Duration.to_milliseconds({1, :minutes})
      seconds_result = Duration.to_milliseconds({60, :seconds})

      validate_functor_identity(minutes_result, seconds_result)
    end

    test "1 hour equals 60 minutes" do
      hours_result = Duration.to_milliseconds({1, :hours})
      minutes_result = Duration.to_milliseconds({60, :minutes})

      validate_functor_identity(hours_result, minutes_result)
    end

    test "1 day equals 24 hours" do
      days_result = Duration.to_milliseconds({1, :days})
      hours_result = Duration.to_milliseconds({24, :hours})

      validate_functor_identity(days_result, hours_result)
    end

    test "1 week equals 7 days" do
      weeks_result = Duration.to_milliseconds({1, :weeks})
      days_result = Duration.to_milliseconds({7, :days})

      validate_functor_identity(weeks_result, days_result)
    end

    test "composition of conversions maintains equivalence" do
      result1 =
        Error.m do
          h1 <- Duration.to_milliseconds({1, :hours})
          h2 <- Duration.to_milliseconds({1, :hours})
          Error.return(h1 + h2)
        end

      result2 = Duration.to_milliseconds({2, :hours})

      validate_functor_identity(result1, result2)
    end
  end
end
