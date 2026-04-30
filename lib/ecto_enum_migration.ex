defmodule EctoEnumMigration do
  @moduledoc """
  Provides a DSL to easily handle Postgres Enum Types in Ecto database migrations.
  """

  import Ecto.Migration, only: [execute: 1, execute: 2]

  @doc """
  Create a Postgres Enum Type.

  ## Examples

  ```elixir
  defmodule MyApp.Repo.Migrations.CreateTypeMigration do
    use Ecto.Migration
    import EctoEnumMigration

    def change do
      create_type(:status, [:registered, :active, :inactive, :archived])
    end
  end
  ```

  By default the type will be created in the `public` schema.
  To change the schema of the type pass the `schema` option.

  ```elixir
  create_type(:status, [:registered, :active, :inactive, :archived], schema: "custom_schema")
  ```

  """
  @spec create_type(name :: atom(), values :: [atom()], opts :: Keyword.t()) :: :ok | no_return()
  def create_type(name, values, opts \\ [])
      when is_atom(name) and is_list(values) and is_list(opts) do
    type_name = type_name(name, opts)
    type_values = values |> Enum.map(fn value -> "'#{value}'" end) |> Enum.join(", ")

    create_sql = "CREATE TYPE #{type_name} AS ENUM (#{type_values});"
    drop_sql = "DROP TYPE #{type_name};"

    execute(create_sql, drop_sql)
  end

  @doc """
  Drop a Postgres Enum Type.

  This command is not reversible, so make sure to include a `down/0` step in the migration.


  ## Examples

  ```elixir
  defmodule MyApp.Repo.Migrations.DropTypeMigration do
    use Ecto.Migration
    import EctoEnumMigration

    def up do
      drop_type(:status)
    end

    def down do
      create_type(:status, [:registered, :active, :inactive, :archived])
    end
  end
  ```

  By default the type will be created in the `public` schema.
  To change the schema of the type pass the `schema` option.

  ```elixir
  drop_type(:status, schema: "custom_schema")
  ```

  """
  @spec drop_type(name :: atom(), opts :: Keyword.t()) :: :ok | no_return()
  def drop_type(name, opts \\ []) when is_atom(name) and is_list(opts) do
    [
      "DROP TYPE",
      if_exists_sql(opts),
      type_name(name, opts),
      ";"
    ]
    |> execute_query()
  end

  @doc """
  Rename a Postgres Type.

  ## Examples

  ```elixir
  defmodule MyApp.Repo.Migrations.RenameTypeMigration do
    use Ecto.Migration
    import EctoEnumMigration

    def change do
      rename_type(:status, :status_renamed)
    end
  end
  ```

  By default the type will be created in the `public` schema.
  To change the schema of the type pass the `schema` option.

  ```elixir
  rename_type(:status, :status_renamed, schema: "custom_schema")
  ```

  """
  @spec rename_type(before_name :: atom(), after_name :: atom(), opts :: Keyword.t()) ::
          :ok | no_return()
  def rename_type(before_name, after_name, opts \\ [])
      when is_atom(before_name) and is_atom(after_name) and is_list(opts) do
    before_type_name = type_name(before_name, opts)
    after_type_name = type_name(after_name, opts)

    up_sql = "ALTER TYPE #{before_type_name} RENAME TO #{after_name};"
    down_sql = "ALTER TYPE #{after_type_name} RENAME TO #{before_name};"

    execute(up_sql, down_sql)
  end

  @doc """
  Add a value to a existing Postgres type.

  Postgres has no native way to remove a value from an enum, so the down
  migration runs the following steps inside a single `DO` block:

    1. Rename the existing type to a temporary name.
    2. Create a new type with all existing values except the one being dropped.
    3. Alter every column currently using the type to use the new type.
    4. Drop the renamed (original) type.

  The down migration will fail if any row holds the value being dropped —
  update or delete those rows before rolling back.

  If running on a version of Postgres <= 11, `add_value_to_type` cannot be
  used inside a transaction block, so you'll need to set
  `@disable_ddl_transaction true` in the migration. The down migration runs
  as a single `DO` block, which is self-contained, so this restriction does
  not affect the down migration.

  ## Examples

  ```elixir
  defmodule MyApp.Repo.Migrations.AddValueToTypeMigration do
    use Ecto.Migration
    import EctoEnumMigration
    # Only needed if running on Postgres <= 11
    @disable_ddl_transaction true

    def change do
      add_value_to_type(:status, :finished)
    end
  end
  ```

  By default the type will be created in the `public` schema.
  To change the schema of the type pass the `schema` option.

  ```elixir
  add_value_to_type(:status, :finished, schema: "custom_schema")
  ```

  If the new value's place in the enum's ordering is not specified,
  then the new item is placed at the end of the list of values.

  But we specify the the place in the ordering for the new value with the
  `:before` and `:after` options.

  ```elixir
  add_value_to_type(:status, :finished, before: :started)
  ```

  ```elixir
  add_value_to_type(:status, :finished, after: :started)
  ```

  Can specify to only add value if not exists with the `:if_not_exists` option

  ```elixir
  add_value_to_type(:status, :finished, if_not_exists: true)
  ```

  Note that `:if_not_exists` only affects the up migration. The down
  migration always drops the value if it is present in the type.
  """
  @spec add_value_to_type(name :: atom(), value :: atom(), opts :: Keyword.t()) ::
          :ok | no_return()

  def add_value_to_type(name, value, opts \\ []) do
    up_sql =
      [
        "ALTER TYPE",
        type_name(name, opts),
        "ADD VALUE",
        if_not_exists_sql(opts),
        to_value(value),
        before_after(opts),
        ";"
      ]
      |> build_query()

    down_sql = remove_value_from_type_sql(name, value, opts)

    execute(up_sql, down_sql)
  end

  @doc """
  Rename a value of a Postgres Type.

  ***Only compatible with Postgres version 10+***

  ## Examples

  ```elixir
  defmodule MyApp.Repo.Migrations.RenameTypeMigration do
    use Ecto.Migration
    import EctoEnumMigration

    def change do
      rename_value(:status, :finished, :done)
    end
  end
  ```

  By default the type will be created in the `public` schema.
  To change the schema of the type pass the `schema` option.

  ```elixir
  rename_value(:status, :finished, :done, schema: "custom_schema")
  ```

  """
  @spec rename_value(
          type_name :: atom(),
          before_value :: atom(),
          after_value :: atom(),
          opts :: Keyword.t()
        ) :: :ok | no_return()

  def rename_value(type_name, before_value, after_value, opts \\ [])
      when is_atom(type_name) and is_atom(before_value) and is_atom(after_value) and is_list(opts) do
    type_name = type_name(type_name, opts)
    before_value = to_value(before_value)
    after_value = to_value(after_value)

    up_sql = "
      ALTER TYPE #{type_name} RENAME VALUE #{before_value} TO #{after_value};
    "

    down_sql = "
      ALTER TYPE #{type_name} RENAME VALUE #{after_value} TO #{before_value};
    "

    execute(up_sql, down_sql)
  end

  defp before_after(opts) do
    before_value = Keyword.get(opts, :before)
    after_value = Keyword.get(opts, :after)

    cond do
      before_value ->
        ["BEFORE ", to_value(before_value)]

      after_value ->
        ["AFTER ", to_value(after_value)]

      true ->
        []
    end
  end

  defp to_value(value) do
    [?', to_string(value), ?']
  end

  defp type_name(name, opts) do
    opts_schema = Keyword.get(opts, :schema, "public")

    repo_prefix =
      %{prefix: nil}
      |> Ecto.Migration.__prefix__()
      |> Map.fetch!(:prefix)

    "#{repo_prefix || opts_schema}.#{name}"
  end

  defp if_exists_sql(opts) do
    if Keyword.get(opts, :if_exists, false) do
      "IF EXISTS"
    else
      []
    end
  end

  defp if_not_exists_sql(opts) do
    if Keyword.get(opts, :if_not_exists, false) do
      "IF NOT EXISTS"
    else
      []
    end
  end

  defp build_query(terms) do
    terms
    |> Enum.reject(&(is_nil(&1) || &1 == []))
    |> Enum.intersperse(?\s)
    |> IO.iodata_to_binary()
  end

  defp execute_query(terms) do
    terms |> build_query() |> execute()
  end

  defp schema_name(opts) do
    opts_schema = Keyword.get(opts, :schema, "public")

    repo_prefix =
      %{prefix: nil}
      |> Ecto.Migration.__prefix__()
      |> Map.fetch!(:prefix)

    repo_prefix || opts_schema
  end

  defp remove_value_from_type_sql(name, value, opts) do
    full_type = type_name(name, opts)
    schema = schema_name(opts)
    rename_to = "#{name}__ecto_enum_migration_drop"
    qualified_renamed = "#{schema}.#{rename_to}"
    value_str = to_string(value)

    """
    DO $ecto_enum_migration$
    DECLARE
      old_oid oid;
      new_values text;
      rec record;
    BEGIN
      old_oid := '#{full_type}'::regtype::oid;

      EXECUTE 'ALTER TYPE #{full_type} RENAME TO #{rename_to}';

      SELECT string_agg(quote_literal(enumlabel), ', ' ORDER BY enumsortorder)
        INTO new_values
        FROM pg_enum
       WHERE enumtypid = old_oid
         AND enumlabel <> '#{value_str}';

      IF new_values IS NULL THEN
        RAISE EXCEPTION 'Cannot drop last value from enum type #{full_type}';
      END IF;

      EXECUTE format('CREATE TYPE #{full_type} AS ENUM (%s)', new_values);

      FOR rec IN
        SELECT n.nspname AS schema_name,
               c.relname AS table_name,
               a.attname AS column_name
          FROM pg_attribute a
          JOIN pg_class c ON c.oid = a.attrelid
          JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE a.atttypid = old_oid
           AND a.attnum > 0
           AND NOT a.attisdropped
           AND c.relkind = 'r'
      LOOP
        EXECUTE format(
          'ALTER TABLE %I.%I ALTER COLUMN %I TYPE #{full_type} USING %I::text::#{full_type}',
          rec.schema_name, rec.table_name, rec.column_name, rec.column_name
        );
      END LOOP;

      EXECUTE 'DROP TYPE #{qualified_renamed}';
    END
    $ecto_enum_migration$;
    """
  end
end
