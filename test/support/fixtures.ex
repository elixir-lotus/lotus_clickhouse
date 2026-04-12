defmodule Lotus.ClickHouse.Test.Fixtures do
  @moduledoc false

  alias Lotus.ClickHouse.Test.Repo

  def insert_user(attrs \\ %{}) do
    defaults = %{
      id: System.unique_integer([:positive]),
      name: "Test User",
      email: "test_#{System.unique_integer([:positive])}@example.com",
      age: 30,
      active: 1
    }

    row = Map.merge(defaults, attrs)

    Repo.query!(
      """
      INSERT INTO test_users (id, name, email, age, active)
      VALUES ({$0:UInt64}, {$1:String}, {$2:String}, {$3:UInt32}, {$4:UInt8})
      """,
      [row.id, row.name, row.email, row.age, row.active]
    )

    row
  end

  def insert_post(attrs \\ %{}) do
    defaults = %{
      id: System.unique_integer([:positive]),
      title: "Test Post",
      content: "Some content",
      user_id: 1,
      published: 1,
      view_count: 0,
      tags: []
    }

    row = Map.merge(defaults, attrs)

    Repo.query!(
      """
      INSERT INTO test_posts (id, title, content, user_id, published, view_count)
      VALUES ({$0:UInt64}, {$1:String}, {$2:String}, {$3:UInt64}, {$4:UInt8}, {$5:UInt64})
      """,
      [row.id, row.title, row.content, row.user_id, row.published, row.view_count]
    )

    row
  end

  def insert_event(attrs \\ %{}) do
    defaults = %{
      id: System.unique_integer([:positive]),
      event_name: "page_view",
      user_id: 1,
      properties: "{}"
    }

    row = Map.merge(defaults, attrs)

    Repo.query!(
      """
      INSERT INTO test_events (id, event_name, user_id, properties)
      VALUES ({$0:UInt64}, {$1:String}, {$2:UInt64}, {$3:String})
      """,
      [row.id, row.event_name, row.user_id, row.properties]
    )

    row
  end
end
