defmodule MnesiaEx.Monad do
  @moduledoc false
  # Internal module for monadic composition.
  # This is a private implementation detail and should not be used directly.
  # Use MnesiaEx functions which return {:ok, value} | {:error, reason} instead.

  # Wraps a value in a successful result: {:ok, value}
  def return(value), do: {:ok, value}

  # Wraps a value in a failed result: {:error, reason}
  def fail(reason), do: {:error, reason}

  # Monadic bind operation - chains operations that return {:ok, value} or {:error, reason}
  def bind({:ok, value}, fun), do: fun.(value)
  def bind({:error, _} = error, _fun), do: error

  # Monadic composition macro - allows writing imperative-style code that composes monadically
  defmacro m(do: block) do
    case block do
      {:__block__, _, statements} ->
        build_monadic_chain(statements)

      single_statement ->
        build_monadic_chain([single_statement])
    end
  end

  defp build_monadic_chain([statement]) do
    statement
  end

  defp build_monadic_chain([{:<-, _, [var, expr]} | rest]) do
    quote do
      unquote(__MODULE__).bind(unquote(expr), fn unquote(var) ->
        unquote(build_monadic_chain(rest))
      end)
    end
  end

  defp build_monadic_chain([expr | rest]) do
    quote do
      unquote(__MODULE__).bind(unquote(expr), fn _ ->
        unquote(build_monadic_chain(rest))
      end)
    end
  end
end
