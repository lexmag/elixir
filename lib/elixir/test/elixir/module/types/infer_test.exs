Code.require_file("../../test_helper.exs", __DIR__)

defmodule Module.Types.InferTest do
  use ExUnit.Case, async: true
  import Module.Types.Infer
  alias Module.Types

  defmacrop quoted_pattern(expr) do
    quote do
      of_pattern(unquote(Macro.escape(expr)), new_context())
      |> lift_result()
    end
  end

  defp unify_lift(left, right, context \\ new_context()) do
    unify(left, right, context)
    |> lift_result()
  end

  defp new_context() do
    %{
      Types.context("types_test.ex", TypesTest, {:test, 0})
      | expr_stack: [{:foo, [], nil}]
    }
  end

  defp lift_result({:ok, type, context}) do
    {:ok, Types.lift_type(type, context)}
  end

  defp lift_result({:error, {Types, reason, location}}) do
    {:error, {reason, location}}
  end

  describe "of_pattern/2" do
    test "error location" do
      assert {:error, {{:unable_unify, :binary, :integer, expr, traces}, location}} =
               quoted_pattern(<<foo::integer, foo::binary>>)

      assert location == [{"types_test.ex", 38, {TypesTest, :test, 0}}]

      assert {:<<>>, _,
              [
                {:"::", _, [{:foo, _, nil}, {:integer, _, nil}]},
                {:"::", _, [{:foo, _, nil}, {:binary, _, nil}]}
              ]} = expr

      assert [
               {{:foo, _, nil},
                {:type, :binary, {:"::", _, [{:foo, _, nil}, {:binary, _, nil}]},
                 {"types_test.ex", 38}}},
               {{:foo, _, nil},
                {:type, :integer, {:"::", _, [{:foo, _, nil}, {:integer, _, nil}]},
                 {"types_test.ex", 38}}}
             ] = traces
    end

    test "literal" do
      assert quoted_pattern(true) == {:ok, {:literal, true}}
      assert quoted_pattern(false) == {:ok, {:literal, false}}
      assert quoted_pattern(:foo) == {:ok, {:literal, :foo}}
      assert quoted_pattern(0) == {:ok, :integer}
      assert quoted_pattern(0.0) == {:ok, :float}
      assert quoted_pattern("foo") == {:ok, :binary}
    end

    test "list" do
      assert quoted_pattern([]) == {:ok, :null}
      assert quoted_pattern([123]) == {:ok, {:cons, :integer, :null}}
      assert quoted_pattern([123 | []]) == {:ok, {:cons, :integer, :null}}
      assert quoted_pattern([123 | 456]) == {:ok, {:cons, :integer, :integer}}

      assert quoted_pattern([123, 456 | 789]) ==
               {:ok, {:cons, :integer, {:cons, :integer, :integer}}}
    end

    test "tuple" do
      assert quoted_pattern({}) == {:ok, {:tuple, []}}
      assert quoted_pattern({:a}) == {:ok, {:tuple, [{:literal, :a}]}}
      assert quoted_pattern({:a, 123}) == {:ok, {:tuple, [{:literal, :a}, :integer]}}
    end

    test "map" do
      assert quoted_pattern(%{}) == {:ok, {:map, []}}
      assert quoted_pattern(%{a: :b}) == {:ok, {:map, [{{:literal, :a}, {:literal, :b}}]}}
      assert quoted_pattern(%{123 => a}) == {:ok, {:map, [{:integer, {:var, 0}}]}}

      assert {:error, {{:unable_unify, {:literal, :foo}, :integer, _, _}, _}} =
               quoted_pattern(%{a: a = 123, b: a = :foo})
    end

    test "binary" do
      assert quoted_pattern(<<"foo"::binary>>) == {:ok, :binary}
      assert quoted_pattern(<<123::integer>>) == {:ok, :binary}
      assert quoted_pattern(<<foo::integer>>) == {:ok, :binary}

      assert quoted_pattern({<<foo::integer>>, foo}) == {:ok, {:tuple, [:binary, :integer]}}
      assert quoted_pattern({<<foo::binary>>, foo}) == {:ok, {:tuple, [:binary, :binary]}}

      assert {:error, {{:unable_unify, :integer, :binary, _, _}, _}} =
               quoted_pattern(<<123::binary>>)

      assert {:error, {{:unable_unify, :binary, :integer, _, _}, _}} =
               quoted_pattern(<<"foo"::integer>>)

      assert {:error, {{:unable_unify, :integer, :binary, _, _}, _}} =
               quoted_pattern(<<foo::binary, foo::integer>>)
    end

    test "variables" do
      assert quoted_pattern(foo) == {:ok, {:var, 0}}
      assert quoted_pattern({foo}) == {:ok, {:tuple, [{:var, 0}]}}
      assert quoted_pattern({foo, bar}) == {:ok, {:tuple, [{:var, 0}, {:var, 1}]}}

      assert quoted_pattern(_) == {:ok, :dynamic}
      assert quoted_pattern({_ = 123, _}) == {:ok, {:tuple, [:integer, :dynamic]}}
    end

    test "assignment" do
      assert quoted_pattern(x = y) == {:ok, {:var, 0}}
      assert quoted_pattern(x = 123) == {:ok, :integer}
      assert quoted_pattern({foo}) == {:ok, {:tuple, [{:var, 0}]}}
      assert quoted_pattern({x = y}) == {:ok, {:tuple, [{:var, 0}]}}

      assert quoted_pattern(x = y = 123) == {:ok, :integer}
      assert quoted_pattern(x = 123 = y) == {:ok, :integer}
      assert quoted_pattern(123 = x = y) == {:ok, :integer}

      assert {:error, {{:unable_unify, {:tuple, [var: 0]}, {:var, 0}, _, _}, _}} =
               quoted_pattern({x} = x)
    end
  end

  describe "unify/3" do
    test "literal" do
      assert unify_lift({:literal, :foo}, {:literal, :foo}) == {:ok, {:literal, :foo}}

      assert {:error, {{:unable_unify, {:literal, :foo}, {:literal, :bar}, _, _}, _}} =
               unify_lift({:literal, :foo}, {:literal, :bar})
    end

    test "type" do
      assert unify_lift(:integer, :integer) == {:ok, :integer}
      assert unify_lift(:binary, :binary) == {:ok, :binary}
      assert unify_lift(:atom, :atom) == {:ok, :atom}
      assert unify_lift(:boolean, :boolean) == {:ok, :boolean}

      assert {:error, {{:unable_unify, :integer, :boolean, _, _}, _}} =
               unify_lift(:integer, :boolean)
    end

    test "subtype" do
      assert unify_lift(:boolean, :atom) == {:ok, :boolean}
      assert unify_lift(:atom, :boolean) == {:ok, :boolean}
      assert unify_lift(:boolean, {:literal, true}) == {:ok, {:literal, true}}
      assert unify_lift({:literal, true}, :boolean) == {:ok, {:literal, true}}
      assert unify_lift(:atom, {:literal, true}) == {:ok, {:literal, true}}
      assert unify_lift({:literal, true}, :atom) == {:ok, {:literal, true}}
    end

    test "tuple" do
      assert unify_lift({:tuple, []}, {:tuple, []}) == {:ok, {:tuple, []}}
      assert unify_lift({:tuple, [:integer]}, {:tuple, [:integer]}) == {:ok, {:tuple, [:integer]}}
      assert unify_lift({:tuple, [:boolean]}, {:tuple, [:atom]}) == {:ok, {:tuple, [:boolean]}}

      assert {:error, {{:unable_unify, {:tuple, [:integer]}, {:tuple, []}, _, _}, _}} =
               unify_lift({:tuple, [:integer]}, {:tuple, []})

      assert {:error, {{:unable_unify, :integer, :atom, _, _}, _}} =
               unify_lift({:tuple, [:integer]}, {:tuple, [:atom]})
    end

    test "cons" do
      assert unify_lift({:cons, :integer, :integer}, {:cons, :integer, :integer}) ==
               {:ok, {:cons, :integer, :integer}}

      assert unify_lift({:cons, :boolean, :atom}, {:cons, :atom, :boolean}) ==
               {:ok, {:cons, :boolean, :boolean}}

      assert {:error, {{:unable_unify, :atom, :integer, _, _}, _}} =
               unify_lift({:cons, :integer, :atom}, {:cons, :integer, :integer})

      assert {:error, {{:unable_unify, :atom, :integer, _, _}, _}} =
               unify_lift({:cons, :atom, :integer}, {:cons, :integer, :integer})
    end

    test "map" do
      assert unify_lift({:map, []}, {:map, []}) == {:ok, {:map, []}}

      assert unify_lift({:map, [{:integer, :atom}]}, {:map, []}) ==
               {:ok, {:map, [{:integer, :atom}]}}

      assert unify_lift({:map, []}, {:map, [{:integer, :atom}]}) ==
               {:ok, {:map, [{:integer, :atom}]}}

      assert unify_lift({:map, [{:integer, :atom}]}, {:map, [{:integer, :atom}]}) ==
               {:ok, {:map, [{:integer, :atom}]}}

      assert unify_lift({:map, [{:integer, :atom}]}, {:map, [{:atom, :integer}]}) ==
               {:ok, {:map, [{:integer, :atom}, {:atom, :integer}]}}

      assert unify_lift(
               {:map, [{{:literal, :foo}, :boolean}]},
               {:map, [{{:literal, :foo}, :atom}]}
             ) ==
               {:ok, {:map, [{{:literal, :foo}, :boolean}]}}

      assert {:error, {{:unable_unify, :integer, :atom, _, _}, _}} =
               unify_lift(
                 {:map, [{{:literal, :foo}, :integer}]},
                 {:map, [{{:literal, :foo}, :atom}]}
               )
    end

    test "union" do
      assert unify_lift({:union, []}, {:union, []}) == {:ok, {:union, []}}
      assert unify_lift({:union, [:integer]}, {:union, [:integer]}) == {:ok, {:union, [:integer]}}

      assert unify_lift({:union, [:integer, :atom]}, {:union, [:integer, :atom]}) ==
               {:ok, {:union, [:integer, :atom]}}

      assert unify_lift({:union, [:integer, :atom]}, {:union, [:atom, :integer]}) ==
               {:ok, {:union, [:integer, :atom]}}

      assert unify_lift({:union, [:atom]}, {:union, [:boolean]}) == {:ok, {:union, [:boolean]}}
      assert unify_lift({:union, [:boolean]}, {:union, [:atom]}) == {:ok, {:union, [:boolean]}}

      assert {:error, {{:unable_unify, {:union, [:integer]}, {:union, [:atom]}, _, _}, _}} =
               unify_lift({:union, [:integer]}, {:union, [:atom]})
    end

    test "dynamic" do
      assert unify_lift({:literal, :foo}, :dynamic) == {:ok, {:literal, :foo}}
      assert unify_lift(:dynamic, {:literal, :foo}) == {:ok, {:literal, :foo}}
      assert unify_lift(:integer, :dynamic) == {:ok, :integer}
      assert unify_lift(:dynamic, :integer) == {:ok, :integer}
    end

    test "vars" do
      assert {{:var, 0}, var_context} = new_var({:foo, [], nil}, new_context())
      assert {{:var, 1}, var_context} = new_var({:bar, [], nil}, var_context)

      assert {:ok, {:var, 0}, context} = unify({:var, 0}, :integer, var_context)
      assert Types.lift_type({:var, 0}, context) == :integer

      assert {:ok, {:var, 0}, context} = unify(:integer, {:var, 0}, var_context)
      assert Types.lift_type({:var, 0}, context) == :integer

      assert {:ok, {:var, _}, context} = unify({:var, 0}, {:var, 1}, var_context)
      assert {:var, _} = Types.lift_type({:var, 0}, context)
      assert {:var, _} = Types.lift_type({:var, 1}, context)

      assert {:ok, {:var, 0}, context} = unify({:var, 0}, :integer, var_context)
      assert {:ok, {:var, 1}, context} = unify({:var, 1}, :integer, context)
      assert {:ok, {:var, _}, context} = unify({:var, 0}, {:var, 1}, context)

      assert {:ok, {:var, 0}, context} = unify({:var, 0}, :integer, var_context)
      assert {:ok, {:var, 1}, context} = unify({:var, 1}, :integer, context)
      assert {:ok, {:var, _}, context} = unify({:var, 1}, {:var, 0}, context)

      assert {:ok, {:var, 0}, context} = unify({:var, 0}, :integer, var_context)
      assert {:ok, {:var, 1}, context} = unify({:var, 1}, :binary, context)

      assert {:error, {{:unable_unify, :binary, :integer, _, _}, _}} =
               unify_lift({:var, 0}, {:var, 1}, context)

      assert {:ok, {:var, 0}, context} = unify({:var, 0}, :integer, var_context)
      assert {:ok, {:var, 1}, context} = unify({:var, 1}, :binary, context)

      assert {:error, {{:unable_unify, :integer, :binary, _, _}, _}} =
               unify_lift({:var, 1}, {:var, 0}, context)
    end

    test "vars inside tuples" do
      assert {{:var, 0}, var_context} = new_var({:foo, [], nil}, new_context())
      assert {{:var, 1}, var_context} = new_var({:bar, [], nil}, var_context)

      assert {:ok, {:tuple, [{:var, 0}]}, context} =
               unify({:tuple, [{:var, 0}]}, {:tuple, [:integer]}, var_context)

      assert Types.lift_type({:var, 0}, context) == :integer

      assert {:ok, {:var, 0}, context} = unify({:var, 0}, :integer, var_context)
      assert {:ok, {:var, 1}, context} = unify({:var, 1}, :integer, context)

      assert {:ok, {:tuple, [{:var, _}]}, context} =
               unify({:tuple, [{:var, 0}]}, {:tuple, [{:var, 1}]}, context)

      assert {:ok, {:var, 1}, context} = unify({:var, 1}, {:tuple, [{:var, 0}]}, var_context)
      assert {:ok, {:var, 0}, context} = unify({:var, 0}, :integer, context)
      assert Types.lift_type({:var, 1}, context) == {:tuple, [:integer]}

      assert {:ok, {:var, 0}, context} = unify({:var, 0}, :integer, var_context)
      assert {:ok, {:var, 1}, context} = unify({:var, 1}, :binary, context)

      assert {:error, {{:unable_unify, :binary, :integer, _, _}, _}} =
               unify_lift({:tuple, [{:var, 0}]}, {:tuple, [{:var, 1}]}, context)
    end

    # TODO: Vars inside unions

    test "recursive type" do
      assert {{:var, 0}, var_context} = new_var({:foo, [], nil}, new_context())
      assert {{:var, 1}, var_context} = new_var({:bar, [], nil}, var_context)
      assert {{:var, 2}, var_context} = new_var({:baz, [], nil}, var_context)

      assert {:ok, {:var, _}, context} = unify({:var, 0}, {:var, 1}, var_context)
      assert {:ok, {:var, _}, context} = unify({:var, 1}, {:var, 0}, context)

      assert {:ok, {:var, _}, context} = unify({:var, 0}, {:var, 1}, var_context)
      assert {:ok, {:var, _}, context} = unify({:var, 1}, {:var, 2}, context)
      assert {:ok, {:var, _}, context} = unify({:var, 2}, {:var, 0}, context)

      assert {:ok, {:var, _}, context} = unify({:var, 0}, {:var, 1}, var_context)

      assert {:error, {{:unable_unify, {:tuple, [var: 0]}, {:var, 0}, _, _}, _}} =
               unify_lift({:var, 1}, {:tuple, [{:var, 0}]}, context)

      assert {:ok, {:var, _}, context} = unify({:var, 0}, {:var, 1}, var_context)
      assert {:ok, {:var, _}, context} = unify({:var, 1}, {:var, 2}, context)

      assert {:error, {{:unable_unify, {:tuple, [var: 0]}, {:var, 0}, _, _}, _}} =
               unify_lift({:var, 2}, {:tuple, [{:var, 0}]}, context)
    end
  end

  test "subtype?/3" do
    assert subtype?({:literal, :foo}, :atom, new_context())
    assert subtype?({:literal, true}, :boolean, new_context())
    assert subtype?({:literal, true}, :atom, new_context())
    assert subtype?(:boolean, :atom, new_context())

    refute subtype?(:integer, :binary, new_context())
    refute subtype?(:atom, {:literal, :foo}, new_context())
    refute subtype?(:boolean, {:literal, true}, new_context())
    refute subtype?(:atom, {:literal, true}, new_context())
    refute subtype?(:atom, :boolean, new_context())
  end

  test "to_union/2" do
    assert to_union([:atom], new_context()) == :atom
    assert to_union([:integer, :integer], new_context()) == :integer
    assert to_union([:boolean, :atom], new_context()) == :atom
    assert to_union([{:literal, :foo}, :boolean, :atom], new_context()) == :atom

    assert to_union([:binary, :atom], new_context()) == {:union, [:binary, :atom]}
    assert to_union([:atom, :binary, :atom], new_context()) == {:union, [:atom, :binary]}

    assert to_union([{:literal, :foo}, :binary, :atom], new_context()) ==
             {:union, [:binary, :atom]}

    assert {{:var, 0}, var_context} = new_var({:foo, [], nil}, new_context())
    assert to_union([{:var, 0}], var_context) == {:var, 0}

    # TODO: Add missing tests that uses variables and higher rank types.
    #       We may have to change, to_union to use unify, check the return
    #       type and throw away the returned context instead of using subtype?
    #       since subtype? is incomplete when it comes to variables and higher
    #       rank types.

    # assert {:ok, {:var, _}, context} = unify({:var, 0}, :integer, var_context)
    # assert to_union([{:var, 0}, :integer], context) == :integer

    assert to_union([{:tuple, [:integer]}, {:tuple, [:integer]}], new_context()) ==
             {:tuple, [:integer]}

    # assert to_union([{:tuple, [:boolean]}, {:tuple, [:atom]}], new_context()) == {:tuple, [:atom]}
  end
end
