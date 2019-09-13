defmodule PaperTrailTest.UUIDTest do
  use ExUnit.Case
  import PaperTrail.RepoClient, only: [repo: 0]
  alias PaperTrail.Version
  import Ecto.Query

  setup_all do
    Application.put_env(:paper_trail, :repo, PaperTrail.UUIDRepo)
    Application.put_env(:paper_trail, :originator, name: :admin, model: Admin)
    Application.put_env(:paper_trail, :originator_type, Ecto.UUID)
    Application.put_env(:paper_trail, :item_type, (if System.get_env("STRING_TEST") == nil, do: Ecto.UUID, else: :string))

    Code.compiler_options(ignore_module_conflict: true)
    Code.eval_file("lib/paper_trail.ex")
    Code.eval_file("lib/version.ex")
    Code.eval_file("test/support/assoc_models.exs")
    Code.compiler_options(ignore_module_conflict: false)

    repo().delete_all(Version)
    repo().delete_all(Admin)
    repo().delete_all(Product)
    repo().delete_all(Item)
    :ok
  end

  test "creates versions with models that have a UUID primary key" do
    product =
      %Product{}
      |> Product.changeset(%{name: "Hair Cream"})
      |> PaperTrail.insert!()

    version = Version |> last |> repo().one

    assert version.item_id == product.id
    assert version.item_type == "Product"
  end

  test "handles originators with a UUID primary key" do
    admin =
      %Admin{}
      |> Admin.changeset(%{email: "admin@example.com"})
      |> repo().insert!

    %Product{}
    |> Product.changeset(%{name: "Hair Cream"})
    |> PaperTrail.insert!(originator: admin)

    version =
      Version
      |> last
      |> repo().one
      |> repo().preload(:admin)

    assert version.admin == admin
  end

  test "versioning models that have a non-regular primary key" do
    item =
      %Item{}
      |> Item.changeset(%{title: "hello"})
      |> PaperTrail.insert!()

    version = Version |> last |> repo().one
    assert version.item_id == item.item_id
  end

  test "test INTEGER primary key for item_type == :string" do
    if PaperTrail.Version.__schema__(:type, :item_id) == :string do
      item =
        %FooItem{}
        |> FooItem.changeset(%{title: "hello"})
        |> PaperTrail.insert!()

      version = Version |> last |> repo().one
      assert version.item_id == "#{item.id}"
    end
  end

  test "test STRING primary key for item_type == :string" do
    if PaperTrail.Version.__schema__(:type, :item_id) == :string do
      item =
        %BarItem{}
        |> BarItem.changeset(%{item_id: "#{:os.system_time}", title: "hello"})
        |> PaperTrail.insert!()

      version = Version |> last |> repo().one
      assert version.item_id == item.item_id
    end
  end

  test "using embeds with UUID enabled should render them in their own version entry" do
    params = %{
      model: "Model S",
      extras: [
        %{name: "Ludicrous mode", price: 10_000},
        %{name: "Autopilot", price: 5_000}
      ]
    }

    car =
      %Embed.Car{}
      |> Embed.Car.changeset(params)
      |> PaperTrail.insert()
      |> case do
        {:ok, %{assoc_versions: versions, model: car}} ->
          assert length(versions) == 2
          car
        _ ->
          assert false
      end

    # update the extras with doubled price
    params = %{
      extras: Enum.map(car.extras, fn %{id: id, price: price} ->
        %{
          id: id,
          price: price * 2
        }
      end)
    }

    car
    |> Embed.Car.changeset(params)
    |> PaperTrail.update()
    |> case do
      {:ok, ret} ->
        assert ret.version == nil
        assert ret.assoc_versions |> length() == 2
      _ ->
        assert false
    end
  end
end
