defmodule Lotus.ClickHouse.Test.Migrations do
  @moduledoc false

  alias Lotus.ClickHouse.Test.Repo

  @create_test_users """
  CREATE TABLE IF NOT EXISTS test_users (
    id UInt64,
    name String,
    email String,
    age Nullable(UInt32),
    active UInt8 DEFAULT 1,
    metadata String DEFAULT '{}',
    inserted_at DateTime DEFAULT now(),
    updated_at DateTime DEFAULT now()
  ) ENGINE = MergeTree() ORDER BY id
  """

  @create_test_posts """
  CREATE TABLE IF NOT EXISTS test_posts (
    id UInt64,
    title String,
    content Nullable(String),
    user_id UInt64,
    published UInt8 DEFAULT 0,
    published_at Nullable(DateTime),
    view_count UInt64 DEFAULT 0,
    tags Array(String) DEFAULT [],
    inserted_at DateTime DEFAULT now(),
    updated_at DateTime DEFAULT now()
  ) ENGINE = MergeTree() ORDER BY id
  """

  @create_test_events """
  CREATE TABLE IF NOT EXISTS test_events (
    id UInt64,
    event_name String,
    user_id UInt64,
    properties String DEFAULT '{}',
    occurred_at DateTime DEFAULT now()
  ) ENGINE = MergeTree() ORDER BY (id, occurred_at)
  """

  def up do
    Repo.query!(@create_test_users)
    Repo.query!(@create_test_posts)
    Repo.query!(@create_test_events)
  end

  def down do
    Repo.query!("DROP TABLE IF EXISTS test_events")
    Repo.query!("DROP TABLE IF EXISTS test_posts")
    Repo.query!("DROP TABLE IF EXISTS test_users")
  end
end
