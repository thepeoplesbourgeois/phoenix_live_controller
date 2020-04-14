defmodule Phoenix.LiveController do
  @moduledoc ~S"""
  Controller-style abstraction for building multi-action live views on top of `Phoenix.LiveView`.

  `Phoenix.LiveView` API differs from `Phoenix.Controller` API in order to emphasize stateful
  lifecycle of live views, support long-lived processes behind them and accommodate their much
  looser ties with the router. Contrary to HTTP requests that are rendered and discarded, live
  actions are mounted and their processes stay alive to handle events & miscellaneous process
  interactions and to re-render as many times as necessary. Because of these extra complexities, the
  library drives developers towards single live view per router action.

  At the same time, `Phoenix.LiveView` provides a complete solution for router-aware live navigation
  and it introduces the concept of live actions both in routing and in the live socket. These
  features mean that many live views may play a role similar to classic controllers.

  It's all about efficient code organization - just like a complex live view's code may need to be
  broken into multiple modules or live components, a bunch of simple live actions centered around
  similar topic or resource may be best organized into a single live view module, keeping the
  related web logic together and giving the room to share common code. That's where
  `Phoenix.LiveController` comes in: to organize live view code that covers multiple live actions in
  a fashion similar to how Phoenix controllers organize multiple HTTP actions. It provides a
  pragmatic convention that still keeps pieces of a stateful picture visible by enforcing clear
  function annotations.

  Here's a live view equivalent of a HTML controller generated with the `mix phx.gen.html Blog
  Article articles ...` scaffold, powered by `Phoenix.LiveController`:

      # lib/my_app_web.ex

      defmodule MyAppWeb do
        # ...

        def live do
          quote do
            use Phoenix.LiveController

            alias MyAppWeb.Router.Helpers, as: Routes
          end
        end
      end

      # lib/my_app_web/router.ex

      defmodule MyAppWeb.Router do
        # ...

        scope "/", MyAppWeb do
          # ...

          live "/articles", ArticleLive, :index
          live "/articles/new", ArticleLive, :new
          live "/articles/:id", ArticleLive, :show
          live "/articles/:id/edit", ArticleLive, :edit
        end
      end

      # lib/my_app_web/live/article_live.ex

      defmodule MyAppWeb.ArticleLive do
        use MyAppWeb, :live

        alias MyApp.Blog
        alias MyApp.Blog.Article

        @action_mount true
        def index(socket, _params) do
          articles = Blog.list_articles()
          assign(socket, articles: articles)
        end

        @action_mount true
        def new(socket, _params) do
          changeset = Blog.change_article(%Article{})
          assign(socket, changeset: changeset)
        end

        @event_handler true
        def create(socket, %{"article" => article_params}) do
          case Blog.create_article(article_params) do
            {:ok, article} ->
              socket
              |> put_flash(:info, "Article created successfully.")
              |> push_redirect(to: Routes.article_path(socket, :show, article))

            {:error, %Ecto.Changeset{} = changeset} ->
              assign(socket, changeset: changeset)
          end
        end

        @action_mount true
        def show(socket, %{"id" => id}) do
          article = Blog.get_article!(id)
          assign(socket, article: article)
        end

        @action_mount true
        def edit(socket, %{"id" => id}) do
          article = Blog.get_article!(id)
          changeset = Blog.change_article(article)
          assign(socket, article: article, changeset: changeset)
        end

        @event_handler true
        def update(socket, %{"article" => article_params}) do
          article = socket.assigns.article

          case Blog.update_article(article, article_params) do
            {:ok, article} ->
              socket
              |> put_flash(:info, "Article updated successfully.")
              |> push_redirect(to: Routes.article_path(socket, :show, article))

            {:error, %Ecto.Changeset{} = changeset} ->
              assign(socket, article: article, changeset: changeset)
          end
        end

        @event_handler true
        def delete(socket, %{"id" => id}) do
          article = Blog.get_article!(id)
          {:ok, _article} = Blog.delete_article(article)

          socket
          |> put_flash(:info, "Article deleted successfully.")
          |> push_redirect(to: Routes.article_path(socket, :index))
        end
      end

  `Phoenix.LiveController` is not meant to be a replacement of `Phoenix.LiveView` - although any
  live view may be implemented with it, it will likely prove beneficial only for specific kinds of
  live views. These include:

  * Live equivalents of HTML resources, e.g. those generated by `mix phx.gen.html`
  * Live actions that share some mounting or event handling logic, e.g. auth logic
  * Live views that don't do much besides mounting and handling events, e.g. GenServer logic

  Finally, there's really no complex magic behind `Phoenix.LiveController` - it's just a simple,
  purely functional abstraction that's easy to comprehend and that doesn't hack or hide any of the
  core live view functionality - which is still at the wheel, available if needed.

  ## Mounting actions

  *Action mounts* replace `c:Phoenix.LiveView.mount/3` entry point in order to split mounting of
  specific live actions into separate functions. They are annotated with `@action_mount true` and,
  just like with Phoenix controller actions, their name is the name of the action they mount.

      # lib/my_app_web/router.ex

      live "/articles", ArticleLive, :index
      live "/articles/:id", ArticleLive, :show

      # lib/my_app_web/live/article_live.ex

      defmodule MyAppWeb.ArticleLive do
        use Phoenix.LiveController

        @action_mount true
        def index(socket, _params) do
          articles = Blog.list_articles()
          assign(socket, articles: articles)
        end

        @action_mount true
        def show(socket, %{"id" => id}) do
          article = Blog.get_article!(id)
          assign(socket, article: article)
        end
      end

  Note that action mounts don't have to wrap the resulting socket in the `{:ok, socket}` tuple,
  which also brings them closer to Phoenix controller actions.

  ## Handling events

  *Event handlers* replace `c:Phoenix.LiveView.handle_event/3` callbacks in order to make the event
  handling code consistent with the action mounting code. These functions are annotated with
  `@event_handler true` and their name is the name of the event they handle.

      # lib/my_app_web/templates/article/*.html.leex

      <%= link "Delete", to: "#", phx_click: :delete, phx_value_id: article.id, data: [confirm: "Are you sure?"] %>

      # lib/my_app_web/live/article_live.ex

      defmodule MyAppWeb.ArticleLive do
        use Phoenix.LiveController

        # ...

        @event_handler true
        def delete(socket, %{"id" => id}) do
          article = Blog.get_article!(id)
          {:ok, _article} = Blog.delete_article(article)

          socket
          |> put_flash(:info, "Article deleted successfully.")
          |> push_redirect(to: Routes.article_path(socket, :index))
        end
      end

  Note that, consistently with action mounts, event handlers don't have to wrap the resulting socket
  in the `{:noreply, socket}` tuple.

  Also note that, as a security measure, LiveController won't convert binary names of events that
  don't have corresponding event handlers into atoms that wouldn't be garbage collected.

  ## Applying session

  Session, previously passed to `c:Phoenix.LiveView.mount/3`, is not passed through to action
  mounts. Instead, an optional `c:apply_session/2` callback may be defined in order to read the
  session and modify socket before any action mount is called.

      defmodule MyAppWeb.ArticleLive do
        use Phoenix.LiveController

        @impl true
        def apply_session(socket, session) do
          user_token = session["user_token"]
          user = user_token && Accounts.get_user_by_session_token(user_token)

          assign(socket, current_user: user)
        end

        # ...
      end

  Note that, in a fashion similar to controller plugs, no further action mounting logic will be
  called if the returned socket was redirected - more on that below.

  ## Pipelines

  Phoenix controllers are [backed by the power of Plug
  pipelines](https://hexdocs.pm/phoenix/Phoenix.Controller.html#module-plug-pipeline) in order to
  organize common code called before actions and to allow halting early. LiveController provides its
  own simplified solution for these problems via optional `c:before_action_mount/3` and
  `c:before_event_handler/3` callbacks supported by the `unless_redirected/2` helper function.

  `c:before_action_mount/3` acts on a socket after session is applied but before an actual action
  mount is called.

      defmodule MyAppWeb.ArticleLive do
        use Phoenix.LiveController

        @impl true
        def before_action_mount(socket, _name, _params) do
          assign(socket, page_title: "Blog")
        end

        # ...
      end

  Similarly, `c:before_event_handler/3` callback acts on a socket before an actual event handler is
  called.

      defmodule MyAppWeb.ArticleLive do
        use Phoenix.LiveController

        @impl true
        def before_event_handler(socket, _name, _params) do
          require_authenticated_user(socket)
        end

        # ...
      end

  After these callbacks, live controller calls `c:action_mount/3` and `c:event_handler/3`
  respectively, but only if the socket was not redirected which is guaranteed by internal use of the
  `unless_redirected/2` function. This simple helper calls any function that takes socket as
  argument & that returns it only if the socket wasn't previously redirected and passes the socket
  through otherwise. It may also be used inside an actual action mount or event handler code for a
  similar result.

      defmodule MyAppWeb.ArticleLive do
        use Phoenix.LiveController

        @action_mount true
        def edit(socket, %{"id" => id}) do
          socket
          |> require_authenticated_user()
          |> unless_redirected(&assign(&1, article: Blog.get_article!(id)))
          |> unless_redirected(&authorize_article_author(&1, &1.assigns.article))
          |> unless_redirected(&assign(&1, changeset: Blog.change_article(&.assigns.article)))
        end
      end

  Finally, `c:action_mount/3` and `c:event_handler/3`, rough equivalents of
  [`action/2`](https://hexdocs.pm/phoenix/Phoenix.Controller.html#module-overriding-action-2-for-custom-arguments)
  plug in Phoenix controllers, complete the pipeline by calling functions named after specific
  actions or events.

  ## Specifying LiveView options

  Any options that were previously passed to `use Phoenix.LiveView`, such as `:layout` or
  `:container`, may now be passed to `use Phoenix.LiveController`.

      use Phoenix.LiveController, layout: {MyAppWeb.LayoutView, "live.html"}

  ## Rendering actions

  Implementation of the `c:Phoenix.LiveView.render/1` callback, previously required in every live
  view, may now be omitted in which case the default implementation will be injected. It'll ask the
  view module named after specific live module to render HTML template named after the action - the
  same way that Phoenix controllers do when the `Phoenix.Controller.render/2` is called without a
  template name.

  For example, `MyAppWeb.ArticleLive` mounted with `:index` action will render with following call:

      MyAppWeb.ArticleView.render("index.html", assigns)

  Custom `c:Phoenix.LiveView.render/1` implementation may still be provided if necessary.

  """

  alias Phoenix.LiveView.Socket

  @doc ~S"""
  Allows to read the session and modify socket before any action mount is called.

  Read more about how to apply the session and the consequences of returning redirected socket from
  this callback in docs for `Phoenix.LiveController`.
  """
  @callback apply_session(
              socket :: Socket.t(),
              session :: map
            ) :: Socket.t()

  @doc ~S"""
  Acts on a socket after session is applied but before an actual action mount is called.

  Read more about the role that this callback plays in the live controller pipeline and the
  consequences of returning redirected socket from this callback in docs for
  `Phoenix.LiveController`.
  """
  @callback before_action_mount(
              socket :: Socket.t(),
              name :: atom,
              params :: Socket.unsigned_params()
            ) :: Socket.t()

  @doc ~S"""
  Invokes action mount for specific action.

  It can be overridden, e.g. in order to modify the list of arguments passed to action mounts.

      @impl true
      def action_mount(socket, name, params) do
        apply(__MODULE__, name, [socket, params, socket.assigns.current_user])
      end

  It can be wrapped, e.g. for sake of logging or modifying the socket returned from action mounts.

      @impl true
      def action_mount(socket, name, params) do
        Logger.debug("#{__MODULE__} started mounting #{name}")
        socket = super(socket, name, params)
        Logger.debug("#{__MODULE__} finished mounting #{name}")
        socket
      end

  Read more about the role that this callback plays in the live controller pipeline in docs for
  `Phoenix.LiveController`.

  """
  @callback action_mount(
              socket :: Socket.t(),
              name :: atom,
              params :: Socket.unsigned_params()
            ) :: Socket.t()

  @doc ~S"""
  Acts on a socket before an actual event handler is called.

  Read more about the role that this callback plays in the live controller pipeline and the
  consequences of returning redirected socket from this callback in docs for
  `Phoenix.LiveController`.
  """
  @callback before_event_handler(
              socket :: Socket.t(),
              name :: atom,
              params :: Socket.unsigned_params()
            ) :: Socket.t()

  @doc ~S"""
  Invokes event handler for specific event.

  It works in a analogous way and opens analogous possibilities to `c:action_mount/3`.

  Read more about the role that this callback plays in the live controller pipeline in docs for
  `Phoenix.LiveController`.
  """
  @callback event_handler(
              socket :: Socket.t(),
              name :: atom,
              params :: Socket.unsigned_params()
            ) :: Socket.t()

  @optional_callbacks apply_session: 2,
                      before_action_mount: 3,
                      action_mount: 3,
                      before_event_handler: 3,
                      event_handler: 3

  defmacro __using__(opts) do
    view_module =
      __CALLER__.module
      |> to_string()
      |> String.replace(~r/Live$/, "View")
      |> String.to_atom()

    quote do
      use Phoenix.LiveView, unquote(opts)

      @behaviour unquote(__MODULE__)

      Module.register_attribute(__MODULE__, :actions, accumulate: true)
      Module.register_attribute(__MODULE__, :events, accumulate: true)

      @on_definition unquote(__MODULE__)
      @before_compile unquote(__MODULE__)

      import unquote(__MODULE__)

      def mount(params, session, socket) do
        action = socket.assigns.live_action

        unless Enum.member?(__live_controller__(:actions), action),
          do:
            raise("#{inspect(__MODULE__)} doesn't implement action mount for #{inspect(action)}")

        socket
        |> apply_session(session)
        |> unless_redirected(&before_action_mount(&1, action, params))
        |> unless_redirected(&action_mount(&1, action, params))
        |> wrap_socket(&{:ok, &1})
      end

      def apply_session(socket, _session), do: socket

      def before_action_mount(socket, _name, _params), do: socket

      def action_mount(socket, name, params), do: apply(__MODULE__, name, [socket, params])

      def handle_event(event_string, params, socket) do
        unless Enum.any?(__live_controller__(:events), &(to_string(&1) == event_string)),
          do:
            raise(
              "#{inspect(__MODULE__)} doesn't implement event handler for #{inspect(event_string)}"
            )

        event = String.to_atom(event_string)

        socket
        |> before_event_handler(event, params)
        |> unless_redirected(&event_handler(&1, event, params))
        |> wrap_socket(&{:noreply, &1})
      end

      def before_event_handler(socket, _name, _params), do: socket

      def event_handler(socket, name, params), do: apply(__MODULE__, name, [socket, params])

      defp wrap_socket(socket = %Phoenix.LiveView.Socket{}, wrapper), do: wrapper.(socket)
      defp wrap_socket(misc, _wrapper), do: misc

      def render(assigns = %{live_action: action}) do
        unquote(view_module).render("#{action}.html", assigns)
      end

      defoverridable apply_session: 2,
                     before_action_mount: 3,
                     action_mount: 3,
                     before_event_handler: 3,
                     event_handler: 3,
                     render: 1
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      Module.delete_attribute(__MODULE__, :action_mount)
      Module.delete_attribute(__MODULE__, :event_handler)

      @doc false
      def __live_controller__(:actions), do: @actions
      def __live_controller__(:events), do: @events
    end
  end

  def __on_definition__(env, _kind, name, _args, _guards, _body) do
    action = Module.delete_attribute(env.module, :action_mount)
    event = Module.delete_attribute(env.module, :event_handler)

    cond do
      action -> Module.put_attribute(env.module, :actions, name)
      event -> Module.put_attribute(env.module, :events, name)
      true -> :ok
    end
  end

  @doc ~S"""
  Calls given function if socket wasn't redirected, passes the socket through otherwise.

  Read more about the role that this function plays in the live controller pipeline in docs for
  `Phoenix.LiveController`.
  """
  def unless_redirected(socket = %{redirected: nil}, func), do: func.(socket)
  def unless_redirected(redirected_socket, _func), do: redirected_socket
end
