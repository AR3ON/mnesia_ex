# Pull Request

## Description
Brief description of the changes in this PR.

## Type of Change
- [ ] Bug fix (non-breaking change which fixes an issue)
- [ ] New feature (non-breaking change which adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Documentation update
- [ ] Refactoring (no functional changes)

## Related Issues
Fixes #(issue number)

## Changes Made
- Change 1
- Change 2
- Change 3

## Code Quality Checklist

### Functional Programming Rules
- [ ] No `if`, `case`, `cond` statements (use pattern matching)
- [ ] No `try`, `rescue`, `raise` (use `Error.fail`)
- [ ] All functions are pure (no side effects)
- [ ] Uses monadic composition (`Error.m do`)
- [ ] No `nil` returns (use `:nothing` or `{:error, reason}`)

### Testing
- [ ] All tests pass (`mix test`)
- [ ] Added tests for new functionality
- [ ] Tests follow functional principles
- [ ] No mocks or stubs used

### Documentation
- [ ] Added/updated `@doc` for public functions
- [ ] Added/updated `@spec` type specs
- [ ] Updated README if needed
- [ ] Added examples in documentation
- [ ] Documentation in English

### Code Style
- [ ] Ran `mix format`
- [ ] No compilation warnings
- [ ] Functions are small and composable
- [ ] Semantic naming (`safe_`, `validate_`, `fetch_`, etc.)

### Elixir Conventions
- [ ] Functions with `!` raise exceptions (have non-`!` version)
- [ ] Functions returning lists return directly (no `{:ok, list}` wrapper)
- [ ] Boolean functions use `?` suffix and return `true/false`
- [ ] No `!` version for list-returning functions

## Examples

```elixir
# Show how to use the new feature

# Single value functions - return tuples
{:ok, user} = MyApp.Users.write(%{name: "Alice"})
user = MyApp.Users.write!(%{name: "Bob"})  # ! version raises on error

# List functions - return lists directly (no ! version)
users = MyApp.Users.select([{:age, :>, 18}])  # Returns [records]
keys = MyApp.Users.all_keys()  # Returns [1, 2, 3, ...]

# Boolean functions - return true/false
exists = MyApp.Users.exists?()  # true or false
```

## Breaking Changes
If this PR introduces breaking changes, describe them here and provide migration guide.

## Additional Notes
Any additional information that reviewers should know.

## Checklist Before Merge
- [ ] Code reviewed and approved
- [ ] All CI checks passing
- [ ] Documentation complete
- [ ] CHANGELOG updated
- [ ] Version bumped (if applicable)

