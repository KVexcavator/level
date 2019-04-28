defmodule Level.SpacesTest do
  use Level.DataCase, async: true

  import Ecto.Query
  import Mox

  alias Level.Groups
  alias Level.Levelbot
  alias Level.Nudges
  alias Level.Posts
  alias Level.Repo
  alias Level.Schemas.OpenInvitation
  alias Level.Schemas.Space
  alias Level.Schemas.SpaceBot
  alias Level.Schemas.SpaceSetupStep
  alias Level.Schemas.SpaceUser
  alias Level.Spaces

  describe "spaces_base_query/1" do
    setup do
      create_user_and_space()
    end

    test "includes spaces the user owns", %{
      user: user,
      space: %Space{id: space_id}
    } do
      query = Spaces.spaces_base_query(user)
      assert Enum.any?(Repo.all(query), fn s -> s.id == space_id end)
    end

    test "includes space the user belongs to", %{
      space: %Space{id: space_id} = space
    } do
      {:ok, %{user: member_user}} = create_space_member(space)
      query = Spaces.spaces_base_query(member_user)
      assert Enum.any?(Repo.all(query), fn s -> s.id == space_id end)
    end

    test "excludes spaces the user does not belong to", %{
      user: user
    } do
      {:ok, %{space: %Space{id: space_id}}} = create_user_and_space()
      query = Spaces.spaces_base_query(user)
      refute Enum.any?(Repo.all(query), fn s -> s.id == space_id end)
    end
  end

  describe "space_users_base_query/1" do
    setup do
      create_user_and_space()
    end

    test "includes the user's own space user", %{
      user: user,
      space_user: %SpaceUser{id: space_user_id}
    } do
      query = Spaces.space_users_base_query(user)
      assert Enum.any?(Repo.all(query), fn su -> su.id == space_user_id end)
    end

    test "includes space users in spaces of which the user is a member", %{
      user: user,
      space: space
    } do
      {:ok, %{space_user: %SpaceUser{id: space_user_id}}} = create_space_member(space)
      query = Spaces.space_users_base_query(user)
      assert Enum.any?(Repo.all(query), fn su -> su.id == space_user_id end)
    end

    test "excludes space users in spaces of which the user is not a member", %{
      user: user
    } do
      {:ok, %{space_user: %SpaceUser{id: space_user_id}}} = create_user_and_space()
      query = Spaces.space_users_base_query(user)
      refute Enum.any?(Repo.all(query), fn su -> su.id == space_user_id end)
    end
  end

  describe "space_bots_base_query/1" do
    setup do
      create_user_and_space()
    end

    test "includes space bots for spaces the user belongs to", %{
      user: user,
      levelbot: %SpaceBot{id: levelbot_id}
    } do
      query = Spaces.space_bots_base_query(user)
      assert Enum.any?(Repo.all(query), fn sb -> sb.id == levelbot_id end)
    end

    test "excludes space users in spaces of which the user is not a member", %{
      user: user
    } do
      {:ok, %{levelbot: %SpaceBot{id: other_levelbot_id}}} = create_user_and_space()
      query = Spaces.space_bots_base_query(user)
      refute Enum.any?(Repo.all(query), fn sb -> sb.id == other_levelbot_id end)
    end
  end

  describe "get_first_member_space/1" do
    test "returns the first space the user belongs to" do
      {:ok, %{space: _, user: user}} = create_user_and_space(%{}, %{name: "Banana"})
      {:ok, %{space: %Space{id: space_id}}} = create_space(user, %{name: "Apple"})
      {:ok, %{space: _, user: _}} = create_user_and_space(%{}, %{name: "Aardvark"})

      assert %Space{id: ^space_id} = Spaces.get_first_member_space(user)
    end

    test "returns nil if user doesn't belong to any spaces" do
      {:ok, user} = create_user()

      assert Spaces.get_first_member_space(user) == nil
    end
  end

  describe "create_space/2" do
    setup do
      {:ok, user} = create_user()
      {:ok, %{user: user}}
    end

    test "creates an org if the space is not a demo", %{user: user} do
      params =
        valid_space_params()
        |> Map.put(:name, "MySpace")

      {:ok, %{org: org, space: space}} = Spaces.create_space(user, params)
      assert org.name == "MySpace"
      assert org.subscription_state == "NONE"
      assert org.seat_quantity == 1
      assert space.org_id == org.id
    end

    test "does not create an org if demo", %{user: user} do
      params =
        valid_space_params()
        |> Map.put(:name, "MySpace")
        |> Map.put(:is_demo, true)

      {:ok, %{space: space}} = Spaces.create_space(user, params)
      assert space.org_id == nil
    end

    test "creates a Stripe subscription if billing is enabled", %{user: user} do
      opts = [billing_enabled: true, billing_plan_id: "plan_000000"]

      Level.Billing.TestAdapter
      |> expect(:create_customer, fn _ ->
        {:ok, %{"id" => "cus_0000000000"}}
      end)
      |> expect(:create_subscription, fn "cus_0000000000", "plan_000000", 1 ->
        {:ok, %{"id" => "sub_0000000000", "status" => "trialing"}}
      end)

      params =
        valid_space_params()
        |> Map.put(:name, "MySpace")

      {:ok, %{org: org}} = Spaces.create_space(user, params, opts)
      assert org.subscription_state == "TRIALING"
      assert org.stripe_customer_id == "cus_0000000000"
      assert org.stripe_subscription_id == "sub_0000000000"
    end

    test "creates a new space", %{user: user} do
      params =
        valid_space_params()
        |> Map.put(:name, "MySpace")

      {:ok, %{space: space}} = Spaces.create_space(user, params)
      assert space.name == "MySpace"
    end

    test "creates an open invitation", %{user: user} do
      params = valid_space_params()
      {:ok, %{open_invitation: open_invitation}} = Spaces.create_space(user, params)
      assert open_invitation.state == "ACTIVE"
    end

    test "installs levelbot", %{user: user} do
      params = valid_space_params()
      {:ok, %{space: space, levelbot: levelbot}} = Spaces.create_space(user, params)

      assert levelbot.space_id == space.id
      assert levelbot.handle == "levelbot"
    end

    test "installs postbot", %{user: user} do
      params = valid_space_params()
      {:ok, %{space: space, postbot: postbot}} = Spaces.create_space(user, params)

      assert postbot.space_id == space.id
      assert postbot.handle == "postbot"
    end

    test "sets a postbot key", %{user: user} do
      params = valid_space_params()
      {:ok, %{space: space}} = Spaces.create_space(user, params)

      assert String.length(space.postbot_key) == 32
    end
  end

  describe "get_space_by_slug/2" do
    setup do
      create_user_and_space()
    end

    test "returns the space if the user can access it", %{user: user, space: space} do
      {:ok, %{space: found_space, space_user: space_user}} =
        Spaces.get_space_by_slug(user, space.slug)

      assert found_space.id == space.id
      assert space_user.space_id == space.id
      assert space_user.user_id == user.id
    end

    test "returns an error if the users access is revoked", %{
      user: user,
      space: space,
      space_user: space_user
    } do
      {:ok, _} = Spaces.revoke_access(space_user)

      {:error, message} = Spaces.get_space_by_slug(user, space.slug)
      assert message == "Space not found"
    end

    test "returns an error if user cannot access the space", %{space: space} do
      {:ok, another_user} = create_user()

      {:error, message} = Spaces.get_space_by_slug(another_user, space.slug)
      assert message == "Space not found"
    end

    test "returns an error if the space does not exist", %{user: user} do
      {:error, message} = Spaces.get_space_by_slug(user, "idontexist")
      assert message == "Space not found"
    end
  end

  describe "get_setup_state/1" do
    setup do
      create_user_and_space()
    end

    test "returns create groups if no setup steps have been completed", %{space: space} do
      assert {:ok, :create_groups} = Spaces.get_setup_state(space)
    end

    test "returns invite users if create groups has been completed", %{
      space: space,
      space_user: space_user
    } do
      Spaces.complete_setup_step(space_user, space, %{
        state: :create_groups,
        is_skipped: false
      })

      assert {:ok, :invite_users} = Spaces.get_setup_state(space)
    end

    test "returns complete if invite users has been completed", %{
      space: space,
      space_user: space_user
    } do
      Spaces.complete_setup_step(space_user, space, %{
        state: :invite_users,
        is_skipped: false
      })

      assert {:ok, :complete} = Spaces.get_setup_state(space)
    end
  end

  describe "complete_setup_step/3" do
    setup do
      create_user_and_space()
    end

    test "inserts a transition record and returns the next state", %{
      space: space,
      space_user: space_user
    } do
      {:ok, next_state} =
        Spaces.complete_setup_step(space_user, space, %{
          state: :create_groups,
          is_skipped: false
        })

      assert Repo.get_by(SpaceSetupStep, %{
               space_id: space.id,
               space_user_id: space_user.id,
               state: "CREATE_GROUPS"
             })

      assert {:ok, ^next_state} = Spaces.get_setup_state(space)
    end

    test "gracefully absorbs duplicate transitions", %{space: space, space_user: space_user} do
      params = %{
        state: :create_groups,
        is_skipped: false
      }

      {:ok, _next_state} = Spaces.complete_setup_step(space_user, space, params)
      assert {:ok, _next_state} = Spaces.complete_setup_step(space_user, space, params)
    end
  end

  describe "create_open_invitation/1" do
    setup do
      create_user_and_space()
    end

    test "inserts a new open invitation", %{space: space} do
      # make sure there are no active invitations conflicting with this operation
      Repo.delete_all(from(i in OpenInvitation))

      {:ok, invitation} = Spaces.create_open_invitation(space)
      assert invitation.state == "ACTIVE"
    end

    test "revokes existing active invitations and creates a new one", %{space: space} do
      # make sure there are no active invitations conflicting with this operation
      Repo.delete_all(from(i in OpenInvitation))

      {:ok, invitation} = Spaces.create_open_invitation(space)
      {:ok, another_invitation} = Spaces.create_open_invitation(space)

      assert %OpenInvitation{state: "REVOKED"} = Repo.get(OpenInvitation, invitation.id)
      assert another_invitation.state == "ACTIVE"
      refute invitation.token == another_invitation.token
    end
  end

  describe "get_open_invitation_by_token/1" do
    setup do
      create_user_and_space()
    end

    test "returns the invitation if it is active", %{open_invitation: invitation} do
      {:ok, found_invitation} = Spaces.get_open_invitation_by_token(invitation.token)
      assert invitation.id == found_invitation.id
    end

    test "returns a revoked result if invitation is revoked", %{open_invitation: invitation} do
      {:ok, _revoked_invitation} =
        invitation
        |> Ecto.Changeset.change(state: "REVOKED")
        |> Repo.update()

      assert {:error, :revoked} = Spaces.get_open_invitation_by_token(invitation.token)
    end

    test "returns not found result if token does not exist" do
      assert {:error, :not_found} = Spaces.get_open_invitation_by_token("notfound")
    end
  end

  describe "create_member/2" do
    setup do
      {:ok, result} = create_user_and_space()
      {:ok, new_user} = create_user()
      {:ok, Map.merge(result, %{new_user: new_user})}
    end

    test "add the user as a member of the space", %{space: space, new_user: new_user} do
      {:ok, space_user} = Spaces.create_member(new_user, space)
      assert space_user.role == "MEMBER"
    end

    test "adds the user to the default groups", %{
      space: space,
      space_user: space_user,
      new_user: new_user
    } do
      {:ok, %{group: default_group}} = create_group(space_user, %{is_default: true})
      {:ok, _} = Spaces.create_member(new_user, space)
      assert Groups.get_user_role(default_group, new_user) == :member
      assert Groups.get_user_state(default_group, new_user) == :subscribed
    end

    test "create default nudges", %{space: space, new_user: new_user} do
      {:ok, space_user} = Spaces.create_member(new_user, space)
      nudges = Nudges.list_nudges(space_user)
      assert Enum.any?(nudges, fn nudge -> nudge.minute == 660 end)
      assert Enum.any?(nudges, fn nudge -> nudge.minute == 900 end)
    end

    test "creates a welcome bot message", %{space: space, new_user: new_user} do
      {:ok, space_user} = Spaces.create_member(new_user, space)

      posts =
        space_user
        |> Posts.Query.base_query()
        |> Posts.Query.where_undismissed_in_inbox()
        |> Repo.all()

      assert Enum.any?(posts, fn post ->
               post.body =~ ~r/Hey \@#{space_user.handle}/ &&
                 post.space_bot_id == Levelbot.get_space_bot!(space).id
             end)
    end
  end

  describe "can_update?/1" do
    test "is true if user is an owner" do
      space_user = %SpaceUser{role: "OWNER"}
      assert Spaces.can_update?(space_user)
    end

    test "is true if user is an admin" do
      space_user = %SpaceUser{role: "ADMIN"}
      assert Spaces.can_update?(space_user)
    end

    test "is false if user is an regular member" do
      space_user = %SpaceUser{role: "MEMBER"}
      refute Spaces.can_update?(space_user)
    end
  end

  describe "can_manage_members?/1" do
    test "is true if user is an owner" do
      space_user = %SpaceUser{role: "OWNER"}
      assert Spaces.can_manage_members?(space_user)
    end

    test "is true if user is an admin" do
      space_user = %SpaceUser{role: "ADMIN"}
      assert Spaces.can_manage_members?(space_user)
    end

    test "is false if user is an regular member" do
      space_user = %SpaceUser{role: "MEMBER"}
      refute Spaces.can_manage_members?(space_user)
    end
  end

  describe "can_manage_owners?/1" do
    test "is true if user is an owner" do
      space_user = %SpaceUser{role: "OWNER"}
      assert Spaces.can_manage_owners?(space_user)
    end

    test "is false if user is an regular member" do
      space_user = %SpaceUser{role: "MEMBER"}
      refute Spaces.can_manage_owners?(space_user)
    end

    test "is false if user is an admin" do
      space_user = %SpaceUser{role: "ADMIN"}
      refute Spaces.can_manage_owners?(space_user)
    end
  end

  describe "revoke_access/1" do
    test "transitions the space user to disabled" do
      {:ok, %{space_user: space_user}} = create_user_and_space()
      {:ok, revoked_user} = Spaces.revoke_access(space_user)
      assert revoked_user.state == "DISABLED"
    end
  end

  describe "accept_open_invitation/2" do
    test "creates a new active space user if the user has never been a member" do
      {:ok, %{open_invitation: invitation}} = create_user_and_space()
      {:ok, user} = create_user()

      {:ok, space_user} = Spaces.accept_open_invitation(user, invitation)
      assert space_user.state == "ACTIVE"
    end

    test "reactivates disabled space user" do
      {:ok, %{space: space, open_invitation: invitation}} = create_user_and_space()
      {:ok, %{user: user, space_user: space_user}} = create_space_member(space)

      {:ok, _} = Spaces.revoke_access(space_user)

      {:ok, reactivated_space_user} = Spaces.accept_open_invitation(user, invitation)
      assert reactivated_space_user.state == "ACTIVE"
    end
  end

  describe "update_role/3" do
    test "admins can promote members to admin" do
      {:ok, %{space: space, space_user: actor}} = create_user_and_space()
      {:ok, %{space_user: member}} = create_space_member(space)

      {:ok, actor} = Spaces.update_space_user(actor, %{role: "ADMIN"})
      {:ok, member} = Spaces.update_space_user(member, %{role: "MEMBER"})

      {:ok, updated_member} = Spaces.update_role(actor, member, "ADMIN")
      assert updated_member.role == "ADMIN"
    end

    test "admins cannot promote anyone to owner" do
      {:ok, %{space: space, space_user: actor}} = create_user_and_space()
      {:ok, %{space_user: member}} = create_space_member(space)

      {:ok, actor} = Spaces.update_space_user(actor, %{role: "ADMIN"})
      {:ok, member} = Spaces.update_space_user(member, %{role: "MEMBER"})

      assert {:error, "You are not allowed to perform this action."} =
               Spaces.update_role(actor, member, "OWNER")
    end

    test "owners can promote anyone to owner" do
      {:ok, %{space: space, space_user: actor}} = create_user_and_space()
      {:ok, %{space_user: member}} = create_space_member(space)

      {:ok, actor} = Spaces.update_space_user(actor, %{role: "OWNER"})
      {:ok, member} = Spaces.update_space_user(member, %{role: "MEMBER"})

      {:ok, updated_member} = Spaces.update_role(actor, member, "OWNER")
      assert updated_member.role == "OWNER"
    end

    test "members cannot change roles" do
      {:ok, %{space: space, space_user: actor}} = create_user_and_space()
      {:ok, %{space_user: member}} = create_space_member(space)

      {:ok, actor} = Spaces.update_space_user(actor, %{role: "MEMBER"})
      {:ok, member} = Spaces.update_space_user(member, %{role: "MEMBER"})

      assert {:error, "You are not allowed to perform this action."} =
               Spaces.update_role(actor, member, "ADMIN")

      {:ok, member} = Spaces.update_space_user(member, %{role: "ADMIN"})

      assert {:error, "You are not allowed to perform this action."} =
               Spaces.update_role(actor, member, "MEMBER")
    end
  end
end
