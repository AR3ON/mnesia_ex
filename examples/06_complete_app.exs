# Complete Application Example - Blog System
#
# This example demonstrates a complete blog system using MnesiaEx
# with users, posts, comments, sessions, and all features combined.
#
# Run with: elixir examples/06_complete_app.exs

Mix.install([
  {:mnesia_ex, path: "."}
])

# Define table modules
defmodule Blog.Users do
  use MnesiaEx, table: :users
end

defmodule Blog.Posts do
  use MnesiaEx, table: :posts
end

defmodule Blog.Comments do
  use MnesiaEx, table: :comments
end

defmodule Blog.Sessions do
  use MnesiaEx, table: :sessions
end

# Application setup
defmodule Blog.Setup do
  def init do
    IO.puts("🚀 Initializing Blog System...")

    MnesiaEx.start()
    {:ok, :created} = MnesiaEx.Schema.create([node()])

    # Create users table
    Blog.Users.create(
      attributes: [:id, :username, :email, :password_hash, :created_at],
      index: [:username, :email],
      counter_fields: [:id],
      type: :set,
      persistence: false
    )

    # Create posts table
    Blog.Posts.create(
      attributes: [:id, :user_id, :title, :content, :views, :created_at],
      index: [:user_id],
      counter_fields: [:id, :views],
      type: :set,
      persistence: false
    )

    # Create comments table
    Blog.Comments.create(
      attributes: [:id, :post_id, :user_id, :content, :created_at],
      index: [:post_id, :user_id],
      counter_fields: [:id],
      type: :set,
      persistence: false
    )

    # Create sessions table (with TTL)
    Blog.Sessions.create(
      attributes: [:id, :user_id, :token, :created_at],
      index: [:user_id],
      type: :set,
      persistence: false
    )

    MnesiaEx.TTL.ensure_ttl_table()

    IO.puts("✅ Blog system initialized\n")
  end

  def teardown do
    IO.puts("\n🧹 Cleaning up...")
    Blog.Users.drop()
    Blog.Posts.drop()
    Blog.Comments.drop()
    Blog.Sessions.drop()
    {:ok, :deleted} = MnesiaEx.Schema.delete([node()])
    MnesiaEx.stop()
    IO.puts("✅ Cleanup complete")
  end
end

# User management
defmodule Blog.UserService do
  def create_user(username, email) do
    {:ok, user_id} = Blog.Users.get_next_id(:id)

    user = %{
      id: user_id,
      username: username,
      email: email,
      password_hash: "hashed_password_#{user_id}",
      created_at: DateTime.utc_now()
    }

    created = Blog.Users.write!(user)
    {:ok, created}
  end

  def get_user_by_username(username) do
    Blog.Users.get_by!(:username, username)
  end

  def list_all_users do
    Blog.Users.select([])
  end
end

# Post management
defmodule Blog.PostService do
  def create_post(user_id, title, content) do
    {:ok, post_id} = Blog.Posts.get_next_id(:id)

    post = %{
      id: post_id,
      user_id: user_id,
      title: title,
      content: content,
      views: 0,
      created_at: DateTime.utc_now()
    }

    created = Blog.Posts.write!(post)
    {:ok, created}
  end

  def get_post(post_id) do
    post = Blog.Posts.read!(post_id)
    {:ok, post}
  end

  def increment_views(post_id) do
    _post = Blog.Posts.read!(post_id)
    {:ok, views} = Blog.Posts.get_next_id(:views)
    updated = Blog.Posts.update!(post_id, %{views: views})
    {:ok, updated}
  end

  def get_user_posts(user_id) do
    Blog.Posts.select([{:user_id, :==, user_id}])
  end

  def get_popular_posts(min_views) do
    Blog.Posts.select([{:views, :>=, min_views}])
  end
end

# Comment management
defmodule Blog.CommentService do
  def add_comment(post_id, user_id, content) do
    {:ok, comment_id} = Blog.Comments.get_next_id(:id)

    comment = %{
      id: comment_id,
      post_id: post_id,
      user_id: user_id,
      content: content,
      created_at: DateTime.utc_now()
    }

    created = Blog.Comments.write!(comment)
    {:ok, created}
  end

  def get_post_comments(post_id) do
    Blog.Comments.select([{:post_id, :==, post_id}])
  end
end

# Session management with TTL
defmodule Blog.SessionService do
  def create_session(user_id) do
    session_id = "session_#{System.unique_integer([:positive])}"
    token = "token_#{System.unique_integer([:positive, :monotonic])}"

    session = %{
      id: session_id,
      user_id: user_id,
      token: token,
      created_at: DateTime.utc_now()
    }

    # Create session with 30 second TTL
    Blog.Sessions.write_with_ttl!(session, 30)
  end

  def get_session(session_id) do
    Blog.Sessions.read!(session_id)
  end

  def list_active_sessions do
    Blog.Sessions.select([])
  end
end

# Run the application
IO.puts("=" <> String.duplicate("=", 60))
IO.puts("  BLOG SYSTEM DEMO")
IO.puts("=" <> String.duplicate("=", 60) <> "\n")

Blog.Setup.init()

IO.puts("👥 Creating users...")
{:ok, alice} = Blog.UserService.create_user("alice", "alice@blog.com")
{:ok, bob} = Blog.UserService.create_user("bob", "bob@blog.com")
{:ok, carol} = Blog.UserService.create_user("carol", "carol@blog.com")
IO.inspect(alice, label: "User created")

IO.puts("\n📝 Creating posts...")
{:ok, post1} = Blog.PostService.create_post(alice.id, "Getting Started with Elixir", "Elixir is amazing...")
{:ok, post2} = Blog.PostService.create_post(alice.id, "MnesiaEx Tutorial", "Learn how to use MnesiaEx...")
{:ok, _post3} = Blog.PostService.create_post(bob.id, "Functional Programming Tips", "FP best practices...")
IO.inspect(post1, label: "Post created")

IO.puts("\n💬 Adding comments...")
{:ok, comment1} = Blog.CommentService.add_comment(post1.id, bob.id, "Great post!")
{:ok, _comment2} = Blog.CommentService.add_comment(post1.id, carol.id, "Very helpful, thanks!")
{:ok, _comment3} = Blog.CommentService.add_comment(post2.id, carol.id, "Looking forward to more!")
IO.inspect(comment1, label: "Comment added")

IO.puts("\n👀 Simulating post views...")
Blog.PostService.increment_views(post1.id)
Blog.PostService.increment_views(post1.id)
updated_post = Blog.PostService.increment_views(post1.id)
IO.inspect(updated_post, label: "Post after views")

IO.puts("\n🔍 Querying data...")
alice_posts = Blog.PostService.get_user_posts(alice.id)
IO.puts("Alice's posts: #{length(alice_posts)}")

post1_comments = Blog.CommentService.get_post_comments(post1.id)
IO.puts("Comments on post 1: #{length(post1_comments)}")

popular = Blog.PostService.get_popular_posts(2)
IO.puts("Popular posts (>=2 views): #{length(popular)}")

IO.puts("\n🔐 Creating sessions with TTL...")
session1 = Blog.SessionService.create_session(alice.id)
_session2 = Blog.SessionService.create_session(bob.id)
IO.inspect(session1, label: "Session created (30s TTL)")

active_sessions = Blog.SessionService.list_active_sessions()
IO.puts("Active sessions: #{length(active_sessions)}")

IO.puts("\n⏰ Waiting for sessions to expire (5 seconds)...")
Process.sleep(5000)

IO.puts("Running TTL cleanup...")
MnesiaEx.TTL.cleanup_expired()

# Check if sessions still exist after partial wait
remaining = Blog.SessionService.list_active_sessions()
IO.puts("Sessions still active: #{length(remaining)}")

IO.puts("\n📊 Final statistics...")
total_users = length(Blog.UserService.list_all_users())
total_posts = length(Blog.Posts.select([]))
total_comments = length(Blog.Comments.select([]))

IO.puts("Total users: #{total_users}")
IO.puts("Total posts: #{total_posts}")
IO.puts("Total comments: #{total_comments}")

# Show a complete post with author and comments
IO.puts("\n📄 Complete post view:")
{:ok, post} = Blog.PostService.get_post(post1.id)
author = Blog.Users.read!(post.user_id)
comments = Blog.CommentService.get_post_comments(post.id)

IO.puts("\nTitle: #{post.title}")
IO.puts("Author: #{author.username}")
IO.puts("Views: #{post.views}")
IO.puts("Comments (#{length(comments)}):")
Enum.each(comments, fn comment ->
  commenter = Blog.Users.read!(comment.user_id)
  IO.puts("  - #{commenter.username}: #{comment.content}")
end)

Blog.Setup.teardown()

IO.puts("\n" <> String.duplicate("=", 62))
IO.puts("  Demo complete! ✨")
IO.puts(String.duplicate("=", 62))
