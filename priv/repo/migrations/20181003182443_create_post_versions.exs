defmodule Level.Repo.Migrations.CreatePostVersions do
  use Ecto.Migration

  def change do
    create table(:post_versions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :space_id, references(:spaces, on_delete: :nothing, type: :binary_id), null: false
      add :post_id, references(:posts, on_delete: :nothing, type: :binary_id), null: false
      add :author_id, references(:space_users, on_delete: :nothing, type: :binary_id), null: false
      add :body, :text, null: false

      timestamps(updated_at: false)
    end

    create index(:post_versions, [:post_id])
  end
end
